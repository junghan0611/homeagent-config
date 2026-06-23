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

## ISA Lanes — ARM now, RISC-V as the open-ISA north star

SG2000 is a transition-era edge SoC (Cvitek camera/ISP/NPU heritage) whose big core
boots **either ARM Cortex-A53 or RISC-V C906**, selected by a board switch. We do not
treat this as trivia; it shapes the open-source roadmap.

- **Product / main lane — ARM A53 (now).** Mature aarch64 ecosystem: Node, Matter,
  Zigbee2MQTT, Go, Zig, vendor blobs. This is where the product hub ships.
- **Open-ISA comparison lane — RISC-V C906 (north star, not Phase 1).** The *same* SoC
  opens this at near-zero marginal cost — a boot switch plus a second rootfs. The future
  phase: boot the same `homeagentd` on the RISC-V core and **measure** toolchain maturity,
  perf-per-watt, and riscv64 package gaps. The gap itself is portfolio data.

Why keep RISC-V a lane instead of dismissing it: it closes the **"open all the way down"**
thesis that the rest of this repo already lives by —

> open ISA (RISC-V option) → open bootloader (mainline U-Boot / OpenSBI) → open kernel →
> open runtime (Zig `homeagentd`) → **open agent surface (A2A / A2UI)**.

ARM gives open *software* on a licensed ISA; the RISC-V option closes the loop to an open
*ISA*, so HomeAgent can claim openness at every layer from instruction set up to the
agent-to-agent and server-driven-UI surfaces. That is the differentiator between "a Linux
box running a smart-home app" and a **full-stack-open, heterogeneous-core product hub
runtime**. The C906 FreeRTOS (reflex), 8051 (autonomic), and EFR32MG24 (radio sense)
layers are independent of this big-core ISA choice.

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
- Booting SG2000 in RISC-V mode for the **product** runtime now (ARM A53 is the product lane; RISC-V is a future open-ISA comparison lane — see *ISA Lanes*).
- Productizing USB-only coordinators.
- Expanding Android server deployment.
- Reviving OPi5 vendor RKNN path.
- Polishing Hailo benchmark narratives.
- Moving ESP32 node definitions into this repo.
