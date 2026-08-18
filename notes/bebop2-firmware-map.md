# Bebop 2 firmware map

Status: first-pass map, 2026-08-18. No flight, RF, calibration, or persistent setting was changed.

## Evidence and confidence

- `LIVE` means observed on the connected Bebop 2 through the Telnet relay.
- `FW` means read from the official Bebop 2 4.4.2 PLF filesystem.
- `INFERENCE` is a conclusion supported by those observations but not yet traced instruction-by-instruction.

Primary local evidence:

- Official image: `firmware/sources/bebop2-4.4.2.plf`
  - MD5 `fe06121568cab659e9a35ca0fbd50b75`
  - SHA-256 `e6d8824259225db88901f0d89b3b01572a8a9287912a4e3e0e20d63c3bd0f105`
- Extracted filesystem and manifests: `firmware/bebop2-4.4.2/`
- Initial live capture: `captures/initial-wifi-capture/codex_capture/`
- Reproducible extractor: `tools/extract_plf.py`
- Read-only relay capture: `capture_bebop_via_relay.sh`

The PLF has 1,381 sections and 1,377 filesystem entries: 830 regular files, 408 symlinks, and 131 directories after extraction.

## System identity

| Item | Finding |
|---|---|
| Product/build | `ardrone3-milos-4.4.2`, original UID `ardrone3-milos-4.4.2-rc3` (`LIVE`, `FW`) |
| Kernel | Linux 3.4.11+, ARMv7, built 2018-02-14 (`LIVE`) |
| Board | Milos revision 2 (`LIVE`) |
| CPU | Two ARM Cortex-A9-class cores (`CPU part 0xc09`) (`LIVE`) |
| RAM | 297,016 KiB total, no swap (`LIVE`) |
| Main process | `/usr/bin/dragon-prog`, 34 threads, about 40 MiB resident (`LIVE`) |
| BLDC firmware | `6.6.R.4` (`LIVE`) |
| Wi-Fi firmware/driver | Broadcom `6.37.114.64 (r516176)` (`LIVE`) |

## Boot and service sequence

```text
eCos bootloader
  -> Linux 3.4.11, read-only UBIFS system
  -> /sbin/init (boxinit)
  -> /etc/boxinit.rc + boxinit.d + hardware-specific standalone rc
  -> /etc/init.d/rcS
  -> mount/initialize eMMC, sensors, cameras, GPS, GPU, Wi-Fi, updater
  -> BLDC_Host_Bootloader verifies/flashes /lib/firmware/BLDC.cyacd
  -> first-boot FVT6 gate
  -> running_mode.sh
  -> rcS_mode_default
  -> DragonStarter.sh
  -> /usr/bin/dragon-prog
```

Important files:

| Path | Role |
|---|---|
| `/etc/boxinit.rc` | Base init, properties, data directories, service classes |
| `/etc/boxinit.standalone.milosboard.rc` | Symlink to the Mykonos3-board service sequence; BLDC flash/FVT/running-mode gates |
| `/etc/init.d/rcS` | Main hardware and filesystem initialization |
| `/usr/bin/running_mode.sh` | Selects `rcS_mode_${persist.running-mode}`, defaulting to `default` |
| `/etc/init.d/rcS_mode_default` | Launches stock Dragon |
| `/usr/bin/DragonStarter.sh` | Applies debug options and starts `dragon-prog` |
| `/etc/debug.conf` | Core dump, blackbox, video, NMEA, CKCM, and system-monitor controls |

`DragonStarter.sh` also reads property `persist.dragon-prog.post_cmd`. This is a hidden argument-injection/debug hook for Dragon, but it is persistent and must not be changed casually.

## Storage and persistence

