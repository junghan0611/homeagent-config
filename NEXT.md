# NOW — flake.nix로 SG2000 이미지 재현가능 빌드 (이 리포의 핵심, 무하드웨어)

- **리포 핵심 정의 (2026-06-23)**: 이 리포의 본질은 **전체 플랫폼을 풀로 빌드해 이미지를 뽑아내는 것**이다 — yocto를 `nix run .#yocto`로 재현가능하게 돌리듯, **`duo-buildroot-sdk-v2`(부트로더→커널→rootfs→freertos)를 flake.nix로 이 리포에서 재현가능하게 빌드**한다. Zig 상태머신·애플리케이션은 *그 이미지 위에서* 하는 다음 단계. 이미지 빌드는 **하드웨어 불필요** → 배송 대기와 무관하게 지금 진행.
- **핵심 결정**: SG2000/Duo S **ARM A53 boot lane 고정**(RISC-V 아님). 아키텍처 SSOT = `runtime/README.md`(L0–L4, ARM Linux + Zig + **C906L** 코프로세서). big-core=C906B(RISC-V/ARM app), small-core RTOS=C906L(L2).
- **달성 (2026-06-23)**: **이미지 재현 빌드 성공** — `bsp/` + 공식 Docker(`milkvtech/milkv-duo`)로 `milkv-duos-glibc-arm64-emmc` eMMC 이미지(55MB) 산출. FHS(nix)는 부트체인+커널+freertos까지 갔으나 buildroot 단계에서 Ubuntu-전용 호스트 마찰(libpcre.so.3, buildroot conf 링커) 누적 → milkv 문서대로 **공식 Docker로 피벗**(AOSP 패턴과 동일). 우리 커스텀(`bsp/board` defconfig 카메라 제외 + `bsp/patches` 비전 스택 스킵)은 컨테이너 안에서 주입, host UID 매칭(`--user`)으로 산출물 host 소유.
- **그 다음**: Zig 100ms `homeagentd` 스켈레톤(L3) → ARM↔C906L mailbox 베이스(L2). 빌드 인프라는 `bsp/README.md` 참고.
- **Blocker (런타임 bring-up만)**: SMHUB Nano + Milk-V Duo S 배송 대기. **이미지 빌드는 게이트 아님.** 실보드 bring-up(Phase 0)·MG24·watchdog만 하드웨어 게이트.
- **THP23**: 파킹됨. `docs/THP23-LIBERATION.md`는 128MB 하한 증거 참고로만 보존(능동 작업 아님).
- **읽을 곳**: `flake.nix`, `runtime/README.md`, `README.md`, `AGENTS.md`, `ROADMAP.md`, `VERSION.md`, `docs/TARGET_DEVICE.md`, `PRIVATE.md`(로컬 의존 경로).
- **상태**: `6647abb` push됨 (C906L/C906B 구분 + runtime/ layout + origin-lane 게이트 + PRIVATE.md). 직전 릴리즈 `v2026.6.23`. 닫힌 변경은 `CHANGELOG.md`.
- **금지**: br/beads 부활 금지. android/python-matter-server 부활 금지. 공개 리포에 secret, private business logic, closed firmware/blob detail, PRIVATE.md 경로 반입 금지. SG2000 RISC-V boot로 런타임 올리지 말 것(ARM 고정).

# ACTIVE

## 1. 재현가능 SG2000 이미지 빌드 — 리포의 핵심 (✅ 첫 이미지 달성, 2026-06-23)

**이 리포의 본질**: 전체 플랫폼(부트로더→커널→rootfs→freertos)을 풀로 빌드해 SG2000 이미지를 뽑아내는 것. 애플리케이션은 그 위에서.

