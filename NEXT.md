# NOW — Duo S Buildroot 제품 서비스 레인: glibc RISC-V Node → Mosquitto → Z2M → HA 호환

- **Stem**: SMHub를 동작 레퍼런스로 삼되 벤더 바이너리·비공개 피드에 의존하지 않고, 우리 Buildroot 이미지가
  **Node.js + Mosquitto + Zigbee2MQTT + ZBDongle-E**를 부팅부터 자동 기동해 Zigbee 1기기의 상태·명령을
  MQTT/Home Assistant 방식으로 왕복시키는 첫 샘플 허브를 만든다. Matter는 이 수직 슬라이스가 닫힌 뒤다.
- **다음 세션 단일 미션 — N0**: 기존 `musl-riscv64` 보드는 보존하고 **`glibc-riscv64` 제품 서비스 변형**을
  추가한 뒤, Node.js 22 LTS를 **공개 upstream source에서 Buildroot 패키지로 재현 빌드**해 `node -p` smoke까지 닫는다.
- **왜 glibc 변형인가 (2026-07-15 실측)**: SMHub beta5의 `/opt/bin/node` 22.22.0-2는 RISC-V glibc ELF
  (`/lib/ld-linux-riscv64-lp64d.so.1`, RUNPATH `/opt/lib`)이고, 로컬 `~/repos/3rd/milkv/nodejs-riscv`도
  공식 Node source를 RISC-V Ubuntu/glibc runner에서 빌드한다. 현재 Duo S는 musl이라 그 바이너리를 직접 쓸 수 없다.
  SDK에는 `riscv64-unknown-linux-gnu` toolchain이 이미 있으므로 **glibc 보드 변형 + source build**가 우선 경로다.
- **Node 기준점**: SDK Buildroot 2025.02 recipe와 SMHub 0.9.8 registry가 같은 **22.13.1**을 첫 pin으로 삼는다.
  N0 통과 뒤 beta5 실설치 **22.22.0-2** 정렬 여부를 결정한다. `nodejs-riscv`의 latest-tag CI/Node 25 산출물은
  포팅 참고·독립 증거일 뿐 제품 패키지로 복사하지 않는다.
- **Blocker**: upstream Buildroot도 RISC-V Node를 아직 열지 않는다. 우리 패치에는 최소한
  `BR2_PACKAGE_NODEJS_ARCH_SUPPORTS += BR2_riscv`와 `NODEJS_SRC_CPU=riscv64`, QEMU/V8 snapshot 경로 검증이 필요하다.
- **Read first**: `docs/BUILDROOT.md` → `bsp/README.md` → SDK `buildroot/package/nodejs/` →
  `~/repos/3rd/milkv/nodejs-riscv/.github/workflows/build-node.yml` → `docs/SMHUB.md §3.2, §5.2, §5.4`.
- **Do not touch**: SMHub 설치/피드 mutation, Matter/Matterbridge/Node-RED, MG24 리플래시, 기존 musl 보드 삭제,
  vendor Node/serialport 바이너리 반입, Type-C full flash. 실기 flash는 GLG go 뒤에만 한다.

## N0 — Node.js 22 Buildroot source package (다음 오푸스 작업 범위)

1. **보드 변형**: `milkv-duos-glibc-riscv64-emmc`를 기존 musl RISC-V 보드의 최소 delta로 추가한다.
   ISA는 그대로 C906/RISC-V이며 libc만 glibc로 분리한다. 기존 musl 산출물과 이름·출력 경로를 섞지 않는다.
2. **패키지 패치**: SDK Node 22.13.1 recipe를 RISC-V에 열고 `--dest-cpu=riscv64`로 cross-build한다.
   source URL/tag, SHA256, license, SDK commit, toolchain, Docker image digest를 manifest에 남긴다.
3. **빌드 검증**: patch 미적용은 WARN이 아니라 실패. 산출물은 `file/readelf`로 RISC-V + glibc interpreter를 확인하고,
   가능하면 Buildroot host QEMU로 `node -p 'process.arch+":"+process.versions.node'`를 실행한다.
4. **실기 게이트(GLG go 후)**: Duo S에 flash → `uname -m=riscv64` → Node smoke → RSS/기동시간 기록 → 재부팅 후 재확인.
5. **N0 종료 산출물**: 재현 가능한 board config/patch/package, build manifest, smoke 결과. Z2M 설치는 아직 하지 않는다.

### N0 합격 기준

- `node -p process.arch` = `riscv64`, 버전 = pin과 일치.
- ELF interpreter가 glibc이며 모든 `NEEDED` 라이브러리가 이미지에서 해소된다.
- 동일 입력의 재빌드 절차와 source/hash/license provenance가 공개 리포에 남는다.
- 기존 `milkv-duos-musl-riscv64-{sd,emmc}` 빌드가 보존된다.
- 실패 시 “Node 불가”로 뭉개지 않고 configure/build/QEMU/runtime 중 정확한 경계를 기록한다.

# AFTER N0 — 순서 고정

## N1. Hub-minimal + 제품 rootfs 기반