| Backing store | Partition/mount | Live state |
|---|---|---|
| NAND MTD0 | `Pbootloader`, 8 MiB | bootloader |
| NAND MTD1 | `Pmain_boot`, 16 MiB | kernel/main boot |
| NAND MTD2 / UBI0 | `Pfactory`, 8 MiB; `/factory` | read-only factory calibration |
| NAND MTD3 / UBI1 | `Psystem`, 50 MiB; `/` | read-only, 42.2 MiB usable, 96% occupied |
| NAND MTD4 / UBI2 | `Pupdate`, 46 MiB split into `/data` and `/update` | writable |
| eMMC | `/dev/mmcblk0` at `/data/ftp/internal_000` | ext4, 7.2 GiB, 818.5 MiB free during capture |

Persistent user settings are JSON in `/data/dragon.conf`. Live values were:

| Setting | Live value |
|---|---:|
| Maximum altitude | 150 m |
| Maximum pitch/roll tilt | 20 deg |
| Maximum vertical speed | 3.3 m/s |
| Maximum yaw rotation speed | 80 deg/s |
| Maximum angular rate | 190 deg/s |
| Maximum distance | 1,000 m |
| Banked turn | enabled |
| Geofence/no-fly-over-max-distance | enabled |
| Wi-Fi country | DE |
| Wi-Fi band/channel | 2.4 GHz, channel 7 |

These are user-facing requested settings, not proof of physical headroom.

## Network and developer interfaces

### Live listeners

| Port | Purpose/status |
|---:|---|
| TCP 21 | FTP, root `/data/ftp`, writable |
| TCP 51 | FTP, root `/update`, writable |
| TCP 61 | FTP, root `/data/ftp/internal_000/flightplans`, writable |
| TCP 23 | root Telnet shell through `/bin/login.sh`; no password prompt observed |
| TCP 9050 | ADB in TCP mode, configured by `/etc/adb.conf`; not a USB ADB interface |
| TCP 44444/44445 | Dragon/ARSDK listeners; exact legacy/new split still to confirm |
| UDP 54321 | Dragon network socket |
| UDP 14551 | MAVLink/flight-plan-related socket |
| UDP 67 | DHCP server |

During the live session Dragon also had a connected UDP socket from a dynamic local port to the Skycontroller at port 9988. Discovery response strings expose FTP ports 21/51 and ARStream2 video ports 5004/5005.

### USB networking

`/bin/usbnetwork.sh` adds RNDIS, assigns `192.168.43.1/24`, starts DHCP, Telnet, and TCP ADB. The USB descriptor exposes MTP/PTP plus RNDIS; it does not expose an ADB USB interface. The Mac saw host-to-drone RNDIS traffic but no return packets, consistent with a legacy gadget/host compatibility problem rather than a missing drone route.

The efficient workaround is a Terminal-owned loopback relay:

```sh
/opt/homebrew/bin/socat TCP-LISTEN:2323,bind=127.0.0.1,reuseaddr,fork TCP:192.168.42.1:23
```

Codex can then use Telnet at `127.0.0.1:2323` while the Mac keeps Internet through iPhone USB tethering.

## Wi-Fi and RF path

### Component chain

```text
BCM43526 USB device (0a5c:bd1d)
  -> udev 50-network.rules
  -> /sbin/broadcom_setup.sh insmod
  -> bcm_dbus.ko + proprietary wl.ko
  -> /lib/firmware/brcm/bcm43526-firmware.bin
  -> /lib/firmware/brcm/bcm43526.nvm
  -> eth0 in AP mode at 192.168.42.1
  -> bcmwl / libBroadcomBWL / libnetmon-bcm43526b
  -> SKY85803 front ends, chains A0/A1
```

`broadcom_setup.sh` contains the complete AP startup transaction:

1. Load `bcm_dbus.ko` and `wl.ko`.
2. Bring up `eth0` and DNS/DHCP.
3. Take the Broadcom interface down for configuration.
4. Disable roaming.
5. Limit AMPDU RX window to one packet to reduce command lag.
6. Enable RX STBC and automatic TX STBC.
7. Select regulatory country.
8. Force RTS/CTS.
9. Disable short guard interval and 802.11ac.
10. Select a 20 MHz channel, enable AP mode, protect access, set SSID, and bring the interface up.
11. Disable legacy g-mode protection and set interference override mode 6.

