# NOW — N0 pure-cross Node: G0-α(소스 판정) → G0(snapshot seam 실측)

- **Stem**: 우리 Milk-V SDK(Buildroot 2025.02, linux 5.10)에서 **Node 22.22.0을 순수 크로스컴파일**해
  `rv64gc/glibc` `.ipk`로 `/opt`에 설치하고, 이후 Mosquitto → Z2M → Zigbee/HA 수직 슬라이스를 닫는다.
- **현재**: 준비 100% / 실행 0. 패치 초안 D1–D7, G0·G1 명령, 합격선까지 전부 문서화돼 있다.
  타깃 툴체인도 이미 로컬에 있다 — `host-tools/gcc/riscv64-linux-x86_64/bin/riscv64-unknown-linux-gnu-gcc`
  = Xuantie glibc **GCC 10.2.0**, `ld-linux-riscv64-lp64d.so.1`(= 합격선 GCC 10.2 / GLIBC ≤ 2.33 일치).
  받아야 할 것은 Node tarball 하나뿐이고, **빌드는 전부 x86 호스트 크로스** — 보드는 마지막 runtime gate에만 등장한다.
- **다음 한 걸음 — 2단, G0까지만**:
  1. **G0-α (2분, 빌드 아님)**: tarball sha256 검증 후 `deps/v8/src/common/globals.h`에서 `USE_SIMULATOR`가
     `V8_TARGET_ARCH_RISCV64 && !V8_HOST_ARCH_RISCV64`로 자동 정의되는지 **소스로 판정**한다.
     riscv64가 목록에 없으면 G0을 돌리기 전에 계획부터 고친다(§14 residual이 여기서 반쯤 닫힌다).
  2. **G0 (2~3시간)**: scratch에서 Node `v22.22.0`을 최소 기능으로 configure하고 **x86 host `mksnapshot` +
     `v8_snapshot/embedded.S` action만 targeted build**한다. full Node/SDK 통합은 하지 않는다.
- **정지 조건**: G0 pass/fail과 정확한 로그를 남긴 즉시 멈춘다. G1으로 자동 진입하지 않는다.
- **Blocker**: none — **GLG G0 실행 승인(2026-07-21)**. 실기 flash·commit·push는 여전히 별도 승인.
- **Read**: `captures/smhub-beta5-20260630/extracted/node-build-forensics.md` **§12–§16**(gitignored),
  `yocto/sources/meta-openembedded/meta-oe/recipes-devtools/nodejs/nodejs_20.20.0.bb`(선례 원본).
- **Do not touch**: SDK 트리 · `bsp/patches/` · 보드 · SMHub 실기. G0은 gitignored scratch 안에서만 돈다.

## 3분 부트 순서

1. 읽기:
   - `captures/smhub-beta5-20260630/extracted/node-build-forensics.md` **§7–§16** (gitignored 포렌식/실험안)
   - `yocto/sources/meta-openembedded/meta-oe/recipes-devtools/nodejs/nodejs_20.20.0.bb` (same-width 선례 원본)
   - SDK `buildroot/package/nodejs/{Config.in,nodejs.mk,nodejs-src/}`
2. source: `node-v22.22.0.tar.xz`, SHA256
   `4c138012bb5352f49822a8f3e6d1db71e00639d0c36d5b6756f91e4c6f30b683` 검증 후 gitignored scratch에 푼다.
3. **G0-α**: `deps/v8/src/common/globals.h`의 `USE_SIMULATOR` 정의 조건에 RISCV64가 있는지 확인 → pass/fail 기록.
4. configure(G0 최소면):
   - target `CC/CXX` = `host-tools/gcc/riscv64-linux-x86_64/bin/riscv64-unknown-linux-gnu-{gcc,g++}` (rv64gc/lp64d)
   - host `CC_host/CXX_host/AR_host` = x86_64 host toolchain
   - `--cross-compiling --dest-cpu=riscv64 --dest-os=linux --with-intl=none --without-npm --without-corepack --ninja`
5. Ninja graph에서 실제 target 이름을 찾고 **host tool + V8 snapshot action만** 빌드한다.
6. 로그·ELF·generated `embedded.S`를 gitignored capture에 보존하고 결과를 보고한다.

### G0 합격 기준

- generated config: `host_arch=x64`, `target_arch=riscv64`, `want_separate_host_toolset=1`,
  `node_use_node_snapshot=false`.
- `mksnapshot` 및 필요한 host generators = **x86-64 ELF**.
- `v8_snapshot` action이 x86 host tool을 실행해 RISC-V `embedded.S`를 생성한다.
- build trace에 `qemu`, RISC-V ELF 실행, `Exec format error`가 없다.
- 실패 시 simulator/host-link/variable-propagation 중 정확한 경계를 기록하며 QEMU로 우회하지 않는다.

### G0 금지선

- full Node build, SDK/`bsp/patches/` 수정, `.ipk` 생성, 실기 flash/deploy 금지.
- SMHub SSH 활성화·설정 변경·opkg mutation 금지. live probe는 N1.5에서 별도 승인한다.
- host `-latomic`은 실제 `__atomic_*` link 실패 때만 추가한다.

# G0 통과 뒤 — N0 통합 순서

1. **보드 변형**: `milkv-duos-glibc-riscv64-emmc` 추가. SDK 보드 목록은 `glibc_arm64_{sd,emmc}` +
   `musl_riscv64_{sd,emmc}`뿐이라 **glibc×riscv64 조합은 존재하지 않는다 — N0이 신설**한다.
   기존 musl sd/emmc는 `homeagentd` baseline으로 보존.
