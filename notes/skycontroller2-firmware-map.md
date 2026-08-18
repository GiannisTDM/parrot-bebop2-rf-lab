# SkyController 2 firmware map

Status: first-pass map, 2026-08-18. The initial controller capture was read-only through its stock root ADB service. No RF setting, pairing record, or calibration was changed. A later explicitly requested maintenance change enabled persistent root Telnet by adding one service line to `/etc/inetd.conf`; the stock file is backed up as `/data/inetd.conf.before-telnet` on the controller.

## Evidence and confidence

- `LIVE` means observed over ADB while the SkyController 2 was associated with the Bebop 2.
- `FW` means read from the locally captured SkyController 2 filesystem.
- `INFERENCE` is a conclusion supported by those observations but not yet traced instruction-by-instruction.

Primary local evidence:

- Capture: `captures/skycontroller2-live-20260818/`
- Extracted filesystem: `firmware/skycontroller2-1.0.9/rootfs/`
- Reusable capture script: `capture_skycontroller2_via_adb.sh`
- Full system archive SHA-256: `00eae79530f589255c76c755c7306b60545c5e964d1bfed1df53d678f7476d99`
- Runtime inventory SHA-256: `8766d9f7da48de36bd0dda20ca831675820c13afbf4c1aeccda566e80697d08f`

The extracted archive has 534 regular files, 369 symlinks, and 92 directories. The capture contains factory identifiers, historical position logs, and paired-device credentials. It is intentionally ignored by Git and should be scrubbed before sharing.

## Proven access path

The controller does not need Telnet. Its stock debug build starts a root ADB daemon on TCP port 9050:

```text
Mac ADB client at 127.0.0.1:9050
  -> Mac socat rendezvous listener
  -> reverse BusyBox nc connection from the Bebop
  -> 192.168.42.88:9050 on the SkyController 2
  -> stock root adbd
```

The exact configuration is visible in the firmware:

```text
/etc/default.mppboard.prop: ro.debuggable=1
/etc/default.mppboard.prop: service.adb.tcp.port=9050
/etc/boxinit.d/50-adb.rc: start adbd when ro.debuggable=1
```

The stock `/etc/inetd.conf` contains only the FTP service. There is no stock Telnet entry, so Telnet is disabled by omission rather than by a hidden authentication problem. On the live controller, Telnet was subsequently enabled at the user's request with:

```text
23 stream tcp nowait root /usr/sbin/telnetd telnetd -i -l /bin/sh
```

`inetd` now listens on TCP 23 and launches a root BusyBox shell. The change resides on the normally read-only system UBIFS and therefore survives reboot. The filesystem was returned to read-only immediately after the edit.

Rollback through ADB is:

```sh
mount -o remount,rw /
cp /data/inetd.conf.before-telnet /etc/inetd.conf
sync
mount -o remount,ro /
kill -HUP "$(pidof inetd)"
```

The tested reverse bridge was:

```sh
# Mac, while its Bebop-facing address was 192.168.42.44
socat TCP-LISTEN:9050,bind=127.0.0.1,reuseaddr \
      TCP-LISTEN:9053,bind=192.168.42.44,reuseaddr

# Bebop, from its Telnet shell
nc 192.168.42.44 9053 -e nc 192.168.42.88 9050

# Mac
adb connect 127.0.0.1:9050
adb -s 127.0.0.1:9050 shell
```

The relay changes only RAM/process state. It leaves no persistent controller modification and disappears when either device reboots.

## System identity

| Item | Finding |
|---|---|
| Product/build | SkyController 2, `mpp-linux-1.0.9` (`LIVE`, `FW`) |
| Build date | 2018-10-30 (`LIVE`, `FW`) |
| Kernel | Linux 3.4.11+, ARMv7 SMP/PREEMPT (`LIVE`) |
| Board | MPP board revision 7 (`LIVE`) |
| CPU | Two Cortex-A9-class cores, ARM part `0xc09` (`LIVE`) |
| RAM | 509,024 KiB total, no swap (`LIVE`) |
| Main application | `/usr/bin/mppd` (`LIVE`, `FW`) |
| Wi-Fi | Broadcom BCM43526 USB (`0xaa06` rev 3), driver 6.37.114.64 (`LIVE`) |

ADB runs as `uid=0(root) gid=0(root)`. The system UBIFS is mounted read-only in normal operation.

## Boot and service architecture

