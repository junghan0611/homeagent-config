# NOW — THP23-ZB-X 오픈소스 해방 (SMHUB 도착 전 현재 작업)

- **현재**: living doc set 재정렬 완료, `v2026.6.22` 릴리즈 태깅됨(`a3c8db1`). 최신 로컬 커밋들은 push 대기; 지금은 THP23-ZB-X 해방 레인 진행 중.
- **바로 다음**: **THP23-ZB-X**(Tuya 제품, THP23-X-M 모듈 기반 / SSD202D + onboard EFR32 / 128MB) bring-up. **이미 in hand.** Tuya stock 펌웨어를 오픈소스 포크(Buildroot/OpenWrt/linux-chenxing)로 교체해 보드를 소유하고 로컬 컨트롤. SMHUB Nano 도착 전에 진행.
- **Blocker(THP23 아님)**: SMHUB Nano + Milk-V Duo 개발보드는 배송 대기 — 별도 레인. THP23-ZB-X는 막혀 있지 않다.
- **읽을 곳**: `README.md`, `AGENTS.md`, `ROADMAP.md`, `VERSION.md`, `docs/TARGET_DEVICE.md`.
- **금지**: br/beads 부활 금지. android/python-matter-server 부활 금지. 공개 리포에 secret, private business logic, closed firmware/blob detail 반입 금지.

# ACTIVE

## 1. THP23-ZB-X 오픈소스 해방 — in hand, 현재 메인 작업

Tuya 제품 **THP23-ZB-X** (모듈 THP23-X-M 기반 / Sigmastar **SSD202D** dual Cortex-A7 1.2GHz / **128MB** / onboard **EFR32**/Gecko-class radio / Wi-Fi TY001 + Ethernet). 목표는 Tuya stock 펌웨어를 **오픈소스 포크로 교체**해 보드를 소유하는 것. comparison ceiling이 아니라 SMHUB 도착 전 실제 해방 작업.

- **상세 SSOT**: `docs/THP23-LIBERATION.md` (데스크 리서치 1차 완료).
- **결정**: **Buildroot 1차.** 경로 우선순위 — linux-chenxing(mainline, 최장기 소유) → vendor SSD202 SDK(빠른 bring-up·드라이버 참고) → OpenWrt-ssd20x(18.06 구식, 후순위). SMHUB(SG2000 `duo-buildroot-sdk`)와는 *빌드시스템 수준* 정합(arch는 ARMv7 vs RISC-V/aarch64로 다름).
- **해방 저위험**: Tuya 공식 문서에 U-Boot 진입(`nvram set persist.uboot.enter on`)·TFTP `nand write` 플래시 절차 공개. glitch/exploit 불필요.
- **부팅 사실**: SSD202D는 **SPI NAND 부팅(SD/eMMC 부팅 불가)**. 복구 = U-Boot + UART SPL 재주입 + TFTP.
- **⚠️ erase 전 백업**: stock NAND 덤프 + nvram 인증키(`UUID`/`AUTHKEY`/`master_mac`/`bsn`). 분실 시 stock·Tuya 복귀 불가.
- Criteria:
  - [x] 물리 검사 — 보드 `THP23-X_V1.3.0`. SSD202D + **EFR32MG21**(Zigbee) + TY001 Wi-Fi + SPI NAND + RJ45 + 좌하단 4핀 UART 헤더 확인
  - [x] 오픈소스 포크 리서치 + 시리얼 연결법 → `docs/THP23-LIBERATION.md` (PM_UART, ttyS0 115200 8N1, IDO-SOM2D01 동일 SoM)
  - [ ] **다음**: 좌하단 4핀 헤더 핀순서 멀티미터로 확정(GND/TX/RX) → USB-Serial **3.3V, GND/TX/RX만**(VCC 미연결, 전원은 USB-C) 연결 → boot log 확보
  - [ ] stock u-boot interrupt(`nvram set persist.uboot.enter on`) + 백업(§7 게이트)
  - [ ] U-Boot/recovery path 파악, stock 백업
  - [ ] 오픈소스 image(linux-chenxing/OpenWrt/Buildroot) boot or flash
  - [ ] onboard EFR32 detection + reset/bootloader path
  - [ ] Zigbee NCP proof with one paired device
  - [ ] RSS/process evidence on 128MB

## 2. run.sh 고도화 — just 공존→점진 이관 (결정됨, 급하지 않음)

run.sh는 작업 스타일상 필연적으로 100KB+로 커진다. help() 수작업 동기화 + 무거운 로직 단일 파일이 한계.

**결정 (2026-06-22)**: 프론트도어를 **just**로. 단 **빅뱅 금지 — run.sh와 공존하다 점진 이관**. 리포 의존성은 키우지 않는다(just는 nixos-config로 설치됨, v1.43.1, 리포 의존성 추가 아님).

- 목표 구조: `justfile`(import만) + `just/{hub,device,go,origin}.just` + `scripts/*.sh`(heredoc/flash/deploy 본체).
- 이점: `just --list` 자동 디스커버리 → help stale 버그 영구 제거. 100KB 분할. legoagent-config(이미 just)와 일관.
- 이관 방식: 한 번에 갈아엎지 않는다. ① just로 커버되는 단순 명령부터 recipe로 옮기고 run.sh는 유지/위임 → ② 무거운 로직은 scripts/로 추출(run.sh·just 양쪽이 호출) → ③ 충분히 안정되면 run.sh를 얇은 shim/제거 → ④ AGENTS/README 진입점 안내 갱신.
- 주의: run.sh는 실장비를 건드린다. 단계별 장비 테스트. `exec nix run .#yocto`(FHS 재진입)·SSH heredoc은 scripts/로 옮겨 정석 bash로.
- Janet: **올인 아님.** 진짜 런타임 로직은 이미 Go 자리. 특정 gnarly 스크립트 1개(예: `hub-radio` 펌웨어 전환)가 bash를 넘어설 때만 Janet 파일럿. 리포 재현성을 niche 툴체인에 베팅하지 않는다.
- 보류: 순수 bash lib/ source 분할 — 자동 디스커버리 없어 help stale 잔존.

## 3. Board bring-up — SMHUB Nano / Milk-V Duo (after hardware arrives)
- Targets: **SMHUB Nano(SG2000)** / **Milk-V Duo SDK board**
- Blocker: 개발보드 배송 대기. 실물 bring-up은 보드 도착 후.
- Criteria:
  - [ ] UART console + U-Boot/recovery path
  - [ ] Buildroot/OpenWrt open image boot or flash
  - [ ] onboard EFR32 detection and reset/bootloader path
  - [ ] Zigbee NCP proof with one paired device
  - [ ] Thread RCP / matter.js proof when resources allow
  - [ ] RSS/process evidence for 512MB lower-bound

# RECENT
- 2026-06-22: Released `v2026.6.22`, tagged at `a3c8db1` (living doc set 재정렬). GitHub Release 노트 완료.
- 2026-06-22: `ae6e98f` records run.sh→just coexistence decision (post-release follow-up).
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
