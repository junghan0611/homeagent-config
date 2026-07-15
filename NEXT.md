# NOW — N0 pure-cross Node: 내일 G0 host-snapshot seam부터

- **Stem**: 우리 Milk-V SDK(Buildroot 2025.02, linux 5.10)에서 **Node 22.22.0을 순수 크로스컴파일**해
  `rv64gc/glibc` `.ipk`로 `/opt`에 설치하고, 이후 Mosquitto → Z2M → Zigbee/HA 수직 슬라이스를 닫는다.
- **현재**: 방향·선례·패치 면은 정리됐고 **아직 컴파일/패치/보드 변경은 0**이다. SMHub ELF 포렌식에서
  Node snapshot은 off지만 V8 embedded blob은 있음을 확인했고, meta-oe의 same-width 해법
  (`CC_host`=x86 host toolchain)으로 QEMU/native-RISC-V 없이 blob을 만들 수 있는 출하 선례를 찾았다.
- **다음 한 걸음 — G0만**: GLG go 후 scratch에서 Node `v22.22.0`을 최소 기능으로 configure하고
  **x86 host `mksnapshot` + `v8_snapshot/embedded.S` action만 targeted build**한다. full Node/SDK 통합은 하지 않는다.
- **정지 조건**: G0 pass/fail과 정확한 로그를 남긴 즉시 멈춘다. G1으로 자동 진입하지 않는다.
- **Blocker**: 오늘은 종료. 내일 GLG의 G0 실행 go.

## 내일 3분 부트 순서

1. 읽기:
   - `captures/smhub-beta5-20260630/extracted/node-build-forensics.md` **§7–§16** (gitignored 포렌식/실험안)
   - `yocto/sources/meta-openembedded/meta-oe/recipes-devtools/nodejs/` (과거 Yocto에서 쓴 local meta-oe 선례)
   - SDK `buildroot/package/nodejs/{Config.in,nodejs.mk,nodejs-src/}`
2. source: `node-v22.22.0.tar.xz`, SHA256
   `4c138012bb5352f49822a8f3e6d1db71e00639d0c36d5b6756f91e4c6f30b683` 검증 후 gitignored scratch에 푼다.
3. configure(G0 최소면):
   - target `CC/CXX` = SDK `riscv64-unknown-linux-gnu-*`, `rv64gc/lp64d`
   - host `CC_host/CXX_host/AR_host` = x86_64 host toolchain
   - `--cross-compiling --dest-cpu=riscv64 --dest-os=linux --with-intl=none --without-npm --without-corepack --ninja`
4. Ninja graph에서 실제 target 이름을 찾고 **host tool + V8 snapshot action만** 빌드한다.
5. 로그·ELF·generated `embedded.S`를 gitignored capture에 보존하고 PM 검토로 반환한다.

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

1. **보드 변형**: `milkv-duos-glibc-riscv64-emmc` 추가. 기존 musl sd/emmc는 `homeagentd` baseline으로 보존.
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
- **2026-07-15 pure-cross 선례**: meta-oe의 same-width(x86_64→riscv64) recipe가 host generators를
  `BUILD_CC`로 빌드해 QEMU 없이 실행한다. N0은 깊은 V8 포트가 아니라 Buildroot host/target toolchain 분리 문제로 좁혀졌다.
- **`3c2d836`**: 순수 cross Node service lane을 NEXT/ROADMAP/SMHUB SSOT에 잠금.

# LEDGER / 불변식

- **빌드 정책**: 제품 package는 pure cross. qemu-user/native RISC-V build 금지.
- **두 libc lane**: musl=`homeagentd` minimal baseline, glibc=Node/Z2M service image.
- **Duo S ≠ SMHub**: 우리 linux 5.10/CVITEK IPC 유지. SMHub kernel/BSP/recipe/ipk는 반입하지 않고
  version·ABI·layout·deps·service 계약만 공개 source로 재현한다.
- **SDK 무포크**: pinned·unforked working clone에 defconfig/overlay/patch로 표현. patch nonapply는 fail-closed.
- 실기 flash, commit, push는 GLG 결정. secret/live 좌표는 공개 파일에 기록하지 않는다.
