# Reproducing the RF results

This procedure reproduces the software-only 2.4 GHz experiment on a Bebop 2 and SkyController 2. It requires no soldering, disassembly, antenna replacement or external amplifier.

The procedure changes persistent Broadcom NVM on both endpoints. Read it completely before applying anything.

> [!CAUTION]
> The experimental profile may exceed the permitted EIRP in your jurisdiction and has not yet been verified for EVM, spectrum mask, band-edge emissions or extended thermal behavior. Perform initial work with the aircraft immobilized and preferably in a shielded or attenuated RF environment. Preserve each device's own original NVM and never write another unit's complete NVM or anything under `/factory`.

## 1. Requirements

- Parrot Bebop 2 running the tested 4.4.2-generation firmware.
- Parrot SkyController 2 running the tested 1.0.9-generation firmware.
- A computer connected to the Bebop network.
- Terminal Telnet client for the Bebop.
- `adb` for a stock SkyController 2, whose Telnet service is disabled by default.
- `lftp` for transferring the common script to each FTP server.
- This repository checked out locally.

The example addresses are:

```text
Bebop 2:         192.168.42.1
SkyController 2: 192.168.42.88  (observed DHCP address; confirm yours)
```

The controller is a station on the Bebop network and does not broadcast its own SSID. If `.88` is not correct, inspect the Bebop's associated-station/ARP information first.

## 2. Fix the experiment geometry

For results comparable with this project:

1. Remove the propellers or otherwise prevent motor start.
2. Place the BB2 and SC2 exactly 5.0 m apart at approximately the same height.
3. Mark their position and orientation.
4. Keep people, large metal objects and moving equipment away from the direct path.
5. Select 2.4 GHz, a fixed channel and 20 MHz bandwidth.
6. Keep the same video/control traffic and physical arrangement for every profile.
7. Allow association and rate adaptation to settle for at least 30 seconds before logging.

Do not use adjacent-device or positive-dBm readings for power comparisons; the antennas and receiver are then in a strong-coupling/saturation regime.

## 3. Upload the same tool to both devices

From the repository root on the computer:

```sh
lftp -e 'set ftp:passive-mode true; put tools/parrot_rf_lab.sh -o internal_000/parrot_rf_lab.sh; bye' \
  ftp://192.168.42.1

lftp -e 'set ftp:passive-mode true; put tools/parrot_rf_lab.sh -o internal_000/parrot_rf_lab.sh; bye' \
  ftp://192.168.42.88
```

The resulting device paths are:

```text
Bebop 2:         /data/ftp/internal_000/parrot_rf_lab.sh
SkyController 2: /data/lib/ftp/internal_000/parrot_rf_lab.sh
```

## 4. Open a shell on each endpoint

Bebop 2:

```sh
telnet 192.168.42.1
```

Stock SkyController 2:

```sh
adb connect 192.168.42.88:9050
adb -s 192.168.42.88:9050 shell
```

If the controller received a different DHCP address, substitute it in both commands.

## 5. Preserve independent original backups

The RF Lab editor makes another timestamped backup immediately before every write. This preliminary copy provides an additional plainly named recovery file.

On the Bebop shell:

```sh
cp /lib/firmware/brcm/bcm43526.nvm \
  /data/ftp/internal_000/bcm43526.bebop2.original.nvm
md5sum /lib/firmware/brcm/bcm43526.nvm \
  /data/ftp/internal_000/bcm43526.bebop2.original.nvm
```

On the SC2 shell:

```sh
cp /lib/firmware/brcm/bcm43526-ffff-ffff.nvm \
  /data/lib/ftp/internal_000/bcm43526.sc2.original.nvm
md5sum /lib/firmware/brcm/bcm43526-ffff-ffff.nvm \
  /data/lib/ftp/internal_000/bcm43526.sc2.original.nvm
```

The two hashes printed on each endpoint must match before proceeding. Download these backups to the computer as well. Do not substitute the SC2 backup for the BB2 file or vice versa.

## 6. Record the stock baseline

Start a labeled 60-second-or-longer log in each shell.

Bebop:

```sh
sh /data/ftp/internal_000/parrot_rf_lab.sh log stock_5m_bb2_rx
```

SkyController:

```sh
sh /data/lib/ftp/internal_000/parrot_rf_lab.sh log stock_5m_sc2_rx
```

The display labels the direction explicitly:

```text
Bebop display: SkyController 2 -> Bebop 2
SC2 display:   Bebop 2 -> SkyController 2
```

After at least 60 settled samples, press `q`. Do not compare cumulative `TX Fail` totals directly; the dashboard and CSV provide per-sample deltas.

Stock NVM values should be:

