# NOW — homeagent-config 문서 세트 조이기

- **현재**: living set을 `README.md` / `AGENTS.md` / `NEXT.md` / `CHANGELOG.md` / `ROADMAP.md`로 정리했다.
- **바로 다음**: commit 전 최종 diff review → release-prep commit → maintainer 승인 후 CalVer tag `v2026.6.22`.
- **Blocker**: SMHUB Nano + Milk-V Duo 개발보드 배송 대기. 실물 bring-up은 보드 도착 후.
- **읽을 곳**: `README.md`, `AGENTS.md`, `ROADMAP.md`, `VERSION.md`, `docs/TARGET_DEVICE.md`.
- **금지**: br/beads 부활 금지. 공개 리포에 secret, private business logic, closed firmware/blob detail 반입 금지.

# ACTIVE

## 1. Release prep review
- Criteria:
  - [x] `AGENTS.md` is week-stable and compact.
  - [x] `README.md` is a compact public landing.
  - [x] `ROADMAP.md` holds phase direction.
  - [x] `VERSION.md` absorbs stack + physical device matrix.
  - [x] `HARDWARE.md` and `INVARIANTS.md` are removed after absorption.
  - [x] br/beads helpers and state are removed.
  - [x] final human/peer diff review (Opus review pass).
  - [x] commit release prep.
  - [ ] tag `v2026.6.22` after maintainer approval.

## 2. run.sh 고도화 — just 공존→점진 이관 (결정됨)

run.sh는 작업 스타일상 필연적으로 100KB+로 커진다. help() 수작업 동기화 + 무거운 로직 단일 파일이 한계.

**결정 (2026-06-22)**: 프론트도어를 **just**로. 단 **빅뱅 금지 — run.sh와 공존하다 점진 이관**. 리포 의존성은 키우지 않는다(just는 nixos-config로 설치됨, v1.43.1, 리포 의존성 추가 아님).

- 목표 구조: `justfile`(import만) + `just/{hub,device,go,origin}.just` + `scripts/*.sh`(heredoc/flash/deploy 본체).
- 이점: `just --list` 자동 디스커버리 → help stale 버그 영구 제거. 100KB 분할. legoagent-config(이미 just)와 일관.
- 이관 방식: 한 번에 갈아엎지 않는다. ① just로 커버되는 단순 명령부터 recipe로 옮기고 run.sh는 유지/위임 → ② 무거운 로직은 scripts/로 추출(run.sh·just 양쪽이 호출) → ③ 충분히 안정되면 run.sh를 얇은 shim/제거 → ④ AGENTS/README 진입점 안내 갱신.
- 주의: run.sh는 실장비를 건드린다. 단계별 장비 테스트. `exec nix run .#yocto`(FHS 재진입)·SSH heredoc은 scripts/로 옮겨 정석 bash로.
- Janet: **올인 아님.** 진짜 런타임 로직은 이미 Go 자리. 특정 gnarly 스크립트 1개(예: `hub-radio` 펌웨어 전환)가 bash를 넘어설 때만 Janet 파일럿. 리포 재현성을 niche 툴체인에 베팅하지 않는다.
- 보류: 순수 bash lib/ source 분할 — 자동 디스커버리 없어 help stale 잔존.

## 3. Board bring-up — after hardware arrives
- Targets: **SMHUB Nano(SG2000)** / **Milk-V Duo SDK board** / **THP23-ZB-X(SSD202D comparison)**
- Criteria:
  - [ ] UART console + U-Boot/recovery path
  - [ ] Buildroot/OpenWrt open image boot or flash
  - [ ] onboard EFR32 detection and reset/bootloader path
  - [ ] Zigbee NCP proof with one paired device
  - [ ] Thread RCP / matter.js proof when resources allow
  - [ ] RSS/process evidence for 512MB lower-bound

# RECENT
- 2026-06-22: Re-centered repo from RPi5/Yocto/Hailo first to minimal open hub BSP.
- 2026-06-22: Compressed root docs into living set: README / AGENTS / NEXT / CHANGELOG / ROADMAP.
- 2026-06-22: Merged hardware/version state into VERSION.md; removed HARDWARE.md and INVARIANTS.md.
- 2026-06-22: Removed br/beads workflow references from docs and run.sh.
- 2026-06-22: Restructured run.sh into Tier-2 (Buildroot/SG2000) + Tier-1 origin lanes; removed Android and python-matter-server command surface (never again). 1464→1116 lines.
- 2026-06-22: Restored EFR32 firmware filenames, OTBR backbone iface, and USB power note into VERSION.md.

# LEDGER
- RPi5/Yocto/Hailo remains high-spec origin evidence, not current product center.
- Current product-size hypothesis: SG2000 / SMHUB Nano / Milk-V Duo S class, 512MB, onboard EFR32, Buildroot lineage.
- NEXT pattern SSOT: botlog `~/sync/org/botlog/20260518T181305--*.org`.
