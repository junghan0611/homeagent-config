# Changelog

## Unreleased

- Nothing yet.

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
