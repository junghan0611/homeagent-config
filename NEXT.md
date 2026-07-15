# NOW — Duo S 제품 레인: 순수 크로스컴파일 Buildroot로 Node `.ipk`를 재현

> **확정 정책 (2026-07-15). 대안 검토 종료.** 아래가 확정 축이며 NEXT · ROADMAP · `docs/SMHUB.md`가 여기에 정렬한다.

- **Stem**: 첫 공개 제품 증명 = "우리 보드가 Zigbee 1기기를 MQTT/Home Assistant 방식으로 왕복시키는 샘플 허브".
  토대는 **Node.js를 보드에 재현 가능하게 올리는 것**(z2m·matter.js 등 이후 JS 스택이 전부 Node 위). Matter는 그 뒤다.
- **참조 원칙**: SMHub 출고 이미지는 **계약(version · ABI · `/opt` layout · deps · service)의 참조**다. 벤더 recipe /
  커널 / `.ipk` / 배포 스크립트는 반입하지 않고 **공개 upstream source(`nodejs/node` 등)로 우리 패키지를 재현**한다.
  측정 계약은 `docs/SMHUB.md §3.2·§5.2·§5.4`(공개 SSOT).
- **빌드 정책**: **순수 크로스컴파일.** 빌드 호스트에서 target 바이너리를 실행(qemu-user)하거나 real RISC-V에서 native
  빌드하지 않는다. 이는 제품 패키지 빌드 정책이다.

## 확정 축

- **N0 = 우리 SDK Buildroot에서 순수 cross-compile로 Node 22.22.0(rv64gc / glibc)을 빌드 → `.ipk`로 `/opt`에
  설치 가능한 패키지 생성 + 실기 smoke.** SMHub 출고 계약 매칭, 공개 source 재현.
- **빌드 시 target 실행 없음(LOCKED 제약)**: QEMU-user, native RISC-V runner 모두 배제. V8 snapshot 처리의 첫 기술
  게이트 = **host cross-snapshot(또는 동등한 V8 pure-cross) 경로 증명**. `--without-node-snapshot`은 후보/보조 옵션이며
  단독으로 target 실행 제거를 보장하지 않는다(Node v22.22.0 `configure.py`: cross면 이미 `node_use_node_snapshot=false`,
  `--without-snapshot`은 미지원 경고). **실패경계는 Node snapshot vs V8 snapshot을 분리**해 기록한다.
- **SDK 무포크**: 확장은 `bsp/patches/`를 pinned·unforked working clone에 주입하는 방식만. **커널은 우리 linux 5.10 유지**(SMHub은
  kernel 6.18 — 별도 vendor Buildroot BSP/external tree·patch 여부는 비공개; 그 커널/BSP를 따라가지 않음 →
  "Duo S ≠ SMHub image" 유지).
- **libc dual-lane**: service image = **glibc**(새 `milkv-duos-glibc-riscv64-emmc` 변형). 기존
  `milkv-duos-musl-riscv64-{sd,emmc}` = `homeagentd` / minimal baseline으로 보존. `homeagentd`가 service image에
  합류할 땐 static/portable artifact로.
- **version**: 첫 parity pin = **22.22.0**(SMHub 출고와 동일). 기술 증명 후 최신 유지보수 Node22 LTS로 update gate.
- **packaging**: **installable `.ipk`(absolute `/opt` prefix, RUNPATH `/opt/lib`) + OpenRC** 서비스.
  untracked 직접 파일 주입은 배제하고 **package manager가 추적하는 preinstall**만 허용한다.

## 역설계 근거 (beta5 이미지 실측, `captures/smhub-beta5-20260630/`; 공개 계약은 `docs/SMHUB.md`)

- opkg status(검증): **`nodejs 22.22.0-2` / `Architecture: riscv64`**, `/opt` 설치, 완전한 opkg 메타셋(`.control /
  .list / .postinst / .npmrc / .pnpmfile.cjs / .schema.json`). → **Buildroot toolchain으로 빌드된 Node가 opkg
  package로 `/opt`에 설치**. (Buildroot가 `.ipk`를 직접 생성하는 exact pipeline은 비공개.)
