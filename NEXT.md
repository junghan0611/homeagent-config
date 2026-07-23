# NOW — Node 22 이미지가 나왔다. 다음은 Z2M + USB 동글 기능검증

- **Stem**: Duo S에서 Node 22 + Z2M이 도는 재현 가능한 hub 이미지. 개발 속도를 위해 **arm64/glibc를 개발 레인**으로 쓴다. RISC-V는 제품 ISA로 남으며 폐기가 아니라 **보관**이다 (아래 PARKED).
- **달성 (2026-07-23)**: arm 전환 → 클린 빌드 → eMMC flash → A53 부팅 → WiFi 지속성 → **툴체인 교체(GCC 7.3.1 → 13.3.0) → Node 22.22.0 이미지 생성**까지. 검증된 스택 전체는 `VERSION.md` "Verified stack — arm64 dev lane" 표가 SSOT다.
- **Next (다음 텀)**: (1) 커널에 USB-serial/CP210x를 넣는다 → (2) USB를 호스트 모드로 돌린다 → (3) MQTT 브로커를 정한다 → (4) Z2M 앱 트리를 호스트에서 빌드해 overlay로 넣는다 → (5) 이미지 빌드·flash → (6) 동글 실기 기능검증.
- **Blocker (1) — 커널에 USB serial이 없다**: arm64 커널 config가 `# CONFIG_USB_SERIAL is not set`이고 `/lib/modules`에 `.ko`가 0개다. Sonoff ZBDongle-E는 CP210x(`10c4:ea60`)라 **지금 이미지로는 동글을 꽂아도 `/dev/ttyUSB0`이 안 생긴다.** `CONFIG_USB_SERIAL` + `CONFIG_USB_SERIAL_CP210X`가 필요하다. 커널 config는 `bsp/board/<board>/defconfig`(SDK 보드 config)가 아니라 `linux_5.10`의 `cvitek_*_defconfig` 계열이라 **우리가 아직 소유하지 않은 파일이다** — 소유 범위를 넓힐지 판단이 필요하다.
- **Blocker (2) — USB 호스트/가젯이 상호 배타적**: `CONFIG_USB_DWC2_DUAL_ROLE=y`라 하드웨어는 되지만, 현재 `/mnt/system/usb.sh -> usb-ncm.sh`(가젯)다. 동글을 쓰려면 `ln -sf /mnt/system/usb-host.sh /mnt/system/usb.sh` + 재부팅이고 **`192.168.42.1`이 사라진다**. eth0/wlan0이 살아 있어 접속은 유지되지만, USB 복구 경로가 없어져 flash는 스위치+recovery 버튼으로만 가능해진다. 되돌리려면 다시 심링크를 바꿔야 한다.
- **아직 없는 것**: 이미지에 **mosquitto 없음**(브로커를 넣을지 외부를 가리킬지 결정) / **Z2M 앱 트리 없음**(`@serialport/bindings-cpp`를 aarch64·ABI 127로 호스트 빌드해야 한다). rootfs 여유는 충분하다 — 235MB / 768MB.
- **SDK workspace**: `~/repos/3rd/milkv/duo-buildroot-sdk-v2`, branch **`feat/arm64-hub-baseline`** (`087547cf8`에서 분기). 워킹트리의 `envsetup_milkv.sh`·musl defconfig 변이와 untracked libuv weak-symbol patch는 **그대로 둔다** — commit/stash 금지.
- **재빌드 규칙**: Buildroot는 defconfig 변경으로 리빌드하지 않는다. 툴체인·보드 설정을 바꾸면 `buildroot/output/<board>`와 `install/soc_sg2000_<board>`를 **먼저 지운다**. 커널 config만 바꿀 때는 `linux_5.10/build/<board>`도 함께 본다.
- **Do not touch**: SDK 워킹트리 변경을 commit/stash하지 않는다. `feat/riscv64-nodejs-pure-cross` 브랜치와 `captures/`의 riscv 증거를 건드리지 않는다.
- **Read**: `VERSION.md` "Verified stack — arm64 dev lane"; `captures/duos-arm64-firstboot-20260723T170600+0900/NOTES.md`; `bsp/flash-emmc.sh` 상단 PROCEDURE 블록; `bsp/overlay/README.md`.

## 다음 텀에 정리할 작은 빚

