import AppKit

final class MainViewController: NSViewController {
    private let parser = SC2TelemetryParser()
    private let telnet = TelnetClient()
    private let restreamProbe = RestreamProbe()
    private let rtpReceiver = RTPH264Receiver()
    private var snapshot = TelemetrySnapshot()
    private var replayTimer: Timer?
    private var replayIndex = 0
    private var videoRunning = false
    private var videoStatus = "Restream idle"

    private let hudView = VideoHUDView(frame: .zero)
    private let hostField = NSTextField(string: "192.168.42.88")
    private let rtpPortField = NSTextField(string: "55004")
    private let connectButton = NSButton(title: "Connect SC2", target: nil, action: nil)
    private let replayButton = NSButton(title: "Replay demo", target: nil, action: nil)
    private let videoButton = NSButton(title: "Start video", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "Disconnected")
    private let rfLabel = NSTextField(labelWithString: "Waiting for RF telemetry")
    private let flightLabel = NSTextField(labelWithString: "Waiting for flight telemetry")
    private let healthLabel = NSTextField(labelWithString: "Waiting for controller health")
    private let videoLabel = NSTextField(labelWithString: "Restream idle")
    private let console = NSTextView(frame: .zero)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.055, alpha: 1).cgColor
        buildInterface()
        wireDataSources()
        updateInterface()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.title = "Parrot Lab — Bebop 2 / SkyController 2"
        view.window?.minSize = NSSize(width: 1050, height: 680)
    }

    private func buildInterface() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        root.addArrangedSubview(buildToolbar())

        let center = NSStackView()
        center.orientation = .horizontal
        center.spacing = 10
        center.distribution = .fill
        hudView.translatesAutoresizingMaskIntoConstraints = false
        hudView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        center.addArrangedSubview(hudView)
        let sidebar = buildSidebar()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: 288).isActive = true
        center.addArrangedSubview(sidebar)
        root.addArrangedSubview(center)

        let consoleScroll = NSScrollView()
        consoleScroll.hasVerticalScroller = true
        consoleScroll.borderType = .noBorder
        consoleScroll.wantsLayer = true
        consoleScroll.layer?.cornerRadius = 8
        consoleScroll.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        console.isEditable = false
        console.isSelectable = true
        console.drawsBackground = false
        console.textColor = NSColor.white.withAlphaComponent(0.72)
        console.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        console.textContainerInset = NSSize(width: 8, height: 6)
        consoleScroll.documentView = console
        consoleScroll.heightAnchor.constraint(equalToConstant: 105).isActive = true
        root.addArrangedSubview(consoleScroll)

        center.setContentHuggingPriority(.defaultLow, for: .vertical)
        center.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    private func buildToolbar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.alignment = .centerY
        bar.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let title = NSTextField(labelWithString: "PARROT LAB")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = .systemCyan
        bar.addArrangedSubview(title)

        let spacer = NSView()
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 12).isActive = true
        bar.addArrangedSubview(spacer)

        let hostLabel = NSTextField(labelWithString: "SC2")
        hostLabel.textColor = .secondaryLabelColor
        bar.addArrangedSubview(hostLabel)
        hostField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hostField.widthAnchor.constraint(equalToConstant: 130).isActive = true
        bar.addArrangedSubview(hostField)

        styleButton(connectButton, action: #selector(toggleConnection))
        styleButton(replayButton, action: #selector(toggleReplay))
        bar.addArrangedSubview(connectButton)
        bar.addArrangedSubview(replayButton)

        let portLabel = NSTextField(labelWithString: "RTP UDP")
        portLabel.textColor = .secondaryLabelColor
        bar.addArrangedSubview(portLabel)
        rtpPortField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        rtpPortField.widthAnchor.constraint(equalToConstant: 65).isActive = true
        bar.addArrangedSubview(rtpPortField)
        styleButton(videoButton, action: #selector(startVideo))
        bar.addArrangedSubview(videoButton)

        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .systemOrange
        statusLabel.alignment = .right
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(statusLabel)
        return bar
    }

    private func buildSidebar() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 9
        stack.alignment = .leading
        stack.addArrangedSubview(card(title: "RF LINK", body: rfLabel))
        stack.addArrangedSubview(card(title: "FLIGHT", body: flightLabel))
        stack.addArrangedSubview(card(title: "SC2 HEALTH", body: healthLabel))
        stack.addArrangedSubview(card(title: "VIDEO", body: videoLabel))

        let notice = NSTextField(wrappingLabelWithString: "Video controls are observational in this build. No RF or Dragon configuration is changed automatically.")
        notice.textColor = .secondaryLabelColor
        notice.font = .systemFont(ofSize: 11)
        notice.maximumNumberOfLines = 4
        notice.widthAnchor.constraint(equalToConstant: 264).isActive = true
        stack.addArrangedSubview(notice)
        return stack
    }

    private func card(title: String, body: NSTextField) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
        container.widthAnchor.constraint(equalToConstant: 288).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let heading = NSTextField(labelWithString: title)
        heading.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        heading.textColor = .systemCyan
        stack.addArrangedSubview(heading)
        body.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        body.textColor = NSColor.white.withAlphaComponent(0.84)
        body.maximumNumberOfLines = 6
        body.lineBreakMode = .byWordWrapping
        body.widthAnchor.constraint(equalToConstant: 264).isActive = true
        stack.addArrangedSubview(body)
        return container
    }

    private func styleButton(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .regular
    }

    private func wireDataSources() {
        telnet.onState = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.snapshot.connectionLabel = "Live SC2"
                self.statusLabel.stringValue = "LIVE"
                self.statusLabel.textColor = .systemGreen
                self.connectButton.title = "Disconnect"
            case .connecting:
                self.statusLabel.stringValue = "CONNECTING"
                self.statusLabel.textColor = .systemYellow
            case .failed(let message):
                self.snapshot.connectionLabel = "Disconnected"
                self.statusLabel.stringValue = "FAILED"
                self.statusLabel.textColor = .systemRed
                self.connectButton.title = "Connect SC2"
                self.appendLog("Connection failed: \(message)")
            case .stopped, .idle:
                if self.replayTimer == nil { self.snapshot.connectionLabel = "Disconnected" }
                self.statusLabel.stringValue = self.replayTimer == nil ? "DISCONNECTED" : "REPLAY"
                self.statusLabel.textColor = self.replayTimer == nil ? .systemOrange : .systemCyan
                self.connectButton.title = "Connect SC2"
            }
            self.updateInterface()
        }
        telnet.onLine = { [weak self] line in self?.consume(line: line) }
        telnet.onDebug = { [weak self] message in self?.appendLog(message) }
        restreamProbe.onDebug = { [weak self] message in self?.appendLog(message) }
        rtpReceiver.onDebug = { [weak self] message in self?.appendLog(message) }
        rtpReceiver.onAccessUnit = { [weak self] nalUnits in self?.hudView.videoView.display(nalUnits: nalUnits) }
        rtpReceiver.onStats = { [weak self] stats in
            guard let self else { return }
            self.snapshot.videoBitrateKbps = stats.bitrateKbps
            self.snapshot.videoPackets = stats.packets
            self.snapshot.videoPacketsLost = stats.packetsLost
            self.snapshot.videoJitterMs = stats.jitterMs
            self.updateInterface()
        }
    }

    @objc private func toggleConnection() {
        stopReplay()
        if connectButton.title == "Disconnect" {
            telnet.stop()
            return
        }
        let host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        appendLog("Connecting to SC2 Telnet at \(host):23")
        telnet.connect(host: host)
    }

    @objc private func toggleReplay() {
        if replayTimer != nil {
            stopReplay()
            return
        }
        telnet.stop()
        replayIndex = 0
        snapshot = TelemetrySnapshot()
        snapshot.connectionLabel = "Replay"
        replayButton.title = "Stop replay"
        statusLabel.stringValue = "REPLAY"
        statusLabel.textColor = .systemCyan
        appendLog("Replaying sanitized SC2 telemetry fixture")
        replayTimer = Timer.scheduledTimer(withTimeInterval: 0.34, repeats: true) { [weak self] _ in
            guard let self else { return }
            let line = DemoTelemetry.lines[self.replayIndex % DemoTelemetry.lines.count]
            self.replayIndex += 1
            self.consume(line: line)
        }
    }

    private func stopReplay() {
        replayTimer?.invalidate()
        replayTimer = nil
        replayButton.title = "Replay demo"
        if connectButton.title != "Disconnect" {
            snapshot.connectionLabel = "Disconnected"
            statusLabel.stringValue = "DISCONNECTED"
            statusLabel.textColor = .systemOrange
            updateInterface()
        }
    }

    @objc private func startVideo() {
        if videoRunning {
            restreamProbe.cancel()
            rtpReceiver.stop()
            hudView.videoView.reset()
            videoRunning = false
            videoButton.title = "Start video"
            videoStatus = "Restream idle"
            snapshot.videoBitrateKbps = nil
            snapshot.videoPackets = 0
            snapshot.videoPacketsLost = 0
            snapshot.videoJitterMs = nil
            updateInterface()
            appendLog("Video receiver stopped")
            return
        }
        guard let port = UInt16(rtpPortField.stringValue) else {
            appendLog("Invalid RTP UDP port")
            return
        }
        do {
            try rtpReceiver.start(port: port)
            videoRunning = true
            videoButton.title = "Stop video"
            videoStatus = "Listening UDP \(port) · probing SC2"
            updateInterface()
        } catch {
            appendLog("Could not open UDP \(port): \(error.localizedDescription)")
            return
        }

        let host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        restreamProbe.probe(host: host) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let descriptor):
                let announced = descriptor.videoPort.map(String.init) ?? "not announced"
                self.videoStatus = "SC2 TCP \(descriptor.requestPort) · RTP \(announced)"
                self.appendLog("Restream response: \(descriptor.response.replacingOccurrences(of: "\r\n", with: " | "))")
                if let announcedPort = descriptor.videoPort, announcedPort != port {
                    self.appendLog("SC2 announced UDP \(announcedPort); switching receiver from \(port)")
                    do {
                        try self.rtpReceiver.start(port: announcedPort)
                        self.rtpPortField.stringValue = String(announcedPort)
                    } catch {
                        self.appendLog("Could not bind announced UDP port: \(error.localizedDescription)")
                        self.videoStatus = "SC2 announced UDP \(announcedPort) · bind failed"
                    }
                }
                self.updateInterface()
            case .failure(let error):
                self.videoStatus = "UDP \(port) ready · probe unavailable"
                self.appendLog("Restream probe: \(error.localizedDescription)")
                self.updateInterface()
            }
        }
    }

    private func consume(line: String) {
        if parser.consume(line: line, into: &snapshot) { updateInterface() }
    }

    private func updateInterface() {
        hudView.update(snapshot: snapshot)
        rfLabel.stringValue = [
            "A0 \(dbm(snapshot.chain0RSSI))   A1 \(dbm(snapshot.chain1RSSI))",
            "AVG \(dbm(snapshot.chainAverage ?? snapshot.reportedRSSI))",
            "NOISE \(dbm(snapshot.noise))   SNR \(number(snapshot.snr, "dB"))",
            "RX \(number(snapshot.rxQuality, "%"))   USEFUL \(number(snapshot.rxUseful, "%"))",
            "PHY \(snapshot.phyRateMbps.map { String(format: "%.1f Mbps", $0) } ?? "—")"
        ].joined(separator: "\n")

        flightLabel.stringValue = [
            snapshot.flightState,
            "ALT \(snapshot.altitude.map { String(format: "%.1f m", $0) } ?? "—")",
            "ROLL \(degrees(snapshot.roll))",
            "PITCH \(degrees(snapshot.pitch))",
            "YAW \(degrees(snapshot.yaw))"
        ].joined(separator: "\n")

        healthLabel.stringValue = [
            "BATTERY \(number(snapshot.sc2BatteryPercent, "%"))",
            "CPU \(number(snapshot.sc2TemperatureC, "°C"))",
            snapshot.sc2PowerState ?? "—"
        ].joined(separator: "\n")

        videoLabel.stringValue = [
            videoStatus,
            "RTP \(snapshot.videoBitrateKbps.map { "\($0) kbps" } ?? "waiting")",
            "PACKETS \(snapshot.videoPackets)",
            "LOST \(snapshot.videoPacketsLost)",
            "JITTER \(snapshot.videoJitterMs.map { String(format: "%.1f ms", $0) } ?? "—")"
        ].joined(separator: "\n")
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        console.textStorage?.append(NSAttributedString(
            string: line,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.74)]
        ))
        console.scrollToEndOfDocument(nil)
    }

    private func dbm(_ value: Int?) -> String { value.map { "\($0) dBm" } ?? "—" }
    private func number(_ value: Int?, _ suffix: String) -> String { value.map { "\($0)\(suffix)" } ?? "—" }
    private func degrees(_ value: Double?) -> String {
        value.map { String(format: "%.1f°", $0 * 180 / .pi) } ?? "—"
    }
}
