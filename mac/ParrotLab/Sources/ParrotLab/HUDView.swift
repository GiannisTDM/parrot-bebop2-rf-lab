import AppKit

final class VideoHUDView: NSView {
    let videoView = H264VideoView(frame: .zero)
    let overlayView = HUDOverlayView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.025, alpha: 1).cgColor

        videoView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(videoView)
        addSubview(overlayView)
        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoView.topAnchor.constraint(equalTo: topAnchor),
            videoView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(snapshot: TelemetrySnapshot) {
        overlayView.snapshot = snapshot
    }
}

final class HUDOverlayView: NSView {
    var snapshot = TelemetrySnapshot() {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        drawVignette(context)
        drawConnectionHeader()
        drawArtificialHorizon(context)
        drawRFPanel()
        drawFlightPanel()
        drawVideoPanel()
        drawCenterReticle(context)
    }

    private func drawVignette(_ context: CGContext) {
        let colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.58).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.55, 1.0]) else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            startRadius: 0,
            endCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            endRadius: max(bounds.width, bounds.height) * 0.7,
            options: []
        )
    }

    private func drawConnectionHeader() {
        let color: NSColor = snapshot.connectionLabel.contains("Live") ? .systemGreen :
            snapshot.connectionLabel.contains("Replay") ? .systemCyan : .systemOrange
        drawPill(snapshot.connectionLabel.uppercased(), at: CGPoint(x: 18, y: bounds.height - 36), color: color)
        drawText(
            "PARROT LAB  •  SC2 DIRECT",
            at: CGPoint(x: bounds.width - 230, y: bounds.height - 31),
            font: .monospacedSystemFont(ofSize: 11, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.72)
        )
    }

    private func drawArtificialHorizon(_ context: CGContext) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let roll = snapshot.roll ?? 0
        let pitch = snapshot.pitch ?? 0
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(-roll))
        context.translateBy(x: 0, y: CGFloat(pitch * 150.0))
        context.setStrokeColor(NSColor.systemCyan.withAlphaComponent(0.78).cgColor)
        context.setLineWidth(1.4)
        context.move(to: CGPoint(x: -92, y: 0))
        context.addLine(to: CGPoint(x: -22, y: 0))
        context.move(to: CGPoint(x: 22, y: 0))
        context.addLine(to: CGPoint(x: 92, y: 0))
        context.strokePath()

        for degree in stride(from: -20, through: 20, by: 10) where degree != 0 {
            let y = CGFloat(degree) * 2.2
            let halfWidth: CGFloat = degree % 20 == 0 ? 42 : 28
            context.move(to: CGPoint(x: -halfWidth, y: y))
            context.addLine(to: CGPoint(x: halfWidth, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawCenterReticle(_ context: CGContext) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        context.setLineWidth(1.5)
        context.move(to: CGPoint(x: center.x - 19, y: center.y))
        context.addLine(to: CGPoint(x: center.x - 6, y: center.y))
        context.addLine(to: CGPoint(x: center.x, y: center.y - 5))
        context.addLine(to: CGPoint(x: center.x + 6, y: center.y))
        context.addLine(to: CGPoint(x: center.x + 19, y: center.y))
        context.strokePath()
    }

    private func drawRFPanel() {
        let x: CGFloat = 18
        var y = bounds.height - 78
        drawText("RF LINK", at: CGPoint(x: x, y: y), font: .monospacedSystemFont(ofSize: 11, weight: .bold), color: .systemCyan)
        y -= 24
        drawSignalRow(label: "A0", value: snapshot.chain0RSSI, x: x, y: y)
        y -= 22
        drawSignalRow(label: "A1", value: snapshot.chain1RSSI, x: x, y: y)
        y -= 22
        drawSignalRow(label: "AVG", value: snapshot.chainAverage ?? snapshot.reportedRSSI, x: x, y: y)
        y -= 28
        drawText("NOISE  \(formatted(snapshot.noise, suffix: " dBm"))", at: CGPoint(x: x, y: y), font: mono(12), color: .white)
        y -= 19
        drawText("SNR    \(formatted(snapshot.snr, suffix: " dB"))", at: CGPoint(x: x, y: y), font: mono(12), color: .white)
        y -= 19
        drawText("LINK   \(formatted(snapshot.rxQuality, suffix: "%"))", at: CGPoint(x: x, y: y), font: mono(12), color: .white)
    }

    private func drawFlightPanel() {
        let x = bounds.width - 190
        var y = bounds.height - 78
        drawText("FLIGHT", at: CGPoint(x: x, y: y), font: .monospacedSystemFont(ofSize: 11, weight: .bold), color: .systemCyan)
        y -= 27
        drawText(snapshot.flightState, at: CGPoint(x: x, y: y), font: .monospacedSystemFont(ofSize: 17, weight: .bold), color: flightColor)
        y -= 30
        drawText("ALT  \(formatted(snapshot.altitude, digits: 1, suffix: " m"))", at: CGPoint(x: x, y: y), font: mono(13), color: .white)
        y -= 22
        drawText("ROLL \(angle(snapshot.roll))", at: CGPoint(x: x, y: y), font: mono(12), color: .white)
        y -= 20
        drawText("PITCH\(angle(snapshot.pitch))", at: CGPoint(x: x, y: y), font: mono(12), color: .white)
        y -= 20
        drawText("YAW  \(angle(snapshot.yaw))", at: CGPoint(x: x, y: y), font: mono(12), color: .white)

        if let battery = snapshot.sc2BatteryPercent {
            y -= 31
            drawText("SC2  \(battery)%", at: CGPoint(x: x, y: y), font: mono(13), color: batteryColor(battery))
        }
        if let temperature = snapshot.sc2TemperatureC {
            y -= 21
            drawText("CPU  \(temperature)°C", at: CGPoint(x: x, y: y), font: mono(12), color: temperature >= 75 ? .systemRed : .white)
        }
    }

    private func drawVideoPanel() {
        let y: CGFloat = 22
        let text = "RTP \(snapshot.videoBitrateKbps.map { "\($0) kbps" } ?? "waiting")   " +
            "PKT \(snapshot.videoPackets)   LOST \(snapshot.videoPacketsLost)   " +
            "JIT \(snapshot.videoJitterMs.map { String(format: "%.1f ms", $0) } ?? "—")"
        drawText(text, at: CGPoint(x: 18, y: y), font: mono(11), color: NSColor.white.withAlphaComponent(0.78))
    }

    private func drawSignalRow(label: String, value: Int?, x: CGFloat, y: CGFloat) {
        let color = signalColor(value)
        drawText(label, at: CGPoint(x: x, y: y), font: mono(12), color: NSColor.white.withAlphaComponent(0.8))
        let barRect = CGRect(x: x + 32, y: y + 1, width: 88, height: 8)
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 4, yRadius: 4).fill()
        if let value {
            let fraction = min(1, max(0, CGFloat(value + 70) / 70.0))
            color.setFill()
            NSBezierPath(roundedRect: CGRect(x: barRect.minX, y: barRect.minY, width: barRect.width * fraction, height: barRect.height), xRadius: 4, yRadius: 4).fill()
        }
        drawText(formatted(value, suffix: ""), at: CGPoint(x: x + 128, y: y), font: mono(12), color: color)
    }

    private func drawPill(_ text: String, at point: CGPoint, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: color
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(x: point.x, y: point.y, width: size.width + 18, height: 22)
        color.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11).fill()
        text.draw(at: CGPoint(x: rect.minX + 9, y: rect.minY + 4), withAttributes: attributes)
    }

    private func drawText(_ text: String, at point: CGPoint, font: NSFont, color: NSColor) {
        text.draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func signalColor(_ value: Int?) -> NSColor {
        guard let value else { return .secondaryLabelColor }
        if value <= -60 { return .systemRed }
        if value <= -40 { return blend(.systemRed, .systemYellow, fraction: CGFloat(value + 60) / 20) }
        if value <= -20 { return blend(.systemYellow, .systemGreen, fraction: CGFloat(value + 40) / 20) }
        if value <= -5 { return blend(.systemGreen, .systemCyan, fraction: CGFloat(value + 20) / 15) }
        return .systemCyan
    }

    private func blend(_ from: NSColor, _ to: NSColor, fraction: CGFloat) -> NSColor {
        from.blended(withFraction: min(1, max(0, fraction)), of: to) ?? to
    }

    private var flightColor: NSColor {
        switch snapshot.flightState {
        case "FLYING", "HOVERING": return .systemGreen
        case "EMERGENCY": return .systemRed
        case "LANDING", "TAKINGOFF": return .systemYellow
        default: return .white
        }
    }

    private func batteryColor(_ value: Int) -> NSColor {
        value <= 15 ? .systemRed : value <= 30 ? .systemYellow : .systemGreen
    }

    private func mono(_ size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .medium) }
    private func formatted(_ value: Int?, suffix: String) -> String { value.map { "\($0)\(suffix)" } ?? "—" }
    private func formatted(_ value: Double?, digits: Int, suffix: String) -> String {
        value.map { String(format: "%.*f%@", digits, $0, suffix) } ?? "—"
    }
    private func angle(_ radians: Double?) -> String {
        guard let radians else { return "    —" }
        return String(format: "%6.1f°", radians * 180.0 / .pi)
    }
}
