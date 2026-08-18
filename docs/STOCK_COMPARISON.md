# Stock Bebop 2 versus SkyController 2 RF configuration

The two endpoints use the same BCM43526-family radio, two enabled RF chains, the same Broadcom driver generation and SKY85803 front-end architecture. Their stock external NVM profiles are nevertheless not identical.

## Direct 2.4 GHz NVM differences

| Field | Bebop 2 | SkyController 2 | Interpretation |
|---|---:|---:|---|
| `agbg0`, `agbg1` | `2`, `2` | `5`, `5` | declared 2.4 GHz antenna gain in dBi |
| `epagain2g` | `0` | `0` | same stock PA topology selection |
| `pdgain2g` | `7` | `7` | same stock detector/TSSI selection |
| `maxp2ga0`, `maxp2ga1` | `76`, `76` | `80`, `80` | 19 versus 20 dBm configuration ceilings |
| `cckbw202gpo` | `0` | `0006` | different CCK power-offset table |
| `mcsbw202gpo` | `0x44300000` | `0x66520000` | different per-MCS backoff table |
| `ofdmlrbw202gpo` | `0x4` | `0` | different legacy-OFDM low-rate offset |

`maxp` values use quarter-dB units on this Broadcom architecture. Per-rate offset nibbles are generally half-dB units, although the precise layout remains tied to the SROM revision.

For MCS7, the observed table layout is consistent with approximately 2 dB backoff on the Bebop and 3 dB on the SC2:

```text
Bebop: 19 dBm maxp - 2 dB MCS7 backoff = 17 dBm target
SC2:   20 dBm maxp - 3 dB MCS7 backoff = 17 dBm target
```

When a 20 dBm EIRP regime also accounts for the declared antennas, the simple ceilings become:

```text
Bebop: 20 - 2 dBi = 18 dBm conducted allowance
SC2:   20 - 5 dBi = 15 dBm conducted allowance
```

Combining the rate target and antenna allowance gives a plausible MCS7 working point near 17 dBm for the Bebop and 15 dBm for the SC2. This is an inference from the profile, not a direct power measurement, but it predicts the reported stock SC2 output being somewhat lower.

## Why the patch antennas are not “more power hungry”

A passive ceramic patch does not draw DC power. Its gain, efficiency, impedance and radiation pattern determine how the available RF power is radiated.

If one RF path is divided between two patches, an ideal splitter sends half the conducted power to each output, a 3 dB reduction per patch, plus real splitter/feed losses. The total radiated power is not automatically halved: the two elements form an array whose directional pattern and gain can recover much of that division in favored directions.

Consequently:

- an output difference measured at the U.FL connector before the feed network cannot be caused by the patches consuming power;
- the SC2's higher declared antenna gain can cause firmware/regulatory logic to request lower conducted power for the same legal EIRP;
- feed splitting and losses can still change the power reaching each individual patch;
- directional patch gain can make SC2 receive readings stronger even when its transmitter is configured lower.

The approximately 5 dB stock directional difference in the 5 m screenshots is therefore quite coherent: roughly 2 dB can come from a lower SC2 conducted target and roughly 3 dB from the SC2's higher-gain receive antennas. This is a useful model, not a calibrated decomposition of the screenshot.

## Why `maxp=80` does not contradict lower stock SC2 output

`maxp` is only one input to the power-control system. Country rules, declared antenna gain, per-rate offsets, TSSI/PA calibration, thermal behavior and board loss are applied around it. The SC2 can have a numerically higher `maxp` and still transmit less in a particular normal-runtime mode.

This is also why setting `maxp=90` did not simply add 2.5 dB: with `pdgain=16`, it pushed the selected calibration regime into a failure state and the useful link collapsed.
