# NOW — Z2M 이미지는 나왔다. flash 한 번만 성공하면 동글 검증이다

- **Stem**: Duo S에서 Node 22 + Z2M이 도는 재현 가능한 hub 이미지. 개발 속도를 위해 **arm64/glibc를 개발 레인**으로 쓴다. RISC-V는 제품 ISA로 남으며 폐기가 아니라 **보관**이다 (아래 PARKED).
- **지금 상태 (2026-07-23 22:00)**: 이미지는 **완성됐고 노트북에 받아뒀다**. flash는 **아직 못 했다** — usb_dl이 6번 실패했고, 원인을 규명해 `flash-emmc.sh`를 고쳤지만 **그 수정은 아직 실전 검증 전이다**. 보드는 무사하고 이전 이미지(Node 없음)로 정상 부팅해 있다.
  ```
  이미지  ~/repos/3rd/milkv/duo-buildroot-sdk-v2/out/milkv-duos-glibc-arm64-emmc_2026-0723-2019.zip  (104M)
  빌드    gpu1i, EXIT=0, 40분 (V8 28m37s)   — 같은 파일이 gpu1i의 bsp/sdk/out/ 에도 있다
  ```
- **Next — 이것부터**: flash 재시도. 고친 스크립트가 실제로 도는지 보는 게 전부다.
  ```bash
  cd ~/repos/gh/homeagent-config
  HOMEAGENT_BSP_SDK=~/repos/3rd/milkv/duo-buildroot-sdk-v2 ./bsp/flash-emmc.sh arm64
  # 스크립트가 뜬 뒤: 케이블 뽑기 → recovery 버튼 누른 채 → Type-C 직결로 다시 꽂기
  # 성공 신호: "[flash] 1-2 enumerated unconfigured — setting configuration 1."
  #            그 다음 updated size 가 올라가고 USB download complete
  ```
  **실패하면 에러 문자열로 원인이 갈린다** — `flash-emmc.sh` PROCEDURE 5b에 세 가지를 적어뒀다.
  `-110`=허브 경유 / 맨 `[ERR]`=cdc_acm / `INVALID_PARAM`=unconfigured(이번에 고친 것).
- **그 다음**: `homeagent-usb-mode host` → `/dev/ttyUSB0` 확인 → `/etc/init.d/S70zigbee2mqtt start`.
- **flash 후 합격선**: `node -v` = v22.22.0 / `/usr/lib/node_modules/zigbee2mqtt` 존재 / `mosquitto -h` / **동글 꽂고 `/dev/ttyUSB0` 생성**(CP210x라 `ttyACM`이 아니다) / Z2M이 어댑터를 잡고 `:8080`이 뜬다.
- **Blocker: 없다.** 커널·USB 모드 blocker 둘은 오늘 풀렸고, flash 실패는 원인이 규명된 상태다.
- **빌드는 다시 할 필요 없다.** 이미지가 이미 있다. 굳이 다시 돌린다면 `bsp/README.md`
  "Building on a remote host (gpu1i)"가 SSOT다 — 맨바닥 세팅·진행 판단·실패 시 재시작·회수까지.
- **Read**: `bsp/overlay/README.md` (overlay 4종 계약); `VERSION.md` "Verified stack — arm64 dev lane"; `bsp/flash-emmc.sh` 상단 PROCEDURE 블록.
- **Do not touch**: `feat/riscv64-nodejs-pure-cross` 브랜치와 `captures/`의 riscv 증거. gpu1i의 `d5d9436`(동료 SeungwooHyunGQ의 Yocto/Hailo 커밋, 4개월째 미push) — 내가 rebase로 해시만 옮겼고 push 여부는 GLG 판단이다.

## 재현가능성 — 오늘 닫혔다

`bsp/setup.sh` → `bsp/build.sh` 두 줄이면 빈 기계에서 같은 이미지가 선다. **gpu1i에서 실증했다** (SDK 5.6G 클론 → pin `3a50ffe28` → 주입 → 패치 멱등 적용 → 빌드).

- SDK fork `junghan0611/duo-buildroot-sdk-v2` 브랜치 **`feat/arm64-hub-baseline`** @ `3a50ffe28` (push 완료).
- **fork에는 주입으로 표현 못 하는 것만** 넣는다 — 커널 config, Buildroot 패키지 수정, 툴 권한. 보드/Buildroot defconfig와 overlay는 `bsp/`가 SSOT이고 `build.sh`가 주입한다. 양쪽에 두면 드리프트가 생긴다.
- `setup.sh`는 레인별 pin이다: `HOMEAGENT_BSP_LANE=arm64|riscv64`.
- `host-tools` 6.8G가 SDK git에 들어 있어 툴체인까지 pin으로 따라온다. `buildroot/dl` 캐시는 gitignore라 새 기계는 소스를 다시 받는다 — 정상이고, 오히려 맨바닥 재현의 증거다.

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

