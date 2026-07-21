# NOW — N0 pure-cross Node: **G0 통과**, 다음은 G1(Buildroot 이식)

- **Stem**: 우리 Milk-V SDK(Buildroot 2025.02, linux 5.10)에서 **Node 22.22.0을 순수 크로스컴파일**해
  `rv64gc/glibc` `.ipk`로 `/opt`에 설치하고, 이후 Mosquitto → Z2M → Zigbee/HA 수직 슬라이스를 닫는다.
- **현재 — G0 PASS (2026-07-21)**: x86-64 호스트 `mksnapshot`이 riscv64 `embedded.S`(6.5MB)를
  **1.08초, qemu·네이티브 RISC-V 실행 0회**로 생성했다. 생성물은 타깃 어셈블러로
  `rv64gc + xthead / lp64d, RVV 없음`으로 검증됐다. §14 **D3의 유일한 잔여 미지수(V8 RISC-V 시뮬레이터
  자동 활성)가 실측으로 닫혔다** — 추정에서 확인으로 승격.
  전체 결과·발견·증거: `captures/n0-g0-20260721T150942+0900/RESULT.md` (gitignored).
- **다음 한 걸음 — G1 (GLG go 필요)**: §14 **D1–D7을 gitignored SDK 워킹클론에 이식**하고
  `milkv-duos-glibc-riscv64-emmc` 보드를 신설해 타깃 Node를 빌드한다. 아래 "N0 통합 순서" 참조.
- **정지 조건**: G1은 host gate(ELF/ABI 검증)까지만. 실기 flash·deploy는 별도 승인.
- **Blocker**: none — G1 착수는 GLG go 대기.
- **Read**: `captures/n0-g0-20260721T150942+0900/RESULT.md`(G0 결과+발견),
  `captures/smhub-beta5-20260630/extracted/node-build-forensics.md` **§12–§16**(패치 초안 D1–D7).
- **Do not touch**: `bsp/patches/`는 D1–D7 적용 전까지 무접촉. SMHub 실기 접속 금지.

## G0에서 확정된 것 (G1이 물려받는 계약)

1. **제너레이터는 make, ninja 아님.** `want_separate_host_toolset=1`이면 `v8.gyp`의 `v8_inspector_headers`가
   `toolsets:['host','target']`인데 출력이 toolset 공용 `gen/`이라 **같은 stamp를 두 번 선언** → ninja 하드 에러.
   make는 용인. Buildroot `nodejs-src.mk`·meta-oe 둘 다 make라 영향 없음. **§16의 ninja 전제는 폐기.**
2. **타깃 toolset mksnapshot은 생성조차 되지 않는다** (`mksnapshot.host.mk`만 존재). snapshot action은
   래퍼 없이 host 바이너리를 직접 호출한다 → **qemu가 낄 자리가 구조적으로 없다.**
3. 실측 configure 면: `--dest-cpu=riscv64 --dest-os=linux --cross-compiling --with-intl=none
   --without-npm --without-corepack --without-inspector`, `CC/CXX`=SDK riscv64 gcc 10.2,
   `CC_host/CXX_host/AR_host`=x86_64. 호스트 컴파일러는 clang 21로도 error 0.
4. host mksnapshot 빌드 실측 **26m55s / 16코어**. G1 full 타깃 빌드는 이보다 크다.
5. `--without-inspector`는 G0 최소면 선택이었다. **제품 빌드에서 inspector를 켤지는 G1에서 재판단**한다.

### G1 host gate (합격선 불변)

- `file node` = riscv64 lp64d, interp `/lib/ld-linux-riscv64-lp64d.so.1`.
- `readelf -V node` 최대 **GLIBC ≤ 2.33 / GLIBCXX ≤ 3.4.28** (벤더 2.38/3.4.32는 참조일 뿐).
- `readelf -A` = rv64gc, **RVV 없음**. `v8_Default_embedded_blob_code_` 존재.
- build trace에 `qemu` / RISC-V 실행 / `Exec format error` **0건**.
- provenance 기록: source sha256, toolchain, docker RepoDigest(`:latest` 금지).

### 금지선

- SDK 포크 금지 — pinned 워킹클론에 defconfig/overlay/patch로만 표현. patch nonapply는 fail-closed.
- qemu-user / 네이티브 RISC-V 빌드로의 우회 금지. 막히면 **경계를 기록하고 멈춘다.**
- 실기 flash/deploy, SMHub SSH·설정 변경·opkg mutation 금지.
- host `-latomic`은 실제 `__atomic_*` link 실패 때만 추가한다.

# G1 — N0 통합 순서

1. **보드 변형**: `milkv-duos-glibc-riscv64-emmc` 추가. SDK 보드 목록은 `glibc_arm64_{sd,emmc}` +
   `musl_riscv64_{sd,emmc}`뿐이라 **glibc×riscv64 조합은 존재하지 않는다 — N0이 신설**한다.
   기존 musl sd/emmc는 `homeagentd` baseline으로 보존.
2. **Buildroot base**: pinned SDK/Buildroot 2025.02 유지. 전체 2026.02 업그레이드 금지.
   2026.02 Node package의 22.22.0 source/hash/patch delta만 비교해 최소 backport한다.
3. **RISC-V pure-cross recipe**: `BR2_RISCV_64` allowlist + `NODEJS_SRC_CPU=riscv64` +
   riscv64에서 `CC_host/HOSTCC` 분리 + QEMU wrapper/dependency 비활성. 다른 arch 동작은 보존.
   **D3는 G0에서 실측 검증됨** — Buildroot `HOSTCC/HOSTCXX/HOSTAR` = OE `BUILD_CC/BUILD_CXX/BUILD_AR`를
   `CC_host/CXX_host/AR_host`로 넘기면 된다(meta-oe `nodejs_20.20.0.bb` same-width 분기와 동형).
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

- **2026-07-21 G0 PASS**: x86-64 host `mksnapshot`(+torque, bytecode_builtins_list_generator)이 전부 x86-64 ELF로
  빌드되고, 1.08초 만에 riscv64 `embedded.S` 6,522,652B + `snapshot.cc` 1,030,517B를 생성했다. 로그의
  qemu / `Exec format error` / RISC-V 실행 = **0건**. 생성물은 SDK 어셈블러로
  `rv64i2p0_m2p0_a2p0_f2p0_d2p0_c2p0_xtheadc2p0` (rv64gc+xthead, lp64d, RVV 없음)으로 확증.
  증거 `captures/n0-g0-20260721T150942+0900/`. **pure-cross Node는 이제 가설이 아니라 실측이다.**
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
