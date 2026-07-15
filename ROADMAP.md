# homeagent-config ROADMAP — current + future direction

> This document is **the present and the forward direction**. `NEXT.md` is the
> disposable next-step compass; `CHANGELOG.md` is the published "closed change" log;
> this `ROADMAP.md` is the phase-direction and design SSOT. Per-session process noise
> of closed work lives in git commit history. Organized by lanes, not by hype level.

---

## What this repo is

An **open, reproducible verification and prototyping ground** for a minimal smart-home
hub — many boards, many dev environments, each technology proven in isolation before it
is wired together. **No business logic lives here**; product logic stays in its own
repos. This tree collects board bring-up records, BSP recipes, runtime skeletons, and
radio/service proofs so an open-source hub developer can reproduce the path.

Two SG2000 / RISC-V lanes anchor the current work:

- **Milk-V Duo S (RISC-V C906) — core lane, full-stack ownership.** We build the whole
  image ourselves (Buildroot → OpenSBI/U-Boot → Linux → rootfs → FreeRTOS), boot the
  RISC-V core on real silicon, and own every layer. This is where the runtime, toolchain,
  and services get prototyped freely.
- **SMHUB Nano MG24 (RISC-V C906) — commercial reference, system-application approach.**
  A shipping product whose kernel/image is vendor-managed (mainline 6.18 + RAUC A/B), so
  we work it as a *system application developer* — on top of the vendor OS — and carry its
  lessons over into the Duo S lane in our own way.

Both are **SG2000 / riscv64**, so the shared axis is real: SoC family, ISA, `musl` libc,
boot-chain knowledge, cross-toolchain. But the **images are not interchangeable** (Duo S =
milkv SDK Linux 5.10 + CVITEK `rtos_cmdqu`; SMHub = mainline 6.18 + standard
remoteproc/rpmsg + open-amp) — see the image-compat table in [`docs/SMHUB.md`](docs/SMHUB.md).

---

## North star — a custom Buildroot productization framework

The goal this lane builds toward: **our own customizable Buildroot** that packages a
**sample hub + app + server as one image**, boots on SG2000/RISC-V, and demonstrates the
functions all work — a public, reproducible reference for **productizing an open hub**. We
reference SMHub for *what* a shipped hub sets up (versions + surfaces recorded in
[`docs/SMHUB.md`](docs/SMHUB.md)), but we **own our Buildroot** rather than depend on a
vendor image whose setup is partly closed. **No business logic** — the deliverable is
"it's all wired, open, and reproducible."

What a productization framework has to pre-bake (reusable pre-work carried from prior
embedded-hub productization on a vendor OpenWrt image):

- **Device network** — DHCP/static, Wi-Fi + Ethernet, hostname / mDNS / provisioning.
- **Log management** — persistent logs, rotation, a clean ro-root / rw-data split.
- **Persistence / rw area** — overlay + writable data partition (SMHub uses p7; we design
  our own equivalent).
- **Package pre-install** — the minimal service set baked into the rootfs (MQTT broker,
  Zigbee2MQTT, matter.js / Matterbridge, `homeagentd`, a sample server + app).
- **Recovery / update path** — A/B or image-replace, first-boot provisioning.

Deliverable = **sample hub + app + server**, end to end, all functions demonstrably working
in a public repo. That is the meaningful result.

### SDK handling — extend `bsp/`, fork only if forced

The Milk-V sources are cloned at `~/repos/3rd/milkv/` (`duo-buildroot-sdk-v2` = BSP base
pinned `ad920f839`, `bootloader-riscv`, `milkv.io` docs). Default: keep working through
**`bsp/`** (committed defconfig + rootfs overlay + patches injected over a pinned, gitignored
clone — no fork needed). Fork a source repo only when a change **cannot** be expressed as a
defconfig, overlay, or patch. Detail + experience log: [`docs/BUILDROOT.md`](docs/BUILDROOT.md);
operational how-to: [`bsp/README.md`](bsp/README.md).

---

## Now — RISC-V C906 boot owned on Duo S

The big core is booted in **RISC-V C906 mode**. SG2000 boots either A53 (ARM) or C906
(RISC-V) by a board switch; our runtime target is `riscv64-linux-musl`, so RISC-V is the
point. **First success (2026-07-14):** our own Buildroot image booted on Duo S real
silicon — `Linux milkv-duo 5.10.4 riscv64`, our build timestamp, our defconfig, eth0 DHCP
+ Wi-Fi (aic8800) up. The lane now opens to memory reclaim, hub-minimal trimming, and the
real goal: measuring `homeagentd` on real RISC-V hardware.