- **2026-07-23 flash가 6번 실패한 진짜 이유 — autoprobe가 제 발등을 찍는다 (수정했으나 미검증)**: `cdc_acm` 차단을 위해 `drivers_autoprobe=0`을 걸면, **그 이후 열거되는 장치는 unconfigured로 남는다** — `bConfigurationValue`가 비고 인터페이스가 0개라 libusb가 claim할 대상 자체가 없다. 증상은 `LIBUSB_ERROR_INVALID_PARAM` + mutex assertion. 스크립트가 autoprobe를 끈 **다음에** replug를 요구하므로 모든 replug가 이 상태로 떨어졌다. 낮에 성공했던 flash는 보드가 미리 꽂혀 있어(=이미 configured) 우연히 피해간 것이고, 그 차이가 기록되지 않아 같은 절차가 오늘은 안 됐다. `flash-emmc.sh`가 이제 매 시도 직전에 configuration을 설정한다(autoprobe=0 유지 → 드라이버 미부착 → 인터페이스만 생성. 실측 `config=[] ifaces=[]` → `config=[1] ifaces=[2]`). **이 수정으로 실제 flash가 되는지는 아직 안 봤다.** 낮 세션에 `autoprobe=0일 때 열거돼서 구성이 안 붙었다`는 관측이 이미 있었는데 flash 실패와 연결되지 않아 문서에 안 들어갔다 — 그래서 오늘 30분을 태웠다.
- **2026-07-23 gpu1i 원격 빌드 — 40분, 재현가능성 실증**: 빈 트리에서 `setup.sh` → `build.sh` 두 줄로 같은 이미지가 섰다(pin `3a50ffe28` 클론 → 주입 → 패치 멱등 적용 → `EXIT=0`). 노트북 1h29m vs gpu1i **40m**(V8 1h16m vs 28m37s), 코어 수는 같은데 절반 이하다. `dl` 캐시가 비어 소스를 새로 받고도 그렇다. 40분이면 걸어놓고 떠나는 빌드가 아니라 돌려보며 고치는 빌드다. 운용 절차는 `bsp/README.md`가 SSOT.
- **2026-07-23 Z2M/mosquitto를 Buildroot 정공법으로 통합**: 호스트에서 트리를 만들어 overlay로 넣을 필요가 없었다. `BR2_PACKAGE_NODEJS_MODULES_ADDITIONAL="zigbee2mqtt@2.10.1"` 한 줄이면 `nodejs-src.mk:340`이 크로스 설정(`npm_config_build_from_source=true`, `nodedir=$(STAGING_DIR)/usr`)으로 `npm install -g`를 돌려 `/usr/lib/node_modules/zigbee2mqtt`에 넣는다 — 2026-07-22에 정한 "rootfs `/usr`에 bake" 그대로다. 빌드 전에 증분으로 실증했다: 158 packages, 91MB, 네이티브 애드온 둘 다 **AArch64** (`@serialport/bindings-cpp`, `unix-dgram`). 버전은 SMHub 기준 (opkg 2.10.1-2 → herdsman 10.0.7, converters 26.46.0, frontend 0.9.21, Node 22.22.0 = 우리와 동일).
- **2026-07-23 Buildroot 업스트림 버그 수정**: `nodejs.mk:20`이 `$(NODEJS_CPU)`를 참조하는데 트리 어디에도 정의가 없다 (실제 이름은 `NODEJS_SRC_CPU`). `npm_config_arch`가 **빈 값**으로 나가서, prebuild를 받는 의존성이 x86_64 바이너리를 aarch64 rootfs에 넣을 수 있었다. Node 본체만 빌드하면 드러나지 않고 `MODULES_ADDITIONAL`을 쓰는 순간 터진다. fork `0913c339a`. upstream 보고 가치가 있다.
- **2026-07-23 동글 정체 확정 — 어제 기록이 맞았다**: 보드에서 실측 `idVendor=10c4, idProduct=ea60, Product: Sonoff Zigbee 3.0 USB Dongle Plus V2, SerialNumber 6c2d3e0d…`(인벤토리 3번, EmberZNet 7.4.2.0). **ZBDongle-E는 CP2102N이지 CH9102F가 아니다.** 오늘 낮에 "ch341 ID 테이블에 55d4가 없다"를 근거로 정정했던 게 틀렸고, cp210x는 5.10에 이미 있으므로 **백포트 불필요**. 커널엔 `USB_ACM`+`USB_SERIAL`+`CP210X`/`CH341`/`FTDI_SIO`를 built-in으로 넣었다 (이 커널은 `.ko`가 0개라 `=m`은 죽은 설정).
- **2026-07-23 벤더 `usb-host.sh`가 USB 모드를 안 바꾼다**: 마지막 줄이 `echo host > /proc/cviusb/otg_role >> /tmp/usb.log 2>&1` — 한 명령에 리다이렉션이 둘이라 stdout이 로그로 가고 proc 파일은 **열리기만 하고 쓰이지 않는다**. S99user가 부팅 때 이걸 source하므로 host로 설정해도 가젯으로 올라온다. overlay로 덮어쓰고 bash 전용 `function name()`도 ash 문법으로 고쳤다. 부수 소득: **proc에 직접 쓰면 재부팅 없이 즉시 전환된다** (동글이 1초 내 열거). `homeagent-usb-mode host`가 심링크와 컨트롤러를 둘 다 처리한다.
- **2026-07-23 Node 22 이미지 완성**: arm64 defconfig 툴체인을 Linaro GCC 7.3.1 → Bootlin **GCC 13.3.0**으로 교체. 1h29m 클린 빌드(V8만 ~1h16m) 끝에 `node 22.22.0` / ABI 127 / ICU 73.2 / V8 12.4가 이미지에 들어갔고 qemu-user 실행 확인. riscv가 몇 시간 못 넘긴 V8 링크를 arm은 그냥 통과했다.
- **2026-07-23 WiFi 지속성 확보**: `aic8800`을 `duo-init.sh`가 백그라운드로 올려 `wlan0`이 늦게 생긴다. `S39`는 조용히 실패했고(재부팅 검증으로 발견) `S99wpa_supplicant` + 인터페이스 대기로 고쳐 2회 검증. PSK는 리포에 없다.
- **2026-07-23 arm64 첫 부팅 성공**: 클린 빌드(983 패키지, `BOOT_CPU=aarch64`) → eMMC flash → Cortex-A53 부팅. `flash-emmc.sh`를 2레인 + ISA 계약 배너 + dry-run + autoprobe 자동 처리로 재작성.
- **2026-07-22 upstream escalation**: modern Node 22 + no-QEMU pure-cross + SDK musl 1.2.2 지원 경로를 Milk-V에 질문(issue #74). 답변 대기 중.

# LEDGER

- **제품 ISA/libc는 여전히 RISC-V C906 + SDK-native musl이다.** arm64는 2026-07-23부터 **개발 레인**이지만 제품 ISA로 승격된 것이 아니다.
- **커널 config는 우리가 소유할 수 있다 (2026-07-23 정정).** 어제 NEXT는 "`linux_5.10`의 `cvitek_*` 계열이라 우리가 소유하지 않은 파일"이라 적었는데, 실제 경로는 `build/boards/cv181x/<board>/linux/cvitek_<board>_defconfig` — **보드 디렉토리 안**이다. 소유 범위를 넓힐지 고민할 문제가 아니었다.
- **SDK의 `board/milkv/<board>/overlay`는 클린 트리에 없다.** `build/Makefile:646`이 빌드 중 `tmp-rootfs`에서 만들고 `:666`에서 지운다. `/mnt/system/*`이 거기서 온다. 그래서 SDK 빌드 스크립트를 우회해 `make -C output`만 돌리면 target-finalize에서 rsync가 실패한다.
- **`/mnt/system`은 별도 파티션이 아니라 rootfs 안의 디렉토리다** (`/dev/root`, ext4 rw). 그래서 그 아래 파일도 overlay로 덮어쓸 수 있다. `/var`도 tmpfs가 아니라 실제 디렉토리라 Z2M/mosquitto 상태가 재부팅을 넘긴다.
- **per-package 디렉토리의 함정**: `BR2_PER_PACKAGE_DIRECTORIES=y`면 각 패키지가 자기 `host/` 트리를 의존성에서 rsync 받는다. 이미 빌드된 패키지에 의존성을 추가하고 `<pkg>-reinstall`만 돌리면 그 트리는 갱신되지 않아 `host/bin/npm`이 없다고 실패한다. 클린 빌드는 이 문제를 정의상 겪지 않는다.
- Buildroot 이미지가 기준 산출물이다. SMHub식 `.ipk`/OpenRC/별도 `/opt` 지속면은 상용 배포 모델 참고이며 blocker가 아니다.
- SG2000은 같은 다이에 A53과 C906을 얹고 **물리 스위치**로 하나를 고른다 (eFuse 아님, 되돌릴 수 있음). 보드 defconfig가 동일해 ISA 전환에 보드 브링업이 필요 없다.
- `BR2_PACKAGE_NODEJS_ARCH_SUPPORTS = arm/aarch64/i386/x86_64 — no riscv`는 2026-06-30 SMHub 포렌식에 이미 있었다. arm 전환의 근거는 새 발견이 아니라 **한 달 전 증거의 재판정**이다.
