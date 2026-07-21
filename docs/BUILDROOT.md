# BUILDROOT — SG2000 / Duo S image build (core lane)

> **Why this exists.** Yocto was the original direction (`YOCTO.md`, the RPi5 origin lane).
> But the SG2000 core lane rides Milk-V's **Buildroot**-based SDK — there is no Yocto path for
> this silicon that we own end to end. So Buildroot is no longer optional: it is how we own the
> Duo S image from the bootloader up. This doc is the **experience log + strategy** for that
> lane; the **operational how-to lives in [`../bsp/README.md`](../bsp/README.md)** — don't
> duplicate it here.

## Yocto vs Buildroot — two lanes, two jobs

| | **Yocto** (`YOCTO.md`) | **Buildroot** (this doc + `../bsp/`) |
|---|---|---|
| Lane | high-spec **origin** (RPi5) | SG2000 **core** (Milk-V Duo S) |
| Why | product-grade offline-first, license compliance, npm shrinkwrap | the Milk-V SDK *is* Buildroot; whole boot chain in one tree |
| Base | Yocto Scarthgap / OpenEmbedded | linux 5.10 + CVITEK + Buildroot (SDK v2) |
| Strength | reproducible air-gapped builds, `LIC_FILES_CHKSUM` | one-tree boot chain (fsbl→opensbi→u-boot→kernel→rootfs→freertos) |
| Status | preserved reference | **active** — booted on real silicon 2026-07-14 |

Yocto's discipline (offline-first, checksummed deps) stays the north star for *product*
reproducibility; Buildroot is what actually boots the SG2000 today. They do not merge — they
sit in different lanes.

## The Duo S Buildroot lane — what we own

BSP base = **`milkv-duo/duo-buildroot-sdk-v2`** (pinned `develop @ ad920f839`), a single in-tree
monorepo carrying the whole boot chain + CVITEK libs. Our reproducible SSOT is the **committed
board defconfig**, which `bsp/build.sh` injects over the SDK's stock defconfig at build time so
the upstream clone stays pristine:

- `bsp/board/milkv-duos-musl-riscv64-sd/defconfig` — RISC-V + musl, microSD
- `bsp/board/milkv-duos-musl-riscv64-emmc/defconfig` — RISC-V + musl, eMMC
- `bsp/board/milkv-duos-glibc-arm64-emmc/defconfig` — **historical**, arm64, not the product ISA

**RISC-V + musl, not ARM.** The runtime target is `riscv64-linux-musl`, so we build the C906
RISC-V lane (physical `RV` switch; boot-log first char `C`). The delta from the stock SDK board
config is small and pinned: `CONFIG_ARCH=riscv`, `CROSS_COMPILE=riscv64-unknown-linux-musl-`,
`KERNEL_ENTRY_HACK_ADDR=0x80200000` (ARM was `0x80108000`), `TOOLCHAIN_MUSL_RISCV64`. `musl`
matches the product / SMHub userspace and the `homeagentd` target.

**hub-minimal delta (partial).** A hub has no camera: the defconfig drops the CVITEK image
sensors + MIPI panel (`bsp/patches/0001-hub-minimal-skip-vision-stack.patch`). *Still partial* —
the osdrv kernel modules (`cvi_vc_driver`, `cv181x_{ive,jpeg,vcodec,tpu}`) still build and load;
full vision removal needs the osdrv module list trimmed too.

## First silicon (2026-07-14) — the lane's first success

Our own Buildroot image booted the C906 in RISC-V mode on a Duo S:
`Linux milkv-duo 5.10.4 riscv64`, `isa: rv64imafdvcsu`, `NAME=Buildroot VERSION=-gad920f839-dirty`
(our pin + our defconfig), busybox + `ld-musl-riscv64v0p7_xthead.so.1` (T-Head C906 extensions),
eMMC 7.3G (p4 rootfs 768M), eth0 DHCP + Wi-Fi (aic8800) up. Evidence:
`captures/duos-riscv64-firstboot-*/`.

## Lessons / gotchas (measured)

Operational steps live in `../bsp/README.md`; these are the traps that cost time:

- **`bsp/build.sh` defconfig-injection bug** — `find … | head -1` matched *three* defconfigs
  (board + kernel + u-boot) and could overwrite the kernel defconfig by readdir luck. Fixed:
  exclude `cvitek_*` and fail unless exactly one matches.
- **eMMC ships blank** → the boot ROM falls to **USB download mode** (`3346:1000 CVITEK USB Com
  Port`), no button needed. The Linux `usb_dl` *is* in the SDK (upstream "Windows only" is
  wrong); on NixOS it's a glibc x86_64 binary → run it inside the vendor container with
  `/dev/bus/usb` passthrough (`bsp/flash-emmc.sh`).
