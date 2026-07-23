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

## ISA: two lanes, one switch

SG2000 carries an ARM Cortex-A53 **and** a RISC-V C906 on one die and boots one or the other.
We build **both** lanes:

- **arm64 / glibc — development lane** (2026-07-23~). `BR2_aarch64` is a first-class
  architecture for Buildroot's `nodejs` package, so the Node/Z2M stack stands up here without
  a downstream toolchain fork. This is where we move fast right now.
- **riscv64 / musl — product lane.** Still the product ISA and the open-ISA thesis. Parked
  while the Node 22 support question sits with upstream (`duo-buildroot-sdk-v2#74`).

Everything above Node — Z2M, image synthesis, flashing, the A2A/A2UI surface — is
ISA-neutral, so returning to RISC-V changes the toolchain and the Node build path, not the
product.

The core is selected by a **physical slide switch** on the board, silkscreened `ARM` and `RV`.
It is a switch, **not an eFuse** — it flips back as many times as you like, nothing is burned
permanently. The image and the switch must agree or nothing boots, and a mismatch looks
exactly like a bricked board. Ground truth is the **first line of the boot log** on the debug
UART (115200):

```text
ARM     B.SCS/0/0.WD.URPL.B.SCS/0/0.WD.URPL.USBI.USBW
RISC-V  C.SCS/0/0.C.SCS/0/0.WD.URPL.USBI.USBW
```

The build log carries the same fact earlier — grep it for `BOOT_CPU=aarch64` or
`BOOT_CPU=riscv` to confirm the lane took before you flash anything.

| Board | ISA / libc | Storage | Flash path |
|-------|-----------|---------|------------|
| `milkv-duos-glibc-arm64-emmc` | arm64 / glibc | eMMC | `usb_dl` in USB recovery mode (see below) — **current dev lane** |
| `milkv-duos-glibc-arm64-sd` | arm64 / glibc | microSD | `dd` the `.img` — eMMC untouched (SD-vs-eMMC boot priority unverified) |
| `milkv-duos-musl-riscv64-sd` | riscv64 / musl | microSD | `dd` the `.img` — reversible, eMMC untouched |
| `milkv-duos-musl-riscv64-emmc` | riscv64 / musl | eMMC | `usb_dl` in USB recovery mode — product lane, parked |

## Use

```bash
./bsp/setup.sh                                   # clone + pin SDK into bsp/sdk/
./bsp/build.sh milkv-duos-glibc-arm64-emmc       # ARM, eMMC       (current dev lane)
./bsp/build.sh milkv-duos-musl-riscv64-sd        # RISC-V, microSD (script default)
./bsp/build.sh milkv-duos-musl-riscv64-emmc      # RISC-V, eMMC
```

Point at an existing local clone (skip re-cloning 5.6G):

```bash
HOMEAGENT_BSP_SDK=~/repos/3rd/milkv/duo-buildroot-sdk-v2 ./bsp/build.sh milkv-duos-glibc-arm64-emmc
```

The build runs in the vendor Docker image (`milkvtech/milkv-duo:latest`), so no nix env is
needed. Output lands in `<sdk>/out/` — SD boards produce a dd-able `.img`, eMMC boards an
`upgrade.zip` for `usb_dl`. Confirm the lane took by grepping the log for `BOOT_CPU=`.

Buildroot does **not** rebuild on a defconfig change. When switching lanes or picking up a
board-config change, delete that board's output tree first — a month-stale tree is how the
riscv lane lost a `host-python3` with `_bz2`/`_ssl`/`_hashlib` missing:

```bash
rm -rf <sdk>/buildroot/output/<board> <sdk>/install/soc_sg2000_<board_underscored>
```

## Flashing eMMC from Linux

