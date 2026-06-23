# Roadmap

HomeAgent roadmap is organized by lanes, not by hype level.

## Current Lane — Minimal Open Hub BSP

| Phase | Name | Goal | Status |
|------:|------|------|--------|
| 0 | Origin proof | Preserve RPi5/Yocto/Hailo + matter.js/Go/Flutter evidence | done |
| 1 | Target taxonomy | SG2000, SSD202D, EFR32, RAM lower-bound strategy | current |
| 2 | Open-source build baseline | Milk-V Duo S Buildroot SDK v2 baseline on ARM boot lane | planned (hardware-gated) |
| 3 | Board ownership | ARM boot fix, UART, U-Boot/recovery, flash/rootfs access on SG2000-class | planned (hardware-gated) |
| 4 | Runtime stratification | Zig 100ms `homeagentd` on ARM Linux + C906 FreeRTOS mailbox base | planned |
| 5 | Radio ownership | Detect onboard EFR32MG24, control reset/bootloader, verify firmware paths | planned |
| 6 | Service lower-bound | MQTT, Zigbee2MQTT, matter.js, Go RSS/process evidence on 512MB-class board | planned |
| 7 | Representative hub | Mirror edge state outward through a stable hub surface | planned |

Architecture center for phases 3–4: [`runtime/README.md`](runtime/README.md)
(ARM Linux + Zig state machine + C906 coprocessor).

## Target Boards

- **Milk-V Duo S / SDK v2 family**: active public BSP + ARM boot lane. The board where the runtime stratification and C906 base get built.
- **SMHUB Nano MG24**: primary product-shaped SG2000 + EFR32MG24 minimal hub candidate.
- **Tuya THP23-ZB-X**: parked 128MB lower-bound evidence (SSD202D, 128MB). No longer the active bring-up lane.
- **RPi5 + Hailo-8**: high-spec origin lane, preserved.
- **OPi5**: lab target, mainline 6.14 evidence preserved, vendor/RKNN parked.

## Done / Preserved Evidence

- matter.js backend and Go controller proof.
- OTBR / EFR32 USB coordinator proof.
- Flutter/Lit client experiments.
- RPi5 Yocto / Hailo integration evidence.
- Android/RK compatibility experiments archived as secondary evidence.

## Non-goals For Now

- Active Tuya THP23-ZB-X liberation/bring-up (kept only as parked 128MB evidence).
- Booting SG2000 in RISC-V mode for the hub runtime (ARM A53 boot lane is fixed).
- Productizing USB-only coordinators.
- Expanding Android server deployment.
- Reviving OPi5 vendor RKNN path.
- Polishing Hailo benchmark narratives.
- Moving ESP32 node definitions into this repo.