- OS = `Buildroot 2026.02-18-g60430d6802 / SMHUB 1.0.0.beta5`, **kernel 6.18**(manual §"upgrade from vendor 5.4.x").
  우리 SDK = **linux 5.10**. 피드 `pkg.smlight.tech`는 `.ipk` 바이너리만(소스 비공개).
- 소스맵은 `docs/SMHUB.md §5.2`(Node 22.22.0 → `nodejs/node`, z2m 2.10.1 → Koenkk + pnpm-lock 확보 …).
- upstream Buildroot 2026.02도 Node RISC-V arch allowlist 없음(raw 확인) → **arch-enable은 확정적으로 필요한 공개 재현
  조각 중 하나**다. V8 pure-cross snapshot 경로는 이미지가 알려주지 않으므로 N0 첫 기술 게이트에서 증명한다.

## N0 착수 시 소유할 surface (GLG go 후)

- 새 `bsp/board/milkv-duos-glibc-riscv64-emmc/` : **top-level defconfig = glibc/toolchain/board 선택**
  (`CONFIG_TOOLCHAIN_GLIBC_RISCV64=y`, `CONFIG_CROSS_COMPILE="riscv64-unknown-linux-gnu-"`, 커널 5.10 유지). **Buildroot
  rootfs config가 package C/CXX/LD `rv64gc/lp64d`와 Node 선택을 소유**(현재 `buildroot/configs/<board>_defconfig`에
  `BR2_PACKAGE_NODEJS` 없음, repo 미소유). 두 surface를 분리한다.
- `bsp/patches/`: Node RISC-V arch-enable(`Config.in` `BR2_riscv` + `nodejs-src.mk` `NODEJS_SRC_CPU=riscv64`) +
  V8 pure-cross snapshot 경로(위 첫 기술 게이트) + Node **22.22.0 source URL/hash로 recipe pin update**.
- `.ipk` 패키징 + `/opt` 배치 + OpenRC autostart(SMHub 서비스 계약 모사, `docs/SMHUB.md §5.4`).
- `bsp/build.sh` **fail-closed**: 패치 미적용 현재 `WARN`+continue(`bsp/build.sh:73-77`) → "미적용=실패"로. SDK dirty는
  scoped(pin 확인 + patch별 reverse/apply-check + exact path/hash), 전체 `git reset/clean` 금지(in-tree output 보존).

## N0 합격 기준

- **host 게이트(실행 아님)**: 산출 ELF = riscv64 + glibc, interpreter가 service image loader와 일치, GLIBC max symbol이
  SDK sysroot 이하, `NEEDED` 전부 `/opt/lib`+base에서 해소(`readelf`). provenance 공개(source URL·tag·SHA256·license·
  toolchain·docker image ID/RepoDigest; `:latest` 문자열 금지). **빌드에 qemu/native target 실행 흔적 0.**
- **runtime 게이트(실기 Duo S 전용, GLG go 후)**: `node -p 'process.arch+":"+process.versions.node'` = `riscv64:22.22.0`.
  host는 riscv 바이너리를 실행할 수 없으므로 runtime 합격은 실기에서만 판정한다.
- 기존 musl sd/emmc 빌드 회귀 보존. 실패 시 정확한 경계 기록.

# AFTER N0 — 순서 고정

- **N1** package lifecycle 확립: `.ipk` install / upgrade / remove / reboot 지속 + OpenRC. Mosquitto를 같은 방식으로
  추가하고 자동 기동 + localhost pub/sub 검증.
- **N1.5** 메모리 회수: camera/codec ION carveout(~170MB) 트림 + 잔여 `cvi_*` 비전 모듈 제거(Node 뒤, Z2M 전 게이트).
- **N2** Zigbee2MQTT 공개 upstream 2.10.1 + lockfile를 같은 `.ipk`/`/opt` 방식으로. private serialport shadow tarball
  금지. `@serialport/bindings-cpp`의 **Node-API compiled addon을 공개 source에서 같은 sysroot로 cross-build** →
  `/dev/ttyUSB*` open smoke.
