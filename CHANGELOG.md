# Changelog

## Unreleased

- Nothing yet.

## v2026.7.24 — Duo S arm64 hub: Node 22 + Zigbee2MQTT, reproducible flash-and-go

The headline: a Milk-V Duo S comes up as a working Zigbee hub from a single flash. Flash the
arm64 image, switch USB to host, plug the dongle — Zigbee2MQTT starts on the seeded config
with no hand-editing. Proven on a second, fresh board (sticker 91) end to end.

### Board / BSP — arm64 development lane

- **Moved the dev lane from RISC-V to arm64/glibc** (A53) for iteration speed, with a Bootlin GCC 13.3.0 toolchain in place of the stock Linaro GCC 7.3.1. RISC-V C906 + SDK-native musl remains the product ISA (parked, not dropped). The two share one die and a physical slide switch picks the boot core, so no board bring-up is needed to move between them.
- **Node.js 22.22.0 in the image** (ABI 127, ICU 73.2, V8 12.4), qemu-user verified. The V8 link that stalled for hours on riscv64 passed cleanly on arm.
- **Zigbee2MQTT 2.10.1 + a local mosquitto broker**, integrated the Buildroot-native way (`BR2_PACKAGE_NODEJS_MODULES_ADDITIONAL`) rather than staging a tree on the host — native addons build as AArch64. Fixed an upstream Buildroot bug where `nodejs.mk` referenced an undefined `NODEJS_CPU`, letting `npm_config_arch` go empty and risking x86_64 prebuilds in an aarch64 rootfs (fork `0913c339a`, worth reporting upstream).
- **USB switched to host mode for real.** The vendor `usb-host.sh` never actually flipped the controller (a double redirection meant the proc write was dropped); overlaid a corrected `homeagent-usb-mode` that drives the mux and writes `otg_role` at runtime — a dongle enumerates within a second, no reboot.
- **WiFi survives a reboot**: `S99wpa_supplicant` associates `wlan0` after the aic8800 driver comes up late in the background.

### Flashing — made reliable, and made honest

- **cdc_acm is let bind, then unbound — not blocked.** Its probe performs the CDC line setup (`SET_LINE_CODING`/`SET_CONTROL_LINE_STATE`) that opens the ROM's data pipe; blocking it (via `drivers_autoprobe=0` or a MODALIAS udev rule) makes every 512 KiB bulk write time out while usb_dl still reports 100%.
- **"USB download complete" is no longer trusted.** usb_dl counts chunks it hands to libusb whether or not they wrote, so a fully failed run still prints success — measured on 2026-07-24, a "100%" run left the eMMC byte-identical to the day before. `flash-emmc.sh` now counts timed-out chunks to detect the lying-progress mode and prints the image rootfs UUID to compare against the board.
- Fixed a `set -o pipefail` trap where `lsmod | grep -q` reported failure even with the module loaded (grep exits first, lsmod dies of SIGPIPE), silently skipping the cdc_acm handling; reads `/proc/modules` instead.
- Added `bsp/usb-recovery-prepare.sh` (idempotent host prep, NixOS read-only `/etc` fallback), the `duo-s-flash` skill capturing the sequence and the four look-alike failure strings, and `bsp/BOARDS.md` as a board inventory keyed on rootfs UUID.

### Zigbee2MQTT — flash-and-go

- **Pinned `serial.port`/`adapter` in the seed config.** The image has no `udevadm` (busybox mdev), so Z2M's serial auto-discovery dies with `spawn udevadm ENOENT` and exits before touching the radio. Our ZBDongle-E is a CP2102N → `/dev/ttyUSB0` via cp210x (not ttyACM), adapter `ember`. Verified end to end: EmberZNet 7.4.2, MQTT connected, frontend on :8080, on a fresh board with zero post-flash edits.

### Build

- **Incremental rebuilds in ~2-3 min.** Overlay/config-only changes do not need a clean build — Buildroot rsyncs the overlay in `target-finalize` every `make` and repacks the image, leaving V8/Node untouched. Measured 2026-07-24: a seed change rebuilt in 2m37s with `cc1plus` never spawning, versus 40m for a clean build. Documented in `bsp/README.md`.

### riscv64 pure-cross Node — parked, method preserved

