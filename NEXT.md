# RAIL — 현재 좌표

- [x] **1. flash-and-go 재현** — v2026.7.24, 보드 91 Z2M :8080
- [~] **2. gecko 패키징 표면을 arm64 이미지에 굽기** ← CURRENT: **minimal 이미지로 표면 증명 완료(2026-08-30)**. 남은 것 = full(Z2M) 이미지 재빌드 + 플래시(gecko 신호 후)
- [ ] **3. #8 나머지 아이덴티티** — hostname·인증서·제조 주입. gecko 지금 요청 없음
- [ ] **4. Matter / matter.js** ← PAUSED: 준비 완료, 착수 보류

현재 좌표: 1 완료 → 2 바이트 나옴(minimal), full은 미빌드 → 3·4 보류

# NOW — 표면은 증명됐다. 남은 것은 full(Z2M) 이미지와 플래시

- **Stem**: Duo S 제품화 이미지. 허브 앱은 별도 레인, **들어앉을 자리는 이 repo**. ARM64 glibc 개발 레인만. RISC-V 아님.
- **이미 들어 있는 것 (레시피, 2026-08-28)**: `BR2_PACKAGE_HOSTAPD=y` (개방망, WPA3 옵션 없음, init으로 안 올림). `/dev/serial/by-id`는 eudev 없이 mdev helper. `stable-mac`은 eMMC CID → LAA (`02:` eth0 / `06:` wlan0) — #8 MAC 조각. init 순서 계약: `S39stablemac` < `S40network`/`S41dhcpcd`, `S99user` < `S99v_stablemac` < `S99wpa_supplicant`. `S99v`의 `v`는 자리용 글자, 번호 옮기지 말 것.
- **닫힌 것 (2026-08-30, 랩탑)**: gpu1i가 못 닿아(점프 호스트 `s3i` kex reset) **로컬에서 minimal 프로파일로 구웠다 — 3분 55초.** `milkv-duos-glibc-arm64-emmc-minimal_2026-0830-1137.zip` (57M, sha256 `08eb904b…`). 6개 파일 전부 확인, Node/Z2M/mosquitto 0건. **init 순서 계약도 실물로 확인**: `S39stablemac … S40network S41dhcpcd … S99serial-by-id S99user S99v_stablemac S99wpa_supplicant`.
- **gecko와 합의 완료 (2026-08-30, entwurf `20260830T131729-9833bd` 왕복 3회)**: 그쪽 `docs/GECKO_PORT.md §8.3` 의존 표를 minimal `target/`과 전수 대조 → **hostapd 포함 10/10**, 추가 요구 `awk`/`sed`/`cut`도 전부 있음(busybox `CONFIG_AWK/SED/CUT=y`, 그리고 minimal 프래그먼트는 심볼 5개만 만져서 **프로파일이 busybox를 건드릴 수 없다**). 남은 이미지 쪽 일 **0**.
- **Next**: (1) **플래시 승인만 GLG 자리다.** 이미지·계약·검증 순서는 양쪽 다 준비됐다. (2) **`full`(Z2M) 이미지는 굽지 마라 — 해롭다.** Z2M이 `/dev/ttyUSB0`을 선점하면 gecko resolver의 by-id 후보가 1개가 아니게 되어 fail-closed 된다(그쪽 `zigbee_backend.zig:574-604`). `gq_gateway`가 Gecko EZSP로 NCP를 직접 잡고 AWS IoT MQTT 클라이언트로 TLS 직결하므로 Z2M도 mosquitto도 쓸 자리가 없다. (3) **플래시하지 마라.**
- **닫은 갈래 둘 (이미지 쪽 작업 아님으로 확정)**:
  - **예제 `/etc/hostapd.conf`는 남긴다.** post-build script 제안했다가 그쪽 근거로 철회. 상세는 arm64 defconfig `# 6) HOSTAPD`.
  - **`CONFIG_CFG80211_WEXT`는 계속 off.** [측정] 이 이미지의 커널 `.config`에 `# CONFIG_CFG80211_WEXT is not set` — `/proc/net/wireless`가 안 생기고, 그쪽 `wifi.zig:462`가 RSSI를 매번 0으로 덮는다. 커널 defconfig가 우리 소유라 한 줄로 켤 수 있고 4분이면 되지만, **켜지 않기로 합의**했다(WEXT deprecated · 그쪽이 이미 `iw`의 `signal:`을 파싱 중 · `§8.3` 표 판정이 원래 `iw` · 그쪽 측정으로 `.network` shadow 발행이 이벤트 구동 4곳뿐이라 spawn 비용이 근거가 못 됨). 그쪽이 `wifi.zig` 한 줄로 닫는다.
