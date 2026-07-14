#!/usr/bin/env bash
# bsp/flash-emmc.sh — flash a built eMMC image to a Milk-V Duo S over USB recovery.
#
# The Duo S eMMC ships blank: with no bootable storage the boot ROM falls through to USB
# download mode and enumerates as 3346:1000 "CVITEK USB Com Port". That is the state we
# flash from — no button press needed on a blank board. (If the board already boots, hold
# the recovery button while plugging the Type-C in.)
#
# The upstream docs only describe a Windows tool, but the SDK ships a Linux usb_dl. It is a
# glibc x86_64 binary, so on NixOS it cannot run on the host — we run it in the same vendor
# container the build uses, with /dev/bus/usb passed through.
#
# Usage:
#   ./bsp/flash-emmc.sh                    # newest riscv64 eMMC image in <sdk>/out/
#   ./bsp/flash-emmc.sh path/to/image.zip
#
# ⚠️ Connect the board's Type-C DIRECTLY to the host. Behind a USB hub or dock the ROM's
#    download device fails to enumerate ("device descriptor read/64, error -110").
# ⚠️ The image ISA must match the board's RISC-V/ARM switch or nothing boots afterwards.
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
SDK_DIR="${HOMEAGENT_BSP_SDK:-$REPO_DIR/bsp/sdk}"
DOCKER_IMAGE="${HOMEAGENT_BSP_IMAGE:-milkvtech/milkv-duo:latest}"
# usb_dl wants the bare family ("181x"), not the SDK's "cv181x" — the vendor doc's
# `-c cv181x` is wrong and the tool rejects it: "choose chip among 180x, 181x, 182x, 183x".
CHIP="${HOMEAGENT_BSP_CHIP:-181x}"

if [ -n "${1:-}" ]; then
  IMG="$1"
else
  IMG=$(ls -t "$SDK_DIR"/out/milkv-duos-musl-riscv64-emmc_*.zip 2>/dev/null | head -1 || true)
  [ -n "$IMG" ] || { echo "Error: no riscv64 eMMC image in $SDK_DIR/out — build one first:" >&2
                     echo "  ./bsp/build.sh milkv-duos-musl-riscv64-emmc" >&2; exit 1; }
fi
[ -f "$IMG" ] || { echo "Error: image not found: $IMG" >&2; exit 1; }

# ISA guard. Historical arm64 images live in the same out/ dir; flashing one onto a board
# whose switch is set to RISC-V (our lane) yields a silent brick-looking no-boot. Refuse.
case "$(basename "$IMG")" in
  *musl-riscv64*) ;;
  *) echo "Error: '$(basename "$IMG")' is not a riscv64 image." >&2
     echo "       Our lane is RISC-V (the board switch must agree). Override deliberately:" >&2
     echo "       HOMEAGENT_ALLOW_NON_RISCV=1 $0 $IMG" >&2
     [ "${HOMEAGENT_ALLOW_NON_RISCV:-0}" = 1 ] || exit 1 ;;
esac

# The ROM's download device is a CDC-ACM class device, so the kernel's cdc_acm driver claims
# it on sight (you see /dev/ttyACM0 appear) and libusb can then no longer claim the interface
# — usb_dl finds the device and dies with an empty "[ERR]". This is the same reason the vendor
# makes Windows users install a dedicated CviUsbDownload driver instead of the COM one.
# Drop cdc_acm for the duration; nothing else here needs it (a CP210x serial cable uses cp210x).
if lsmod 2>/dev/null | grep -q "^cdc_acm"; then
  echo "[flash] cdc_acm is loaded and will steal the ROM's download interface — removing it."
  sudo modprobe -r cdc_acm || {
    echo "Error: could not remove cdc_acm. Free it (close anything on /dev/ttyACM*) and retry." >&2
    exit 1; }
fi

USBDL_DIR="$SDK_DIR/build/tools/common/usb_dl/Linux"
[ -x "$USBDL_DIR/usb_dl" ] || chmod +x "$USBDL_DIR/usb_dl" 2>/dev/null || true
[ -f "$USBDL_DIR/usb_dl" ] || { echo "Error: usb_dl not found at $USBDL_DIR" >&2; exit 1; }

# Stage the layout usb_dl expects: usb_dl + cv_dl_magic.bin next to a rom/ dir of firmware.
WORK="$SDK_DIR/out/.flash-work"
rm -rf "$WORK"; mkdir -p "$WORK/rom"
cp "$USBDL_DIR/usb_dl" "$USBDL_DIR/cv_dl_magic.bin" "$WORK/"
chmod +x "$WORK/usb_dl"
unzip -q -o "$IMG" -d "$WORK/rom"

echo "[flash] image : $IMG"
echo "[flash] chip  : $CHIP"
echo "[flash] files : $(find "$WORK/rom" -maxdepth 1 -type f | wc -l) in rom/"
echo "[flash] Waiting for the board in USB download mode (3346:1000)."
echo "[flash] If it never appears: Type-C must be DIRECT to the host, not through a hub/dock."

# Root in-container: the host /dev/bus/usb nodes are root-owned. usb_dl only reads our stage.
exec docker run --rm --privileged \
  -v /dev/bus/usb:/dev/bus/usb \
  -v "$WORK":/work \
  "$DOCKER_IMAGE" \
  /bin/bash -ec "cd /work && ./usb_dl -s linux -c '$CHIP' -i ./rom"
