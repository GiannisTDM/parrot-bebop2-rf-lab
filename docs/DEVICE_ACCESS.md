# Device access and important paths

This page documents the interfaces used during the research. Addresses assume the stock Bebop network.

## Bebop 2

| Service | Address | Notes |
|---|---|---|
| Telnet | `192.168.42.1:23` | Root BusyBox shell on the tested firmware |
| FTP | `192.168.42.1:21` | Root is `/data/ftp`; `internal_000` is writable storage |
| ADB/TCP | `192.168.42.1:9050` | Present on the tested debug firmware but Telnet was simpler |

Important paths:

```text
/lib/firmware/brcm/bcm43526.nvm          active radio NVM
/lib/firmware/brcm/bcm43526-firmware.bin radio firmware
/data/ftp/internal_000/                  FTP-visible writable storage
/sbin/broadcom_setup.sh                  AP-mode Wi-Fi startup
```

Run the RF Lab tool:

```sh
telnet 192.168.42.1
sh /data/ftp/internal_000/parrot_rf_lab.sh menu
```

## SkyController 2

The tested stock image exposes root ADB over TCP 9050 when reachable through the Bebop network:

```sh
adb connect 192.168.42.88:9050
adb -s 192.168.42.88:9050 shell
```

The controller is normally a DHCP client, so `.88` is an observed address rather than a universal guarantee. Confirm it from the Bebop ARP table or DHCP leases if needed.

Its stock `/etc/inetd.conf` provides FTP but no Telnet service. The research controller was later given an explicitly requested persistent Telnet entry; that is a local maintenance change, not a stock capability.

Important paths:

```text
/lib/firmware/brcm/bcm43526-ffff-ffff.nvm active radio NVM
/factory/bcm43526-ffff-ffff.nvm            factory recovery/calibration copy
/lib/firmware/brcm/bcm43526-firmware.bin  radio firmware
/data/lib/ftp/internal_000/                FTP-visible writable storage
/var/lib/ftp/internal_000/                 alternate view of the same storage
/usr/bin/wifid                             Wi-Fi daemon
/usr/sbin/bcmwl                            Broadcom query/control utility
```

Run the RF Lab tool from the controller shell:

```sh
sh /data/lib/ftp/internal_000/parrot_rf_lab.sh menu
```

## Internet-preserving relay

When the Mac needs to remain on an Internet connection while the Bebop network is reached through another interface, a local relay can expose the Telnet service only on loopback:

```sh
socat TCP-LISTEN:2323,bind=127.0.0.1,reuseaddr,fork TCP:192.168.42.1:23
telnet 127.0.0.1 2323
```

This relay is ephemeral and does not modify the drone.

## Recovery rules

- Never publish complete captures: they can contain Wi-Fi credentials, paired-device records, serial numbers, GPS history and per-unit RF calibration.
- Never overwrite `/factory` as part of an experiment.
- Never flash another unit's complete NVM. Change only the intended named fields in a copy of the device's own active file.
- Keep a digest and an FTP-visible backup before each write.
- Reboot after changing NVM, then compare file values with `bcmwl nvram_dump` runtime values.