- **플래시 게이트**: 보드 `192.168.0.164` MAC `06:b3:51:d1:75:4e`는 gecko가 잡고 있다. 플래시 **직전에** 그쪽에 한 번 더 신호 → 로그 회수 + 보드 비움 → 우리 플래시 → 그쪽 `install`+`certs`. 펌웨어를 우리가 기동하지 마라 (WiFi 끊김).
- **Verify (zip, 보드 아님) — 방법이 바뀌었다**: zip 안 `rootfs_ext4.emmc`는 **raw ext4가 아니라 CIMG**다(LEDGER 참조). 파일 단위 확인은 `<sdk>/buildroot/output/<board>/target/`에서 하고, 산출물 확인은 `LC_ALL=C grep -a -c <이름> rootfs_ext4.emmc`로 한다. 같은 CID면 플래시 뒤 wlan0이 다시 `06:b3:51:d1:75:4e`여야 한다 — 그건 플래시 후 gecko 검증.
- **Blocker**: 없음. full 이미지는 gpu1i 대기(급하지 않음), 플래시는 gecko 로그 회수 신호 대기.
- **Read**: `bsp/README.md` "Profiles — one board, two package sets"; `bsp/overlay/README.md` "Two overlays, split by profile"; arm64 defconfig `# 6) HOSTAPD` + `PROFILES`; gecko `board/duo-s/README.md` + `docs/GECKO_PORT.md` §8.
- **Do not touch**: 보드 `.164`. RISC-V defconfig. `feat/riscv64-nodejs-pure-cross`. gecko 펌웨어. hostapd를 부팅 init으로 올리지 말 것. eudev 넣지 말 것. `S39`/`S99v` 번호 변경. gpu1i untracked `meta-hailo/`·`yocto/sstate-cache-backup/`. **minimal 이미지를 허브 보드에 굽지 말 것** (`flash-emmc.sh arm64`는 이미 못 집게 돼 있다).

## 빌드 프로파일 — full / minimal (2026-08-30 신설)

`HOMEAGENT_BSP_PROFILE`로 **한 보드에서 두 패키지 셋**을 굽는다. 툴체인·커널·`bsp/overlay/common`은 동일하고 애플리케이션 층만 움직인다.

| 프로파일 | 패키지 | 오버레이 | 산출물 | 플래시 |
|---|---|---|---|---|
| `full` (기본) | Node 22 + Z2M + mosquitto | `common` + `z2m` | `<board>_<date>.zip` | `flash-emmc.sh arm64` |
| `minimal` | 없음 (ICU도 제외) | `common`만 | `<board>-minimal_<date>.zip` | `flash-emmc.sh arm64-minimal` |

```bash
HOMEAGENT_BSP_SDK=~/repos/3rd/milkv/duo-buildroot-sdk-v2 \
HOMEAGENT_BSP_PROFILE=minimal ./bsp/build.sh milkv-duos-glibc-arm64-emmc
```