- **Two flash traps** — (1) `usb_dl -c` wants `181x`, not the vendor doc's `cv181x`; (2) the
  kernel `cdc_acm` grabs the ROM's download interface → libusb can't claim it → `modprobe -r
  cdc_acm` first. Both are baked into `flash-emmc.sh`.
- **USB hub / dock kills enumeration** (`error -110`) → **connect the Type-C directly to the host.**
- **ISA guard** — `flash-emmc.sh` refuses a non-riscv64 image (the historical arm64 zips share
  `out/`, and flashing one against an `RV`-switched board looks exactly like a brick).

## Node.js pure cross-compile — proven on riscv64 (2026-07-21)

Buildroot's stock `nodejs` package cross-compiles by building a **target** `mksnapshot` and running
it under **qemu-user** (`package/nodejs/nodejs-src/`: `v8-qemu-wrapper`,
`select BR2_PACKAGE_HOST_QEMU_LINUX_USER_MODE`), and its arch allowlist has no riscv at all. Our
build policy forbids that path. The alternative — build the host tools with the **host** toolchain
and drop qemu — is meta-oe's same-width branch (`nodejs_20.20.0.bb`: `HOST_AND_TARGET_SAME_WIDTH=1`
→ `CC_host=BUILD_CC`, empty qemu wrapper), a mechanism that ships for aarch64 but that the same
recipe *disables* for riscv (`COMPATIBLE_HOST:riscv64 = "null"`). It is now measured working:

- **V8 auto-enables its RISC-V simulator when the toolsets differ** —
  `deps/v8/src/common/globals.h`: `V8_TARGET_ARCH_RISCV64 && !V8_HOST_ARCH_RISCV64 → USE_SIMULATOR 1`.
  An x86-64 `mksnapshot` can therefore serialize a riscv64 snapshot without executing any RISC-V code.
- **Measured** (Node `v22.22.0`, target = SDK Xuantie glibc GCC 10.2, host = x86-64): `mksnapshot`,
  `torque`, `bytecode_builtins_list_generator` all build as x86-64 ELF (26m55s at `-j16`); the
  snapshot action emits a 6.5MB riscv64 `embedded.S` in **1.08s**; `qemu` / target execution /
  `Exec format error` = 0. The output assembles as `rv64…c_xtheadc`, lp64d, no RVV.
- **Trap — the ninja generator is unusable here.** With `want_separate_host_toolset=1`,
  `tools/v8_gypfiles/v8.gyp`'s `v8_inspector_headers` (`toolsets: ['host','target']`) writes into the
  toolset-shared `gen/`, so both toolsets declare the same output and ninja hard-errors
  (`multiple rules generate …/js_protocol.stamp`). Use the **GYP make generator** — which is what
  Buildroot and meta-oe use anyway. `--without-inspector` does not help: that is V8's inspector, not
  Node's.
- **No target-toolset `mksnapshot` is generated at all** (`mksnapshot.host.mk` only), and the snapshot
  action invokes the host binary with no wrapper. QEMU has no place in the graph; Buildroot's stock
  recipe uses it by choice, not by necessity.

Evidence bundle: `captures/n0-g0-*/RESULT.md` (gitignored).

## Open items (post-boot)

- **Reclaim ~170MB** — the camera/codec ION carveout (`0x9400000` = 148MB + rtos 22MB) is
  reserved for vision buffers a hub never uses; trim defconfig/DT + drop the remaining `cvi_*`
  modules. `MemTotal` is currently ~323MB of 512MB.
- **Complete hub-minimal** — trim the osdrv vision module list (above), not just sensors/panel.
- **UART console** — `/dev/ttyUSB0` (CP210x) silent; console is `ttyS0,115200`, UART wiring
  unconfirmed.
- **SD lane (optional)** — with a microSD, build `…-riscv64-sd` → `dd` the `.img` (eMMC
  untouched, fast iteration).
- **`homeagentd` on RISC-V** — the real point: put the `riscv64-linux-musl` Zig binary on the
  board and measure the 100ms tick / RSS / watchdog on real silicon (see `../runtime/README.md`).

## Contrast — the SMHub product Buildroot (diff target)

SMHub Nano is the same SG2000, but SMLIGHT ships a **separate, more mainline product Buildroot**
(kernel 6.18 / OpenSBI 1.8 / U-Boot 2026.04 / Buildroot 2025.11, standard remoteproc/rpmsg +
open-amp, RAUC A/B). We **don't rebuild it** — we read and diff it as a system-application
developer (`SMHUB.md`). The two images are **not interchangeable**; the shared axis is
SoC / ISA / musl / toolchain / boot-chain knowledge, not the image.

---

See also: [`../bsp/README.md`](../bsp/README.md) (operational build/flash), [`../runtime/README.md`](../runtime/README.md)
(L0–L4 runtime), [`TARGET_DEVICE.md`](TARGET_DEVICE.md) (board/radio strategy), [`SMHUB.md`](SMHUB.md)
(product diff target), [`YOCTO.md`](YOCTO.md) (origin-lane build).