- **corepack이 이미지에 남아 있다** (1.2MB). npm은 `--without-npm`으로 빠졌는데 `--without-corepack`이 patch 0002의 `ifeq ($(BR2_RISCV_64),y)` 분기 안에만 있어서 arm엔 안 걸린다. 기능상 무해하지만 corepack은 `npm`/`npx` shim을 품고 있어 `corepack enable` 한 번이면 **레지스트리에서 코드를 받아 실행하는 경로**가 생긴다. npm을 뺀 이유를 우회하는 문이라 닫는 게 맞다. patch 0002를 손댈 때 한 줄 밖으로 옮긴다 — 단, bsp/patches를 수정하면 이미 커밋된 SDK와 멱등 적용이 깨지므로 SDK 커밋과 함께 처리해야 한다.
- **`/proc/cmdline`에 `earlycon=sbi riscv.fwsz=0x80000`**가 aarch64 커널에 그대로 남아 있다. 커널이 무시하므로 무해하지만 SDK cmdline 템플릿이 레인별로 분리돼 있지 않다는 뜻이다. 커널 config를 건드릴 때 같이 본다.
- **`bsp/overlay`가 arm64 defconfig에만 연결돼 있다.** riscv 레인 복귀 시 같은 overlay를 붙일지 결정해야 한다.
- **MemTotal 311MB / 512MB.** 나머지는 예약분. hub-minimal에서 회수 여지가 있는지 안 봤다.
- **SD-vs-eMMC 부트 우선순위 미확정.** eMMC 경로가 열려 급하지 않다.

## PARKED — RISC-V Node 레인 (재개 대기, 폐기 아님)

