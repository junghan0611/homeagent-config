# NOW — 재현성 닫혔다. flash-and-go가 두 번째 보드에서 실증됐다

- **Stem**: Duo S에서 Node 22 + Z2M이 도는 재현 가능한 hub 이미지. **arm64/glibc가 개발 레인**, RISC-V는 제품 ISA로 보관(아래 PARKED).
- **지금 상태 (2026-07-24)**: **flash → host전환 → 동글 = Z2M 자동 기동**이 보드 91에서 config 손 안 대고 실증됐다. seed에 serial pin이 박혀 이미지가 flash-and-go다. 증분 빌드도 실증(2m37s). 오늘 세션 목표(재현성 완성)는 닫혔다.
  ```
  이미지  milkv-duos-glibc-arm64-emmc_2026-0724-1244.zip  rootfs UUID f0cd08f2-…
  보드    91 (신규, aarch64, eth0 192.168.0.162) + dev보드 (192.168.0.192) 둘 다 Z2M :8080 OK
  ```
- **다음 후보 (급한 것 없음, 아래 '작은 빚'에서 고른다)**:
  1. 보드 90(dev)을 `2026-0724-1244`로 reflash해 flash-and-go parity 맞추기 + MAC 채우기(`bsp/BOARDS.md`).
  2. Z2M 상태 백업 절차를 `flash-emmc.sh`/README에 박기 (reflash = 페어링 소실).
  3. 커널 defconfig 주석 정정(SDK pin 올라감), corepack 제거(patch 0002), 커널 cmdline riscv 잔재 등 '작은 빚'.
- **재현 절차 (SSOT)**: 맨바닥/클린은 `bsp/README.md` "Building on a remote host (gpu1i)", 증분은 같은 문서 "Rebuilding after an overlay/config change". flash는 `duo-s-flash` 스킬 + `bsp/flash-emmc.sh` 상단 PROCEDURE.
- **flash 요약** (상세는 duo-s-flash 스킬): `sudo ./bsp/usb-recovery-prepare.sh` → `./bsp/flash-emmc.sh arm64` → 꽂고 `dmesg`에 `ttyACM` 확인 → UUID로 증명. 핵심은 **cdc_acm은 막는 게 아니라 붙였다 뗀다**, **100%/complete는 증거가 아니다(UUID로 대조)**.
- **Blocker: 없다.**
- **Read**: `bsp/BOARDS.md` (보드 인벤토리); `duo-s-flash` 스킬; `bsp/README.md` 증분 절차; `VERSION.md`.
- **Do not touch**: `feat/riscv64-nodejs-pure-cross` 브랜치와 `captures/`의 riscv 증거. gpu1i의 `d5d9436`(SeungwooHyunGQ Hailo)은 **2026-07-24 버렸다**(gpu1i homeagent-config를 origin/main으로 reset). 원본은 SeungwooHyunGQ 쪽. gpu1i untracked `meta-hailo/`·`yocto/sstate-cache-backup/`은 남겨둠 — GLG 판단.

## 재현 파이프라인 (요지 — 상세는 CHANGELOG v2026.7.24 + bsp/README.md)

`bsp/setup.sh` → `bsp/build.sh` 두 줄이면 빈 기계에서 같은 이미지가 선다.

- SDK fork `junghan0611/duo-buildroot-sdk-v2` **`feat/arm64-hub-baseline`** @ `3a50ffe28` (push 완료).
- **fork에는 주입으로 표현 못 하는 것만** — 커널 config, Buildroot 패키지 수정, 툴 권한. 보드/Buildroot defconfig와 `bsp/overlay`는 `bsp/`가 SSOT이고 `build.sh`가 주입한다. 양쪽에 두면 드리프트.
- `host-tools` 6.8G가 SDK git에 있어 툴체인까지 pin으로 따라온다. `buildroot/dl`은 gitignore(다운로드 캐시).
- overlay/config만 바뀐 재빌드는 **증분 ~2-3분** — output 트리를 지우지 마라 (`bsp/README.md` "Rebuilding after an overlay/config change").

## 다음 텀에 정리할 작은 빚

- **커널 defconfig 주석이 틀렸다.** `cvitek_sg2000_..._defconfig`에 "ZBDongle-E는 CH9102F → CDC-ACM"이라 적었는데 **실측은 CP210x**였다 (아래 RECENT). 설정 자체(`CP210X=y`)는 맞아서 기능 영향은 0이고 주석만 거짓이다. 고치면 SDK pin이 올라가므로 **실기 검증이 끝난 뒤에** 한 커밋으로 처리한다. `USB_ACM`/`CH341`/`FTDI_SIO`는 다른 코디네이터 대비로 남겨둘지 같이 판단한다.
- **corepack이 이미지에 남아 있다** (1.2MB). npm은 `--without-npm`으로 빠졌는데 `--without-corepack`이 patch 0002의 `ifeq ($(BR2_RISCV_64),y)` 분기 안에만 있어서 arm엔 안 걸린다. `corepack enable` 한 번이면 레지스트리에서 코드를 받아 실행하는 경로가 열리므로 npm을 뺀 이유를 우회하는 문이다. patch 0002를 손댈 때 한 줄 밖으로 옮긴다.
- **`/proc/cmdline`에 `earlycon=sbi riscv.fwsz=0x80000`**가 aarch64 커널에 그대로 남아 있다. 무해하지만 SDK cmdline 템플릿이 레인별로 분리돼 있지 않다는 뜻이다.
- **`bsp/overlay`가 arm64 defconfig에만 연결돼 있다.** riscv 레인 복귀 시 같은 overlay를 붙일지 결정해야 한다.
- **MemTotal 311MB / 512MB**, rootfs 235MB/768MB(Z2M 91MB 추가 전). hub-minimal에서 회수 여지를 안 봤다.
- **Z2M 상태 백업 절차가 없다.** `/var/lib/zigbee2mqtt`에 device DB와 네트워크 키가 있고 **reflash하면 날아간다** — 페어링을 다시 해야 한다. flash 전 백업을 `flash-emmc.sh`나 README에 절차로 박을지 판단.