```text
eCos/P7 bootloader
  -> Linux 3.4.11
  -> /sbin/init (boxinit)
  -> /etc/boxinit.rc + /etc/boxinit.d/*.rc
  -> core services: console, udev, jubamountd, adbd
  -> main services: wifid, inetd, sensorsd-mpp, usbnetd, logging
  -> mpp services: mppd, Android AOA bridge, iOS bridge
```

`/etc/boxinit.rc` mounts the factory, data, and update UBI volumes, resets the Wi-Fi module for at least 70 ms, starts the `core` class, then starts `main` and `mpp`. Important services are:

| Service | Role |
|---|---|
| `mppd` | Controller application, ARSDK routing, drone manager, mappings, UI state |
| `wifid` | BCM43526 station-mode configuration and DHCP orchestration |
| `sensorsd-mpp` | IMU/magnetometer service |
| `jubamountd` | Device discovery/event bus used for the bottom board and USB devices |
| `adbd` | Stock root ADB transport, TCP 9050 |
| `inetd` | FTP only |
| `usbnetd` | DHCP service for attached USB/Ethernet network interfaces |
| `aoad` | Android Open Accessory bridge |
| `iosd` | Apple External Accessory/iOS bridge and charging control |
| `usbctrl-mon` | USB controller watchdog/recovery |

## Storage and persistence

| Backing store | Mount | Live state |
|---|---|---|
| MTD0, 8 MiB | bootloader | raw NAND partition |
| MTD1, 16 MiB | main boot | kernel/main boot |
| MTD2/UBI0, 8 MiB | `/factory` | read-only, factory IDs/calibration/NVM |
| MTD3/UBI1, 40 MiB | `/` | read-only system, 33.4 MiB usable, 76% occupied |
| MTD4/UBI2, 56 MiB | `/data`, `/update` | writable; about 10.4 MiB and 35.4 MiB usable |

Persistent controller settings are under `/data/lib`. In particular:

- `/data/lib/libshsettings/wifi.cfg` stores country, band, channel, and automatic-channel state.
- `/data/lib/mppd/` stores controller mappings and paired-drone records.
- `/factory/` stores joystick calibration, board identity, and a copy of the radio NVM.

The pairing database contains Wi-Fi credentials and should never be pasted into notes or published with a dump.

## Network surface

The controller was a Wi-Fi station on the Bebop subnet and received `192.168.42.88` during the capture. `wifid` is launched with an initial `192.168.42.3` station address and `--dhclient`; DHCP supplies the final address.

Observed listeners:

| Port | Role/status |
|---:|---|
| TCP 21 | FTP rooted at `/var/lib/ftp`, which resolves to persistent `/data/lib/ftp`; `internal_000` is `/data/lib/ftp/internal_000` |
| TCP 9050 | stock ADB transport, confirmed reachable even though the old `netstat` output did not list it |
| TCP 44444 | ARSDK/controller service (`mppd`) |
| TCP 6007, 7711 | live listeners; exact owners still to map |
| UDP 9988 | ARSDK/control path |
| UDP 5004 | ARStream2 drone video input |
| UDP 55004, 55005 | ARStream2 client stream/control ports |
| UDP 54321 | loopback service socket |

No TCP 23 listener or Telnet service exists in the stock controller image. The live controller now has the explicitly added persistent TCP 23 service described above.

## Wi-Fi and RF path

### Component chain

```text
BCM43526 USB radio
  -> wifid detects bcm43526
  -> bcm_dbus.ko + proprietary wl.ko from bcm43526-extra
  -> bcm43526-firmware.bin + bcm43526-ffff-ffff.nvm
  -> wlan0 in station mode
  -> bcmdriver.so + libnetmon-bcm43526b.so
  -> persistent libshsettings country/channel policy
  -> association with the Bebop access point
```

Live boot logs repeatedly show the device detection and both module loads. `/etc/boxinit.d/50-wifi.rc` also implements a hardware watchdog that stops `wifid`, resets the Wi-Fi USB device and hub, rebinds the USB controller, and restarts the service.

### Live radio state

| Query | Result |
|---|---|
| Driver/firmware | `6.37.114.64 (r516176)` |
| Chip/board | `0xaa06` rev 3, device `0x43a0`, board `0x623` / P452 |
| Mode | managed/station, associated to the Bebop |
| Channel | 2.4 GHz channel 11, 20 MHz |
| Signal/noise | about -16 dBm / -92 dBm while devices were adjacent |
| Country | `DE (DE/20)` |
| `qtxpower` | 127 quarter-dBm (31.75 dBm requested ceiling), override off |
| TX/RX chains | `3` / `3`, both chains enabled |
| PHY rate | MCS 7, STF mode 2, 65 Mbps |
| MPC | enabled (`1`) |
| Interference override | mode 6 |

