import Foundation

struct TelemetrySnapshot: Equatable {
    var updatedAt = Date()

    var sc2RSSI: Int?
    var reportedRSSI: Int?
    var chain0RSSI: Int?
    var chain1RSSI: Int?
    var noise: Int?
    var snr: Int? {
        guard let signal = chainAverage ?? reportedRSSI, let noise else { return nil }
        return signal - noise
    }
    var chainAverage: Int? {
        let values = [chain0RSSI, chain1RSSI].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    var txQuality: Int?
    var rxQuality: Int?
    var rxUseful: Int?
    var phyRateMbps: Double?

    var flightState = "UNKNOWN"
    var altitude: Double?
    var latitude: Double?
    var longitude: Double?
    var roll: Double?
    var pitch: Double?
    var yaw: Double?
    var horizontalSpeed: Double?
    var distanceFromHome: Double?
    var satelliteCount: Int?

    var sc2BatteryPercent: Int?
    var droneBatteryPercent: Int?
    var sc2TemperatureC: Int?
    var sc2PowerState: String?

    var videoBitrateKbps: Int?
    var videoFPS: Double?
    var videoPackets: UInt64 = 0
    var videoPacketsLost: UInt64 = 0
    var videoJitterMs: Double?

    var connectionLabel = "Disconnected"

    mutating func markUpdated() {
        updatedAt = Date()
    }
}

final class SC2TelemetryParser {
    private let mppExpression = try! NSRegularExpression(
        pattern: #"rssi_mpp:\s*(-?\d+),\s*rssi:\s*(-?\d+),\s*state:([A-Z_]+),\s*altitude:([-+\d.]+),\s*latitude:([-+\d.]+),\s*longitude:([-+\d.]+),\s*roll:([-+\d.]+),\s*pitch:([-+\d.]+),\s*yaw:([-+\d.]+)"#
    )
    private let qualityExpression = try! NSRegularExpression(
        pattern: #"link_quality:\s*tx_quality=(-?\d+)%,\s*rx_quality=(-?\d+)%,\s*rx_useful=(-?\d+)%"#
    )
    private let healthExpression = try! NSRegularExpression(
        pattern: #"cpu:(-?\d+)°C,\s*battery:(\d+)%\s*\(([^)]+)\)"#
    )

    @discardableResult
    func consume(line: String, into snapshot: inout TelemetrySnapshot) -> Bool {
        let clean = Self.stripANSI(from: line)
        var changed = false

        if let groups = captures(mppExpression, in: clean), groups.count == 9 {
            snapshot.sc2RSSI = Int(groups[0])
            snapshot.reportedRSSI = Int(groups[1])
            snapshot.flightState = groups[2]
            snapshot.altitude = validCoordinateLikeValue(groups[3])
            snapshot.latitude = validCoordinateLikeValue(groups[4])
            snapshot.longitude = validCoordinateLikeValue(groups[5])
            snapshot.roll = Double(groups[6])
            snapshot.pitch = Double(groups[7])
            snapshot.yaw = Double(groups[8])
            changed = true
        }

        if let groups = captures(qualityExpression, in: clean), groups.count == 3 {
            snapshot.txQuality = Self.validPercent(groups[0])
            snapshot.rxQuality = Self.validPercent(groups[1])
            snapshot.rxUseful = Self.validPercent(groups[2])
            changed = true
        }

        if let groups = captures(healthExpression, in: clean), groups.count == 3 {
            snapshot.sc2TemperatureC = Int(groups[0])
            snapshot.sc2BatteryPercent = Int(groups[1])
            snapshot.sc2PowerState = groups[2]
            changed = true
        }

        if let range = clean.range(of: "extra_cnt:") {
            let values = clean[range.upperBound...]
                .split(separator: ":")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if values.count >= 12 {
                snapshot.chain0RSSI = values[0]
                snapshot.chain1RSSI = values[1]
                snapshot.noise = values[11]
                changed = true
            }
        }

        if let range = clean.range(of: "evt_accu: 1: rate:") {
            let rates = clean[range.upperBound...]
                .split(separator: ":")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                .filter { $0 > 0 }
            if let last = rates.last {
                snapshot.phyRateMbps = last / 1_000.0
                changed = true
            }
        }

        if changed { snapshot.markUpdated() }
        return changed
    }

    private func captures(_ expression: NSRegularExpression, in text: String) -> [String]? {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = expression.firstMatch(in: text, range: nsRange) else { return nil }
        return (1..<result.numberOfRanges).compactMap { index in
            guard let range = Range(result.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private func validCoordinateLikeValue(_ value: String) -> Double? {
        guard let number = Double(value), abs(number) < 499 else { return nil }
        return number
    }

    private static func validPercent(_ value: String) -> Int? {
        guard let number = Int(value), (0...100).contains(number) else { return nil }
        return number
    }

    static func stripANSI(from text: String) -> String {
        text.replacingOccurrences(
            of: #"\u{001B}\[[0-?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
    }
}

enum DemoTelemetry {
    static let lines = [
        "I bcmevtlog (wifid): evt_accu: 1: rate: 65000: 65000: 65000: 65000",
        "I bcmevtlog (wifid): extra_cnt: -42: -45: 0: 0: 1: 1: 1: 4: 1: 2: 0: -91: 49: 46: 4: 104: 0: 98: 0: 0",
        "I mpp (mppd): rssi_mpp:-42, rssi:-44, state:FLYING, altitude:18.400000, latitude:0.001000, longitude:0.001000, roll:0.041000, pitch:-0.082000, yaw:1.870000",
        "I proxy_drone (mppd): link_quality: tx_quality=96%, rx_quality=94%, rx_useful=98%",
        "I mpp (mppd): cpu:55°C, battery:83% (DISCHARGING)",
        "I bcmevtlog (wifid): extra_cnt: -44: -46: 0: 0: 1: 1: 1: 5: 1: 2: 0: -92: 48: 46: 4: 104: 0: 97: 0: 0",
        "I mpp (mppd): rssi_mpp:-44, rssi:-45, state:FLYING, altitude:19.100000, latitude:0.001200, longitude:0.001300, roll:-0.063000, pitch:0.035000, yaw:1.920000",
        "I proxy_drone (mppd): link_quality: tx_quality=94%, rx_quality=92%, rx_useful=97%",
        "I bcmevtlog (wifid): extra_cnt: -47: -49: 0: 0: 1: 1: 1: 6: 1: 3: 0: -92: 45: 43: 4: 104: 0: 95: 0: 0",
        "I mpp (mppd): rssi_mpp:-47, rssi:-48, state:FLYING, altitude:21.600000, latitude:0.001500, longitude:0.001700, roll:0.092000, pitch:0.071000, yaw:2.010000",
        "I proxy_drone (mppd): link_quality: tx_quality=91%, rx_quality=89%, rx_useful=95%"
    ]
}