## PARKED — RISC-V Node 레인 (재개 대기, 폐기 아님)

- **보관 위치**: branch `feat/riscv64-nodejs-pure-cross` @ `087547cf8` (upstream base `ad920f839`). 전 `develop` 변이는 `stash@{0}`.
- **재개 조건**: upstream [`milkv-duo/duo-buildroot-sdk-v2#74`](https://github.com/milkv-duo/duo-buildroot-sdk-v2/issues/74) 답변, 또는 arm 레인에서 Z2M 스택이 서서 riscv로 되돌릴 여유가 생겼을 때.
- **멈춘 지점**: Node/ICU host generator 링크에 target pkg-config의 `-L<riscv64-musl-sysroot>/usr/lib`가 섞이고, target sysroot의 8-byte musl compatibility archive가 host library를 가린다. `-lm` A안은 반증되어 폐기.
- **유지보수 예산(양 레인 공통)**: Buildroot recipe·defconfig·overlay + 작고 검증 가능한 compatibility patch 소수까지만. Node.js/V8/libc/toolchain downstream fork와 늘어나는 patch series는 금지.
- **riscv 합격선(재개 시 복원용)**: `GLIBC_*` 0건; `GLIBCXX <= 3.4.28`; Node ABI 127; V8 embedded blob 존재; stock C906/RVV 0.7 ISA·musl interpreter; target npm/corepack 부재; ICU 연결; QEMU·native target 실행 0.
- **Read**: `docs/BUILDROOT.md` "Node.js pure cross-compile" + "Native-musl product contract"; `captures/n0-musl-gap-20260722T115500+0900/`.

# RECENT

- **2026-07-24 flash-and-go 완성 + v2026.7.24 태그**: 보드 91에서 flash → host전환 → 동글 = Z2M 자동 기동을 config 손 안 대고 실증. flash 신뢰성(cdc_acm bind-then-unbind, 거짓완료 UUID 대조), Z2M seed serial pin(udevadm 부재 회피), 증분 빌드 2m37s. `duo-s-flash` 스킬 + `bsp/usb-recovery-prepare.sh` + `bsp/BOARDS.md` 신설. **상세 전부 CHANGELOG v2026.7.24.**
- 그 이전(arm64 전환, Node 22, Z2M 통합, riscv pure-cross 등)은 CHANGELOG v2026.7.24 및 v2026.7.15.

# LEDGER

- **제품 ISA/libc는 여전히 RISC-V C906 + SDK-native musl이다.** arm64는 2026-07-23부터 **개발 레인**이지만 제품 ISA로 승격된 것이 아니다.
- **커널 config는 우리가 소유할 수 있다 (2026-07-23 정정).** 어제 NEXT는 "`linux_5.10`의 `cvitek_*` 계열이라 우리가 소유하지 않은 파일"이라 적었는데, 실제 경로는 `build/boards/cv181x/<board>/linux/cvitek_<board>_defconfig` — **보드 디렉토리 안**이다. 소유 범위를 넓힐지 고민할 문제가 아니었다.
- **SDK의 `board/milkv/<board>/overlay`는 클린 트리에 없다.** `build/Makefile:646`이 빌드 중 `tmp-rootfs`에서 만들고 `:666`에서 지운다. `/mnt/system/*`이 거기서 온다. 그래서 SDK 빌드 스크립트를 우회해 `make -C output`만 돌리면 target-finalize에서 rsync가 실패한다.
- **`/mnt/system`은 별도 파티션이 아니라 rootfs 안의 디렉토리다** (`/dev/root`, ext4 rw). 그래서 그 아래 파일도 overlay로 덮어쓸 수 있다. `/var`도 tmpfs가 아니라 실제 디렉토리라 Z2M/mosquitto 상태가 재부팅을 넘긴다.
- **per-package 디렉토리의 함정**: `BR2_PER_PACKAGE_DIRECTORIES=y`면 각 패키지가 자기 `host/` 트리를 의존성에서 rsync 받는다. 이미 빌드된 패키지에 의존성을 추가하고 `<pkg>-reinstall`만 돌리면 그 트리는 갱신되지 않아 `host/bin/npm`이 없다고 실패한다. 클린 빌드는 이 문제를 정의상 겪지 않는다.
- Buildroot 이미지가 기준 산출물이다. SMHub식 `.ipk`/OpenRC/별도 `/opt` 지속면은 상용 배포 모델 참고이며 blocker가 아니다.
- SG2000은 같은 다이에 A53과 C906을 얹고 **물리 스위치**로 하나를 고른다 (eFuse 아님, 되돌릴 수 있음). 보드 defconfig가 동일해 ISA 전환에 보드 브링업이 필요 없다.
- `BR2_PACKAGE_NODEJS_ARCH_SUPPORTS = arm/aarch64/i386/x86_64 — no riscv`는 2026-06-30 SMHub 포렌식에 이미 있었다. arm 전환의 근거는 새 발견이 아니라 **한 달 전 증거의 재판정**이다.