Relevant implementation is in `firmware/bebop2-4.4.2/rootfs/sbin/broadcom_setup.sh`, especially lines 61-92 and 95-184.

### Live radio state

| Query | Result |
|---|---|
| `bcmwl ver` | 6.37.114.64 (r516176) |
| `bcmwl revinfo` | vendor 14e4, device 43a0, chip aa06 rev 3, board 0623 rev P452, PHY 11 rev 1 |
| `bcmwl status` | AP/managed presentation, channel 7, 20 MHz, noise -88 dBm |
| `bcmwl country` | `DE (DE/20) GERMANY` |
| `bcmwl qtxpower` | `127 (0x7f)` |
| `bcmwl txchain` / `rxchain` | `3` / `3`, meaning both A0 and A1 enabled |
| `bcmwl nrate` | MCS 7, STF mode 2, auto |
| `bcmwl rate` | 65 Mbps |
| `bcmwl mpc` | 1 |
| `bcmwl interference_override` | 6 |

`qtxpower=127` is a requested quarter-dBm ceiling (31.75 dBm), not proof that 31.75 dBm reaches the antenna. Regulatory rules, per-rate backoff, NVRAM maxima, TSSI control, PA response, and losses can all clamp the actual output.

### Terminal signal logger

`tools/bebop_signal_logger.py` is a read-only replacement for the unavailable PES utility. It connects to the Bebop Telnet shell, discovers the associated Skycontroller, and logs the Bebop's per-chain received signal, aggregate RSSI/noise/SNR, link rates, packet counts, TX-failure deltas, channel, and battery level. It writes both CSV and unprocessed command output under `measurements/` and requires only the Mac's standard Python 3 installation.

`tools/pes_live_busybox.sh` is the on-drone counterpart. It runs under the stock BusyBox `ash` shell and reproduces the original PES scrolling terminal layout: A0/A1, SNR, noise, global TX-failure count, last RX rate, and the associated station's IP address. It requires neither Python nor an installed package on the Bebop.

Use a label for controlled comparisons so it is stored in every CSV row:

```sh
python3 tools/bebop_signal_logger.py --label stock --samples 60
python3 tools/bebop_signal_logger.py --label epa2 --samples 60
```

With no explicit host it tries the loopback relay at `127.0.0.1:2323` and then the direct Bebop address at `192.168.42.1:23`. All radio commands issued by the logger are getters; it does not modify RF or flight settings. The logger is a relative A/B instrument, not a conducted-power meter: fixed separation, orientation, band, channel, traffic, and surroundings are required, and dBm RSSI differences must not be converted directly into transmitter milliwatts.

### NVRAM and RF calibration

The NVRAM explicitly identifies `BCM943526USB`, `SKY85803`, and A2 silicon. Key raw values:

| Parameter | Value | Interpretation |
|---|---:|---|
| `aa2g`, `aa5g` | `0x3`, `0x3` | both antenna chains available |
| `txchain`, `rxchain` | `0x3`, `0x3` | both chains enabled |
| `pdgain2g`, `pdgain5g` | 7, 7 | PA detector gain selection; calibration-sensitive |
| `femctrl` | 1 | selects built-in FEM control table 1; not a Boolean enable |
| `maxp2ga0`, `maxp2ga1` | 76, 76 | 19 dBm in quarter-dBm representation, before other constraints |
| `maxp5ga0`, `maxp5ga1` | 72 per sub-band | 18 dBm in quarter-dBm representation |
| `sar2g`, `sar5g` | 18, 15 | raw SAR caps; driver-specific interpretation |
| `pa2ga*`, `pa5ga*` | per-chain tables | PA calibration coefficients; do not edit blindly |

The live driver loads `/lib/firmware/brcm/bcm43526.nvm` directly. On this Bebop image there is no boot-time copy from `/factory`; the factory-copy question remains specific to the Skycontroller 2 layout.