- **빌드 경로 = 공식 Docker** (`milkvtech/milkv-duo:latest`). milkv 문서가 "Ubuntu 22.04 전용 또는 Docker"라 명시 — vendor SDK는 호스트 환경 가정이 많아 nix FHS로는 buildroot 단계에서 마찰 누적. GLG의 사내 AOSP/Rockchip 빌드 패턴(vendor Ubuntu 이미지 + host UID 매칭 빌더 유저)과 동일한 접근. 참고 경로는 PRIVATE.md.
- **인프라 (committed, 재현 SSOT)**:
  - `bsp/setup.sh` — upstream `duo-buildroot-sdk-v2` develop `ad920f8` 핀 clone(gitignored `bsp/sdk/`; 로컬 oracle은 `HOMEAGENT_BSP_SDK`).
  - `bsp/build.sh` — 공식 Docker로 빌드. `--user $(id -u):$(id -g)`(host 소유), `bsp/`를 `/bsp` ro 마운트, 컨테이너 안에서 defconfig+patch 주입 후 `./build.sh`.
  - `bsp/board/milkv-duos-glibc-arm64-emmc/defconfig` — 카메라 센서·MIPI 패널 제외(hub 커스텀).
  - `bsp/patches/0001-hub-minimal-skip-vision-stack.patch` — `build_all`에서 CVITEK 카메라/ISP/RTSP/AI(`cvi_mpi`/tpu/tdl) 스킵(`HOMEAGENT_HUB_MINIMAL=1`).
  - `flake.nix packages.buildroot` — FHS는 보존(실험/일부 단계용)이나 풀 이미지 빌드 경로는 아님.
- **검증됨**: `out/milkv-duos-glibc-arm64-emmc_*.zip`(eMMC upgrade, ~55MB) 산출. 부트체인(fip.bin)+커널+rtos_cmdqu(mailbox)+freertos C906L 포함. 실보드 부트로그 첫 줄 `B`(ARM)는 하드웨어 도착 후 Phase 0.
- **Criteria**:
  - [x] `bsp/` 인프라(setup/build/board/patches) + 공식 Docker 빌드
  - [x] 카메라/AI 비전 스택 제외(hub minimal) — 우리 defconfig+patch
  - [x] `milkv-duos-glibc-arm64-emmc` 재현 빌드 무에러 완주 → eMMC 이미지 산출
  - [ ] 공개 재현용 SDK 소싱 확정: `bsp/setup.sh` 핀 clone(gitignored) — 현재 로컬 oracle로 검증, 공개시 fresh clone 재현 테스트 필요
  - [ ] 빌드 절차 문서화: `bsp/README.md`(완료) + `docs/BUILD.md`/`runtime/README.md` 교차링크
  - [ ] `-sd` SD 이미지 변형 + 제품(SMHUB Nano) diff는 별도 레인

## 2. SG2000 런타임 stratification — 이미지 위 애플리케이션 (런타임 bring-up은 보드 대기)

이미지가 재현 빌드된 위에서: **ARM A53 boot 고정** + **Zig 100ms `homeagentd` 상태머신**(L3) + **C906L FreeRTOS mailbox 코프로세서 베이스**(L2, 공개 쇼케이스) + EFR32MG24 radio(L0). 8051 always-on(L1)은 후순위. 실보드 bring-up은 **Milk-V Duo S / SMHUB Nano MG24** 도착 후.