The runtime is a **Zig 100ms `homeagentd` state machine on Linux (L3)** over a **C906
FreeRTOS mailbox coprocessor (L2)**, with radio at L0 and an 8051 always-on layer (L1,
deferred). Architecture center: [`runtime/README.md`](runtime/README.md).

### Phase grid

| Phase | Name | Goal | Status |
|------:|------|------|--------|
| 0 | Origin proof | RPi5/Yocto/Hailo + matter.js/Go/Flutter evidence preserved | done |
| 1 | Target taxonomy | SG2000, SSD202D, EFR32, RAM lower-bound strategy | done |
| 2 | Open BSP baseline | Own Buildroot `riscv64-musl` build for Duo S (SDK v2 lineage) | done |
| 3 | Board ownership (Duo S) | RISC-V boot on silicon, USB-download flash, rootfs/net | done |
| 4 | Board minimization | Reclaim camera/codec ION memory, trim `cvi_*` vision modules | current |
| 5 | Runtime on RISC-V | Measure Zig 100ms `homeagentd` + C906 mailbox base on silicon | next |
| 6 | Radio via USB dongle | ZBDongle-E Zigbee NCP / Thread RCP on Duo S, z2m / matter proof | planned |
| 7 | SMHub reference diff | System-app review of the vendor product, port lessons to Duo S | ongoing |
| 8 | Productization rootfs | our Buildroot pre-bakes network / logging / rw-overlay / package set (the framework) | next major |
| 9 | Sample hub + app + server | end-to-end open demo — all functions working, reproducibly | goal |

### BSP base — own the Duo S build, diff the SMHub product

