# BCM43526 RF experiment notes

## What is established

The two Parrot endpoints use the same BCM43526/SKY85803 radio design, but the stock external NVM files are not identical. Relevant 2.4 GHz stock fields are:

| Endpoint | `epagain2g` | `pdgain2g` | `maxp2ga0/1` |
|---|---:|---:|---:|
| Bebop 2 | 0 | 7 | 76 / 76 |
| SkyController 2 | 0 | 7 | 80 / 80 |

`maxp2ga*` uses quarter-dB units, so the raw values represent 19 and 20 dBm respectively before regulatory, per-rate, calibration, thermal, and other limits. This is a configured ceiling/target input, not a conducted-power measurement.

The recovered 12 February 2025 A/B record isolates `epagain2g=2` as decisive when the shorthand `PA` setting was held at 16: changing EPA from 1 to 2 moved the Bebop's received A0/A1 from about -35/-41 to -17/-23 dBm. The shorthand `PA` is now strongly associated with `pdgain2g`, but the exact Broadcom encoding of `pdgain` remains undocumented in the primary material found so far.

The newer controlled results add an important interaction:

| 2.4 GHz profile | Result at 5 m |
|---|---|
| `pdgain2g=14`, `maxp2ga0/1=80` | about -21/-22 dBm |
| `pdgain2g=16`, `maxp2ga0/1=80` | about -17 dBm |
| `pdgain2g=16`, `maxp2ga0/1=90` | link collapses to about -70 dBm |

That collapse proves the fields do not form a simple monotonic power slider. A defensible working model is that `pdgain` selects part of the detector/TSSI calibration model and `maxp` supplies a requested maximum/target. The PD16/MAXP90 pair appears to push the closed-loop/calibration regime outside a usable range. This is an inference from the A/B result, not a decoded vendor definition.

At the same fixed 5 m distance, the observed bidirectional stock-to-modified changes were approximately:

- SC2 to Bebop: -36.5 to -20.3 dBm, about +16.2 dB.
- Bebop to SC2: -31.5 to -17.5 dBm, about +14.0 dB.

These are excellent relative A/B observations but are not direct transmitter power measurements. Near-field geometry, receiver AGC/calibration behavior, antenna coupling, and RSSI quantization prevent converting the delta directly to milliwatts.

## Parameter meanings and confidence

| Field family | Current interpretation | Confidence |
|---|---|---|
| `maxp2ga*` | documented per-chain maximum power value, quarter-dB units | high |
| `pa2ga*` | TSSI-derived PA calibration coefficients | high; do not guess values |
| `mcs*po`, `ofdm*po`, `cck*po` | per-rate power offsets/backoffs | high |
| `epagain2g` | PA topology/mode selector; value 2 is empirically decisive on this hardware | high for the result, incomplete for numeric encoding |
| `pdgain2g` | detector/TSSI gain or calibration selector interacting strongly with `maxp` | medium; exact encoding unknown |
| `femctrl` | selects a built-in FEM control table, not a Boolean LNA switch | high |
| `rxgains*elnagain*` | eLNA gain-model calibration numbers | high; not direct enable bits |
| `rxgains*trelnabyp*` | eLNA bypass-path isolation calibration | high; not Boolean bypass flags |

The SKY85803 devices are controlled by logic pins from the Broadcom radio rather than a separate I2C/SPI register file. A second user-space SKY85803 configuration file is therefore not expected; relevant alternate behavior would be in the Broadcom NVM, embedded radio profile, selected FEM table, explicit switch-control map, or a boot-time `bcmwl` override.

## Primary documentation

- [Infineon AN215294: CYW4335 OTP Programming and NVRAM](https://www.infineon.com/dgdl/Infineon-AN215294_CYW4335_OTP_Programming_and_NVRAM-ApplicationNotes-v04_00-EN.pdf?fileId=8ac78c8c7cdc391c017d0d2c9c1b6422) documents `maxp2ga*`, `pa2ga*`, and per-rate offsets on a closely related Broadcom architecture. It also calls for EVM, spectral-mask, RX-PER, and band-edge validation after NVRAM tuning.
- [Infineon AN229472: OTP Memory Programming and NVRAM Development](https://www.infineon.com/dgdl/Infineon-AN229472_-_OTP_Memory_Programming_and_NVRAM_Development_-_CYW8X373-ApplicationNotes-v05_00-EN.pdf?fileId=8ac78c8c7cdc391c017d0d39db956707) provides newer NVRAM-development context.
- [Skyworks SKY85803 data sheet](https://www.skyworksinc.com/-/media/AD1A750EED664950910713311CB9F3AD.pdf) defines the FEM control-pin truth table and RX-LNA/TX-PA states.

Neither Infineon application note searched above defines `pdgain`. Until a BCM43526-specific SROM map or source-level definition is recovered, claims that a `pdgain` number directly means a requested dB gain should be treated as shorthand, not documentation.