- ION 170MB 멀티미디어 carveout과 비전 모듈을 제거하되 **C906L FreeRTOS 2MB + `rtos_cmdqu`는 보존**한다.
- Buildroot 파일 주입용 `BR2_ROOTFS_OVERLAY`와 런타임 rw DATA/OverlayFS를 구분한다.
- DATA 파티션, BusyBox init 서비스, first-boot, 네트워크, 지속 로그를 최소 단위로 만든다.

## N2. Mosquitto + Z2M 재현 패키지

- Mosquitto를 먼저 자동 기동하고 localhost pub/sub를 검증한다.
- Zigbee2MQTT는 공개 upstream **2.10.1** + lockfile로 패키징한다. SMHub의 private `rigel.smlight.tech`
  serialport shadow tarball은 쓰지 않는다. `@serialport/bindings-cpp` RISC-V native addon을 공개 source에서
  같은 Buildroot sysroot로 빌드해 `/dev/ttyUSB*` open smoke를 먼저 통과시킨다.
- Node → serialport → Z2M 순으로 실패 경계를 분리한다. 한 번에 z2m 전체를 디버그하지 않는다.

## N3. Zigbee 1기기 + Home Assistant 호환 수직 슬라이스

- ZBDongle-E = EmberZNet 7.4.2 / EZSP 13 / 115200 / `rtscts:false` (`firmware/zbdonglee/`).
- cold boot → Z2M `bridge/state=online` → 1기기 pair → report → command ack → 재부팅 생존.
- `homeassistant.enabled: true`; retained discovery `homeassistant/…/config`,
  `zigbee2mqtt/<friendly_name>` state, `…/set` command 왕복을 증거로 남긴다.
- 캡처는 pass/fail JSONL + 버전/RSS/포트/로그로 남긴다. “프로세스 started”만으로 합격시키지 않는다.

## N4. 샘플 허브 + 서버 + 앱 세트

- **허브**: Buildroot + Node/Mosquitto/Z2M + USB radio.
- **서버**: 기존 Go surface에 최소 Z2M/MQTT adapter를 붙여 REST/SSE로 정규화한다. 비즈니스 로직 없음.
- **앱**: 기존 Lit `ui/dist`를 정적 제공해 상태 표시·on/off 한 동작만 왕복시킨다.
- Z2M frontend는 운영/진단 UI로 유지한다. Matter/commissioning/A2A/A2UI 확장은 이 세트 합격 뒤다.

# DECISIONS / GUARDRAILS

- **libc 두 레인**: musl = 최소 런타임·`homeagentd` 실험 기준선, glibc = Node/Z2M 제품 서비스 후보.
  N0 실측 전 표준 문서의 제품 libc를 일괄 전환하지 않는다.
- **SMHub에서 가져오는 것**: 버전·ABI·패키지 구성·서비스 계약·검증 기준. 가져오지 않는 것:
  벤더 Node ELF, authenticated opkg payload, private serialport shadow package, 비공개 Buildroot diff.
- **첫 공개 제품 증명**은 Zigbee/HA 호환까지다. Matter는 명시적으로 후속이다.
- **실행 ≠ 동작**: installed/enabled/running/working을 구분하고 실제 MQTT/serial/radio 왕복으로 판정한다.
- live IP/MAC/키/네트워크키는 `PRIVATE.md`/gitignored captures에만 둔다. git hook 우회 금지.

# RECENT

- **2026-07-15 PM 담금질**: 원격 `ff3ba12` fast-forward. SMHub beta5 `user.img`를 read-only로 재확인해
  Node 22.22.0-2가 **glibc RISC-V**임을 확정했다(74.8MB ELF, `/opt/lib` shared deps). SDK Buildroot Node recipe는
  22.13.1이나 RISC-V menu/CPU mapping이 닫혀 있고, QEMU user RISC-V와 glibc RISC-V toolchain은 이미 있다.
  SMHub Z2M 2.10.1은 `@serialport/bindings-cpp` 13.0.1 RISC-V addon을 private shadow tarball로 치환하므로,
  공개 재현 레인은 addon source build를 별도 게이트로 삼는다.
- **v2026.7.15**: Duo S RISC-V 자체 이미지 실기 부팅, ARM→RISC-V 문서 전환, ZBDongle-E 7.4.2 펌웨어,
  `docs/BUILDROOT.md` 추가. 상세 이력은 `CHANGELOG.md`와 `docs/SMHUB.md`.

# LEDGER

- Duo S SDK Linux 5.10 + CVITEK `rtos_cmdqu`와 SMHub Linux 6.18 + remoteproc/rpmsg는 이미지 비호환이다.
  SMHub는 동작 레퍼런스, Duo S `bsp/`가 공개 빌드 레인이다.
- RISC-V C906 big core + C906L FreeRTOS + EFR32 radio의 3분할은 유지한다. USB ZBDongle-E는 Duo S 개발 증명용이며
  최종 제품 형상은 onboard EFR32다.
- `homeagentd`/C906L 메일박스와 제품화 rootfs는 폐기하지 않는다. 다만 첫 종단 표적은 Node/Z2M/HA 호환이며,
  각 단계가 닫힐 때 원래 런타임 stem으로 합류한다.