`tools/parrot_rf_lab.sh` supersedes the two device-specific PES-style monitors for controlled RF experiments. The same BusyBox script auto-detects Bebop 2 versus SkyController 2, labels the incoming RF direction, separates last-frame PHY rate from measured byte-counter throughput, logs per-peer and global error deltas, exports snapshots, and provides a staged/verified NVM editor with FTP-visible backups. Its empirical parameter matrix and primary documentation links are recorded in `notes/bcm43526-rf-experiment-notes.md`.

`country_regul.yaml` describes legal channel availability and nominal power ceilings. `device_perf.yaml` supplies per-device TX power and RX gain for link-distance estimation. These tables feed `libnetmon-bcm43526b.so`; they are not evidence that changing a YAML number directly programs the PA.

Exported/embedded Broadcom iovars already confirmed in `libnetmon-bcm43526b.so` include:

```text
autocountry_default bw_cap rxchain txchain ampdu_rts rtsthresh
ampdu_rx ampdu_tx ampdu_ba_wsize_rx ampdu_ba_wsize_tx autocountry
stbc_rx stbc_tx sgi_rx sgi_tx mimo_bw_cap vhtmode chanspec
```

## Flight control architecture

`dragon-prog` links the ARSDK networking stack, `libdrone`, Parrot's Colibry controller, hardware abstraction, vision, GPS, video, and Broadcom networking into one process.

Live thread names reveal the major pipeline:

```text
hal -> colibry -> Behaviour -> CmdsRecv/ARNtwkRecv/ARNtwkSend
ms5607 + ultrasound + GPS + Vision + camera/video threads
MassStorage + MAVLink flight-plan threads + NetworkMonitor
```

Dragon's important live device ownership:

| Device | Function |
|---|---|
| `/dev/i2c-0` | P7MU/power management and camera-control devices |
| `/dev/i2c-1` | Cypress BLDC controller, AK8963 magnetometer, MS5607 barometer |
| `/dev/i2c-2` | MPU6050 gyro/accelerometer |
| `/dev/ttyPA1` | GPS UART at 115200 baud |
| `/dev/spidev1.0` | P7 ultrasound path |
| `/dev/video0..4`, V4L subdevices | front/bottom camera and processing pipeline |
| `/dev/hx280a` | H.264 encoder |
| `/dev/mali`, `/dev/ump`, `/dev/p7ump` | GPU/video memory |

The GPS mapping corrects an early mistaken inference: `/dev/ttyPA1` is not the motor bus.

## Motors and BLDC controller

### Command path

```text
ARSDK piloting command
  -> Dragon Behaviour/API
  -> Colibry attitude/position controllers
  -> RPM command output
  -> libHAL
  -> Cypress BLDC controller on /dev/i2c-1
  -> four motor/ESC channels
```

The active Colibry mode uses RPM commands and receives RPM observations. The exact airframe model is in `etc/colibry/milosboard/drone.cfg`:

| Parameter | Value |
|---|---:|
| `motorsRpmMax` | 12,200 RPM on all four motors |
| `motorsRpmMin` | 3,000 RPM on all four motors |
| `motorsKv` | 1,630 RPM/V |
| airframe mass | 0.500 kg |
| `motorA` thrust coefficient | `2.15e-8 N/RPM²` per motor |
| `motorB` yaw-torque coefficient | alternating `±2.85e-10 N·m/RPM²` |
| motor arm coordinates | X ±0.0875 m, Y ±0.115 m |
| PWM representation | 0-255, but this airframe's active command mode is RPM |

`dragon-prog` contains a lower-level HAL assertion that each requested motor speed is no greater than 16,000 RPM. That is a protocol/software bound, **not** a safe operating value and not evidence that the stock propulsion system has headroom above 12,200 RPM.

The BLDC bootloader hashes `/lib/firmware/BLDC.cyacd`, compares it with `/data/.BLDC_flashed.md5`, and flashes only when needed. Live boot logs reported MD5 `8A7D6E8CA3E15142F5D59771B7165B95` and firmware `6.6.R.4`.

