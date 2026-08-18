# Controlled A/B test protocol

The purpose of this procedure is to determine whether an NVM change improves the useful link rather than merely changing a displayed number.

## Before changing anything

1. Remove the propellers or otherwise make motor start impossible.
2. Confirm local RF regulations and use a shielded/attenuated setup for high-power work.
3. Export a read-only RF snapshot from both endpoints.
4. Preserve an untouched copy of each active NVM and its digest.
5. Leave `/factory` and Broadcom OTP/SROM programming interfaces untouched.
6. Use a fixed channel, band, bandwidth, separation, antenna orientation and surrounding layout.
7. Photograph or mark the positions so the geometry can be reproduced.

## Baseline

Run a labeled log on both devices for at least 60 seconds after association and rate adaptation settle:

```sh
sh /path/to/parrot_rf_lab.sh log stock
```

Record:

- A0/A1 last and average RSSI;
- driver RSSI, noise and SNR;
- last-frame PHY rates;
- actual TX/RX byte-counter throughput;
- failure, retry, retry-exhaustion, CRC and bad-FCS deltas;
- active-file and runtime NVM values;
- distance, orientation, channel and any obstruction.

## Change one endpoint first

Change only the transmitter being evaluated. Reboot it, verify that runtime values match the active NVM, and repeat the same log duration. The unchanged receiving endpoint makes a transmitter-side conclusion much stronger.

Do not modify both endpoints until each direction has its own isolated result.

## Compare distributions, not one line

Use the median and spread of A0, A1, combined RSSI and SNR. Confirm that retries and errors remain healthy and that throughput does not collapse. A single unusually strong line can come from multipath, AGC state or rate change.

Historical cumulative `TX Fail` values should be converted to deltas. A large total that stops increasing after association is not an ongoing failure rate.

## Parameter sequence

The included editor offers these controlled presets:

1. device-specific stock;
2. `EPA2/PD7` with the device's factory MAXP, isolating the EPA mode;
3. `EPA2/PD14/MAXP80`;
4. `EPA2/PD16/MAXP80`.

`PD16/MAXP90` is deliberately not provided as a preset because it produced approximately -70 dBm at 5 m.

## Restore

The tool creates timestamped backups before every write. Stage the known-good backup or the device-specific stock preset, review the diff, apply, reboot, and verify active-file/runtime agreement.

Never use an SC2 NVM wholesale on a Bebop or vice versa. Per-unit identity, board and PA calibration values must remain with their original device.

## What RSSI can and cannot prove

RSSI can establish a repeatable link-level change under controlled geometry. It cannot by itself establish:

- conducted watts;
- legal EIRP;
- spectral cleanliness or EVM;
- whether the PA is compressed;
- safe long-duration thermal behavior;
- guaranteed flight range.

Those require calibrated RF instruments and a test plan that fixes rate, channel, bandwidth, chain and packet duty cycle.