Duo S BSP base is **`milkv-duo/duo-buildroot-sdk-v2`** — the whole boot chain in one tree
(fsbl/opensbi/u-boot/linux_5.10/ramdisk/**freertos**). Our config lives in-repo under
`bsp/board/milkv-duos-musl-riscv64-{sd,emmc}/` (RISC-V + `musl` + hub-minimal delta); the
SDK itself is a pinned, gitignored clone. The SMHUB Nano is the same SG2000 but SMLIGHT
ships a **separate mainline product Buildroot** (kernel 6.18 / OpenSBI 1.8 / U-Boot
2026.04 / Buildroot 2025.11) we do **not** rebuild — we read and diff it as a system-app
developer. Detail in [`runtime/README.md`](runtime/README.md),
[`docs/TARGET_DEVICE.md`](docs/TARGET_DEVICE.md), [`docs/SMHUB.md`](docs/SMHUB.md).

## Near-term lane — post-boot (Duo S)

Boot is owned; the near-term turns the board into a runtime lab (live detail in
[`NEXT.md`](NEXT.md)):

- **Reclaim memory** — the camera/codec ION carveout (~170MB of 512MB) is reserved for
  vision buffers a hub never uses; trim defconfig/DT + drop `cvi_*` vision modules.
- **Measure `homeagentd` on RISC-V** — put the `riscv64-linux-musl` Zig binary on the
  board and measure the 100ms tick, RSS, and watchdog on real silicon (previously only
  estimated from SMHub).
- **Radio via USB dongle** — bring up ZBDongle-E (EmberZNet 7.4.2) + z2m on Duo S.
- **Diff SMHub lessons in** — carry vendor-product insight (persistence, service
  lifecycle, radio flow-control) into the Duo S lane as our own design.

## Radio — onboard on SMHub, USB dongle on Duo S

Duo S has **no onboard radio** (512MB DDR, Wi-Fi6/BT5, 100M eth, eMMC — no MG24). So
Zigbee/Matter on the Duo S lane rides a **USB coordinator**: Sonoff **ZBDongle-E**
(EFR32MG21), flashed to match the SMHub board stack — **EmberZNet 7.4.2 / EZSP 13** — so
z2m behaves identically on dongle and board. Firmware + flash notes:
[`firmware/zbdonglee/`](firmware/zbdonglee/). SMHub keeps its **onboard EFR32MG24** (ember
coordinator). One radio, one protocol at a time (Zigbee NCP **or** Thread RCP by firmware).

## Big direction — ISA: RISC-V now, open all the way down

Earlier this repo treated ARM A53 as the product boot lane and RISC-V as a north-star
comparison. **That is inverted now:** the target is **RISC-V C906**, and Duo S proves we
can own it end to end. SG2000 boots either core by a board switch; choosing RISC-V closes
the "open all the way down" thesis the rest of this repo lives by —

> open ISA (RISC-V) → open bootloader (mainline U-Boot / OpenSBI) → open kernel →
> open rootfs (our Buildroot) → open runtime (Zig `homeagentd`) →
> **open agent surface (A2A / A2UI)**.

ARM gives open *software* on a licensed ISA; RISC-V closes the loop to an open *ISA*, so
HomeAgent can claim openness at every layer from the instruction set up. ARM A53 builds
are kept only as **historical** artifacts (`out/…-arm64-…`), not an active lane. The C906
FreeRTOS (reflex), 8051 (autonomic), and EFR32 (radio sense) layers are independent of the
big-core ISA choice.

## Target boards & dev environments

This repo is a multi-board record. Active and parked lanes:

- **Milk-V Duo S (SG2000, RISC-V C906)** — **core lane**. Own the full image (Buildroot →
  RISC-V boot → rootfs → runtime). Radio via USB ZBDongle-E.
- **SMHUB Nano MG24 (SG2000, RISC-V C906)** — **commercial reference**. Vendor SMHUB OS;
  system-application approach; onboard EFR32MG24. Diff target for lessons.
- **Tuya THP23-ZB-X (SSD202D, 128MB)** — parked lower-bound evidence. Not active.
- **RPi5 + Hailo-8** — high-spec origin lane, preserved (matter.js / OTBR / Go / Flutter / Hailo).
- **OPi5** — lab target, mainline 6.14 evidence preserved; vendor / RKNN parked.

## Frozen invariants — lines not to cross

- **RISC-V C906 is the target boot lane** for the Duo S core lane; the runtime target is
  `riscv64-linux-musl`. ARM A53 builds are historical comparison only, not the product.
- **Duo S and SMHub images are not interchangeable** — different kernel, inter-core IPC,
  init, and update system. Do not treat a Duo S image as a product image, or flash one
  where the other belongs.
- **No business logic in this repo** — verification surfaces and prototypes only; product
  logic stays in its own repos.
- One radio, one protocol at a time — Zigbee NCP **or** Thread RCP by firmware switching.
- Public repo only: no secrets, private business logic, internal production detail, or live
  device coordinates. Redistributable firmware blobs only (public upstream).
- On-device first; cloud is a fallback, not a dependency for local control.
- LLM output is data to parse, never code to execute.
- br/beads is retired and not reintroduced.

## Measured / preserved evidence

- **Duo S RISC-V first boot (2026-07-14)** — our Buildroot image on real silicon, riscv64,
  eth0 DHCP + Wi-Fi; evidence under `captures/`.
- **SMHub Nano live stack** grounded (0.9.8 + OTA beta5): ember Zigbee coordinator, C906L
  RTOS remoteproc/rpmsg, install/persistence/GPIO surface — [`docs/SMHUB.md`](docs/SMHUB.md).
- matter.js backend + Go controller proof; OTBR / EFR32 USB coordinator proof.
- Flutter / Lit client experiments; RPi5 Yocto / Hailo integration evidence.
- Android / RK compatibility experiments archived as secondary evidence.

## Deprecated — closed, do not reopen

- **ARM A53 as the product boot lane** (superseded by RISC-V C906; ARM kept historical only).
- Active Tuya THP23-ZB-X liberation / bring-up (kept only as parked 128MB evidence).
- USB-only coordinator as the *final product* radio (the USB dongle is a dev / proto radio;
  the product radio is onboard EFR32).
- Expanding Android server deployment.
- Reviving OPi5 vendor RKNN path.
- Polishing Hailo benchmark narratives.
- Moving ESP32 node definitions into this repo.

## Reference paths

- [`runtime/README.md`](runtime/README.md) — runtime architecture + Zig / C906 code home.
- [`docs/SMHUB.md`](docs/SMHUB.md) — SMHub Nano live-measured SSOT (HW / radio / install / persistence / GPIO).
- [`docs/TARGET_DEVICE.md`](docs/TARGET_DEVICE.md) — board / radio strategy.
- [`docs/HUBS.md`](docs/HUBS.md) — certified Zigbee/Matter hub landscape + SoC / radio comparison.
- [`docs/MULTIPROTOCOL.md`](docs/MULTIPROTOCOL.md) — single-radio Zigbee+Thread timing (MG21/24/26 → Series 3).
- [`firmware/zbdonglee/`](firmware/zbdonglee/) — ZBDongle-E coordinator firmware, version-aligned to the board.
- [`docs/THP23-LIBERATION.md`](docs/THP23-LIBERATION.md) — parked 128MB-evidence research.
- [`VERSION.md`](VERSION.md) — stack / version / physical device matrix.
- `bsp/` — in-repo Duo S RISC-V board configs + build / flash scripts.
- Local clones: `~/repos/3rd/milkv/` (`duo-buildroot-sdk-v2`, milkv.io docs, SMHUB-OS release notes).
