import Foundation
import Network

struct RTPVideoStats: Equatable {
    var packets: UInt64 = 0
    var packetsLost: UInt64 = 0
    var bitrateKbps: Int = 0
    var jitterMs: Double = 0
}

final class RTPH264Receiver {
    var onAccessUnit: (([Data]) -> Void)?
    var onStats: ((RTPVideoStats) -> Void)?
    var onDebug: ((String) -> Void)?

    private let queue = DispatchQueue(label: "parrotlab.rtp-h264")
    private var listener: NWListener?
    private var senderConnection: NWConnection?
    private var assembler = H264RTPAssembler()
    private var stats = RTPVideoStats()
    private var previousSequence: UInt16?
    private var previousTransit: Double?
    private var jitterSeconds = 0.0
    private var bytesInWindow = 0
    private var windowStarted = Date()

    func start(port: UInt16) throws {
        stop()
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "ParrotLab.RTP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UDP port"])
        }
        let listener = try NWListener(using: .udp, on: endpointPort)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.debug("Listening for H.264/RTP on UDP \(port)")
            case .failed(let error): self?.debug("RTP listener failed: \(error.localizedDescription)")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.senderConnection?.cancel()
            self.senderConnection = connection
            self.debug("RTP sender connected: \(connection.endpoint)")
            connection.start(queue: self.queue)
            self.receive(on: connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        senderConnection?.cancel()
        senderConnection = nil
        assembler.reset()
        stats = RTPVideoStats()
        previousSequence = nil
        previousTransit = nil
        jitterSeconds = 0
        bytesInWindow = 0
        windowStarted = Date()
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self, let connection else { return }
            if let data { self.consume(packetData: data) }
            if let error {
                self.debug("RTP receive error: \(error.localizedDescription)")
                return
            }
            self.receive(on: connection)
        }
    }

    private func consume(packetData: Data) {
        guard let packet = RTPPacket(data: packetData), packet.payloadType == 96 else { return }
        stats.packets += 1
        bytesInWindow += packetData.count

        if let previousSequence {
            let expected = previousSequence &+ 1
            if packet.sequence != expected {
                let forwardGap = packet.sequence &- expected
                if forwardGap < 0x8000 { stats.packetsLost += UInt64(forwardGap) }
            }
        }
        previousSequence = packet.sequence

        let arrival = Date().timeIntervalSince1970
        let transit = arrival - Double(packet.timestamp) / 90_000.0
        if let previousTransit {
            let delta = abs(transit - previousTransit)
            jitterSeconds += (delta - jitterSeconds) / 16.0
        }
        previousTransit = transit
        stats.jitterMs = jitterSeconds * 1_000.0

        if let accessUnit = assembler.consume(packet: packet) {
            DispatchQueue.main.async { [weak self] in self?.onAccessUnit?(accessUnit) }
        }

        let elapsed = Date().timeIntervalSince(windowStarted)
        if elapsed >= 1.0 {
            stats.bitrateKbps = Int((Double(bytesInWindow) * 8.0 / 1_000.0 / elapsed).rounded())
            bytesInWindow = 0
            windowStarted = Date()
            let current = stats
            DispatchQueue.main.async { [weak self] in self?.onStats?(current) }
        }
    }

    private func debug(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onDebug?(message) }
    }

    static func assemblySelfTest() -> Bool {
        var assembler = H264RTPAssembler()
        guard let single = RTPPacket(data: makeTestPacket(sequence: 1, timestamp: 90_000, marker: true, payload: Data([0x65, 0x11, 0x22]))),
              assembler.consume(packet: single) == [Data([0x65, 0x11, 0x22])] else { return false }

        guard let start = RTPPacket(data: makeTestPacket(sequence: 2, timestamp: 180_000, marker: false, payload: Data([0x7c, 0x85, 0xaa, 0xbb]))),
              let end = RTPPacket(data: makeTestPacket(sequence: 3, timestamp: 180_000, marker: true, payload: Data([0x7c, 0x45, 0xcc]))) else { return false }
        guard assembler.consume(packet: start) == nil,
              assembler.consume(packet: end) == [Data([0x65, 0xaa, 0xbb, 0xcc])] else { return false }
        return true
    }

    private static func makeTestPacket(sequence: UInt16, timestamp: UInt32, marker: Bool, payload: Data) -> Data {
        var data = Data([
            0x80,
            marker ? 0xe0 : 0x60,
            UInt8(sequence >> 8), UInt8(sequence & 0xff),
            UInt8(timestamp >> 24), UInt8((timestamp >> 16) & 0xff), UInt8((timestamp >> 8) & 0xff), UInt8(timestamp & 0xff),
            0, 0, 0, 1
        ])
        data.append(payload)
        return data
    }
}

