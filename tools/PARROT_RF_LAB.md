# Parrot RF Lab

`parrot_rf_lab.sh` is one BusyBox-compatible RF dashboard and experiment tool for both the Parrot Bebop 2 and SkyController 2. It auto-detects the device, uses the correct `bcmwl` invocation and active BCM43526 NVM path, and needs no Python or added packages on either device.

## What it measures

- Incoming link direction, peer MAC/IP, per-chain last and average RSSI, combined RSSI, driver RSSI, noise, and SNR.
- Last-frame TX/RX PHY rates, clearly separated from actual byte-counter throughput.
- Per-peer TX failure/retry/retry-exhaustion deltas and global driver retransmit/error/CRC/FCS deltas. Cumulative association-time failures do not look like new live failures because the dashboard emphasizes deltas.
- Active-file and driver-runtime values for `epagain2g`, `pdgain2g`, `maxp2ga0`, and `maxp2ga1`, plus `qtxpower` and `txinstpwr` output.
- Optional CSV records with 38 fields under the device's FTP-visible storage.

The signal colors interpolate through red at -60 dBm, yellow at -40 dBm, green at -20 dBm, and cyan at -5 dBm or stronger.

On an interactive terminal the frame is drawn once; subsequent samples update only the peer/sample counter, signal bars, rates, throughput, and error rows. `RF_LAB_NO_CLEAR=1` intentionally retains the scrolling form for captures and primitive terminals.

## Put the same script on both devices

From the Mac, while the relevant device is reachable:

```sh
lftp -e 'set ftp:passive-mode true; put tools/parrot_rf_lab.sh -o internal_000/parrot_rf_lab.sh; bye' ftp://192.168.42.1
```

For the SkyController 2:

```sh
lftp -e 'set ftp:passive-mode true; put tools/parrot_rf_lab.sh -o internal_000/parrot_rf_lab.sh; bye' ftp://192.168.42.88
```

The device-side paths are:

- Bebop 2: `/data/ftp/internal_000/parrot_rf_lab.sh`
- SkyController 2: `/data/lib/ftp/internal_000/parrot_rf_lab.sh` (also visible as `/var/lib/ftp/internal_000/parrot_rf_lab.sh`)

No executable permission is needed when starting it through the shell explicitly:

```sh
sh /data/ftp/internal_000/parrot_rf_lab.sh
```

```sh
sh /data/lib/ftp/internal_000/parrot_rf_lab.sh
```

To make direct `./parrot_rf_lab.sh` launches work, run `chmod +x` on the corresponding device path once.

## Main commands

```text
parrot_rf_lab.sh menu             interactive menu
parrot_rf_lab.sh monitor          live dashboard
parrot_rf_lab.sh log pd16_m80     dashboard plus labeled CSV
parrot_rf_lab.sh snapshot         full read-only BCM snapshot on screen
parrot_rf_lab.sh export           clean snapshot in FTP storage
parrot_rf_lab.sh config           staged NVM editor, presets, backups, recovery
parrot_rf_lab.sh self-test        parser/editor sanity check
```

The menu is the simplest entry point. `RF_LAB_INTERVAL=2` changes the sample interval, `RF_LAB_PEER=aa:bb:cc:dd:ee:ff` forces a peer, `NO_COLOR=1` disables colors, and `RF_LAB_NO_CLEAR=1` makes each dashboard frame scroll instead of replacing the previous frame.

For the complete experimental procedure rather than only the command reference, see [`docs/REPRODUCING_RESULTS.md`](../docs/REPRODUCING_RESULTS.md).

## NVM editing and recovery

The active files are:

- Bebop 2: `/lib/firmware/brcm/bcm43526.nvm`
- SkyController 2: `/lib/firmware/brcm/bcm43526-ffff-ffff.nvm`

The root filesystem is read-only by default on both products. Before using `config`, explicitly run this on the relevant BB2 or SC2 shell:

```sh
mount -o remount,rw /
```

Edits are made to a temporary staged copy first. The tool shows a unified diff and requires the literal confirmation `APPLY`. Before writing, it stores a timestamped, checksummed-name backup in `internal_000/rf_lab_backups/` and verifies the resulting file byte-for-byte. The SC2 factory file and Broadcom OTP are never written.

After leaving the editor, flush the write and restore the normal read-only mount before rebooting:

```sh
sync
mount -o remount,ro /
```

The tool retains an automatic remount attempt as defense in depth, but the tested procedure requires the explicit read-write remount on both endpoints.

A reboot is required for a written NVM file to become the driver runtime. The live screen shows file and runtime values side by side so a forgotten reboot is obvious.

The included presets are the known stock profile for each device, EPA2/PD7 with its factory maximum, EPA2/PD14/MAXP80, and EPA2/PD16/MAXP80. The empirically bad PD16/MAXP90 combination is not a preset and triggers a visible warning if staged manually.

## Controlled A/B procedure

1. Fix device separation, orientation, band, channel, and surrounding objects.
2. Start `log stock` on both endpoints and collect at least 60 seconds after association settles.
3. Change one parameter family at a time, apply it, and reboot the edited endpoint.
4. Start a new, clearly named log on both endpoints for the same duration.
5. Compare medians and variation for A0/A1/RSSI/SNR, actual traffic, and error deltas. Do not infer conducted RF power directly from RSSI.
6. Validate promising profiles with proper RF measurements for output power, EVM, spectral mask, band edge, and receiver PER before treating them as safe or compliant.