- **존재 이유는 V8 하나다.** 랩탑 1h29m 중 1h16m, gpu1i 40m 중 28m37s가 V8이다. 증명해야 할 표면(hostapd·stable-mac·by-id)은 전부 Node **아래**라 Node가 필요 없다. 그래서 랩탑에서 4분에 끝난다.
- **베이스는 하나.** `<board>_defconfig`가 곧 `full`이고, `profiles/<board>_<profile>.fragment`를 뒤에 붙인다. kconfig가 **마지막 값**을 취하므로 override지 충돌이 아니다 → 두 프로파일이 툴체인·BSP에서 갈라질 수 없다.
- **패키지와 rootfs 파일이 같이 움직인다.** 프래그먼트가 `z2m` 오버레이도 같이 뗀다. 없는 바이너리를 가리키는 init 스크립트는 부팅 에러다.
- **이름이 안전장치다.** `flash-emmc.sh arm64`의 glob `<board>_*.zip`은 `<board>-minimal_*.zip`에 안 걸린다. 명시 경로로 줘도 `profile: MINIMAL` 배너가 뜬다.
- **산출물마다 매니페스트**: `out/<artifact>.manifest.txt`에 repo 커밋(`-dirty` 표시)·SDK 핀·sha256·해결된 패키지 셋이 남는다.
- **아직 검증 안 된 한 곳 — `full` 프로파일은 분리 이후 빌드된 적이 없다.** overlay 분리는 git이 순수 rename으로 인식했고(내용 변경 0줄) 합집합은 이전과 동일하지만, `BR2_ROOTFS_OVERLAY`에 `/bsp/overlay/z2m`가 더해진 상태로 실제로 구워보진 않았다. gpu1i 복귀 후 첫 full 빌드에서 `target/etc/init.d/S70zigbee2mqtt`와 `target/etc/mosquitto/mosquitto.conf`가 있는지만 보면 닫힌다.

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

