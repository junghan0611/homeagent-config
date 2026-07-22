# bsp — reproducible SG2000 image build

The core of this repo: build the **full platform image** (bootloader → kernel →
rootfs → freertos) for the SG2000 hub, reproducibly, the same way `yocto/` builds
the RPi5 image. The Zig runtime and applications sit *on top* of this image.

## Model (mirrors `yocto/`)

| Piece | Where | Tracked? |
|-------|-------|----------|
| Build environment (host tools) | `flake.nix` → `packages.buildroot` (FHS) | ✅ committed |
| SDK fork (~5.6G in-tree monorepo) | `bsp/sdk/` cloned by `setup.sh`, pinned to `087547cf8` | ❌ gitignored |
| Our board + Buildroot configs (reproducible SSOT) | `bsp/board/`, `bsp/buildroot/` — `build.sh` injects both | ✅ committed |
| Further customizations (rootfs overlay, patches) | `bsp/board/`, `bsp/patches/` *(as added)* | ✅ committed |

`build.sh` injects our committed outer board config and Buildroot userspace config before
building. Common SDK changes live on `junghan0611/duo-buildroot-sdk-v2` branch
`feat/riscv64-nodejs-pure-cross`; the local patch remains an auditable, fail-closed mirror.
First hub customization: dropped the camera image sensors and MIPI panel (CVITEK vision
middleware is dead weight for a hub).

The fork is based on `milkv-duo/duo-buildroot-sdk-v2` and carries the whole boot chain
(fsbl/opensbi/u-boot/linux_5.10/buildroot/freertos) plus CVITEK libs.
It builds **in-tree** and git-clones a prebuilt toolchain (~840MB) on first build,
so it must be a **writable, pinned working clone** — not vendored, not frozen in nix.

## What this lane is (and is not)

A **fully open, reproducible image for a dev board** — Milk-V Duo S (SG2000). Every layer
(fsbl → opensbi → u-boot → kernel → rootfs → freertos) is built from public sources with a
public SDK, pinned, in a container. No vendor-private repo, no vendor OS.

It is **not** a hub-product image and cannot become one by swapping files: a shipping SG2000
hub like SMHub runs a different OS entirely (mainline ~6.18 kernel, standard
remoteproc/rpmsg + open-amp, RAUC A/B), while this SDK is linux 5.10 with CVITEK's own
`rtos_cmdqu` core-to-core path. Those images are incompatible by construction. Keep the lanes
separate. What actually transfers is the **axis**, not the image: SG2000 SoC, riscv64 ISA,
boot-chain knowledge and cross toolchain. SMHub uses glibc; our image deliberately keeps the
SDK-native musl userspace — a lab where Node/Z2M and `homeagentd`
(`riscv64-linux-musl`) can be built, run and measured on real RISC-V silicon we own.

There is also no MG24 radio on this board, so Zigbee/EZSP work does not happen here.

## ISA: build RISC-V, not ARM

SG2000 can boot **either** an ARM Cortex-A53 core **or** a RISC-V C906 core — same chip,
one or the other. Our runtime targets **riscv64 + musl**, so that is the lane we build. The
`*-glibc-arm64-*` boards exist because the SoC allows it; they are **historical**.

On a Milk-V Duo S the core is selected by a **physical slide switch next to the USB-C jack**,
silkscreened `ARM` on one side and `RV` on the other — slide it to **`RV`**. The image and the
switch must agree or nothing boots. Ground truth is the **first character of the boot log** on
the debug UART (115200): `C` = RISC-V C906, `B` = ARM A53.

| Board | ISA / libc | Storage | Flash path |
|-------|-----------|---------|------------|
| `milkv-duos-musl-riscv64-sd` | riscv64 / musl | microSD | `dd` the `.img` — reversible, eMMC untouched |
| `milkv-duos-musl-riscv64-emmc` | riscv64 / musl | eMMC | `usb_dl` in USB recovery mode (see below) |
| `milkv-duos-glibc-arm64-emmc` | arm64 / glibc | eMMC | historical — **not the product ISA** |

## Use

```bash
./bsp/setup.sh                                   # clone + pin SDK into bsp/sdk/
./bsp/build.sh milkv-duos-musl-riscv64-sd        # RISC-V, microSD   (default)
./bsp/build.sh milkv-duos-musl-riscv64-emmc      # RISC-V, eMMC
```

Point at an existing local clone (skip re-cloning 5.6G):

```bash
HOMEAGENT_BSP_SDK=~/repos/3rd/milkv/duo-buildroot-sdk-v2 ./bsp/build.sh milkv-duos-musl-riscv64-emmc
```

The build runs in the vendor Docker image (`milkvtech/milkv-duo:latest`), so no nix env is
needed. Output lands in `<sdk>/out/` — SD boards produce a dd-able `.img`, eMMC boards an
`upgrade.zip` for `usb_dl`. Confirm the lane took by grepping the log for `BOOT_CPU=riscv`.

## Flashing eMMC from Linux

```bash
HOMEAGENT_BSP_SDK=~/repos/3rd/milkv/duo-buildroot-sdk-v2 ./bsp/flash-emmc.sh
```

The Duo S eMMC ships **blank**. With no bootable storage the boot ROM falls through to **USB
download mode** and enumerates as `3346:1000 CVITEK USB Com Port` — that is the state you
flash from, no button press needed. (If the board already boots, hold the **recovery button**
while plugging the Type-C in.) The ROM re-enumerates on a timeout loop, so the USB device
number keeps climbing while it waits; `usb_dl` blocks until it catches one.

The upstream docs only document a Windows tool, but the SDK ships a Linux `usb_dl`
(`build/tools/common/usb_dl/Linux/`). It is a glibc x86_64 binary, so on NixOS it cannot run
on the host — `flash-emmc.sh` runs it inside the same vendor container the build uses, with
`/dev/bus/usb` passed through, and stages the `usb_dl` + `cv_dl_magic.bin` + `rom/` layout it
expects. It defaults to the newest riscv64 eMMC image in `<sdk>/out/` and **refuses a
non-riscv64 image** (the historical arm64 zips sit in the same dir; flashing one against a
board switched to RISC-V looks exactly like a brick).

- **Connect the Type-C directly to the host.** Behind a USB hub or dock the ROM's download
  device fails to enumerate (`device descriptor read/64, error -110`, observed).

## Pin

`setup.sh` pins `junghan0611/duo-buildroot-sdk-v2` branch
`feat/riscv64-nodejs-pure-cross` @ `087547cf8` (upstream base `ad920f839`). See
[`../runtime/README.md`](../runtime/README.md) for the L0–L4 architecture.
