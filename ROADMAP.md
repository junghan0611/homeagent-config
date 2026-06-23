# homeagent-config ROADMAP — current + future direction

> This document is **the present and the forward direction**. `NEXT.md` is the
> disposable next-step compass; `CHANGELOG.md` is the published "closed change" log;
> this `ROADMAP.md` is the phase-direction and design SSOT. Per-session process noise
> of closed work lives in git commit history. Organized by lanes, not by hype level.

---

## Now — SG2000 minimal open hub runtime (boards in transit)

The active lane is a product-shaped minimal open hub on **SG2000-class** hardware —
**Milk-V Duo S (dev) + SMHUB Nano MG24 (product)**, both bought, delivery pending. The
big core is **fixed to ARM Cortex-A53 boot**. The runtime is a **Zig 100ms `homeagentd`
state machine on Linux (L3)** over a **C906 FreeRTOS mailbox coprocessor (L2)**, with
EFR32MG24 radio (L0) and an 8051 always-on layer (L1, deferred).

Architecture center for the runtime: [`runtime/README.md`](runtime/README.md)
(L0–L4 stratification, ARM boot decision, Zig state machine, C906 mailbox base).

### Phase grid

| Phase | Name | Goal | Status |
|------:|------|------|--------|
| 0 | Origin proof | Preserve RPi5/Yocto/Hailo + matter.js/Go/Flutter evidence | done |
| 1 | Target taxonomy | SG2000, SSD202D, EFR32, RAM lower-bound strategy | current |
| 2 | Open-source build baseline | `duo-buildroot-sdk-v2` (develop) baseline on ARM boot lane | planned (hardware-gated) |
| 3 | Board ownership | ARM boot fix, UART, U-Boot/recovery, flash/rootfs access on SG2000-class | planned (hardware-gated) |
| 4 | Runtime stratification | Zig 100ms `homeagentd` on ARM Linux + C906 FreeRTOS mailbox base | planned |
| 5 | Radio ownership | Detect onboard EFR32MG24, control reset/bootloader, verify firmware paths | planned |
| 6 | Service lower-bound | MQTT, Zigbee2MQTT, matter.js, Go RSS/process evidence on 512MB-class board | planned |
| 7 | Representative hub | Mirror edge state outward through a stable hub surface | planned |

### BSP base — dev SDK, then diff the product

