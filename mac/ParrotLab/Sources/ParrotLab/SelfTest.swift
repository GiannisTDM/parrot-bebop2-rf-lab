import Foundation

enum ParrotLabSelfTest {
    static func run() -> Int32 {
        let parser = SC2TelemetryParser()
        var snapshot = TelemetrySnapshot()

        guard parser.consume(
            line: "I mpp (mppd): rssi_mpp:-42, rssi:-48, state:FLYING, altitude:21.5, latitude:38.1, longitude:21.7, roll:0.1, pitch:-0.2, yaw:1.5",
            into: &snapshot
        ), snapshot.sc2RSSI == -42,
           snapshot.reportedRSSI == -48,
           snapshot.flightState == "FLYING",
           snapshot.altitude == 21.5,
           snapshot.pitch == -0.2 else {
            fputs("Self-test failed: flight telemetry parser\n", stderr)
            return 1
        }

        _ = parser.consume(
            line: "I bcmevtlog (wifid): extra_cnt: -37: -44: 0: 0: 1: 1: 1: 4: 1: 2: 0: -92: 22: 21: 4: 104: 0: 100: 0: 0",
            into: &snapshot
        )
        _ = parser.consume(
            line: "I proxy_drone (mppd): link_quality: tx_quality=-1%, rx_quality=99%, rx_useful=100%",
            into: &snapshot
        )
        guard snapshot.chain0RSSI == -37,
              snapshot.chain1RSSI == -44,
              snapshot.noise == -92,
              snapshot.rxQuality == 99,
              snapshot.rxUseful == 100,
              snapshot.txQuality == nil else {
            fputs("Self-test failed: RF telemetry parser\n", stderr)
            return 1
        }

        var sentinel = TelemetrySnapshot()
        _ = parser.consume(
            line: "rssi_mpp:-16, rssi:-20, state:LANDED, altitude:500.000000, latitude:500.000000, longitude:500.000000, roll:0.0, pitch:0.0, yaw:0.0",
            into: &sentinel
        )
        guard sentinel.altitude == nil, sentinel.latitude == nil, sentinel.longitude == nil else {
            fputs("Self-test failed: invalid-coordinate sentinel handling\n", stderr)
            return 1
        }

        let sdp = "HTTP/1.1 200 OK\r\n\r\nc=IN IP4 192.168.42.88\nm=video 55004 RTP/AVP 96\n"
        guard RestreamProbe.firstCapture(#"m=video\s+(\d+)"#, in: sdp) == "55004" else {
            fputs("Self-test failed: restream SDP parser\n", stderr)
            return 1
        }

        guard RTPH264Receiver.assemblySelfTest() else {
            fputs("Self-test failed: RTP/H.264 assembler\n", stderr)
            return 1
        }

        print("Parrot Lab self-test passed")
        return 0
    }
}