`qtxpower=127` is not measured conducted or radiated output. It is a requested ceiling and remains subject to regulatory data, NVM maxima, rate backoff, TSSI/PA control, thermal behavior, and RF-path loss.

### NVM and calibration

The system and factory NVM copies are byte-identical:

- SHA-256: `1b44fb53d3db02061e22172c8da0065754d437d2d75779e13761f79f7d308c2c`
- Radio firmware SHA-256: `62a0f030dd59ec82fa7986bdc97e18f41798f3e5e934b6e20d0fa0c0dd0bc70e`

Key NVM fields:

| Parameter | Value | Interpretation |
|---|---:|---|
| `aa2g`, `aa5g` | `0x3`, `0x3` | both antenna paths present |
| `txchain`, `rxchain` | `0x3`, `0x3` | both chains enabled |
| `femctrl` | 1 | selects the built-in FEM pin-control logic table; this is not a Boolean enable |
| `pdgain2g`, `pdgain5g` | 7, 7 | calibration-sensitive PA detector gain |
| `maxp2ga0`, `maxp2ga1` | 80, 80 | 20 dBm in quarter-dBm representation |
| `maxp5ga0`, `maxp5ga1` | 72 per band | 18 dBm in quarter-dBm representation |
| `sar2g`, `sar5g` | 18, 15 | raw driver-specific SAR caps |
| `pa2ga*`, `pa5ga*` | per-chain tables | PA calibration coefficients; do not edit blindly |

The controller differs from the Bebop's stock NVM primarily in the 2.4 GHz maxima: 20 dBm on the SC2 versus 19 dBm on the Bebop. Both use the same chip family, board identity, driver version, and two-chain design.

### SKY85803 FEM/LNA forensic correction

The two external SKY85803 front ends do not have an I2C/SPI register interface. Each FEM is controlled by four logic inputs from the Broadcom radio: `C0`, `C1`, the 2.4 GHz PA enable `ENG`, and the 5 GHz PA enable `ENA`. The Skyworks truth table makes the distinction explicit:

- 2.4 GHz RX with LNA active: `C0=0, C1=1, ENA=0, ENG=0`;
- 2.4 GHz TX through the external PA: `C0=0, C1=0, ENA=0, ENG=1`;
- 2.4 GHz RX bypass: `C0=0, C1=0, ENA=0, ENG=0`;
- the corresponding 5 GHz states use `C0=1`, with `C1=1` for active LNA and `ENA=1` for TX.

Therefore a separate SKY85803 register/config file is not expected. Any alternate configuration must define how the BCM43526 drives those pins. Four possible sources exist in this image:

1. the external `/lib/firmware/brcm/bcm43526-ffff-ffff.nvm` file;
2. an NVRAM profile embedded inside `bcm43526-firmware.bin` and used as a fallback/base profile;
3. the firmware's built-in FEM truth table selected by `femctrl`;
4. temporary runtime iovar overrides issued through `bcmwl`.

The normal startup scripts contain no `bcmwl fem`, `bcmwl antgain`, `nvset`, `swctrlmap`, or direct GPIO override. The only readable external configuration containing the candidate FEM/LNA variables is the pair of identical system/factory NVM files. The firmware binary nevertheless contains parsers for `femctrl`, `swctrlmap_2g`, `swctrlmap_5g`, `swctrlmapext_*`, `extpagain*`, and all of the `rxgains*` fields, so the decisive state can live inside radio RAM or an embedded table without appearing in a shell script.

The external and embedded profiles are not identical. The relevant baseline differences are:

| Field | External SC2 NVM | Embedded fallback profile | Likely significance |
|---|---:|---:|---|
| `agbg0`, `agbg1` | 5 | 2 | 2.4 GHz declared antenna gain differs by 3 dB |
| `maxp2ga0`, `maxp2ga1` | 80 | 76 | external file permits a 1 dB higher calibrated 2.4 GHz maximum |
| `boardflags2` | `0x00009002` | `0x0` | board-specific behavior differs; not yet decoded instruction-by-instruction |
| `femctrl` | 1 | 1 | both select the same numbered built-in FEM control logic |
| `epagain2g`, `epagain5g` | 0, 0 | 0, 0 | both describe the same PA topology to the PHY |