| Device | `epagain2g` | `pdgain2g` | `maxp2ga0/1` |
|---|---:|---:|---:|
| Bebop 2 | 0 | 7 | 76 / 76 |
| SkyController 2 | 0 | 7 | 80 / 80 |

If your stock values differ, preserve and report them rather than forcing this project's assumed baseline.

## 7. Stage and apply the experimental profile

Launch the menu on each endpoint:

```sh
# Bebop
sh /data/ftp/internal_000/parrot_rf_lab.sh menu

# SC2
sh /data/lib/ftp/internal_000/parrot_rf_lab.sh menu
```

On one endpoint at a time:

1. Choose `5` — **NVM experiment editor / presets / recovery**.
2. Choose `4` — **EPA2 / PD16 / MAXP80**.
3. Read the displayed unified diff.
4. Choose `a` to apply.
5. Type the literal confirmation `APPLY`.
6. Record the displayed timestamped backup path.
7. Reboot that endpoint before evaluating it.

The target profile is:

```text
epagain2g=2
pdgain2g=16
maxp2ga0=80
maxp2ga1=80
```

On the SC2, `maxp=80/80` is already stock, so the demonstrated change modifies the two causal selectors `epagain2g` and `pdgain2g`. On the Bebop, the shared test envelope also raises its stock `maxp` from 76/76 to 80/80. This distinction should be retained in any report.

The editor changes only these named lines in a staged copy, verifies identity fields, creates an FTP-visible backup, writes the active filesystem NVM, verifies it byte-for-byte and restores the original root mount state. It never modifies the factory SC2 NVM or Broadcom OTP.

Do not use `PD16/MAXP90`; that combination produced an approximately -70 dBm link at 5 m and is intentionally absent from the presets.

## 8. Verify active-file and runtime agreement

After rebooting and reconnecting, run:

```sh
# Use the path appropriate to the endpoint
sh /path/to/parrot_rf_lab.sh snapshot
```

Then start `monitor`. The configuration section displays both the active NVM file and Broadcom runtime values. Do not collect modified measurements if it reports:

```text
FILE/RUNTIME MISMATCH - reboot before evaluating
```

The runtime should show EPA 2, PD 16 and MAXP 80/80 on both endpoints.

## 9. Record the modified bidirectional result

Return both devices to precisely the stock-test marks and orientations. Let the link settle again, then log both directions for the same duration:

```sh
# Bebop receiver
sh /data/ftp/internal_000/parrot_rf_lab.sh log epa2_pd16_m80_5m_bb2_rx

# SC2 receiver
sh /data/lib/ftp/internal_000/parrot_rf_lab.sh log epa2_pd16_m80_5m_sc2_rx
```

The original fixed-distance results were approximately:

| Direction | Stock | Modified | Change |
|---|---:|---:|---:|
| SC2 -> Bebop | -36.5 dBm | -20.3 dBm | +16.2 dB |
| Bebop -> SC2 | -31.5 dBm | -17.5 dBm | +14.0 dB |

Your exact absolute numbers will vary. A successful reproduction is a stable directional change with healthy throughput and retry/error deltas, not a requirement to match one dBm value exactly.

## 10. Retrieve the CSV logs

From the computer:

```sh
mkdir -p measurements/bebop2 measurements/sc2

lftp -e 'set ftp:passive-mode true; mirror internal_000/rf_lab_logs measurements/bebop2; bye' \
  ftp://192.168.42.1

lftp -e 'set ftp:passive-mode true; mirror internal_000/rf_lab_logs measurements/sc2; bye' \
  ftp://192.168.42.88
```

Each row records 38 fields, including A0/A1 last and average RSSI, signal/noise/SNR, PHY rates, measured byte-counter throughput, peer and driver error deltas, active-file/runtime NVM values and the experiment label.

Compare medians and variation rather than selecting the strongest line. Report A0 and A1 separately so antenna/orientation effects remain visible.

## 11. Longer-distance validation

Only after the bench comparison is stable should the same configuration be checked at a longer fixed distance. This project recorded useful far-field behavior at 52 m. A later 650 m flight was qualitative field validation, not a substitute for conducted RF, EVM or spectrum measurements.

Operate within applicable flight and radio regulations. Do not use range testing as the first proof that a calibration profile is safe.

## 12. Restore stock

Open the configuration menu on each endpoint and choose either:

- `1` to stage the known device-specific stock values; or
- `6` to stage the exact timestamped backup made from that endpoint.

Review the diff, apply with `APPLY`, reboot and verify file/runtime agreement.

Expected stock restoration:

```text
Bebop 2: epagain2g=0, pdgain2g=7, maxp2ga0/1=76/76
SC2:     epagain2g=0, pdgain2g=7, maxp2ga0/1=80/80
```

Keep the original backup files even after a successful restoration.
