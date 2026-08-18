# Bebop 2 video and SC2 restream map

This map is based on the extracted Bebop 2 4.4.2 and SkyController 2 1.0.9 firmware used by this project. Option meanings must not be carried across firmware generations without checking the installed binary.

## Bebop 2 configuration layers

The normal persistent ARDrone3 settings are stored in:

```text
/data/dragon.conf
```

The stock fallback is:

```text
/etc/default-dragon.conf
```

The fallback exposes settings including video autorecord, stabilization mode, recording mode, frame-rate enum and resolution mode. These are the settings normally manipulated through ARCommands/FreeFlight.

An independent startup-options layer is provided by the persistent property:

```text
persist.dragon-prog.post_cmd
```

`/usr/bin/DragonStarter.sh` reads that property with `gprop` and appends it verbatim to the `dragon-prog` command line. This is the most plausible location of historical persistent bitrate/latency experiments.

Read it without changing anything:

```sh
gprop persist.dragon-prog.post_cmd
```

The future Video Lab will preserve that exact value before offering any edit. It will also capture the running command line and `/data/dragon.conf` so file, property, and runtime state cannot be confused.

## `dragon-prog` 4.4.2 video options

The following strings come from the exact 4.4.2 ARM binary:

| Option | 4.4.2 description |
|---|---|
| `-V mode` | Video mode: `0` legacy, `1` recording priority, `2` streaming priority |
| `-b br` | Recording bitrate in Kbit/s |
| `-p preset` | Record encoder preset: `0` encoding-time priority, `1` quality priority |
| `-H mode` | Stream mode: `0` low latency, `1` high reliability, `2` high reliability/low frame rate |
| `-q br` | Maximum streaming bitrate in Kbit/s |
| `-s` | Disable streaming bitrate adaptation; constant stream bitrate |
| `-f fps` | Force 29.97, 25, or 23.976 FPS using `30`, `25`, or `24` |
| `-R mode` | Reprojection: `off`, `cpu`, or `gpu` |
| `-I mode` | Temporal-noise-reduction mode: `off`, `on`, `half`, `luma`, or `chroma` |
| `-S value` | Disable/enable stabilization |
| `-F path` | Dump H.264 stream |
| `-d path` | Dump raw Bayer video |
| `-k` | Video debug information; repeated `-k` increases the level |
| `-o` | Serialize FrameInfo in the video stream |
| `-O` | Serialize FrameInfo in the recording |

The binary directly calls the Hantro H1 encoder rate-control, coding-control and preprocessing APIs. `libdragonvideo` also exposes dynamic encoder and ARStream2 configuration calls. The public ARStream2 sender interface includes maximum bitrate, maximum total latency and per-importance-level network-latency controls.

## Critical cross-version warning

Old Bebop research describes different meanings for several short options. In particular, older versions used:

- `-V` for field of view;
- `-s` with a resolution argument for the live stream;
- a different meaning for `-H`.

On this project's **4.4.2** binary, `-V` is the video-priority mode, bare `-s` disables adaptive bitrate, and `-H` selects latency/reliability behavior. An old wide-angle or FPV startup command must therefore not be copied into 4.4.2.

## First controlled profiles to characterize

These are experiment definitions, not yet recommended permanent settings:

| Label | Candidate selectors | Purpose |
|---|---|---|
| Stock | Empty custom property | Baseline |
| Low latency | `-H 0 -V 2 -f 30` | Prioritize stream responsiveness while leaving bitrate adaptation active |
| Quality ceiling 3M | Previous selectors plus `-q 3000` | Establish low-load quality/latency point |
| Quality ceiling 5M | Previous selectors plus `-q 5000` | Historical short-range quality target |
| Reliable | `-H 1` with adaptation active | Measure resilience and additional latency |

Constant bitrate should remain off during the first tests. The adaptive controller is useful when a flight link encounters fading or interference. Only after measuring actual output bitrate, latency, loss, encoder errors, temperature and CPU load should `-s` be evaluated.

No profile should be changed while airborne. A future write path must require:

1. positive confirmation that the flight state is `LANDED`;
2. a timestamped copy of `/data/dragon.conf`;
3. preservation of the exact original persistent property;
4. an explicit diff/command preview;
5. a one-click stock restoration path.

## SkyController 2 video and HUD surface

SC2 1.0.9 `mppd` contains:

- the ARStream2 drone connection;
- client video and control bridges;
- a `/video` HTTP-style restream request;
- SDP output containing `c=IN IP4`, `m=video ... RTP/AVP 96`, and `a=rtpmap:96 H264/90000`;
- a persistent `mppd.restream.ip` property;
- separate normal and HUD restream contexts;
- live receiver-link-quality reporting;
- controller/drone HUD update functions.

Observed network roles:

| Endpoint | Role |
|---|---|
| TCP 44444 | ARSDK/controller service |
| UDP 5004 | ARStream2 drone-side video path |
| UDP 55004 | SC2 client stream port |
| UDP 55005 | SC2 client control port |
| TCP 6007 / 7711 | Unmapped SC2 listeners; Parrot Lab probes both for the `/video` endpoint |

The exact restream request port and destination-port behavior remain the first powered-hardware question for the macOS application. Parrot Lab records the complete response rather than embedding another assumption.

## Existing SC2 telemetry suitable for a HUD

With periodic logging enabled, `mppd` emits a compact state line at roughly HUD update rates containing:

```text
rssi_mpp, remote rssi, flight state, altitude, latitude, longitude,
roll, pitch, yaw
```

`wifid` separately emits per-chain RSSI/noise/rate values; `proxy_drone` emits transmit/receive/useful link quality; the SC2 health line supplies CPU temperature and controller battery. Parrot Lab 0.1 combines those existing sources without modifying either endpoint.

Native ARSDK ingestion remains preferable for the final application because it will also provide drone battery, speed, satellite count, home distance, alerts, record state and other structured events. Parrot's official native Bebop sample confirms that a computer controller can receive both command telemetry and the video stream.

## Primary public references

- [Parrot Bebop SDK reference](https://developer.parrot.com/docs/bebop/index.html)
- [Parrot native/mobile Bebop samples](https://github.com/Parrot-Developers/Samples)
- [Parrot libARStream2 sender interface](https://github.com/Parrot-Developers/libARStream2/blob/master/Includes/libARStream2/arstream2_stream_sender.h)
- [ARSDK protocols](https://developer.parrot.com/docs/bebop/ARSDK_Protocols.pdf)