Live verification found the external system NVM at `/lib/firmware/brcm/bcm43526-ffff-ffff.nvm` and a byte-identical factory copy at `/factory/bcm43526-ffff-ffff.nvm` (both MD5 `f3b32579fc66b08568d643e407a3702c`). Signal experiments should operate on a backed-up system copy only; the factory file should remain unchanged as the recovery reference. The demonstrated candidate lines in the external file are `epagain2g=0`, `pdgain2g=7`, `epagain5g=0`, and `pdgain5g=7`.

This makes the embedded NVRAM a credible source for the remembered antenna-gain change, but not by itself for a measured 14–15 dB increase. A 5 dBi to 2 dBi declaration can at most create roughly 3 dB of additional EIRP headroom where antenna-gain accounting is the active limiter.

The candidate fields now have firm meanings from Broadcom/Infineon documentation:

| Candidate | Actual role | Can directly explain stronger SC2 transmission? |
|---|---|---|
| `rxgains*elnagain*` | numerical eLNA gain in dB used by the RX gain model | no; it is not an LNA-enable bit |
| `rxgains*trelnabyp*` | isolation supplied by the eLNA in bypass mode | no; value `1` is calibration data, not Boolean bypass-on |
| `femctrl` | selects the FEM/RF-switch control logic for both bands | potentially; this is the candidate that can change physical C0/C1/ENG/ENA sequencing |
| `swctrlmap_2g/5g` | explicit per-band FEM truth table | potentially, but the stock file has none and `boardflags3=0`, so this build uses its built-in table rather than a custom NVRAM table |
| `extpagain*` / `epagain*` | tells the PHY that an external PA is present and changes PA/TSSI handling | yes, on the TX side, but it is topology/calibration state rather than a safe power-level knob |
| `antgain` / `ag*` | declared antenna gain used in regulatory/EIRP accounting | yes, indirectly, when regulatory power is limiting |

This table preserves the meanings of parameters investigated during reverse engineering; it is not a list of equally viable explanations. The recovered experiment and the user's clarification rule out RX-gain, antenna-gain, SAR, and detector-offset suggestions as causes of the original demonstrated jump. The historical `PA`/`epa` pair remains the active causal model. Later controlled work also established that `maxp2ga*` interacts strongly with that pair: it was not the original trigger, but it can determine whether a selected `pdgain` regime works or collapses.

`bcmwl` exposes exactly the two temporary override families that fit part of the old description: `bcmwl fem ...` changes temporary per-band FEM/TSSI parameters including `extpagain*`, and `bcmwl antgain ag0=... ag1=...` changes temporary antenna-gain declarations. It also exposes `nvset`, `nvget`, and `nvram_dump`.

#### Recovered 12 February 2025 A/B evidence

A Discord record from the original experiment substantially narrows the TX-side setting. The record must be preserved with the author's shorthand rather than silently relabelled, because the exact command line has not yet been recovered:

| Recorded test | Bebop-reported A0/A1 |
|---|---:|
| stock | -31 / -37 dBm |
| `int PA 12, E pa 10` | -36 / -41 dBm |
| `int PA 14, E pa 2` | -16 / -22 dBm |
| `PA 15, epa 2` | -16 / -22 dBm |
| `PA 16, epa 1` | -35 / -41 dBm |
| `PA 16, epa 2` | -17 / -23 dBm |

Holding `PA=16` while changing only `epa` from 1 to 2 produced approximately 18 dB more received signal on both chains. Relative to stock, the repeated `epa=2` results were approximately 14-15 dB stronger. This is the strongest surviving evidence that the large improvement was a TX-path topology/mode change rather than an antenna-gain declaration or RX eLNA calibration value. The close agreement between A0 and A1 deltas also argues against a single-chain accident.

The screenshot additionally records a later combination described as `max p gain 100 2g 90 5g sar 2g&5g=12 pdoff=3`. The user confirms that these were speculative GPT-4 suggestions rather than the discovered modification. They are excluded from the causal model. The demonstrated modification consists only of the paired `PA`/`epa` values, with the `PA=16, epa=1` versus `PA=16, epa=2` comparison providing the cleanest isolation.

Two similarly named parameter families must not yet be conflated:

