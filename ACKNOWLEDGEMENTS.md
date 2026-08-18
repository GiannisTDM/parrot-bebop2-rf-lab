# Acknowledgements and inspiration

## The unofficial Bebop drone hacking guide

GiannisTDM credits the authors, contributors and wider forum community behind [*An unofficial Bebop drone hacking guide 1.7.2*](https://fargesportfolio.com/wp-content/uploads/2018/01/BeebopHackingGuide1_7_2.pdf), last updated 15 January 2018.

The guide gathered years of community investigation into one practical reference: the ARDrone3/Linux filesystem, Telnet and FTP access, writable-mount procedure, backups, `dragon-prog`, `bcmwl`, diagnostics, power-button hooks, USB networking, firmware recovery and numerous reversible experiments. More importantly, it made clear that the Bebop was not merely an appliance but a remarkably open flying Linux computer. That was a meaningful part of the inspiration for beginning this Bebop 2 work.

No source code or RF-power recipe was taken from the guide. The `epagain2g`/`pdgain2g` result, bidirectional testing, RF Lab tooling and firmware analysis in this repository are independent follow-on work. The acknowledgement is for the guide's foundational documentation, community knowledge and the curiosity it encouraged.

## Solaris/PES prior work

The unavailable PES utility and Solaris's commercial BB2/SC2 booster demonstrations provided historical prior art and a useful target for comparison. Public videos showed per-chain RSSI telemetry, hardware amplifier kits and conducted-power demonstrations. No PES source code or commercial booster design was available or incorporated here; the RF Lab tool is an independent BusyBox implementation based on locally observed `bcmwl` output.

## Parrot and the broader community

Parrot's accessible Linux systems, published developer material and open-source releases made unusually deep independent investigation possible. This repository also benefits from the many Bebop owners who preserved firmware, forum posts, experiments and repair knowledge after official product development ended.