BSP base is **`milkv-duo/duo-buildroot-sdk-v2` (`develop`)** — the whole boot chain in one
tree (fsbl/opensbi/u-boot-2021.10/linux_5.10/ramdisk/**freertos**). The SMHUB Nano is the
same SG2000 but SMLIGHT ships a **separate, more mainline product Buildroot** (kernel
6.18 / OpenSBI 1.8 / U-Boot 2026.04 / Buildroot 2025.11). Methodology: **build from the
dev SDK first, then diff the product** to learn the tuning. Detail in
[`runtime/README.md`](runtime/README.md) and [`docs/TARGET_DEVICE.md`](docs/TARGET_DEVICE.md).

## Near-term lane — board-less prep (do before hardware)

Everything here is doable now, on the cloned sources in `~/repos/3rd/milkv/`:

- Pin the ARM build recipe: SDK V2 `build.sh` with an `-arm64-` board config (Docker);
  acceptance = boot-log first line `B` (ARM) not `C` (RISC-V).
- Study the L2 mailbox base: `duo-buildroot-sdk-v2/freertos` + `duo-examples/mailbox-test`
  (8-byte cmdqu; `CMD_*`/`param_ptr` pattern) — shape it into a hub lifecycle supervisor.
- Design the `homeagentd.zig` 100ms loop skeleton (timerfd/epoll/monotonic), and define
  the first milestone: "I am the hub → MG24/MQTT/Z2M alive? → state → recovery command".
- Keep `runtime/zig/homeagentd/` and `runtime/c906/rtos-agent/` checklists current.

## Big direction — ISA Lanes: ARM now, RISC-V open-ISA north star

SG2000 is a transition-era edge SoC (Cvitek camera/ISP/NPU heritage) whose big core boots
**either ARM Cortex-A53 or RISC-V C906**, selected by a board switch. This shapes the
open-source story.

- **Product / main lane — ARM A53 (now).** Mature aarch64 ecosystem (Node, Matter,
  Zigbee2MQTT, Go, Zig, vendor blobs). The product hub ships here.
- **Open-ISA comparison lane — RISC-V C906 (north star, not Phase 1).** The *same* SoC
  opens this for the price of a boot switch and a second rootfs. Future phase: boot the
  same `homeagentd` on the RISC-V core and **measure** toolchain maturity, perf-per-watt,
  and riscv64 package gaps. The gap itself is portfolio data.

Why keep RISC-V a lane instead of dismissing it: it closes the **"open all the way down"**
thesis the rest of this repo already lives by —

> open ISA (RISC-V option) → open bootloader (mainline U-Boot / OpenSBI) → open kernel →
> open runtime (Zig `homeagentd`) → **open agent surface (A2A / A2UI)**.

ARM gives open *software* on a licensed ISA; the RISC-V option closes the loop to an open
*ISA*, so HomeAgent can claim openness at every layer from instruction set up to the
agent-to-agent and server-driven-UI surfaces. That is the difference between "a Linux box
running a smart-home app" and a **full-stack-open, heterogeneous-core product hub
runtime**. The C906 FreeRTOS (reflex), 8051 (autonomic), and EFR32MG24 (radio sense)
layers are independent of this big-core ISA choice.

## Target boards

- **Milk-V Duo S / SDK v2 family** — active public BSP + ARM boot lane; the board the
  runtime and C906 base get built on.
- **SMHUB Nano MG24** — primary product-shaped SG2000 + EFR32MG24 minimal hub candidate;
  the product-tuning diff target.
- **Tuya THP23-ZB-X** — parked 128MB lower-bound evidence (SSD202D). Not an active lane.
- **RPi5 + Hailo-8** — high-spec origin lane, preserved.
- **OPi5** — lab target, mainline 6.14 evidence preserved, vendor/RKNN parked.

## Frozen invariants — lines not to cross

- ARM A53 is the **product** boot lane; do not put the product runtime on RISC-V (RISC-V
  is the future comparison lane only).
- One radio, one protocol at a time — Zigbee NCP **or** Thread RCP by firmware switching.
- Public repo only: no secrets, private business logic, internal production detail, or
  closed firmware blobs.
- On-device first; cloud is a fallback, not a dependency for local control.
- Go owns hub state; protocol backends do protocol work. LLM output is data to parse,
  never code to execute.
- br/beads is retired and not reintroduced.

## Measured / preserved evidence

- matter.js backend and Go controller proof.
- OTBR / EFR32 USB coordinator proof.
- Flutter/Lit client experiments.
- RPi5 Yocto / Hailo integration evidence.
- Android/RK compatibility experiments archived as secondary evidence.

## Deprecated — closed, do not reopen

- Active Tuya THP23-ZB-X liberation/bring-up (kept only as parked 128MB evidence).
- Booting SG2000 in RISC-V mode for the product runtime now.
- Productizing USB-only coordinators.
- Expanding Android server deployment.
- Reviving OPi5 vendor RKNN path.
- Polishing Hailo benchmark narratives.
- Moving ESP32 node definitions into this repo.

## Reference paths

- [`runtime/README.md`](runtime/README.md) — runtime architecture + Zig/C906 code home.
- [`docs/TARGET_DEVICE.md`](docs/TARGET_DEVICE.md) — board/radio strategy.
- [`docs/THP23-LIBERATION.md`](docs/THP23-LIBERATION.md) — parked 128MB-evidence research.
- [`VERSION.md`](VERSION.md) — stack / version / physical device matrix.
- Local clones: `~/repos/3rd/milkv/` (`duo-buildroot-sdk-v2` develop, `milkv.io` docs,
  `slzb-os-scripts`, SMHUB-OS release notes).
