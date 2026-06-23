# Changelog

## Unreleased

- Nothing yet.

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
