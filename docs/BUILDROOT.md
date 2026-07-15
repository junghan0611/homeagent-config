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
