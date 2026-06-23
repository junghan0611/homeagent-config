# NOW — SG2000 런타임 stratification (보드 배송 대기 중 설계 레인)

- **방향 전환 (2026-06-23)**: Tuya/THP23 능동 해방은 **중단**. 진짜 작업은 보드 오면 **Milk-V Duo S + SMHUB Nano**로 제대로 한다. 이 리포 = 공개 포트폴리오. 부트로더→커널→애플리케이션 전부 여기서 재현하고, **Zig 100ms 상태머신** + **C906 FreeRTOS mailbox 연동**을 멋진 공개 베이스로 만든다.
- **핵심 결정**: SG2000/Duo S **ARM A53 boot lane 고정**(RISC-V 아님). 새 아키텍처 SSOT = `runtime/README.md`(L0–L4, ARM Linux + Zig + C906 코프로세서).
- **바로 다음 (보드 도착 전, 무하드웨어)**: `runtime/README.md`를 기준으로 (1) Phase 0/1/2 작업 항목 구체화, (2) Milk-V Duo S ARM boot + C906 FreeRTOS mailbox 공식 예제·문서 조사, (3) `homeagentd.zig` 100ms 루프 스켈레톤 설계(timerfd/epoll). 실보드 bring-up은 Phase 0(보드 도착)부터.
- **Blocker**: SMHUB Nano + Milk-V Duo S 배송 대기. Phase 0 이후는 하드웨어 게이트.
- **THP23**: 파킹됨. `docs/THP23-LIBERATION.md`는 128MB 하한 증거 참고로만 보존(능동 작업 아님).
- **읽을 곳**: `runtime/README.md`, `README.md`, `AGENTS.md`, `ROADMAP.md`, `VERSION.md`, `docs/TARGET_DEVICE.md`.
- **상태**: 최신 로컬 커밋들 push 대기. living doc set은 방향 전환 반영 완료.
- **금지**: br/beads 부활 금지. android/python-matter-server 부활 금지. 공개 리포에 secret, private business logic, closed firmware/blob detail 반입 금지. SG2000 RISC-V boot로 런타임 올리지 말 것(ARM 고정).

# ACTIVE

## 1. SG2000 런타임 stratification — 새 메인 레인 (보드 배송 대기)

보드(**Milk-V Duo S / SMHUB Nano MG24**) 도착 시 부트로더→커널→애플리케이션을 공개 리포에서 재현한다. 중심: **ARM A53 boot 고정** + **Zig 100ms `homeagentd` 상태머신**(L3) + **C906 FreeRTOS mailbox 코프로세서 베이스**(L2, 공개 쇼케이스) + EFR32MG24 radio(L0). 8051 always-on(L1)은 후순위.