- **SSOT**: `runtime/README.md` (L0–L4, ARM 결정, **BSP 베이스 dev-vs-제품 diff**, C906L mailbox, phased plan).
- **BSP 베이스 확정**: `milkv-duo/duo-buildroot-sdk-v2` **develop** 브랜치(fsbl/opensbi/u-boot-2021.10/linux_5.10/ramdisk/**freertos** 한 트리). 클론됨 `~/repos/3rd/milkv/`. 제품(SMHUB Nano)은 mainline kernel 6.18 / OpenSBI 1.8 / U-Boot 2026.04 / Buildroot 2025.11 — **dev SDK로 올린 뒤 제품 튜닝 diff**. Duo S + Nano 둘 다 구매(배송 대기).
- **무하드웨어 선행작업**: dev SDK develop ARM A53 빌드 절차 정리(`build.sh`에서 `-arm64-` 보드 config; 검증=부트로그 첫 줄 `B`); `duo-buildroot-sdk-v2/freertos` + `duo-examples/mailbox-test`(8B cmdqu) 구조 파악(C906L L2 베이스); `homeagentd.zig` 100ms 루프 스켈레톤(timerfd/epoll/monotonic) 설계; 첫 마일스톤 "나는 허브다 → MG24/MQTT/Z2M alive? → 상태 → 복구" 정의.
- **Criteria**:
  - [ ] **Phase 0**: ARM firmware + serial boot log + `uname`/arch + eMMC layout + package manager + GPIO/UART/MG24 device 확인
  - [ ] **Phase 1**: `homeagentd.zig` 100ms tick + state table + event queue + MQTT in/out + MG24 presence + watchdog heartbeat
  - [ ] **Phase 2**: ARM ↔ C906L FreeRTOS mailbox 베이스(`LED_SET`/`RADIO_RESET`/`WATCHDOG_KICK`/…) — 공개 쇼케이스
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

## 3. run.sh 고도화 — just 공존→점진 이관 (결정됨, 급하지 않음)

run.sh는 작업 스타일상 필연적으로 100KB+로 커진다. help() 수작업 동기화 + 무거운 로직 단일 파일이 한계.

**결정 (2026-06-22)**: 프론트도어를 **just**로. 단 **빅뱅 금지 — run.sh와 공존하다 점진 이관**. 리포 의존성은 키우지 않는다(just는 nixos-config로 설치됨, v1.43.1, 리포 의존성 추가 아님).

- 목표 구조: `justfile`(import만) + `just/{hub,device,go,origin}.just` + `scripts/*.sh`(heredoc/flash/deploy 본체).
- 이점: `just --list` 자동 디스커버리 → help stale 버그 영구 제거. 100KB 분할. legoagent-config(이미 just)와 일관.
- 이관 방식: 한 번에 갈아엎지 않는다. ① just로 커버되는 단순 명령부터 recipe로 옮기고 run.sh는 유지/위임 → ② 무거운 로직은 scripts/로 추출(run.sh·just 양쪽이 호출) → ③ 충분히 안정되면 run.sh를 얇은 shim/제거 → ④ AGENTS/README 진입점 안내 갱신.
- 주의: run.sh는 실장비를 건드린다. 단계별 장비 테스트. `exec nix run .#yocto`(FHS 재진입)·SSH heredoc은 scripts/로 옮겨 정석 bash로.
- Janet: **올인 아님.** 진짜 런타임 로직은 이미 Go 자리. 특정 gnarly 스크립트 1개(예: `hub-radio` 펌웨어 전환)가 bash를 넘어설 때만 Janet 파일럿. 리포 재현성을 niche 툴체인에 베팅하지 않는다.
- 보류: 순수 bash lib/ source 분할 — 자동 디스커버리 없어 help stale 잔존.

# RECENT

Closed work lives in `CHANGELOG.md` (latest: `v2026.6.23`). Keep only the last 1–2
in-flight notes here.

- 2026-06-23: `6647abb` — C906L/C906B 명칭 구분(milkv 공식 확인), README runtime/ layout, origin-lane docs 게이트, PRIVATE.md(로컬 의존 경로) scaffolding. NOW 재구성: 리포 핵심 = flake.nix 재현 빌드.
- 2026-06-23: `v2026.6.23` cut — SG2000 runtime pivot + RISC-V open-ISA roadmap + ROADMAP standard-pattern rebuild. milkv sources cloned to `~/repos/3rd/milkv/`. (Disk: yocto/flutter caches cleared, 35G→2.0G.)

# LEDGER
- **리포 핵심 (durable)**: 이 리포의 본질은 전체 플랫폼(부트로더→커널→rootfs→freertos)을 풀로 재현 빌드해 SG2000 이미지를 뽑아내는 것. yocto(`nix run .#yocto`)와 동형으로 buildroot-sdk-v2를 flake.nix로 빌드. 애플리케이션(Zig 상태머신 등)은 그 이미지 위. 이미지 빌드는 무하드웨어.
- 코어 명칭 (durable): big-core **C906B**(RISC-V/ARM app, ARM A53 고정), small-core RTOS **C906L**(L2 FreeRTOS mailbox 코프로세서, 공개 쇼케이스). milkv `8051core.md`로 확인. 로컬 의존 경로·private prior-art는 `PRIVATE.md`(git-ignored).
- RPi5/Yocto/Hailo remains high-spec origin evidence, not current product center.
- Current product-size hypothesis: SG2000 / SMHUB Nano / Milk-V Duo S class, 512MB, onboard EFR32, Buildroot lineage.
- Runtime decision (durable): SG2000 big core booted in **ARM A53 mode (fixed)**; **Zig 100ms state machine + C906L FreeRTOS mailbox coprocessor**; C906L mailbox base is the public showcase. SSOT `runtime/README.md`.
- Tuya/THP23 active liberation is parked — kept only as 128MB lower-bound evidence.
- NEXT pattern SSOT: botlog `~/sync/org/botlog/20260518T181305--*.org`.
