# Roadmap

HomeAgent roadmap is organized by lanes, not by hype level.

## Current Lane — Minimal Open Hub BSP

| Phase | Name | Goal | Status |
|------:|------|------|--------|
| 0 | Origin proof | Preserve RPi5/Yocto/Hailo + matter.js/Go/Flutter evidence | done |
| 1 | Target taxonomy | SG2000, SSD202D, EFR32, RAM lower-bound strategy | current |
| 2 | Open-source fork baseline | Boot/build linux-chenxing/OpenWrt/Buildroot baseline for THP23-ZB-X now; Milk-V SDK after arrival | current |
| 3 | Board ownership | UART, U-Boot/recovery, flash/rootfs access on THP23-ZB-X now; SMHUB/Milk-V after delivery | current / partial hardware blocked |
| 4 | Radio ownership | Detect onboard EFR32, control reset/bootloader, verify firmware paths | planned |
| 5 | Service lower-bound | MQTT, Zigbee2MQTT, matter.js, Go RSS/process evidence on 512MB-class board | planned |
| 6 | Representative hub | Mirror edge state outward through a stable hub surface | planned |

## Target Boards

- **SMHUB Nano MG24**: primary SG2000 + EFR32MG24 minimal hub candidate.
- **Milk-V Duo S / SDK v2 family**: public Buildroot baseline.
- **Tuya THP23-ZB-X**: current in-hand liberation target (128MB, SSD202D, onboard EFR32). Open-source fork bring-up before SMHUB-class arrives.
- **RPi5 + Hailo-8**: high-spec origin lane, preserved.
- **OPi5**: lab target, mainline 6.14 evidence preserved, vendor/RKNN parked.

## Done / Preserved Evidence

- matter.js backend and Go controller proof.
- OTBR / EFR32 USB coordinator proof.
- Flutter/Lit client experiments.
- RPi5 Yocto / Hailo integration evidence.
- Android/RK compatibility experiments archived as secondary evidence.

## Non-goals For Now

- Productizing USB-only coordinators.
- Expanding Android server deployment.
- Reviving OPi5 vendor RKNN path.
- Polishing Hailo benchmark narratives.
- Moving ESP32 node definitions into this repo.