- Promoted the proven pure-cross Node.js build method (no QEMU, SDK-native musl) to SSOT in `docs/BUILDROOT.md`, with the native-musl runtime contract. The lane is parked behind an upstream question (milkv-duo/duo-buildroot-sdk-v2#74), not abandoned; the arm64 lane exists to keep momentum while it waits.

## v2026.7.15 — Duo S RISC-V boot + SMHub live SSOT + repo-wide ARM→RISC-V realignment

### Board / BSP (Milk-V Duo S)

- Built a reproducible SG2000 hub image via the official Milk-V Docker (`bsp/`): config-in-repo + a pinned, gitignored SDK clone.
- **Switched the Duo S lane from ARM to RISC-V C906 and booted our own Buildroot image on real silicon (2026-07-14)** — `Linux milkv-duo 5.10.4 riscv64`, `isa: rv64imafdvcsu`, our defconfig, eth0 DHCP + Wi-Fi (aic8800). First success of the board-ownership lane; the runtime target is `riscv64-linux-musl`, matching the product ISA.
- Added in-repo RISC-V board configs `bsp/board/milkv-duos-musl-riscv64-{sd,emmc}/` (RISC-V + musl + hub-minimal delta), fixed a defconfig-injection bug in `bsp/build.sh` (was matching 3 defconfigs), and scripted the eMMC USB-download flash (`bsp/flash-emmc.sh`: `cdc_acm` unbind, `181x` chip arg, riscv64 ISA guard).

### SMHub reference (single SSOT)

- Merged the former SMHub docs (PRODUCT-CONFIG-MODEL + SMHUB-CONTROL-MAP + SMHUB-MANUAL-REVIEW) into one SSOT `docs/SMHUB.md`, and grounded the live **0.9.8** verify, then the **OTA beta5** stack.
- Grounded the beta5 live C906L RTOS stack + app wiring (remoteproc/rpmsg + open-amp, `smhub-broker`, ESPHome-on-RTOS), set the install policy (OTA over ssh repair; p7 as the only rw persistence surface), and derisked the RISC-V self-firmware path (RAM/persistence/NCP flow).
- Mapped the MG24 EmberZNet **7.4.2 [GA] / EZSP v13** host↔NCP version contract, documented the install surface + LED/button/GPIO map for open-source hub devs (incl. the 10s-hold vendor factory-reset conflict), and reconciled the vendor manual against the live Nano MG24.

### Radio

- Added version-aligned ZBDongle-E coordinator firmware for the Duo S lane: `firmware/zbdonglee/zbdonglee_zigbee_ncp_7.4.2.0_hw_flow_115200.gbl` (EmberZNet 7.4.2 / EZSP 13, matching the SMHub board stack) plus `firmware/zbdonglee/README.md` (upstream provenance + sha256, flash procedure, measured z2m `rtscts:false` note).

### Hubs / multiprotocol

- Added the certified Zigbee/Matter hub landscape SSOT `docs/HUBS.md` (SoC/radio comparison, product line) and the single-radio Zigbee+Thread timing SSOT `docs/MULTIPROTOCOL.md` (MG21/24/26 → Series 3; "one radio, one protocol" for now).

### Docs — repo-wide ARM → RISC-V realignment (Phase D)

- Rewrote `ROADMAP.md` around the new stance: a reproducible **verification/prototyping ground** (no business logic), two SG2000/RISC-V lanes — **Duo S full-stack ownership** ‖ **SMHub commercial reference (system-application approach)**, RISC-V-now ISA direction, USB-dongle radio on Duo S. Moved "ARM A53 as the product boot lane" to Deprecated.
- Realigned the standard doc set from "ARM Cortex-A53, fixed" to "RISC-V C906" across `README.md`, `AGENTS.md`, `VERSION.md`, `docs/README.md`, `docs/TARGET_DEVICE.md`, `runtime/README.md` (Decision + L0–L4 + BSP/phase + portfolio), `runtime/zig/homeagentd/README.md`, `runtime/c906/rtos-agent/README.md`, and the `docs/FLUTTER.md` main-lane pointer.
- Updated `VERSION.md` physical state — Duo S in hand (RISC-V boot verified), SMHub in hand (OTA beta5 verified) — and corrected the radio matrix to the actual in-repo `firmware/zbdonglee/` files.
- Recorded the two-lane invariant (Duo S milkv SDK Linux 5.10 + CVITEK `rtos_cmdqu` vs SMHub mainline 6.18 + remoteproc/rpmsg + open-amp — **images not interchangeable**; shared axis = SoC/ISA/musl/toolchain).
- Renamed `docs/YOCTO-OFFLINE-FIRST.md` → `docs/YOCTO.md` (origin lane, RPi5) and added `docs/BUILDROOT.md` — the SG2000/Duo S Buildroot experience + strategy for the core lane (Buildroot is now unavoidable; operational how-to stays in `bsp/README.md`).
- Reconciled the DIRIGERA framing across the standard doc set — README, `docs/README.md`, and a `docs/HUBS.md` status banner now mark it as parked landscape research, not our direction.

### Parked

- Parked the **IKEA DIRIGERA** lane (not bought, not pursued); `docs/HUBS.md` stays as landscape research only, not our direction.

## v2026.6.23 — SG2000 runtime pivot + RISC-V open-ISA roadmap

### Added

- Added `runtime/` as the SG2000 hub-runtime home (separate from the `go/` origin lane), with the architecture doc moved there as the folder front-door: `runtime/README.md` (L0–L4 stratification, ARM Cortex-A53 boot decision, Zig 100ms `homeagentd` state machine, C906 FreeRTOS mailbox base as the public showcase).
- Scaffolded `runtime/zig/homeagentd/` and `runtime/c906/rtos-agent/` with first-milestone and board-less prep checklists, fixed to SG2000-class only (Milk-V Duo S / SMHUB Nano).
- Rebuilt `ROADMAP.md` into the standard dashboard pattern (blurb header → Now → Near-term lane → Big direction → Target boards → Frozen invariants → Measured evidence → Deprecated → Reference paths).
- Added the `Big direction — ISA Lanes` section: ARM A53 as the product lane now, RISC-V C906 as a future open-ISA comparison north star, tied to the open-all-the-way-down thesis (open ISA → bootloader → kernel → runtime → A2A/A2UI agent surface).
- Captured the Tuya THP23-ZB-X liberation research in `docs/THP23-LIBERATION.md` (board teardown, serial console, repo-set freshness grading, LAN recon) before parking it.

### Changed

- Pivoted the active main lane from Tuya THP23 liberation to the SG2000-class runtime (Milk-V Duo S / SMHUB Nano MG24), with the big core fixed to ARM Cortex-A53 boot.
- Grounded the BSP base on `milkv-duo/duo-buildroot-sdk-v2` (`develop`) with the full boot chain in one tree (fsbl/opensbi/u-boot-2021.10/linux_5.10/ramdisk/freertos).
- Documented the SMHUB Nano product diff (mainline kernel 6.18 / OpenSBI 1.8 / U-Boot 2026.04 / Buildroot 2025.11) and the build-from-dev-SDK-then-diff-the-product methodology.
- Added concrete L0–L2 references: ARM `-arm64-` board build + boot-log `B`/`C` verification, `duo-examples/mailbox-test` (8-byte cmdqu), and `duo-8051` for the always-on layer.
- Corrected the `slzb-os-scripts` classification to an L4 Berry-language automation API reference (not a build system).
- Repointed every doc reference to `runtime/README.md` and realigned `README.md`, `AGENTS.md`, `ROADMAP.md`, `VERSION.md`, `NEXT.md`, and `docs/` to the SG2000 runtime lane.
- Pivoted the parked THP23 base to mainline Linux/U-Boot/Buildroot 2025.x after grading the cloned repo set for freshness.
- Recorded the `run.sh` → `just` coexistence (gradual migration) decision.

### Parked

- Parked active Tuya THP23-ZB-X liberation to 128MB lower-bound evidence only; the research stays reachable in `docs/THP23-LIBERATION.md`.

### Ops

- Reclaimed ~33G of regenerable build caches (`yocto/downloads`, `yocto/sstate-cache`, `flutter/build`); working tree 35G → 2.0G. No tracked files removed.

## v2026.6.22 — Minimal hub BSP re-center

### Changed

- Re-centered the public landing and agent instructions from RPi5/Yocto/Hailo first to a minimal open hub BSP thesis.
- Compressed the living root document set to `README.md`, `AGENTS.md`, `NEXT.md`, `CHANGELOG.md`, and `ROADMAP.md`.
- Moved phase direction into the new `ROADMAP.md`.
- Rewrote `AGENTS.md` as week-stable rules only, with a Korean direction header and compact English operating rules.
- Promoted SG2000 / SMHUB Nano / Milk-V Duo Buildroot SDK v2 as the current 512MB-class hub lane.
- Reframed RPi5/Yocto/Hailo, OPi5, and Android/RK work as preserved high-spec origin or compatibility lanes.
- Rewrote `VERSION.md` as the single stack, version, and physical device matrix.
- Rebuilt `docs/TARGET_DEVICE.md` as the active board/radio strategy document instead of an absorbed stale note.
- Updated `docs/README.md` so the document map points to the compact living set and current references.

### Removed

- Removed `HARDWARE.md` after absorbing current physical state into `VERSION.md`.
- Removed `INVARIANTS.md` after absorbing stable principles into `AGENTS.md`.
- Removed br/beads workflow references from project docs and `run.sh` helper commands.
- Removed tracked `.beads/` state from the worktree.
- Dropped stale local OPi5 Yocto build config files from the worktree; OPi5 remains a parked lab target in docs.
- Removed the Android and python-matter-server command surface from `run.sh` (`android`, `apk-build/apk-debug/apk-go`, `ha-deploy/ha-start/ha-stop/ha-status/ha-logs`, deprecated chip-tool stubs). These were learning-only, dirty paths and will not be revisited.
- Removed the now-orphaned python-matter-server Docker stack config: `docker-compose.yml` and `.env.docker.rpi5`.

### Added

- Added `NEXT.md` as the active NOW/ACTIVE/RECENT/LEDGER handoff file for this repo.
- Added `ROADMAP.md` for phase direction separate from stable agent instructions.
- Restructured `run.sh` around the current lane model: a Tier-2 minimal-hub (Buildroot/SG2000) section at the top so new-device bring-up commands land in the right place (`cmd_hub_*` convention), with Yocto RPi5/OPi5 work clearly marked as Tier-1 origin lane.
- Restored reproduction-critical device facts into `VERSION.md` that were lost in the first absorption pass: EFR32 firmware filenames/baudrate, OTBR backbone interface, and the USB power/CP210x-timeout note.