- **SSOT**: `runtime/README.md` (L0–L4, ARM 결정, **BSP 베이스 dev-vs-제품 diff**, C906 mailbox, phased plan).
- **BSP 베이스 확정**: `milkv-duo/duo-buildroot-sdk-v2` **develop** 브랜치(fsbl/opensbi/u-boot-2021.10/linux_5.10/ramdisk/**freertos** 한 트리). 클론됨 `~/repos/3rd/milkv/`. 제품(SMHUB Nano)은 mainline kernel 6.18 / OpenSBI 1.8 / U-Boot 2026.04 / Buildroot 2025.11 — **dev SDK로 올린 뒤 제품 튜닝 diff**. Duo S + Nano 둘 다 구매(배송 대기).
- **무하드웨어 선행작업**: dev SDK develop ARM A53 빌드 절차 정리(`build.sh`에서 `-arm64-` 보드 config; 검증=부트로그 첫 줄 `B`); `duo-buildroot-sdk-v2/freertos` + `duo-examples/mailbox-test`(8B cmdqu) 구조 파악(C906 L2 베이스); `homeagentd.zig` 100ms 루프 스켈레톤(timerfd/epoll/monotonic) 설계; 첫 마일스톤 "나는 허브다 → MG24/MQTT/Z2M alive? → 상태 → 복구" 정의.
- **Criteria**:
  - [ ] **Phase 0**: ARM firmware + serial boot log + `uname`/arch + eMMC layout + package manager + GPIO/UART/MG24 device 확인
  - [ ] **Phase 1**: `homeagentd.zig` 100ms tick + state table + event queue + MQTT in/out + MG24 presence + watchdog heartbeat
  - [ ] **Phase 2**: ARM ↔ C906 FreeRTOS mailbox 베이스(`LED_SET`/`RADIO_RESET`/`WATCHDOG_KICK`/…) — 공개 쇼케이스
  - [ ] **Phase 3**: 8051 always-on (sleep/wake + RTC + emergency recovery, 후순위)
  - [ ] onboard EFR32MG24 detection + reset/bootloader path
  - [ ] Zigbee NCP proof with one paired device
  - [ ] 512MB service lower-bound 측정 (MQTT/Z2M/matter.js/Go RSS)

## 1b. THP23-ZB-X — 파킹됨 (128MB 하한 증거, 능동 작업 아님)

Tuya **THP23-ZB-X** (Sigmastar **SSD202D** dual Cortex-A7 1.2GHz / **128MB** / onboard EFR32 / Wi-Fi TY001 + Ethernet)은 **능동 해방 작업 중단**. 닫힌 상용 게이트웨이를 128MB에서 얼마나 열 수 있는지의 **하한 증거**로만 보존한다. 리서치는 `docs/THP23-LIBERATION.md`에 남는다. 아래 in hand 사실은 기록 보존:

- **상세 SSOT**: `docs/THP23-LIBERATION.md` (데스크 리서치 1차 완료).
- **결정(활성도 점검 후)**: 단단한 베이스 = **mainline Linux + U-Boot + Buildroot 2025.x**(SSD202D DTS in-tree, 활발). 커뮤니티 포크(buildroot_idosom2d01/chenxing kernel/openwrt-ssd20x)는 2022~23 정체 → **포팅 레시피·드라이버 diff로 강등**. 빠른 첫 부팅엔 vendor SSD202 SDK를 oracle로. 등급표: `docs/THP23-LIBERATION.md` §9. SMHUB(SG2000 `duo-buildroot-sdk`)와는 *빌드시스템 수준* 정합(arch ARMv7 vs RISC-V/aarch64).
- **해방 저위험**: Tuya 공식 문서에 U-Boot 진입(`nvram set persist.uboot.enter on`)·TFTP `nand write` 플래시 절차 공개. glitch/exploit 불필요.
- **부팅 사실**: SSD202D는 **SPI NAND 부팅(SD/eMMC 부팅 불가)**. 복구 = U-Boot + UART SPL 재주입 + TFTP.
- **⚠️ erase 전 백업**: stock NAND 덤프 + nvram 인증키(`UUID`/`AUTHKEY`/`master_mac`/`bsn`). 분실 시 stock·Tuya 복귀 불가.
- **LAN 정찰 완료(무땜)**: 보드 `SmartGateway-BDE2`(192.168.0.134). nmap 전체포트 `6668/tcp`(Tuya 제어)만 open → SSH/telnet/web 닫힘. **LAN-only 해방 불가, 시리얼 필수** 확정.
- Criteria:
  - [x] 물리 검사 — `THP23-X_V1.3.0`: SSD202D + **EFR32MG21** + TY001 + SPI NAND + RJ45 + 좌하단 4핀 UART 후보
  - [x] 오픈소스 포크 리서치 + 시리얼 연결법 + LAN 정찰 → `docs/THP23-LIBERATION.md`
  - ⏸ **나머지(UART 납땜·desk build·stock 백업·flash) 전부 파킹.** 재개하려면 의식적으로 결정. 절차는 `docs/THP23-LIBERATION.md`에 보존.

## 2. run.sh 고도화 — just 공존→점진 이관 (결정됨, 급하지 않음)

run.sh는 작업 스타일상 필연적으로 100KB+로 커진다. help() 수작업 동기화 + 무거운 로직 단일 파일이 한계.

**결정 (2026-06-22)**: 프론트도어를 **just**로. 단 **빅뱅 금지 — run.sh와 공존하다 점진 이관**. 리포 의존성은 키우지 않는다(just는 nixos-config로 설치됨, v1.43.1, 리포 의존성 추가 아님).

- 목표 구조: `justfile`(import만) + `just/{hub,device,go,origin}.just` + `scripts/*.sh`(heredoc/flash/deploy 본체).
- 이점: `just --list` 자동 디스커버리 → help stale 버그 영구 제거. 100KB 분할. legoagent-config(이미 just)와 일관.
- 이관 방식: 한 번에 갈아엎지 않는다. ① just로 커버되는 단순 명령부터 recipe로 옮기고 run.sh는 유지/위임 → ② 무거운 로직은 scripts/로 추출(run.sh·just 양쪽이 호출) → ③ 충분히 안정되면 run.sh를 얇은 shim/제거 → ④ AGENTS/README 진입점 안내 갱신.
- 주의: run.sh는 실장비를 건드린다. 단계별 장비 테스트. `exec nix run .#yocto`(FHS 재진입)·SSH heredoc은 scripts/로 옮겨 정석 bash로.
- Janet: **올인 아님.** 진짜 런타임 로직은 이미 Go 자리. 특정 gnarly 스크립트 1개(예: `hub-radio` 펌웨어 전환)가 bash를 넘어설 때만 Janet 파일럿. 리포 재현성을 niche 툴체인에 베팅하지 않는다.
- 보류: 순수 bash lib/ source 분할 — 자동 디스커버리 없어 help stale 잔존.

# RECENT
- 2026-06-23: BSP 베이스 확정 — `duo-buildroot-sdk-v2` develop(linux 5.10/u-boot 2021.10/freertos 한 트리). SMHUB Nano 제품은 mainline 6.18/OpenSBI 1.8/U-Boot 2026.04/Buildroot 2025.11로 별도 튜닝 확인 → dev-then-diff 방법론. slzb-os-scripts는 BSP 아님(Berry L4 자동화 API). `runtime/README.md`·TARGET_DEVICE·VERSION 반영. (디스크: yocto/flutter 캐시 33G 정리, 35G→2.0G.)
- 2026-06-23: 방향 전환 — Tuya/THP23 능동 작업 중단(128MB 증거로 파킹). SG2000 런타임 stratification(ARM A53 boot 고정 + Zig 100ms 상태머신 + C906 FreeRTOS mailbox 베이스)을 새 메인 레인으로. 새 SSOT `runtime/README.md`; ROADMAP/AGENTS/TARGET_DEVICE/docs README 반영.
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
- Runtime decision (durable): SG2000 big core booted in **ARM A53 mode (fixed)**; **Zig 100ms state machine + C906 FreeRTOS mailbox coprocessor**; C906 mailbox base is the public showcase. SSOT `runtime/README.md`.
- Tuya/THP23 active liberation is parked — kept only as 128MB lower-bound evidence.
- NEXT pattern SSOT: botlog `~/sync/org/botlog/20260518T181305--*.org`.
