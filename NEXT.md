# NOW — 다음 축: 제품화 수준의 Duo S 구성 준비

- **Stem**: Duo S를 Zigbee/Matter 허브로 세우는 재현 이미지. **flash-and-go 재현성은 v2026.7.24로 닫혔다**(아래 RECENT + "flash-and-go 재현"). 다음 단계는 **"개발 보드가 도는 이미지" → "제품이 될 수 있는 이미지"**.
- **왜 이 축인가 (2026-07-24 GLG)**: 선행 세대 허브는 제품이 되기까지 **ssh push 십수 단계 + 제조사에 패키지 이관**이었다 — 재현 가능한 지점이 없고 최종 산출물 통제권도 넘어간다. Buildroot 레인을 재현성으로 조이는 이유가 이것이다: **부팅부터 패키징까지 전 영역을 우리가 소유한다.** 허브 앱은 별도 레인에서 오더라도, **그것이 들어앉을 자리는 이 repo가 제품 수준으로 준비**한다(필요한 구성이 대략 비슷하다).
- **다음 한 걸음**: **[#8](https://github.com/junghan0611/homeagent-config/issues/8)의 "남은 축" 1번 — 기기 아이덴티티를 어디서 넣을지 결정**(첫 부팅 생성+지속면 저장 / 제조 단계 주입 / SoC 고유값 파생). flash-and-go는 *전 보드가 같은 이미지*라는 뜻이므로, 이 결정이 공장초기화·OTA·프로비저닝 설계를 전부 좌우한다.
- **병행(다른 레인)**: 회사 레인(`~/repos/work/`)에서 Zigbee 허브(z2m 이용) 개발 → 완성분을 Duo S 이미지에서 검증. **이 repo는 보드 검증·풀이미지 표면**(비즈니스 로직 아님).
- **Matter / matter.js**: **준비 완료, 착수 보류 (언제든)** — 아래 "## Matter / matter.js 올리기" 참조. 라디오는 지금 USB 동글(어쩔 수 없음), 제품화 시 온보드 MG24/MG26.
- **Blocker: 없다.**
- **Read**: **[#8 제품화 구성](https://github.com/junghan0611/homeagent-config/issues/8)**(대조표 + 남은 축); [#7 왜 이 작업을 하고 왜 공개하는가](https://github.com/junghan0611/homeagent-config/issues/7); `bsp/README.md`(빌드/증분); `duo-s-flash` 스킬(flash); `docs/SMHUB.md`(참조 제품 대조); `VERSION.md`.
- **Do not touch**: `feat/riscv64-nodejs-pure-cross` 브랜치와 `captures/`의 riscv 증거. gpu1i의 `d5d9436`(SeungwooHyunGQ Hailo)은 **2026-07-24 버렸다**(gpu1i homeagent-config를 origin/main으로 reset). 원본은 SeungwooHyunGQ 쪽. gpu1i untracked `meta-hailo/`·`yocto/sstate-cache-backup/`은 남겨둠 — GLG 판단.

## flash-and-go 재현 (닫힘 — 참조용)

- **마지막 이미지**: `milkv-duos-glibc-arm64-emmc_2026-0724-1244.zip` (rootfs UUID f0cd08f2-…), 보드 91(aarch64, eth0 192.168.0.162) + dev보드(192.168.0.192) 둘 다 Z2M :8080 OK.
- **재현 절차 (SSOT)**: 맨바닥/클린은 `bsp/README.md` "Building on a remote host (gpu1i)", 증분은 같은 문서 "Rebuilding after an overlay/config change". flash는 `duo-s-flash` 스킬 + `bsp/flash-emmc.sh` 상단 PROCEDURE.
- **flash 요약**: `sudo ./bsp/usb-recovery-prepare.sh` → `./bsp/flash-emmc.sh arm64` → 꽂고 `dmesg`에 `ttyACM` 확인 → UUID로 증명. 핵심은 **cdc_acm은 막는 게 아니라 붙였다 뗀다**, **100%/complete는 증거가 아니다(UUID로 대조)**.
- **잔여 후보 (급한 것 없음, 아래 '작은 빚')**: 보드 90(dev) `2026-0724-1244`로 reflash + MAC 채우기(`bsp/BOARDS.md`); Z2M 상태 백업 절차.

## 재현 파이프라인 (요지 — 상세는 CHANGELOG v2026.7.24 + bsp/README.md)

`bsp/setup.sh` → `bsp/build.sh` 두 줄이면 빈 기계에서 같은 이미지가 선다.

- SDK fork `junghan0611/duo-buildroot-sdk-v2` **`feat/arm64-hub-baseline`** @ `3a50ffe28` (push 완료).
- **fork에는 주입으로 표현 못 하는 것만** — 커널 config, Buildroot 패키지 수정, 툴 권한. 보드/Buildroot defconfig와 `bsp/overlay`는 `bsp/`가 SSOT이고 `build.sh`가 주입한다. 양쪽에 두면 드리프트.
- `host-tools` 6.8G가 SDK git에 있어 툴체인까지 pin으로 따라온다. `buildroot/dl`은 gitignore(다운로드 캐시).
- overlay/config만 바뀐 재빌드는 **증분 ~2-3분** — output 트리를 지우지 마라 (`bsp/README.md` "Rebuilding after an overlay/config change").

## 다음 텀에 정리할 작은 빚

- **커널 defconfig 주석이 틀렸다 — 이미지엔 무해 (2026-07-24 fork 실물 확인).** `build/boards/cv181x/sg2000_milkv_duos_glibc_arm64_emmc/linux/cvitek_..._defconfig` 203번 설명주석이 "ZBDongle-E (CH9102F) → CDC-ACM"인데 **실측은 CP210x**(ttyUSB0). **심볼은 전부 맞다** (`USB_ACM=y`·`USB_SERIAL_CP210X=y`·`CH341=y`·`FTDI_SIO=y`) — 거짓인 건 순수 `#` 주석뿐. kconfig가 주석을 무시하므로 고쳐도 **이미지는 바이트 불변 → 실기 검증 불필요**. fork에서 주석만 정정하고 `setup.sh`의 `SDK_COMMIT` pin만 올리면 끝. (이전 NEXT의 "실기 검증이 끝난 뒤에"는 과한 신중함이었다.)
- **corepack은 이미지에 남지만 의도적 유지 (2026-07-24 GLG 판단).** `--without-corepack`이 patch 0002의 `ifeq ($(BR2_RISCV_64),y)` 분기 안에만 있어 arm 레인엔 안 걸리고, corepack 1.2MB가 이미지에 남는다. 원래 "닫을 빚"으로 적었으나 **아직 개발 중이라 corepack이 필요하고 급하지 않으므로 지금은 닫지 않는다.** 제품화 단계에서 재판정(그때 patch 0002의 해당 3줄을 `ifeq/else` 분기 **밖**으로 옮기면 양 레인 공통 적용).
- **`/proc/cmdline`에 `earlycon=sbi riscv.fwsz=0x80000`**가 aarch64 커널에 그대로 남아 있다. 무해하지만 SDK cmdline 템플릿이 레인별로 분리돼 있지 않다는 뜻이다.
- **`bsp/overlay`가 arm64 defconfig에만 연결돼 있다.** riscv 레인 복귀 시 같은 overlay를 붙일지 결정해야 한다.
- **MemTotal 311MB / 512MB**, rootfs 235MB/768MB(Z2M 91MB 추가 전). hub-minimal에서 회수 여지를 안 봤다.
- **Z2M 상태 백업 — 스킬엔 있고 스크립트엔 없다 (2026-07-24 검수로 정정).** `/var/lib/zigbee2mqtt`에 device DB와 **네트워크 키**가 있어 **reflash하면 날아간다**(전 기기 재페어링). `duo-s-flash` 스킬 §7이 이미 백업 한 줄(`ssh root@192.168.42.1 'tar cz -C /var/lib zigbee2mqtt' > …`)을 담고 있다 — 없는 건 `flash-emmc.sh`/README 쪽이다. flash 직전에 자동화/강제할지만 판단하면 된다. 청사진 참고: SMHub 매뉴얼도 OTBR reflash 시 Thread 데이터 소실을 백업 절차와 함께 명시한다(`docs/smhub-manual/pages/17-*`).

## Matter / matter.js 올리기 — 준비 완료, 착수 보류 (언제든)

버전 지도 (2026-07-24 확인):

| 대상 | 스택 | `@matter/*` | 시점 |
|---|---|---|---|
| **우리** (origin lane) | matterjs-server → `matter-server` **0.3.5** | `0.16.9-alpha` | 2026-02-04 |
| upstream `matter-server` 최신 **1.3.1** | — | **`0.17.7-alpha`** | 2026-07-23 |
| 최신 안정 matter.js | — | `0.17.5` | 2026-07-13 |
| 로컬 `~/repos/3rd/ha/matter.js` (develop) | — | `0.17.7-alpha` | 2026-07-24 |

- **관문은 열려 있다**: upstream `matter-server 1.3.1`이 이미 `@matter 0.17.7`을 문다 → 우리가 앞서갈 필요 없이 `matterjs-server`의 두 dep(`matter-server ^1.3.1`, `@matter/nodejs ^0.17.7`) bump + 재번들(`scripts/bundle-backend.sh`) + `npm-shrinkwrap.json` 재생성이면 된다.
- **진짜 부담 = `matter-server 0.3.5 → 1.3.1` major(0.x→1.x)**, `@matter` breaking이 아니다 — 우리는 matter-server 경유라 0.17.0 breaking(Matter 1.5/1.5.1 Namespace rename, `@matter/model` 배열 인덱스 제거, Blob 스토리지 제거)에 직접 노출이 작다. **착수 시 우리 래퍼가 matter-server API를 부르는 표면부터 파악**할 것.
- **0.17 이득이 우리 방향에 정합**: RAM **20–50% 감소**(512MB 보드), `threadNetwork` commissioning 옵션 + Thread Border Router DnssdParameters enrichment(RCP/Thread 경로에 직접 필요).
- **RCP 경로**: GLG "1번 동글" = SONOFF ZBDongle-E를 **RCP 펌웨어**로 flash → `otbr-agent` → matter.js. `VERSION.md`: RCP/OTBR는 **origin(Yocto) lane proven**, **arm64 hub-minimal은 TBD**. 커널 defconfig에 CP210x/ACM이 다 있어 동글 인식은 확보돼 있다.
- **우리 스택 구조**: `matterjs-server`(래퍼) → `matter-server 0.3.5`(`@matter-server/ws-controller`·`ws-client`·`custom-clusters`·`dashboard`) + `@matter/nodejs`. SSOT pin은 `yocto/meta-homeagent/recipes-connectivity/matterjs-server/matterjs-server/npm-shrinkwrap.json`.
- **SMHub과 다른 방향**: SMHub은 `matterbridge`(Zigbee→Matter 노출, bridge). 우리는 **matter.js controller + OTBR**(Zigbee·Thread를 직접 commissioning). 아래 LEDGER "SMHub 라디오 아키텍처" 참조.

## PARKED — RISC-V Node 레인 (재개 대기, 폐기 아님)

- **보관 위치**: branch `feat/riscv64-nodejs-pure-cross` @ `087547cf8` (upstream base `ad920f839`). 전 `develop` 변이는 `stash@{0}`.
- **재개 조건**: upstream [`milkv-duo/duo-buildroot-sdk-v2#74`](https://github.com/milkv-duo/duo-buildroot-sdk-v2/issues/74) 답변, 또는 arm 레인에서 Z2M 스택이 서서 riscv로 되돌릴 여유가 생겼을 때.
- **멈춘 지점**: Node/ICU host generator 링크에 target pkg-config의 `-L<riscv64-musl-sysroot>/usr/lib`가 섞이고, target sysroot의 8-byte musl compatibility archive가 host library를 가린다. `-lm` A안은 반증되어 폐기.
- **유지보수 예산(양 레인 공통)**: Buildroot recipe·defconfig·overlay + 작고 검증 가능한 compatibility patch 소수까지만. Node.js/V8/libc/toolchain downstream fork와 늘어나는 patch series는 금지.
- **riscv 합격선(재개 시 복원용)**: `GLIBC_*` 0건; `GLIBCXX <= 3.4.28`; Node ABI 127; V8 embedded blob 존재; stock C906/RVV 0.7 ISA·musl interpreter; target npm/corepack 부재; ICU 연결; QEMU·native target 실행 0.
- **Read**: `docs/BUILDROOT.md` "Node.js pure cross-compile" + "Native-musl product contract"; `captures/n0-musl-gap-20260722T115500+0900/`.

# RECENT

- **2026-07-24 (2세션) 방향 정리 — Matter 준비 + SMHub 대조**: matter.js bump 경로 조사 완료(관문 열림 — 위 "Matter / matter.js 올리기"), **corepack은 개발 중이라 의도적 유지**로 재판정, 커널 defconfig 주석은 **이미지 불변이라 실기 검증 불필요**로 확정, SMHub Nano 단일 MG24 배타 / 벤더 매뉴얼의 "별도 칩"은 상위 모델 전제임을 교정(LEDGER). **다음 실질 축 = 제품화 수준의 Duo S 구성 준비**([#8](https://github.com/junghan0611/homeagent-config/issues/8) — 선행 세대의 ssh push/제조사 이관을 반면교사로, 이미지가 소유해야 할 것 대조표 + 남은 축 5개). 회사 레인의 z2m 허브 개발은 병행, Matter는 언제든. **문서 조이기**: 리포 문서는 토픽 이슈로 이전(#7·#8·#9), absorbed 스텁 5개 제거 → `docs/` 25→18, 루트는 표준 7개.
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
- **SMHub 라디오 아키텍처 — "별도 칩"의 정확한 뜻 (2026-07-24 교정).** 실물 **SMHub Nano는 MG24 하나뿐**이라 Zigbee coordinator **또는** Thread RCP **배타**다(`docs/SMHUB.md §2`; RCP로 재플래시하면 Zigbee 상실 → Thread/OTBR 보류). 벤더 매뉴얼(`docs/smhub-manual/pages/`)의 "Thread(EFR32MG series) native OTBR", "별도 EFR32MG `/dev/ttyS2`", "OTBR + Matterbridge 통합"은 **§6 제네릭 = 상위 모델(Essential/Premium) 전제** 문서이지 Nano 실물 능력이 아니다 — `§2.2`가 "Nano 검수 시 §6 표를 그대로 따르면 안 됨"으로 못 박았다. **matterbridge는 앱 계층(IP 위 Zigbee→Matter 노출)이라 Thread 지원 여부와 별개 축**이며, 한 제품에서 OTBR와 공존한다. 우리 Duo S의 **USB 2동글(NCP+RCP)이 그 상위 모델의 "별도 칩 2개"에 대응** → 단일 MG24 Nano가 못 하는 **Zigbee+Thread 동시**가 개발 단계에서 가능하다. 지금 USB인 건 온보드 라디오가 없어서일 뿐, 제품화는 **MG24(단일→배타)/MG26(concurrent multiprotocol)/별도 칩** 중 하드웨어 결정. **Thread/OTBR는 우리가 처음 실증하는 영역**(Nano도 안 세웠고, 매뉴얼은 상위 모델용이라 절차 청사진이지 검증 근거가 아니다). SMHub은 낮춰볼 대상이 아니라 **지향하는 완성형 참조 제품**이다.
