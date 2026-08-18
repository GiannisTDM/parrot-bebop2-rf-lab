# RF experiment record

This document preserves the available measurements, including unsuccessful profiles and qualitative field observations. Values copied from screenshots are intentionally not given false precision.

## Test interpretation rules

- A0/A1 values are receiver-reported power per chain.
- `S` is signal or calculated SNR depending on the display version; the raw A0/A1 and noise values are more useful.
- Historical `TX Fail` values are cumulative association counters. A value that does not increase after association is not a continuing failure rate.
- Strong readings near or above 0 dBm are likely outside the calibrated linear range of the receiver.
- RSSI comparisons are strongest when distance, orientation, channel, bandwidth, rate and surroundings are unchanged.

## Recovered 12 February 2025 tests

Only the SkyController 2 was modified; the Bebop 2 was the unchanged receiver. This direction isolation rules out an SC2 receive-LNA change as the explanation for the improvement.

The original shorthand is preserved because the command line itself has not been recovered:

| Recorded profile | Bebop-reported A0/A1 | Comment |
|---|---:|---|
| stock | -31 / -37 dBm | baseline |
| `int PA 12, E pa 10` | -36 / -41 dBm | worse than stock |
| `int PA 14, E pa 2` | -16 / -22 dBm | large improvement |
| `PA 15, epa 2` | -16 / -22 dBm | same result |
| `PA 16, epa 1` | -35 / -41 dBm | weak |
| `PA 16, epa 2` | -17 / -23 dBm | large improvement |

An `EPA=0` note contains two nearby pairs, approximately `-30/-28` and `-34/-42`; the surviving screenshot does not make the exact association clear, so neither pair is used in calculations.

Holding the shorthand `PA=16` while changing only `epa` from 1 to 2 produced approximately 18 dB more received signal on both chains. Later reproduction associates the shorthand with persistent NVM values `pdgain2g` and `epagain2g` respectively.

The same record contains later GPT-4 suggestions involving maximum power 100/90, SAR 12 and `pdoff=3`. The experimenter confirms that these were speculative suggestions, not part of the demonstrated modification; they are excluded from the causal result.

## Reproduced calibration matrix

The following profiles were tested at approximately 5 m:

| `epagain2g` | `pdgain2g` | `maxp2ga0/1` | Result |
|---:|---:|---:|---|
| 2 | 14 | 80 / 80 | approximately -21/-22 dBm |
| 2 | 16 | 80 / 80 | approximately -17 dBm |
| 2 | 16 | 90 / 90 | link collapsed to approximately -70 dBm |

The collapse at `PD16/MAXP90` is important negative evidence. These parameters do not behave as additive or monotonic gain settings.

## Fixed 5 m bidirectional comparison

Both endpoints were observed before and after applying the stable `EPA2/PD16/MAXP80` profile.

| Receiver | Transmitter | Stock | Modified | Delta |
|---|---|---:|---:|---:|
| Bebop 2 | SkyController 2 | approximately -36.5 dBm | approximately -20.3 dBm | +16.2 dB |
| SkyController 2 | Bebop 2 | approximately -31.5 dBm | approximately -17.5 dBm | +14.0 dB |

Representative modified per-chain values were about -20/-20 dBm at the Bebop and -15/-20 dBm at the SkyController. Representative stock values were about -35/-39 dBm at the Bebop and -30/-33 dBm at the controller.

The asymmetry is consistent with the stock Bebop being a little stronger than the stock controller, but it does not by itself identify whether the difference comes from conducted power, antenna pattern, calibration, or receiver-chain layout.

### Fresh annotated replication

A later same-channel 5 m capture reproduced the effect with the unified RF Lab display and the active values visible in every image. Both endpoints were stock during the baseline and both used the experimental profile during the modified run:

| Receiver | Incoming direction | Stock | Modified | Delta |
|---|---|---:|---:|---:|
| Bebop 2 | SC2 -> Bebop | -38 dBm | -22 dBm | +16 dB |
| SkyController 2 | Bebop -> SC2 | -33 dBm | -18 dBm | +15 dB |

The screen reports the active NVM of the **receiving** endpoint. Accordingly, the stock Bebop capture shows `EPA0/PD7/MAXP76`, while the stock SC2 capture shows `EPA0/PD7/MAXP80`. Both modified captures show `EPA2/PD16/MAXP80`. The driver request remained `qtxpower=127`, confirming that this generic ceiling readout does not reveal the NVM calibration change.

The associated screenshots are the primary visual evidence in the repository README. Earlier approximately +16.2 dB and +14.0 dB runs remain useful independent repetitions rather than being replaced by the newer values.

## Adjacent-device observations

With the antennas extremely close after modifying both endpoints, reported values moved through roughly -8 dBm to positive readings; one chain displayed as high as +8 dBm.

This is evidence of very strong coupling, not a calibrated power measurement. At that separation the antennas are in each other's reactive/radiating near field, mutual coupling dominates, and the receiver/FEM can saturate or enter bypass. These readings are excluded from the power estimate.

## 52 m comparison

At approximately 52 m:

- Bebop receiver: the two chains were generally around -41 to -46 dBm, commonly -42/-42 through -45/-45.
- SkyController receiver: A0 was roughly -36 to -40 dBm and A1 roughly -42 to -48 dBm.
- SC2 noise was approximately -89 to -92 dBm, producing displayed SNR values around 45–53 dB.
- Link rates continued to vary normally between Broadcom rate selections rather than remaining at one fixed 65 Mbps value.

This distance is much more useful than an adjacent-device test because the link is safely in the far field and below receiver saturation.

## 650 m field observation

A later flight reached approximately 650 m horizontal separation. The aircraft was about 14 m below the takeoff elevation. The controller did not have clean optical line of sight for the entire path; some dirt/terrain and trees were in the propagation path.

The aircraft used an aftermarket 4,000 mAh GiFi pack. That pack has produced more than 35 minutes of flight in prior use; it changes endurance and supply behavior but is not part of the RF modification.

Observed behavior:

- three to four indicated signal bars;
- responsive controls;
- no visible video clipping, freezing or frame drops;
- waves remained clearly visible in the live feed;
- normal Bebop image-stabilization/jello artifacts only.

This is encouraging link-level validation, but no synchronized CSV or conducted-power measurement was captured. It must therefore remain a qualitative field observation rather than a claimed range guarantee.

## Third-party Solaris/PES comparison

Historical videos from the developer of the unavailable PES utility and commercial booster kits provide context, but the apparatus and calibration files are unavailable:

- reported stock SC2 output was about 14 mW for the relevant antenna path;
- the Bebop 2 was described as somewhat stronger in stock form;
- the commercial kits were described as roughly 1–2 W amplifiers;
- a booster-equipped SC2 displayed approximately 1.35 W on an RF power meter connected near the U.FL path;
- a separate drone-side 5 GHz demonstration was described as approximately 1.34 W conducted output;
- booster-equipped 5 m RSSI screenshots were approximately -15 to -20 dBm, close to this project's software-profile readings;
- a published flight showed approximately -73 dBm around 1.3 km with obstruction, according to the video overlay.

These are comparison points, not measurements performed by this project. The similarity at 5 m cannot distinguish 0.6 W from 1.35 W because receiver RSSI, antenna geometry and strong-signal behavior differ between setups.

## Current conclusion

The evidence supports a real and useful link-budget increase. It does not yet prove exact conducted power, spectral cleanliness, legal EIRP, or long-term PA temperature. Those require an RF power meter or spectrum analyzer, calibrated attenuation, a 50-ohm load, fixed rates/channels, and preferably one chain at a time.