- **보관 위치**: branch `feat/riscv64-nodejs-pure-cross` @ `087547cf8` (upstream base `ad920f839`). 그대로 살아 있다. 전 `develop` 변이는 `stash@{0}` (`pre-fork-build-mutations-20260722T122809`).
- **재개 조건**: upstream [`milkv-duo/duo-buildroot-sdk-v2#74`](https://github.com/milkv-duo/duo-buildroot-sdk-v2/issues/74) 답변, 또는 arm 레인에서 Node/Z2M 스택이 서서 riscv로 되돌릴 여유가 생겼을 때. 답변이 오면 arm 진행과 무관하게 **읽고 NEXT에 기록만** 한다.
- **멈춘 지점**: Node/ICU host generator 링크에 target pkg-config의 `-L<riscv64-musl-sysroot>/usr/lib`가 섞이고, target sysroot의 8-byte musl compatibility archive(`libm.a` 등)가 host library를 가린다. **`-lm` A안은 격리 실험으로 반증되어 폐기**했다. host/target library search path 경계가 진짜 문제다.
- **해소된 것**: stale `host-python3` 재빌드로 `_bz2`/`_ssl`/`_hashlib` 복구. libuv 1.51 `pthread_getname_np` 부재는 weak-symbol patch(`GLOBAL UND → WEAK UND`)로 통과.
- **유지보수 예산(양 레인 공통)**: Buildroot recipe·defconfig·overlay + 작고 검증 가능한 compatibility patch 소수까지만. Node.js/V8/libc/toolchain downstream fork와 늘어나는 patch series는 금지. 넘으면 upstream에 묻고 baseline을 다시 고른다.
- **riscv 합격선(재개 시 복원용)**: `GLIBC_*` 0건; `GLIBCXX <= 3.4.28`; Node ABI 127; V8 embedded blob 존재; stock C906/RVV 0.7 ISA·musl interpreter; target npm/corepack 부재; ICU 연결; QEMU·native target 실행 0.
- **Read**: `docs/BUILDROOT.md` "Node.js pure cross-compile" + "Native-musl product contract"; `captures/n0-musl-gap-20260722T115500+0900/{GAP,COMPARISON}.md`; GitHub issue #6.

# RECENT

- **2026-07-23 Node 22 이미지 완성**: arm64 defconfig의 툴체인을 Linaro GCC 7.3.1 → Bootlin **GCC 13.3.0**으로 교체하고 `BR2_PACKAGE_NODEJS`/`BR2_PACKAGE_ICU`를 켰다. 1h29m 클린 빌드(V8만 ~1h16m) 끝에 `node 22.22.0` / ABI 127 / ICU 73.2 / V8 12.4가 이미지에 들어갔고 qemu-user로 실행까지 확인했다. **riscv 레인이 몇 시간 태우고도 못 넘긴 V8 링크 단계를 arm은 그냥 통과했다.** 미검증이던 host-qemu(aarch64)도 벤더 docker에서 정상 빌드됐다. 검증 스택은 `VERSION.md`가 SSOT.
- **2026-07-23 WiFi 지속성 확보**: `aic8800` 드라이버를 `duo-init.sh`가 **백그라운드로** 올려서 `wlan0`이 늦게 생긴다. 처음 넣은 `S39`는 조용히 실패했고(재부팅 검증으로 발견), `S99wpa_supplicant` + 인터페이스 대기로 고쳐 재부팅 2회 검증했다. 스크립트는 `bsp/overlay/common/`에 있고 **PSK는 리포에 없다**.
- **2026-07-23 arm64 첫 부팅 성공**: SDK `feat/arm64-hub-baseline` 브랜치 생성 → stale 6/23 output 트리 삭제 후 클린 빌드(983 패키지, `BOOT_CPU=aarch64`, rc=0) → eMMC flash → Cortex-A53 부팅 확인. 이 리포에 arm 부팅 증거가 남은 건 처음이다. `flash-emmc.sh`를 2레인 지원 + ISA 계약 배너 + dry-run + autoprobe 자동 처리로 재작성했고, 오늘 실측한 플래시 절차를 스크립트 상단 PROCEDURE 블록과 `bsp/README.md`에 박았다.
- **2026-07-23 ISA 레인 전환**: 개발 속도를 위해 arm64/glibc를 **개발 레인**으로, riscv64/musl을 **제품 레인**으로 분리했다. Node 위쪽(Z2M, 이미지 합성, flash, A2A/A2UI)은 ISA 무관이라 riscv 복귀 시 바뀌는 건 툴체인과 Node 빌드 경로뿐이다.
- **2026-07-22 upstream escalation**: modern Node 22 + no-QEMU pure-cross + SDK musl 1.2.2의 유지보수 가능한 지원 경로를 Milk-V에 질문(issue #74). 답변 대기 중.
- **2026-07-22 방향 확정**: SMHub는 Node/Z2M 버전과 제품 surface의 관측 기준이지 libc·배포판 정답이 아니다. Node/ICU/Z2M을 rootfs `/usr`에 bake하고 BusyBox init·전체 이미지 검증을 유지한다. npm/Corepack, `/opt`, RUNPATH, opkg/OpenRC는 독립 앱 업데이트가 필요할 때 재판정.
- **2026-07-21 pure-cross 메커니즘 PASS**: x86 host `mksnapshot`이 RISC-V embedded blob을 만들고 전체 Node 22.22.0 glibc target build 완료. QEMU·target 실행 0. 제품 바이너리가 아니라 libc-neutral 빌드 메커니즘 증거다.

# LEDGER

- **제품 ISA/libc는 여전히 RISC-V C906 + SDK-native musl이다.** arm64는 2026-07-23부터 "historical"이 아니라 **개발 레인**이지만 제품 ISA로 승격된 것이 아니다. `bsp/README.md`·`docs/BUILDROOT.md`·`bsp/build.sh`의 "arm64 = historical" 문구는 2026-07-23에 2레인 구조로 재작성했다.
- Buildroot 이미지가 기준 산출물이다. SMHub식 `.ipk`/OpenRC/별도 `/opt` 지속면은 상용 배포 모델 참고이며 blocker가 아니다.
- glibc G0/G1/RevA와 B-probe 설계는 `captures/` 역사 증거로만 보존한다.
- SG2000은 같은 다이에 A53과 C906을 함께 얹고 물리 스위치로 하나를 고른다. arm64/riscv64 보드 defconfig는 `CONFIG_CHIP_sg2000`·DDR·eMMC·커널 5.10이 동일해 **ISA 전환에 보드 브링업이 필요 없다**.
- Duo S는 코어 선택에 **eFuse를 쓰지 않는다** — 물리 스위치이므로 전환은 몇 번이든 되돌릴 수 있고 영구 잠금이 없다. (Duo256M/SG2002는 "dual system 동시 구동"까지 지원한다고 문서에 있으나 우리 보드가 아니다.)
- `BR2_PACKAGE_NODEJS_ARCH_SUPPORTS = arm/aarch64/i386/x86_64 — no riscv`는 2026-06-30 SMHub 포렌식(`captures/smhub-beta5-20260630/extracted/node-build-forensics.md:257`)에 이미 기록돼 있었다. arm 전환의 근거는 새 발견이 아니라 **한 달 전 증거의 재판정**이다.
