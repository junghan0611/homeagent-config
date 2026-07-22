# NOW — HOLD: upstream direction before more Node 22 native-musl work

- **Stem**: Milk-V Duo S의 기존 `riscv64-musl` Buildroot 이미지에 Node 22.22.0을 정규 target package로 bake하고, 실기에서 직접 실행한 뒤 Z2M으로 간다. glibc loader·wrapper·`/opt` 우회는 제품 경로가 아니다.
- **HOLD (2026-07-22)**: 추가 probe·패치·G1 재실행을 멈췄다. upstream Milk-V SDK maintainers에게 지원 경로를 먼저 묻는다: [`milkv-duo/duo-buildroot-sdk-v2#74`](https://github.com/milkv-duo/duo-buildroot-sdk-v2/issues/74). 답변 또는 GLG의 새 판정 전에는 실행하지 않는다.
- **SDK baseline / workspace**: `~/repos/3rd/milkv/duo-buildroot-sdk-v2`, branch `feat/riscv64-nodejs-pure-cross`, pin `087547cf8`, remote `junghan0611/duo-buildroot-sdk-v2`. 작업트리에는 매 빌드가 주입하는 `envsetup_milkv.sh`·musl defconfig 변이와 검증된 untracked libuv weak-symbol patch 1개가 있다. commit/stash하지 않는다. 전 `develop` 변이는 `stash@{0}` (`pre-fork-build-mutations-20260722T122809`)에 별도 보존한다.
- **확정 증거**: stale 7/14 `host-python3`를 재빌드해 `_bz2`, `_ssl`, `_hashlib` 3개를 복구했다. libuv 1.51의 `pthread_getname_np`는 SDK musl 1.2.2에 없으며 weak-symbol compatibility patch가 `GLOBAL UND → WEAK UND`로 바꾸고 libuv package gate를 통과했다.
- **현재 blocker**: Node/ICU host generator 링크에 target pkg-config의 `-L<riscv64-musl-sysroot>/usr/lib`가 섞인다. target sysroot의 8-byte musl compatibility archive(`libm.a` 등)가 host library를 가리므로 trailing `-lm`도 실패한다. 단순 `-lm` 패치는 기각했다. host/target library search path 경계가 문제다.
- **유지보수 예산**: Buildroot recipe·defconfig·overlay와 소수의 작고 검증 가능한 compatibility patch까지만 소유한다. Node.js/V8/libc/toolchain downstream fork, 런타임 시맨틱 수선, 늘어나는 patch series는 금지한다. 그 선을 넘으면 upstream에 묻고 baseline을 다시 고른다.
- **검토 중인 최소 경로**: Node package에 한정해 target pkgconf의 `--keep-system-libs`를 쓰지 않고, target compiler wrapper의 기존 `--sysroot`에 맡기는 Buildroot-recipe 해법. Node `configure.py`·V8 GYP 수정은 하지 않는다. 아직 실행·채택하지 않았다.
- **최종 빌드 합격선**: 깨끗한 output에서 `[pkg] DONE`; `GLIBC_*` 0건; `GLIBCXX <= 3.4.28`; Node ABI 127; V8 embedded blob 존재; stock C906/RVV 0.7 ISA·musl interpreter; target npm/corepack 부재; ICU 연결; QEMU·native target 실행 0.
- **통과 후**: 같은 깨끗한 Buildroot output tree를 재사용해 전체 eMMC 이미지를 합성한다(V8 재빌드 금지) → GLG flash go → Node JS/fs/DNS/TLS → Z2M 2.10.1 + `@serialport/bindings-cpp`.
- **정지 조건**: upstream source patch가 libuv compatibility 1개를 넘어가거나 Node/V8/libc/toolchain 시맨틱 변경이 필요하면 중단한다. 자동 수정·연쇄 재실행 금지. commit/push/flash는 GLG 결정.
- **Read**: upstream issue #74; `docs/BUILDROOT.md` “Node.js pure cross-compile” + “Native-musl product contract”; `captures/n0-musl-gap-20260722T115500+0900/{GAP,COMPARISON}.md`; GitHub issue #6.

# RECENT

- **2026-07-22 upstream escalation**: modern Node 22 + no-QEMU pure-cross + SDK musl 1.2.2의 유지보수 가능한 지원 경로를 Milk-V에 질문했다. 답변 전에는 Buildroot recipe와 libuv patch 1개를 넘는 수선을 진행하지 않는다.
- **2026-07-22 방향 확정**: SMHub는 Node/Z2M 버전과 제품 surface의 관측 기준이지 libc·배포판 정답이 아니다. Buildroot 정공법을 채택했다: Node/ICU/후속 Z2M을 기존 musl rootfs의 `/usr`에 bake하고 BusyBox init·전체 이미지 검증을 유지한다. npm/Corepack, `/opt`, RUNPATH, opkg/OpenRC는 N1 이후 독립 앱 업데이트가 필요할 때 재판정한다.
- **2026-07-21 pure-cross 메커니즘 PASS**: x86 host `mksnapshot`이 RISC-V embedded blob을 만들고 전체 Node 22.22.0 glibc target build가 완료됐다. QEMU·target 실행 0. 이 산출물은 제품 바이너리가 아니라 libc-neutral 빌드 메커니즘 증거다.
- **SDK fork 관리 시작**: common Buildroot 변경(Node 22.22.0, libuv 1.51, riscv64 host-tool 분리, host deps, no-QEMU)을 `junghan0611/duo-buildroot-sdk-v2@087547cf8`에 커밋했다. 제품 defconfig와 이미지 정책은 이 repo가 소유한다.

# LEDGER

- 제품 ISA/libc: RISC-V C906 + SDK-native musl. stock rootfs는 draft RVV 0.7/T-Head ELF와 해당 loader를 이미 포함한다.
- Buildroot 이미지가 기준 산출물이다. SMHub식 `.ipk`/OpenRC/별도 `/opt` 지속면은 상용 배포 모델 참고이며 N0 blocker가 아니다.
- glibc G0/G1/RevA와 B-probe 설계는 `captures/` 역사 증거로만 보존한다.