private struct RTPPacket {
    let marker: Bool
    let payloadType: UInt8
    let sequence: UInt16
    let timestamp: UInt32
    let payload: Data

    init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, bytes[0] >> 6 == 2 else { return nil }
        let hasPadding = bytes[0] & 0x20 != 0
        let hasExtension = bytes[0] & 0x10 != 0
        let csrcCount = Int(bytes[0] & 0x0f)
        marker = bytes[1] & 0x80 != 0
        payloadType = bytes[1] & 0x7f
        sequence = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        timestamp = UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7])

        var offset = 12 + csrcCount * 4
        guard offset <= bytes.count else { return nil }
        if hasExtension {
            guard offset + 4 <= bytes.count else { return nil }
            let wordCount = Int(UInt16(bytes[offset + 2]) << 8 | UInt16(bytes[offset + 3]))
            offset += 4 + wordCount * 4
            guard offset <= bytes.count else { return nil }
        }
        var end = bytes.count
        if hasPadding {
            let padding = Int(bytes.last ?? 0)
            guard padding > 0, padding <= end - offset else { return nil }
            end -= padding
        }
        guard end > offset else { return nil }
        payload = data.subdata(in: offset..<end)
    }
}

private struct H264RTPAssembler {
    private var timestamp: UInt32?
    private var nalUnits: [Data] = []
    private var fragmentedNAL: Data?

    mutating func reset() {
        timestamp = nil
        nalUnits.removeAll(keepingCapacity: false)
        fragmentedNAL = nil
    }

    mutating func consume(packet: RTPPacket) -> [Data]? {
        if timestamp != nil, timestamp != packet.timestamp {
            nalUnits.removeAll(keepingCapacity: true)
            fragmentedNAL = nil
        }
        timestamp = packet.timestamp

        let bytes = [UInt8](packet.payload)
        guard let first = bytes.first else { return nil }
        let type = first & 0x1f

        switch type {
        case 1...23:
            nalUnits.append(packet.payload)
        case 24:
            var offset = 1
            while offset + 2 <= bytes.count {
                let length = Int(UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1]))
                offset += 2
                guard length > 0, offset + length <= bytes.count else { break }
                nalUnits.append(packet.payload.subdata(in: offset..<(offset + length)))
                offset += length
            }
        case 28:
            guard bytes.count >= 2 else { return nil }
            let start = bytes[1] & 0x80 != 0
            let end = bytes[1] & 0x40 != 0
            let reconstructedHeader = (bytes[0] & 0xe0) | (bytes[1] & 0x1f)
            if start {
                fragmentedNAL = Data([reconstructedHeader])
                fragmentedNAL?.append(packet.payload.dropFirst(2))
            } else {
                fragmentedNAL?.append(packet.payload.dropFirst(2))
            }
            if end, let complete = fragmentedNAL {
                nalUnits.append(complete)
                fragmentedNAL = nil
            }
        default:
            break
        }

        guard packet.marker, !nalUnits.isEmpty else { return nil }
        let output = nalUnits
        nalUnits.removeAll(keepingCapacity: true)
        fragmentedNAL = nil
        timestamp = nil
        return output
    }
}