- **N3** Zigbee 1기기 + HA 호환 수직 슬라이스. ZBDongle-E = EmberZNet 7.4.2 / EZSP 13 / 115200 / `rtscts:false`.
  cold boot → Z2M `bridge/state=online` → pair → report → command ack → 재부팅 생존. discovery+state+`…/set` 왕복 증거.
- **N4** 샘플 허브 + 서버(Go 최소 adapter) + 앱(Lit `ui/dist` 정적). Matter/commissioning/A2A/A2UI는 이후.

# DECISIONS / GUARDRAILS

- **확정: 순수 크로스컴파일 Buildroot → `.ipk` → `/opt`.** 빌드 시 target 실행(qemu-user)·native RISC-V 빌드 배제.
- **SMHub은 계약 참조만**: version 22.22.0 · rv64gc/glibc ABI · `/opt` layout · deps · service를 매칭. **반입 안 함**:
  벤더 커널/BSP, 비공개 recipe, 벤더 `.ipk`, authenticated opkg payload, private serialport shadow, SLZB-OS/배포 스크립트.
- **SDK 무포크**: `bsp/patches/` 주입만, pinned·unforked working clone과 커널 5.10 유지.
- **재현 빌드만**: 벤더 바이너리 복사 금지, 공개 source에서 cross-build.
- **installed ≠ running ≠ working**: package 존재/서비스 enable/프로세스 기동/실제 왕복을 구분해 판정.
- live IP/MAC/키/네트워크키는 `PRIVATE.md`/gitignored captures에만. git hook 우회 금지.
- **실기 flash는 GLG go 후에만**. 커밋/푸시는 GLG 결정.

## ROADMAP invariant — 함께 정렬(정교화)

1. **runtime target**: `homeagentd` = `riscv64-linux-musl` artifact baseline + Node service image = glibc(dual-lane).
2. **"Duo S ≠ SMHub image"**: 유지. 커널 5.10 유지 + 무포크 → SMHub 이미지로 수렴하지 않고 형상(ABI/패키징 계약)만 재현.

# RECENT

- **2026-07-15**: N0 방향 확정 — 순수 크로스컴파일 Buildroot로 Node `.ipk`를 공개 source에서 재현(target 실행 없음,
  SDK 무포크, 커널 5.10, SMHub은 계약 참조만). beta5 이미지 실측으로 `nodejs 22.22.0-2 riscv64` opkg `/opt` 설치 확인,
  SMHub kernel 6.18 / 비공개 피드 확인. 실기는 read-only만, flash/mutation 없음.
- **v2026.7.15**: Duo S RISC-V 자체 이미지 실기 부팅, ARM→RISC-V 문서 전환, ZBDongle-E 7.4.2 펌웨어,
  `docs/BUILDROOT.md` 추가. 상세 이력은 `CHANGELOG.md`와 `docs/SMHUB.md`.

# LEDGER

- base = 우리 SDK 유지 + glibc-riscv64 service 변형. mainline BSP 이전 / dual-libc(musl base+glibc Node)는 배제.
  SDK에 glibc RISC-V toolchain/sysroot + `TOOLCHAIN_GLIBC_RISCV64` Kconfig 존재, Duo board 변형만 부재(확인).
- target 실행 배제 배경: T-Head C906 draft RVV0.7(`v0p7_xthead`)이 mainline QEMU와 충돌 → 우회(Node 범위 rv64gc
  mksnapshot-under-qemu)는 폐기, 순수 크로스 + rv64gc glibc service 변형으로 대체.
- RISC-V C906 big core + C906L FreeRTOS + EFR32 radio 3분할 유지. USB ZBDongle-E는 Duo S 개발 증명용, 최종 제품
  형상은 onboard EFR32.
- `homeagentd`/C906L 메일박스와 제품화 rootfs는 폐기 안 함. 첫 종단 표적이 Node/Z2M/HA 호환일 뿐, 각 단계가 닫힐 때
  원래 런타임 stem으로 합류.