- **2026-08-30 빌드 프로파일 신설 + minimal 이미지 실증 (랩탑)**: gpu1i 불통(점프 호스트 `s3i`가 kex에서 reset)이라 로컬로 돌렸다. 랩탑 트리를 재보니 **타깃 V8은 애초에 빌드된 적이 없었고**(`nodejs/.stamp_built` 없음, `target/`·`images/` 비어 있음, 159/162만 스탬프) — 그래서 Node를 빼도 지불한 것을 버리는 게 아니었다. `HOMEAGENT_BSP_PROFILE=full|minimal` 도입, `bsp/overlay`를 `common`/`z2m`으로 분리, 산출물 이름·매니페스트로 버전 관리. **minimal 빌드 3분 55초**, zip 57M(full 104M, −47M). 6개 표면 파일 확인, Node/Z2M/mosquitto 0건. 보드는 안 만졌다.
- **2026-08-28 gecko 패키징 표면 (레시피만, 미빌드)**: sks-hub-gecko SoftAP가 이미지에 없어 막힘. arm64에 hostapd(개방망) + mdev `/dev/serial/by-id` + stable-mac(eMMC CID, #8 MAC 조각) 넣음. 보드 `.164` 안 만짐. 다음 = gpu1i 증분 빌드.
- **2026-07-24 (2세션) 방향 정리 — Matter 준비 + SMHub 대조**: matter.js bump 경로 조사 완료(관문 열림 — 위 "Matter / matter.js 올리기"), **corepack은 개발 중이라 의도적 유지**로 재판정, 커널 defconfig 주석은 **이미지 불변이라 실기 검증 불필요**로 확정, SMHub Nano 단일 MG24 배타 / 벤더 매뉴얼의 "별도 칩"은 상위 모델 전제임을 교정(LEDGER). **다음 실질 축 = 제품화 수준의 Duo S 구성 준비**([#8](https://github.com/junghan0611/homeagent-config/issues/8) — 선행 세대의 ssh push/제조사 이관을 반면교사로, 이미지가 소유해야 할 것 대조표 + 남은 축 5개). 회사 레인의 z2m 허브 개발은 병행, Matter는 언제든. **문서 조이기**: 리포 문서는 토픽 이슈로 이전(#7·#8·#9), absorbed 스텁 5개 제거 → `docs/` 25→18, 루트는 표준 7개.
- **2026-07-24 flash-and-go 완성 + v2026.7.24 태그**: 보드 91에서 flash → host전환 → 동글 = Z2M 자동 기동을 config 손 안 대고 실증. flash 신뢰성(cdc_acm bind-then-unbind, 거짓완료 UUID 대조), Z2M seed serial pin(udevadm 부재 회피), 증분 빌드 2m37s. `duo-s-flash` 스킬 + `bsp/usb-recovery-prepare.sh` + `bsp/BOARDS.md` 신설. **상세 전부 CHANGELOG v2026.7.24.**
- 그 이전(arm64 전환, Node 22, Z2M 통합, riscv pure-cross 등)은 CHANGELOG v2026.7.24 및 v2026.7.15.

# LEDGER

- **zip 안의 `rootfs_ext4.emmc`가 CVITEK `CIMG`라는 건 이 리포가 이미 알고 있었다 — 내가 다시 발견한 게 아니다 (2026-08-30 정정).** `flash-emmc.sh:356-357`이 "vendor wraps the partition in a 64-byte CIMG header … locate the superblock by its magic instead of assuming"이라 적고 그렇게 구현돼 있다. 내가 처음에 이걸 새 발견처럼 LEDGER에 올렸는데, 알려진 사실을 재발견으로 적는 건 다음 사람에게 "이 리포는 자기가 아는 걸 모른다"고 가르치는 셈이라 고친다. **새로운 건 실패 모드 쪽이다**: `debugfs -R "stat <path>"`가 어떤 경로에도 조용히 빈 결과를 주므로, 있어야 할 6개가 전부 `MISSING`으로 **그리고 없어야 할 Node/Z2M도 전부 `absent`로** 나온다 — 두 답이 다 무효인데 절반은 원하던 답처럼 보인다. `100%/complete는 증거가 아니다`와 같은 계열. 파일 단위 확인은 `buildroot/output/<board>/target/`에서, 산출물 확인은 `LC_ALL=C grep -a -c`로. (구조: 64B 파일 헤더 + 청크당 64B 헤더, 이 이미지는 48청크. 형식 SSOT `build/tools/common/image_tool/raw2cimg.py`.)
- **`flash-emmc.sh` step 5가 `usb-recovery-prepare.sh`와 정반대를 말하고 있었다 (2026-08-30 정정, sks-hub-gecko가 플래시 전 두 파일을 대조해 발견).** 헤더는 "installs the udev rule that stops cdc_acm from ever being loaded"라 적었는데, 스크립트는 **cdc_acm을 일부러 `modprobe`하고 차단 룰을 발견하면 지운다**(`usb-recovery-prepare.sh:66-70, 86`). 즉 헤더가 설명하던 그 룰이 스크립트가 삭제하는 그 룰이다 — 헤더만 읽은 사람은 `removed …` 로그를 이상 징후로 읽거나 룰을 손으로 되살려 `config cdc(0x22) failed: TIMEOUT`을 부른다. **계약은 "막는다"가 아니라 "붙였다 뗀다"**이고, 그건 이 리포가 이틀 걸려 반증한 것이다. 문서가 그 값을 되돌리고 있었다.
- **제품 ISA/libc는 여전히 RISC-V C906 + SDK-native musl이다.** arm64는 2026-07-23부터 **개발 레인**이지만 제품 ISA로 승격된 것이 아니다.
- **커널 config는 우리가 소유할 수 있다 (2026-07-23 정정).** 어제 NEXT는 "`linux_5.10`의 `cvitek_*` 계열이라 우리가 소유하지 않은 파일"이라 적었는데, 실제 경로는 `build/boards/cv181x/<board>/linux/cvitek_<board>_defconfig` — **보드 디렉토리 안**이다. 소유 범위를 넓힐지 고민할 문제가 아니었다.
- **SDK의 `board/milkv/<board>/overlay`는 클린 트리에 없다.** `build/Makefile:646`이 빌드 중 `tmp-rootfs`에서 만들고 `:666`에서 지운다. `/mnt/system/*`이 거기서 온다. 그래서 SDK 빌드 스크립트를 우회해 `make -C output`만 돌리면 target-finalize에서 rsync가 실패한다.
- **`/mnt/system`은 별도 파티션이 아니라 rootfs 안의 디렉토리다** (`/dev/root`, ext4 rw). 그래서 그 아래 파일도 overlay로 덮어쓸 수 있다. `/var`도 tmpfs가 아니라 실제 디렉토리라 Z2M/mosquitto 상태가 재부팅을 넘긴다.
- **per-package 디렉토리의 함정**: `BR2_PER_PACKAGE_DIRECTORIES=y`면 각 패키지가 자기 `host/` 트리를 의존성에서 rsync 받는다. 이미 빌드된 패키지에 의존성을 추가하고 `<pkg>-reinstall`만 돌리면 그 트리는 갱신되지 않아 `host/bin/npm`이 없다고 실패한다. 클린 빌드는 이 문제를 정의상 겪지 않는다.
- Buildroot 이미지가 기준 산출물이다. SMHub식 `.ipk`/OpenRC/별도 `/opt` 지속면은 상용 배포 모델 참고이며 blocker가 아니다.
- SG2000은 같은 다이에 A53과 C906을 얹고 **물리 스위치**로 하나를 고른다 (eFuse 아님, 되돌릴 수 있음). 보드 defconfig가 동일해 ISA 전환에 보드 브링업이 필요 없다.
- `BR2_PACKAGE_NODEJS_ARCH_SUPPORTS = arm/aarch64/i386/x86_64 — no riscv`는 2026-06-30 SMHub 포렌식에 이미 있었다. arm 전환의 근거는 새 발견이 아니라 **한 달 전 증거의 재판정**이다.
- **SMHub 라디오 아키텍처 — "별도 칩"의 정확한 뜻 (2026-07-24 교정).** 실물 **SMHub Nano는 MG24 하나뿐**이라 Zigbee coordinator **또는** Thread RCP **배타**다(`docs/SMHUB.md §2`; RCP로 재플래시하면 Zigbee 상실 → Thread/OTBR 보류). 벤더 매뉴얼(`docs/smhub-manual/pages/`)의 "Thread(EFR32MG series) native OTBR", "별도 EFR32MG `/dev/ttyS2`", "OTBR + Matterbridge 통합"은 **§6 제네릭 = 상위 모델(Essential/Premium) 전제** 문서이지 Nano 실물 능력이 아니다 — `§2.2`가 "Nano 검수 시 §6 표를 그대로 따르면 안 됨"으로 못 박았다. **matterbridge는 앱 계층(IP 위 Zigbee→Matter 노출)이라 Thread 지원 여부와 별개 축**이며, 한 제품에서 OTBR와 공존한다. 우리 Duo S의 **USB 2동글(NCP+RCP)이 그 상위 모델의 "별도 칩 2개"에 대응** → 단일 MG24 Nano가 못 하는 **Zigbee+Thread 동시**가 개발 단계에서 가능하다. 지금 USB인 건 온보드 라디오가 없어서일 뿐, 제품화는 **MG24(단일→배타)/MG26(concurrent multiprotocol)/별도 칩** 중 하드웨어 결정. **Thread/OTBR는 우리가 처음 실증하는 영역**(Nano도 안 세웠고, 매뉴얼은 상위 모델용이라 절차 청사진이지 검증 근거가 아니다). SMHub은 낮춰볼 대상이 아니라 **지향하는 완성형 참조 제품**이다.