2. **Buildroot base**: pinned SDK/Buildroot 2025.02 유지. 전체 2026.02 업그레이드 금지.
   2026.02 Node package의 22.22.0 source/hash/patch delta만 비교해 최소 backport한다.
3. **RISC-V pure-cross recipe**: `BR2_RISCV_64` allowlist + `NODEJS_SRC_CPU=riscv64` +
   riscv64에서 `CC_host/HOSTCC` 분리 + QEMU wrapper/dependency 비활성. 다른 arch 동작은 보존.
4. **ICU**: system ICU 73.2 configure-check가 우선. 실패/기능 부족 시 small-icu 또는 full-icu를 선택하되,
   추가 source/data URL·hash와 offline 재현 비용을 명시한다.
5. **패키징**: Node/npm/pnpm을 package manager가 추적하는 `.ipk`(absolute `/opt`, RUNPATH `/opt/lib`) + OpenRC로 구성.
6. **host gate**: riscv64/lp64d, loader 일치, `GLIBC <= 2.33`, `GLIBCXX <= 3.4.28`, rv64gc/no-RVV,
   NEEDED 해소, V8 embedded blob 존재, qemu/native target 실행 0.
7. **runtime gate(GLG go 후 실기)**: `node -p 'process.arch+":"+process.versions.node'` = `riscv64:22.22.0`.

# AFTER N0 — 순서 고정

- **N1** `.ipk` install/upgrade/remove/reboot 지속 + OpenRC lifecycle, Mosquitto localhost pub/sub.
- **N1.5** ION carveout(~170MB)·`cvi_*` 비전 모듈 제거. C906L FreeRTOS/`rtos_cmdqu`는 보존.
- **N2** Z2M 2.10.1 + lockfile, `@serialport/bindings-cpp` Node-API addon 공개 source cross-build.
- **N3** ZBDongle-E(EmberZNet 7.4.2/EZSP13) + Zigbee 1기기 pair/report/command/reboot + HA discovery.
- **N4** 샘플 허브 + 서버 adapter + Lit 앱. Matter/A2A/A2UI는 이후.

# RECENT

- **2026-07-15 포렌식**: SMHub Node `22.22.0-2`의 config.gypi·symbols·opkg index를 복원했다.
  `host_arch=riscv64`, separate host toolset, Node snapshot/code-cache off, V8 embedded blob on, `/opt` prefix,
  shared deps를 확인했다. 공개 측정 계약은 `docs/SMHUB.md §5.2`; 상세 raw는 gitignored forensic report.
- **2026-07-21 선례 정밀 판독 + 07-15 표현 정정**: meta-oe `nodejs_20.20.0.bb`를 직접 읽었다.
  same-width(64→64)면 `CC_host=BUILD_CC`(x86 호스트 컴파일러) + `qemu_cmd=""`(래퍼 공백) = **QEMU 0회**,
  different-width(64→32)면 타깃 컴파일러 + QEMU 실행. **우리 §14 D3 초안과 1:1 일치**하고
  Buildroot `HOSTCC/HOSTCXX` = OE `BUILD_CC/BUILD_CXX`로 그대로 옮겨 적을 수 있다.
  ⚠️ **단 같은 레시피가 `COMPATIBLE_HOST:riscv64 = "null"`로 riscv를 배제**한다 — 메커니즘은 다른 arch에서
  출하 검증됐지만 **riscv64로는 미증명**이다. 07-15 RECENT의 "same-width(x86_64→riscv64) 출하 선례" 표현은
  과했고, 배제 사유(미검증 vs 실패)는 미상(로컬 meta-oe는 shallow clone이라 이력 추적 불가).
  → G0은 남의 선례로 대체할 수 없는 실측이다.
- **2026-07-21 벤더 요청 검토 종결**: SMLIGHT에 Node 관련으로 **요청할 것이 없다.** Node은 MIT(GPL 의무 없음),
  그쪽은 Buildroot 정규 recipe = **qemu-user 경로**(우리가 닫은 방법)이며, 베이스도 glibc 2.42 / GCC 15.2 /
  kernel 6.18로 우리(2.33 / 10.2 / 5.10)와 불일치해 recipe·바이너리 모두 이식 불가. 남은 요청 후보는
  `docs/SMHUB.md §6-5` **ESPHome C906L 컴포넌트(GPLv3 근거)** 하나뿐이며 별개 레인이다.
  `YoeDistro/meta-riscv`에도 nodejs 레시피는 없다(커널/BSP 전용).
- **`3c2d836`**: 순수 cross Node service lane을 NEXT/ROADMAP/SMHUB SSOT에 잠금.

# LEDGER / 불변식

- **빌드 정책**: 제품 package는 pure cross. qemu-user/native RISC-V build 금지.
- **두 libc lane**: musl=`homeagentd` minimal baseline, glibc=Node/Z2M service image.
- **Duo S ≠ SMHub**: 우리 linux 5.10/CVITEK IPC 유지. SMHub kernel/BSP/recipe/ipk는 반입하지 않고
  version·ABI·layout·deps·service 계약만 공개 source로 재현한다.
- **SDK 무포크**: pinned·unforked working clone에 defconfig/overlay/patch로 표현. patch nonapply는 fail-closed.
- 실기 flash, commit, push는 GLG 결정. secret/live 좌표는 공개 파일에 기록하지 않는다.