- SROM revision 11 stores `epagain2g` and `epagain5g`, each as a three-bit field in the FEM configuration words.
- The `bcmwl fem` runtime interface exposes `extpagain2g` and `extpagain5g` alongside `tssipos`, `pdetrange`, `triso`, and `antswctl`.

The local `bcmwl` help itself uses `extpagain2g=0x2` and `extpagain5g=0x2` in its example. The recovered A/B record and the subsequently reproduced persistent NVM experiment now identify `epagain2g=2`, rather than the earlier recalled value 1, as the decisive tested 2.4 GHz value. The exact semantic label for numeric mode 2 remains generation-specific; the empirical statement is stronger than any attempted translation to “internal” or “external” PA terminology.

The historical shorthand `PA` is now strongly associated with `pdgain2g`: values 14 and 16 reproduce the recorded pattern when paired with `epagain2g=2`. This remains an empirical identification because the available Infineon NVRAM notes do not define `pdgain`. New tests also show `maxp2ga*` is part of the operating envelope: PD16/MAXP80 gives the expected strong link while PD16/MAXP90 collapses it. `sar`, `pdoffset`, antenna-gain, and RX-gain suggestions remain excluded from the demonstrated modification.

The persistence is now explained by editing the active `/lib/firmware/brcm/bcm43526-ffff-ffff.nvm` file and rebooting; an unassisted runtime `bcmwl fem`/`antgain` invocation is not the recipe. The factory copy remains an untouched recovery source. This build does expose irreversible OTP/SROM/CIS write commands, but there is no reason to use them for this modification and the new RF-lab tool deliberately never invokes them.

Most important for interpreting the old test: the Bebop was the receiver and only the other SC2 had been modified. Enabling the SC2's receive LNA cannot make the Bebop report the SC2 14–15 dB stronger. The recovered A/B evidence and the user's clarification attribute the effect specifically to the historical transmit-side `PA`/`epa` pair: the SKY85803 PA-enable/topology and Broadcom PA/TSSI model. Antenna-gain, regulatory, RX-gain, SAR, `maxp`, and `pdoffset` settings are not part of the demonstrated modification.