### BLDC protection model

Strings in Dragon and `BLDC_Test_Bench` enumerate hardware-enforced error classes:

- motor stalled/low speed;
- propeller shock/security event;
- communication timeout;
- H-bridge over-current, voltage drop, or over-temperature;
- scheduler real-time fault;
- invalid motor setting;
- Cypress/BLDC temperature out of bounds;
- battery voltage out of bounds or wrong LiPo cell count;
- self-test MOSFET/phase failure;
- EEPROM and firmware-flash errors.

The BLDC EEPROM contains settings for rated speed, cell count and voltage limits, motor pole pairs, PWM frequency, timing, ramp voltages/speeds/durations, PID gains, feed-forward, minimum speed, maximum acceleration, saturation and cutout thresholds, communication timeout, temperature bounds, and maximum error counts. Their exact stock numeric values are not in the filesystem configs and have not yet been read.

`BLDC_Test_Bench` exposes those settings, but even its read operations contend with Dragon for `/dev/i2c-1`. Do not run it while Dragon owns the flight-control bus. A later bench-only session can cleanly stop Dragon, read `-I` and `-a`, then reboot without writing anything.

### Flight-control ceilings surrounding RPM

Important internal Colibry values, distinct from current user settings:

| Internal limit/model | Value |
|---|---:|
| maximum manual attitude reference | 35 deg pitch/roll |
| maximum horizontal speed model | 12 m/s |
| maximum horizontal acceleration | 3 m/s² |
| maximum vertical speed model | 6 m/s |
| maximum vertical acceleration, normal flight | 6 m/s² |
| internal maximum altitude config | 1,000 m |
| flight-plan velocity maximum | 10 m/s |
| RTH speed | 8 m/s |
| RTH height | 20 m |

These are controller clamps and model parameters, not a recommendation to expose their maxima through user settings. Horizontal speed can be limited by angle reference, attitude control, aerodynamic drag, position controller, battery power, and motor RPM independently.

## Battery model

The firmware does not use a smart battery (`smartBatteryIsUsed=false`). It estimates state from filtered voltage plus a model and a 29-point voltage-to-percentage table.

Key values:

| Parameter | Value |
|---|---:|
| estimated no-load shutdown voltage | 9.3 V |
| modeled battery energy | 29.97 Wh |
| modeled hover/landing/RTH power | 91 W |
| minimum percentage for low-battery alert | 10% |

The attached pack is 4,000 mAh (about 44.4 Wh nominal for a 3S/11.1 V pack), not 6,000 mAh as initially assumed. Its extra capacity is still not represented by the hard-coded 29.97 Wh model. The displayed percentage and remaining-flight-time logic therefore should not be interpreted as a direct coulomb count for that pack. During the first live mapping session the reported value fell from 22% to 19%; that capture was stopped at that point.

## Sensors and cameras

| Component | Bus/path | Role |
|---|---|---|
| MPU6050 | I2C2; synchronized by a ~32 kHz PWM clock | gyro/accelerometer |
| AK8963 | I2C1 | magnetometer |
| MS5607 | I2C1, dedicated Dragon thread | barometer |
| P7US | SPI1 | ultrasound altimeter |
| GPS | `/dev/ttyPA1`, 115200 baud | GNSS; ephemeris managed by `ephemerisd` |
| P7MU | I2C0 plus ADC/IIO | power management, voltage/temperature acquisition |
| MT9F002 | I2C0/V4L | front camera |
| MT9V117 | I2C0/V4L | vertical camera |
| Mali/HX280 | GPU and encoder devices | stabilization/video encoding |

The IMU has a PWM-controlled heating resistor and a fan GPIO. Factory storage contains per-unit IMU temperature bias/orthogonality and camera calibration; these files must remain untouched.

## Hidden or unusual interfaces

