# Contributing

Contributions are welcome, particularly calibrated RF measurements, sanitized stock-profile comparisons, Broadcom BCM43526 documentation and reproducible parser fixes.

## Do not upload sensitive or proprietary data

Do not commit complete firmware images, extracted Parrot root filesystems, device captures, factory partitions, pairing databases, Wi-Fi credentials, serial numbers, MAC addresses, GPS logs, flight logs, or per-unit calibration blobs.

Small quoted configuration fragments are useful when they contain only the fields needed to reproduce a finding and have been scrubbed of identity/calibration data.

## Measurement reports

Please include:

- device and firmware version;
- which endpoint was changed and which remained stock;
- exact named NVM fields before and after;
- band, channel, bandwidth and PHY rate where available;
- chain configuration;
- separation, antenna orientation and obstruction;
- instrument model, attenuation and calibration date for conducted measurements;
- A0/A1 distributions, noise/SNR, throughput and error deltas;
- thermal conditions and packet duty cycle;
- a known-good recovery path.

Distinguish direct measurements from estimates and third-party reports.

## Tool changes

The on-device script must remain compatible with the stock BusyBox `ash`; avoid Bash-only syntax. Run:

```sh
sh tools/parrot_rf_lab.sh self-test
```

before submitting changes. Changes to NVM writing must preserve staging, a visible diff, explicit confirmation, backup creation, write verification and rollback behavior.
