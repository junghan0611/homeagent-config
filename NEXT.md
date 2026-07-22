# NOW — N0 native-musl Node 22.22.0 → board runtime → Z2M

- **Stem**: Milk-V Duo S의 기존 `riscv64-musl` Buildroot 이미지에 Node 22.22.0을 정규 target package로 bake하고, 실기에서 직접 실행한 뒤 Z2M으로 간다. glibc loader·wrapper·`/opt` 우회는 제품 경로가 아니다.
- **SDK**: `~/repos/3rd/milkv/duo-buildroot-sdk-v2`, branch `feat/riscv64-nodejs-pure-cross`, pin `087547cf8`, remote `junghan0611/duo-buildroot-sdk-v2`. 현재 clean. 전 `develop` 작업트리 변이는 `stash@{0}` (`pre-fork-build-mutations-20260722T122809`)에 보존했으나 제품 빌드에 적용하지 않는다.
- **Preflight PASS (2026-07-22 12:31)**: resolved config = native musl + `NODEJS=y` + `ICU=y` + existing `OPENSSL=y`; configure opts include `--with-intl=system-icu --without-npm --without-corepack`; dependencies include `host-icu`; `NODEJS_SRC_CPU=riscv64`; host QEMU not selected. Exact board flags로 링크한 tiny ELF는 stock과 같은 `/lib/ld-musl-riscv64v0p7_xthead.so.1` 및 RVV 0.7/T-Head ISA를 방출했고 해당 loader가 기존 `rootfs.ext2`에 존재한다.
- **다음 한 걸음**: 위 계약을 바꾸지 말고 tmux에서 `HOMEAGENT_BSP_SDK=~/repos/3rd/milkv/duo-buildroot-sdk-v2 G1_CLEAN=1 ./bsp/build-package.sh` **1회** 실행한다. 빌드 중 자동 수정·재시작 금지.
- **빌드 합격선**: `[pkg] DONE`; `GLIBC_*` 0건; `GLIBCXX <= 3.4.28`; Node ABI 127; V8 embedded blob 존재(`readelf -sW`); stock C906/RVV 0.7 ISA·musl interpreter; target npm/corepack 부재; ICU 연결; QEMU·native target 실행 0.
- **통과 후**: 같은 Buildroot output tree를 재사용해 전체 eMMC 이미지를 합성한다(V8 재빌드 금지) → GLG flash go → `node -p 'process.arch+":"+process.versions.node'` → JS/fs/DNS/TLS → Z2M 2.10.1 + `@serialport/bindings-cpp`.
- **정지 조건**: 첫 실제 실패에서 멈추고 원인·최소 변경을 보고한다. 자동 수정·재실행 금지. SDK pin/Node·V8 시맨틱/ABI gate/ISA를 임의 완화하지 않는다. commit/push/flash는 GLG 결정.
- **Read**: `docs/BUILDROOT.md` “Node.js pure cross-compile” + “Native-musl product contract”; `captures/n0-musl-gap-20260722T115500+0900/{GAP,COMPARISON}.md`; `captures/n0-g0-*`, `captures/n0-g1-*`; GitHub issue #6.

# RECENT

- **2026-07-22 방향 확정**: SMHub는 Node/Z2M 버전과 제품 surface의 관측 기준이지 libc·배포판 정답이 아니다. Buildroot 정공법을 채택했다: Node/ICU/후속 Z2M을 기존 musl rootfs의 `/usr`에 bake하고 BusyBox init·전체 이미지 검증을 유지한다. npm/Corepack, `/opt`, RUNPATH, opkg/OpenRC는 N1 이후 독립 앱 업데이트가 필요할 때 재판정한다.
- **2026-07-21 pure-cross 메커니즘 PASS**: x86 host `mksnapshot`이 RISC-V embedded blob을 만들고 전체 Node 22.22.0 glibc target build가 완료됐다. QEMU·target 실행 0. 이 산출물은 제품 바이너리가 아니라 libc-neutral 빌드 메커니즘 증거다.
- **SDK fork 관리 시작**: common Buildroot 변경(Node 22.22.0, libuv 1.51, riscv64 host-tool 분리, host deps, no-QEMU)을 `junghan0611/duo-buildroot-sdk-v2@087547cf8`에 커밋했다. 제품 defconfig와 이미지 정책은 이 repo가 소유한다.

# LEDGER

- 제품 ISA/libc: RISC-V C906 + SDK-native musl. stock rootfs는 draft RVV 0.7/T-Head ELF와 해당 loader를 이미 포함한다.
- Buildroot 이미지가 기준 산출물이다. SMHub식 `.ipk`/OpenRC/별도 `/opt` 지속면은 상용 배포 모델 참고이며 N0 blocker가 아니다.
- glibc G0/G1/RevA와 B-probe 설계는 `captures/` 역사 증거로만 보존한다.