- Four short button presses run `/bin/usbnetwork.sh`, enabling RNDIS, Telnet, ADB, and optional debug daemons.
- Three short presses attempt to replace stock Dragon with an ArduCopter binary from `/data/ftp/internal_000/ardupilot/arducopter`. The stock PLF ships the integration wrapper and service declaration, but not the ArduCopter executable.
- `dragon_ipc.sh` talks to `unix:@/com/parrot/dragon_ipc` with message 0 for shutdown and message 1 for forced Wi-Fi band.
- `/etc/profile` defines a GDB server shortcut on TCP 1111.
- `debug.conf` can enable CKCM, blackbox, NMEA, frame-info, dynamic kernel debugging, or memory monitoring.
- `ssr` can record to `/data/ftp/internal_000/Debug/current/ssr` when property `persist.enable_ssr=1`.
- Netdata, LTTng, telemetryd, and ADB exist but are normally disabled or conditional.
- `/etc/manifest.xml` preserves exact internal component Git revisions, useful for matching public Parrot source trees to stripped binaries.

## Safe read-only queries

These are safe while landed and do not alter configuration:

```sh
ulogcat -d 2>/dev/null | sed -n 's/.*Battery percentage : *\([0-9][0-9]*\).*/\1%/p' | tail -n 1
uname -a
cat /etc/build.prop
cat /proc/cmdline
cat /proc/mtd
mount
df -h
ps w
cat /proc/modules
ifconfig -a
route -n
netstat -an
cat /data/dragon.conf
gprop ro.hardware
gprop ro.build.version
gprop state.wifi
```

Safe Broadcom queries:

```sh
bcmwl -i eth0 ver
bcmwl -i eth0 revinfo
bcmwl -i eth0 status
bcmwl -i eth0 channel
bcmwl -i eth0 chanspec
bcmwl -i eth0 country
bcmwl -i eth0 qtxpower
bcmwl -i eth0 txchain
bcmwl -i eth0 rxchain
bcmwl -i eth0 nrate
bcmwl -i eth0 rate
bcmwl -i eth0 rateset
bcmwl -i eth0 mpc
bcmwl -i eth0 interference
bcmwl -i eth0 counters
```

`bcmwl curpower` failed because the interface was in power-save control (`mpc=1`). Do not disable MPC merely to satisfy that query during normal operation.

## State-changing or hazardous interfaces

Do not run these without a specific test plan and backup:

- any `bcmwl` query name followed by a value, especially `qtxpower`, `txchain`, `rxchain`, `country`, `chanspec`, `phy_txpwrindex`, `pavars`, `sar`, `down`, `up`, or `reboot`;
- edits to `bcm43526.nvm`, especially PA calibration, PDET/TSSI, FEM, chain, SAR, and per-rate power fields;
- `BLDC_Test_Bench -S`, `-D`, `-R`, `-A`, `-E`, `-w`, `-G`, `-s`, `-m`, `-b`, `-F`, `-K`, or `-Z`;
- running any BLDC bench operation while Dragon owns `/dev/i2c-1`;
- property writes with `sprop`, `persist.*` changes, `pomp-cli` IPC messages, or replacement `dragon-prog` arguments;
- remounting `/`, `/factory`, or flashing the PLF/BLDC firmware.

## Open questions and next capture

1. Obtain ARSDK state-event bounds for altitude, tilt, vertical speed, yaw speed, pitch/roll angular rate, and distance. The protocol sends current/min/max; the filesystem config alone does not prove the UI/API bounds.
2. In a propeller-off, bench-powered session, stop Dragon cleanly and use `BLDC_Test_Bench -I` plus `-a` to read firmware info and all stock EEPROM motor settings. Reboot immediately afterward; perform no writes.
3. Capture P7MU ADC names/scales and map battery voltage/current/temperature channels.
4. Trace the 44444/44445 and 54321 socket roles precisely from ARSDK callbacks.
5. Capture the Skycontroller 2 filesystem and live `wifid` state. The SC2-specific priority is the factory-to-runtime NVM copy path and the exact successful TX-power control path through `wifid`/`bcmdriver.so`/Broadcom iovars.