```bash
export HOMEAGENT_BSP_SDK=~/repos/3rd/milkv/duo-buildroot-sdk-v2

HOMEAGENT_BSP_DRYRUN=1 ./bsp/flash-emmc.sh   # resolve image + print ISA contract, touch nothing
./bsp/flash-emmc.sh                          # default lane (HOMEAGENT_BSP_LANE, currently arm64)
./bsp/flash-emmc.sh arm64                    # newest arm64 eMMC image
./bsp/flash-emmc.sh riscv64                  # newest riscv64 eMMC image
./bsp/flash-emmc.sh path/to/image.zip        # explicit image
```

Both ISA lanes are supported. The script resolves the image's ISA from its filename, refuses
anything it cannot classify, and prints the switch position and boot signature that image
requires — it cannot read the switch, so it makes the contract explicit instead. Always
dry-run first; it is the cheapest way to catch a wrong lane before the board is written.

The Duo S eMMC ships **blank**. With no bootable storage the boot ROM falls through to **USB
download mode** and enumerates as `3346:1000 CVITEK USB Com Port` — that is the state you
flash from, no button press needed. A board whose eMMC holds the *other* ISA lands in the same
state for the same reason: it cannot boot, so it falls through.

**Start the script first, then replug the Type-C.** The upstream docs say the ROM
re-enumerates on a timeout loop with the device number climbing. Measured 2026-07-23, it does
not: it enumerates **once per replug**, disconnects about a second later, and then stays
silent. `usb_dl` waits ~90s and times out with `usb device not found` if that single window
already closed — which is exactly what happens if you replug before starting the script.
(If the board boots normally, hold the **recovery button** while plugging in.)

**`cdc_acm` will steal the download interface.** It binds ~186 ms after enumeration and then
libusb cannot claim the interface, so `usb_dl` prints `found usb device vid=0x3346 pid=0x1000`
followed by a bare `[ERR]`. Neither `modprobe -r cdc_acm` (the kernel autoloads it on the next
enumeration) nor an `install cdc_acm /bin/true` drop-in in `/run/modprobe.d` (udev loaded it
anyway) is enough. What works is disabling USB driver autoprobe for the duration:

```bash
echo 0 | sudo tee /sys/bus/usb/drivers_autoprobe   # ... flash ...
echo 1 | sudo tee /sys/bus/usb/drivers_autoprobe
```

`flash-emmc.sh` does this and restores it from an `EXIT` trap. **Restoring promptly matters**:
the board reboots immediately after the download and its NCM gadget enumerates within seconds,
so if autoprobe is still off at that moment the device appears with no interfaces and no
netdev, and only another replug fixes it.

The upstream docs only document a Windows tool, but the SDK ships a Linux `usb_dl`
(`build/tools/common/usb_dl/Linux/`). It is a glibc x86_64 binary, so on NixOS it cannot run
on the host — `flash-emmc.sh` runs it inside the same vendor container the build uses, with
`/dev/bus/usb` passed through, and stages the `usb_dl` + `cv_dl_magic.bin` + `rom/` layout it
expects.

- **Connect the Type-C directly to the host.** Behind a USB hub or dock the ROM's download
  device fails to enumerate (`device descriptor read/64, error -110`, observed).
- **Rollback is always available.** Both lanes' zips live in `<sdk>/out/`; flip the switch and
  reflash the other one.

Success is `[INFO] USB download complete` after ~800 MB of `updated size: N/809230635`. Then
verify — the flash completing is not proof the image boots:

```bash
lsusb | grep 3346                    # 100c = running system, 1000 = still in download mode
ssh root@192.168.42.1                # password: milkv, over the USB network gadget
uname -m                             # aarch64 | riscv64
cat /etc/issue                       # "Welcome to Milk-V DuoS ARM64 eMMC"
```

Wired Ethernet also comes up over DHCP if a cable is plugged in (`eth0`), so the board is
reachable on the LAN as well as on `192.168.42.1`.

## Pin

`setup.sh` pins `junghan0611/duo-buildroot-sdk-v2` branch
`feat/riscv64-nodejs-pure-cross` @ `087547cf8` (upstream base `ad920f839`). See
[`../runtime/README.md`](../runtime/README.md) for the L0–L4 architecture.
