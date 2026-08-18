# Transmit-power estimate

There are two relevant power quantities that must not be conflated:

- **Likely clean average modulated output:** approximately 0.12–0.25 W combined, depending on PHY mode and rate.
- **Instantaneous/peak-envelope output:** approximately 0.4–0.7 W combined in the high-power FCC measurements and the simple RSSI extrapolation.

Neither quantity has yet been measured directly on the modified devices.

## The direct RSSI extrapolation

The historical stock reference is 14 mW, or 11.46 dBm, for the relevant SkyController antenna path. The fixed-distance A/B test produced about +16.2 dB at the unchanged Bebop receiver:

```text
14 mW x 10^(16.2/10) = 584 mW
```

Using the strongest approximately +17 dB samples gives 702 mW. For the Bebop, a working 22 mW stock baseline and the observed +14 dB change give approximately 553 mW.

These calculations are mathematically correct but metrologically weak. They assume that the historical 14 mW figure and Broadcom receiver RSSI describe the same power quantity, remain linear across the entire change, and are unaffected by rate, antenna geometry or receiver compression. Those assumptions are not established.

The resulting 0.55–0.70 W figure is best treated as a **peak-equivalent or upper-bound estimate**, not clean average RF power.

## SKY85803 clean-output rating

The [Skyworks SKY85803 data sheet](https://www.skyworksinc.com/-/media/AD1A750EED664950910713311CB9F3AD.pdf) gives typical rated 2.4 GHz output of:

| Mode | Per FEM/chain | Two equal chains combined |
|---|---:|---:|
| 802.11n/64-QAM at 3% EVM | +18 dBm, about 63 mW | +21 dBm, about 126 mW |
| 802.11b/11 Mbps at the stated ACPR | +21 dBm, about 126 mW | +24 dBm, about 252 mW |

That makes approximately **0.12 W combined average output** a strong central expectation for a healthy two-chain high-rate OFDM link. Lower-order or CCK modes can permit higher average power.

The modified calibration could drive the PAs beyond those clean-output conditions. If it does, average power may rise while EVM and spectral regrowth become worse. Smooth video and a high received signal do not establish spectral cleanliness.

## FCC peak measurements

The FCC reports explicitly label their values **maximum conducted peak output power**. Representative results were:

| Device/mode | Per-chain peak | Combined peak |
|---|---:|---:|
| SC2 802.11n | approximately 24.2–25.6 dBm | approximately 26.1–28.0 dBm, or 0.41–0.63 W |
| Bebop 2 802.11n | approximately 24.6–25.2 dBm | approximately 27.7–28.0 dBm, or 0.59–0.63 W |

- [SkyController 2 FCC test report](https://fccid.io/2AG6ISKC2/Test-Report/Test-Report-3077117)
- [Bebop 2 FCC test report](https://fccid.io/RKXMYKONOS3/Test-Report/Test-Report-2838596)

These peak figures explain why the earlier 0.5–0.7 W estimate looked so physically coherent. They do not show that the average OFDM carrier power is 0.5–0.7 W; OFDM has substantial peak-to-average ratio and the SKY85803 data sheet specifies average clean output through EVM.

## Free-space consistency check

At 2.4 GHz, ideal free-space path loss is approximately 54.0 dB at 5 m and 74.4 dB at 52 m.

Using approximately 21 dBm combined average OFDM power and roughly 8 dB total nominal antenna gain across both endpoints predicts about -45 dBm at 52 m before implementation and propagation corrections. The observed modified readings were approximately -42 to -45 dBm on the Bebop side and -36 to -48 dBm across the SC2 chains.

That longer-distance result is compatible with operation near the FEM's rated clean output. A 28 dBm average transmitter would instead predict around -38 dBm before additional losses. Both can be made to fit a real outdoor path, but the lower clean-average estimate requires fewer assumptions.

The 5 m readings are less decisive because strong-signal RSSI behavior, multipath and antenna geometry have more influence. Adjacent-device readings near or above 0 dBm are excluded entirely.

## Why the estimate remains uncertain

- The 14 mW historical reference may describe one chain, one antenna pair, a particular rate, or time-averaged traffic.
- Broadcom RSSI can compress or become biased at high input levels.
- Different PHY modes and rates have different power backoffs and peak-to-average ratios.
- Antenna orientation and MIMO/STBC combining move received power without a corresponding conducted-power change.
- An incorrectly selected TSSI/PDET regime can increase indicated or peak power while degrading EVM.
- The RF Lab `qtxpower` and `txinstpwr` values are driver requests/estimates, not calibrated external measurements.

The defensible current statement is therefore:

> The modification produced a measured +14 to +16.2 dB receiver-reported link change. Primary specifications suggest roughly 0.12–0.25 W combined clean average output and 0.4–0.7 W combined peak envelope, but the modified devices have not yet been measured conductively.

## Decisive future measurement

Measure each U.FL chain into a 50-ohm instrument path using enough 2.4 GHz-rated attenuation to protect the meter or analyzer. Record:

1. stock and modified profiles;
2. both chains separately;
3. fixed 2.4 GHz channels;
4. CCK, OFDM and MCS rates;
5. average burst power and peak-envelope power separately;
6. EVM, spectrum mask and band-edge emissions;
7. FEM temperature during a controlled packet duty cycle.

Do not connect an unattenuated transmitter directly to a sensitive analyzer input.