Primary references: [Skyworks SKY85803 data sheet](https://www.skyworksinc.com/-/media/AD1A750EED664950910713311CB9F3AD.pdf), [Infineon AN215294](https://www.infineon.com/dgdl/Infineon-AN215294_CYW4335_OTP_Programming_and_NVRAM-ApplicationNotes-v04_00-EN.pdf?fileId=8ac78c8c7cdc391c017d0d2c9c1b6422), and [Infineon AN214915](https://www.infineon.com/dgdl/Infineon-AN214915_OTP_Programming_and_NVRAM_Development_in_SDIO_Mode_CYW43241-ApplicationNotes-v03_00-EN.pdf?fileId=8ac78c8c7cdc391c017d0d28a6176376).

`tools/parrot_rf_lab.sh` is now the common on-device experiment frontend for both endpoints. On the SC2 it uses `/usr/sbin/bcmwl`, labels its measurements as Bebop-to-SC2 reception, writes logs/backups under `/data/lib/ftp/internal_000`, and stages only the active system NVM. It never modifies `/factory/bcm43526-ffff-ffff.nvm` or Broadcom OTP.

### Country and power-control findings

The default Wi-Fi config says US, while the live persistent config selected DE, 2.4 GHz, channel 11, and manual channel selection. Boot logs show two distinct stages:

1. `NETMON_REGUL` maps Broadcom version 44 to internal base definition `US/44` from `/etc/wifi/mppboard_config.yaml`.
2. `wifid` applies the user's persistent country and the live driver reports `DE/20`.

`US/44` is therefore a Broadcom compatibility mapping, not proof that the controller ignores the final country.

`/usr/share/netmon/country_regul.yaml` defines country/channel authorization. `/usr/share/netmon/device_perf.yaml` contains nominal device TX-power and RX-gain values used by the distance/link-budget manager. For `SkyController` it lists channel-dependent figures as high as 28 dBm at 2.4 GHz and 38 dBm at 5 GHz. Thumb-2 disassembly of `netmon_distance_mngr_get_limit` shows table lookups, country/device minima, RX-gain addition, and a final link-distance calculation; it makes no call to `netmon_bcm_iovar_set`. The YAML is therefore an estimator input, not a direct PA-programming path.

A full string scan of normal executables and libraries found no stock startup call to `txpwr`, `qtxpower`, `maxpower`, or `phy_txpwrindex`. The sole bundled caller is `/usr/bin/radio_test.sh`, a factory continuous-packet test that takes the interface down and ends with `bcmwl txpwr1 -1`, meaning restore calibrated defaults.

The no-argument `bcmwl maxpower` query is unsupported on this driver. Its failed output included byte values spelling fragments of the word `maxpower`; those are placeholder/uninitialized fields after the failed getter and are not RF limits. They must not be used as telemetry.

Current conclusion: a genuine RF-output change would have to occur through a temporary Broadcom override or through NVM/calibration data, not the distance-estimation YAML. Either route is regulatory- and hardware-sensitive, can defeat calibration/thermal margins, and must be evaluated on an attenuated RF bench with a power meter or spectrum analyzer rather than inferred from `qtxpower`.

## Controls, sensors, and companion devices

The physical controls enumerate as one USB HID device named `www.parrot.com MPP GAMEPAD`, exposed as `/dev/input/js0` and `/dev/input/event0`. It supplies buttons plus five axes:

- left stick: yaw and vertical/gaz;
- right stick: roll and pitch;
- slider: camera tilt.

`/etc/mppd/mapping_bebop_2.cfg` supplies the stock button/action mapping and uses expo level 1 on all five axes. A writable copy under `/data/lib/mppd/` allows user mappings without replacing the read-only system file.

The controller also exposes:

| Component | Path/role |
|---|---|
| ICM20608 | IIO device 0; accelerometer, gyro, internal temperature |
| AK8963 | IIO device 1; magnetometer |
| P7MU ADC | IIO device 2; board analog acquisition |
| P7 temperature | IIO device 3; live P7/P7MU temperatures |
| Bottom board | `libmppbb.so` over the Juba device layer; buttons, LEDs, battery state, calibration |

Battery state is delivered by the bottom board to `mppd`; there is no Linux `/sys/class/power_supply` device. The bottom-board state machine exposes `CHARGED`, `DISCHARGING`, `DISCHARGING_LOW`, `DISCHARGING_CRITICAL`, and `AUTO_SHUTDOWN`. During capture it reported about 8.047 V, 83%, `DISCHARGING`; CPU temperature rose from about 54°C to 57°C and stabilized. The voltage is consistent with a two-cell controller battery. The present capture is not enough to derive its percentage curve or aging state.

Android phones are handled by `aoad` through Android Open Accessory mode. iOS devices are handled by `iosd` and the `g_aea` USB gadget/External Accessory protocol; strings also show 2.1 A charging control. `usbnetd` watches `eth*` and `usb*` interfaces and launches an interface-specific DHCP server at `192.168.X.1`, which explains the alternative direct-USB-Ethernet access method used by compatible adapters.

## Read-only queries versus modifying commands

Safe stock-state queries while ADB is connected:

```sh
adb -s 127.0.0.1:9050 shell 'id; uname -a; getprop'
adb -s 127.0.0.1:9050 shell 'bcmwl status; bcmwl country; bcmwl qtxpower'
adb -s 127.0.0.1:9050 shell 'bcmwl txchain; bcmwl rxchain; bcmwl mpc'
adb -s 127.0.0.1:9050 shell 'ulogcat -d | grep -i "cpu:" | tail -n 1'
```

Treat these as modifying/hazardous and do not run casually:

- `wifid-cli set_country` / `set_autocountry`;
- `bcmwl down`, `up`, `country`, `txpwr`, `txpwr1`, `maxpower`, `phy_txpwrindex`, or `mpc` setters;
- `/usr/bin/radio_test.sh` (it deliberately disrupts normal Wi-Fi and starts packet transmission);
- edits under `/data/lib/libshsettings`, `/data/lib/mppd`, `/factory`, or `/lib/firmware`;
- joystick/bottom-board calibration or firmware-update routines.

## High-value next steps

1. Disassemble `libnetmon-bcm43526b.so` around `netmon_distance_mngr_get_limit` to formally separate the link-budget model from driver iovar writes.
2. Trace `mppd -> wifid` country-setting messages and the exact persistent-settings transaction.
3. Reverse `libmppbb.so` and the bottom-board firmware protocol to recover battery thresholds and the percentage curve.
4. Attribute TCP 6007/7711 to exact processes in a short future live capture using `/proc/*/fd` inode matching.
5. If RF output is to be characterized, use a shielded/attenuated bench and record conducted power by channel/rate/chain before considering any override.

The controller no longer needs to remain powered for steps 1-3; the necessary binaries and logs are local.
