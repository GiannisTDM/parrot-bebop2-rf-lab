import AppKit

enum PreviewRenderer {
    static func render(to path: String) -> Bool {
        let hud = VideoHUDView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        hud.layoutSubtreeIfNeeded()

        let parser = SC2TelemetryParser()
        var snapshot = TelemetrySnapshot()
        for line in DemoTelemetry.lines { _ = parser.consume(line: line, into: &snapshot) }
        snapshot.connectionLabel = "Replay"
        snapshot.videoBitrateKbps = 4_860
        snapshot.videoPackets = 18_442
        snapshot.videoPacketsLost = 3
        snapshot.videoJitterMs = 2.7
        hud.update(snapshot: snapshot)
        hud.displayIfNeeded()

        guard let bitmap = hud.bitmapImageRepForCachingDisplay(in: hud.bounds) else { return false }
        hud.cacheDisplay(in: hud.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
            print(path)
            return true
        } catch {
            fputs("Preview render failed: \(error.localizedDescription)\n", stderr)
            return false
        }
    }
}
