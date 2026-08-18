# Parrot Lab for macOS

Parrot Lab is a native macOS HUD and diagnostic client for the Parrot SkyController 2 and Bebop 2. It is intentionally built from Apple system frameworks rather than Electron or an embedded browser.

Version 0.1 provides:

- direct, read-only Telnet connection to the SC2 at `192.168.42.88`;
- parsing of the SC2's existing `mppd`, `wifid`, and link-quality telemetry;
- per-chain RSSI, noise, SNR, PHY rate, flight state, altitude, attitude, controller battery and temperature;
- a graphical video HUD with the RF Lab red/yellow/green/cyan signal gradient;
- an artificial horizon and live link/video statistics;
- a sanitized replay mode that works without either device;
- SC2 `/video` restream discovery on the two listeners observed in firmware 1.0.9;
- a UDP/RTP H.264 receiver with FU-A and STAP-A reassembly and low-latency AVFoundation display;
- an ad-hoc-signed, double-clickable Apple-silicon `.app` bundle.

The program performs no RF, NVM, Dragon, or flight-setting writes in this release.

## Requirements

- macOS 13 or later on Apple silicon;
- SC2 and Bebop 2 powered and associated;
- a network route from the Mac to `192.168.42.88`;
- the project's explicitly enabled SC2 Telnet service on TCP 23;
- Local Network access when macOS requests it.

The HUD's replay mode has no hardware or network requirement.

## Build the application

From this directory:

```sh
./scripts/build-app.sh
```

The signed bundle is created at:

```text
dist/Parrot Lab.app
dist/Parrot-Lab-macOS-arm64.zip
```

You can also build and test only the executable:

```sh
swift build
.build/debug/ParrotLab --self-test
```

For an off-screen HUD render suitable for UI regression checks:

```sh
.build/debug/ParrotLab --render-preview /tmp/parrot-lab-preview.png
```

## First launch without hardware

1. Open `Parrot Lab.app`.
2. Select **Replay demo**.
3. Confirm that the RF bars, artificial horizon, flight data, link quality, SC2 health, and status cards update.
4. Select **Stop replay** when finished.

The replay contains sanitized representative values, not a simulated flight model.

## Connect to the SkyController 2

1. Power the Bebop 2 and SC2 and wait for their link to settle.
2. Connect the Mac using the established USB/network route.
3. Leave the default SC2 address `192.168.42.88`, or replace it with the current DHCP address.
4. Select **Connect SC2**.

The app opens a Telnet connection and starts `ulogcat`. It does not log in with a credential and it does not write any device configuration. The captured lines are parsed locally; the full raw feed is not retained by default.

The SC2 already publishes the key HUD line at approximately five updates per second:

```text
rssi_mpp, rssi, flight state, altitude, latitude, longitude, roll, pitch, yaw
```

It separately publishes per-chain Broadcom values, link-quality percentages, controller temperature, and controller battery.

Values of `500` used by `mppd` as unavailable altitude/position sentinels are deliberately shown as unavailable rather than as real telemetry.

## Experimental live video

Select **Start video** after the SC2 telemetry connection is working.

The app:

1. opens the requested local UDP port, initially `55004`;
2. probes the SC2's observed TCP listeners `7711` and `6007` with its built-in `GET /video` request;
3. parses any returned SDP address and video port;
4. switches the local listener if the SC2 announces another port;
5. accepts H.264/RTP payload type 96 and displays decoded access units immediately.

The request/port assumptions come from the exact SC2 1.0.9 `mppd` binary and have not yet been exercised against a powered controller from this build. The console records the complete discovery response so the next live session can finish this mapping without another firmware excavation.

If the endpoint probe fails while UDP remains ready, this does not affect SC2 control or the telemetry HUD. It means the restream handshake needs to be adjusted from the captured live response.

## Why the app runs on the Mac

The drone should spend its resources on stabilization, encoding, networking, and flight control. Drawing the HUD on the Mac means:

- no extra graphics work on the BB2;
- no overlay burned permanently into recordings;
- no additional video encode generation;
- easier logging, plotting, and future layout changes;
- the ability to merge SC2 receive statistics with drone telemetry.

## Planned suite modules

- native ARSDK telemetry ingestion for drone battery, speed, home distance, satellites and events;
- verified SC2 video restream negotiation and recorded-stream playback;
- Video Lab with backed-up, firmware-aware `dragon-prog` profiles;
- RF Lab NVM inspection and editing through the same safety checks as the BusyBox tool;
- synchronized flight, RF and video experiment bundles;
- live graphs, CSV export and an optional minimal fullscreen flight layout;
- a strict landed-state interlock before any configuration write.

Old Bebop camera options changed meaning across firmware generations. The future Video Lab must inspect the installed firmware and current `persist.dragon-prog.post_cmd` value before offering a preset.
