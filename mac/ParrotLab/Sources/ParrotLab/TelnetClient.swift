import Foundation
import Network

final class TelnetClient {
    enum State: Equatable {
        case idle
        case connecting
        case ready
        case failed(String)
        case stopped
    }

    var onState: ((State) -> Void)?
    var onLine: ((String) -> Void)?
    var onDebug: ((String) -> Void)?

    private let queue = DispatchQueue(label: "parrotlab.telnet")
    private var connection: NWConnection?
    private var lineBuffer = Data()
    private var state: State = .idle {
        didSet {
            let reportedState = state
            DispatchQueue.main.async { [weak self] in self?.onState?(reportedState) }
        }
    }

    func connect(host: String, port: UInt16 = 23, startupCommand: String = "ulogcat") {
        stop()
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            state = .failed("Invalid Telnet port")
            return
        }

        state = .connecting
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] newState in
            guard let self, let connection else { return }
            switch newState {
            case .ready:
                self.state = .ready
                self.onDebugMain("Telnet connected to \(host):\(port)")
                self.receive(on: connection)
                self.queue.asyncAfter(deadline: .now() + 0.15) {
                    self.send("\r\n", on: connection)
                }
                self.queue.asyncAfter(deadline: .now() + 0.45) {
                    self.send("export TERM=dumb; \(startupCommand)\r\n", on: connection)
                }
            case .failed(let error):
                self.state = .failed(error.localizedDescription)
                self.onDebugMain("Telnet failed: \(error.localizedDescription)")
            case .cancelled:
                if self.state != .stopped { self.state = .stopped }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func sendCommand(_ command: String) {
        guard let connection else { return }
        send(command + "\r\n", on: connection)
    }

    func stop() {
        connection?.cancel()
        connection = nil
        lineBuffer.removeAll(keepingCapacity: false)
        state = .stopped
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection else { return }
            if let data, !data.isEmpty {
                let payload = self.processTelnet(data, on: connection)
                self.consumeText(payload)
            }
            if let error {
                self.state = .failed(error.localizedDescription)
                self.onDebugMain("Telnet receive error: \(error.localizedDescription)")
                return
            }
            if complete {
                self.state = .stopped
                self.onDebugMain("Telnet connection closed")
                return
            }
            self.receive(on: connection)
        }
    }

    private func processTelnet(_ data: Data, on connection: NWConnection) -> Data {
        let bytes = [UInt8](data)
        var output = Data()
        var index = 0
        while index < bytes.count {
            if bytes[index] == 255, index + 1 < bytes.count {
                let command = bytes[index + 1]
                if [251, 252, 253, 254].contains(command), index + 2 < bytes.count {
                    let option = bytes[index + 2]
                    let response: UInt8 = (command == 253 || command == 254) ? 252 : 254
                    connection.send(content: Data([255, response, option]), completion: .contentProcessed { _ in })
                    index += 3
                    continue
                }
                if command == 255 {
                    output.append(255)
                    index += 2
                    continue
                }
                index += 2
                continue
            }
            output.append(bytes[index])
            index += 1
        }
        return output
    }

    private func consumeText(_ data: Data) {
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: 10) {
            let lineData = lineBuffer.prefix(upTo: newline)
            lineBuffer.removeSubrange(...newline)
            guard var line = String(data: lineData, encoding: .utf8) else { continue }
            line = line.trimmingCharacters(in: .newlines)
            if line.last == "\r" { line.removeLast() }
            DispatchQueue.main.async { [weak self] in self?.onLine?(line) }
        }
    }

    private func send(_ text: String, on connection: NWConnection) {
        connection.send(content: text.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if let error { self?.onDebugMain("Telnet send error: \(error.localizedDescription)") }
        })
    }

    private func onDebugMain(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onDebug?(message) }
    }
}
