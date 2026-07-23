#!/usr/bin/env bash
# bsp/flash-emmc.sh — flash a built eMMC image to a Milk-V Duo S over USB recovery.
#
# ==============================================================================
# PROCEDURE — read this before flashing; every line is something that cost us time
# ==============================================================================
#
# 0. THERE IS NO FUSING. The Duo S picks its boot core with a PHYSICAL SLIDE SWITCH
#    on the board, silkscreened ARM / RV. It is not an eFuse, nothing is burned, and
#    it flips back as often as you like. Set it to match the image ISA BEFORE flashing.
#    (Milk-V's docs mention "fuse" only in TPU model compilation — unrelated.)
#
# 1. Set the switch. arm64 image -> ARM. riscv64 image -> RV.
#    Mismatch = no boot at all, which is indistinguishable from a brick.
#
# 2. Get the board into USB download mode. It enumerates as 3346:1000
#    "CVITEK USB Com Port". Either of these puts it there:
#      - blank eMMC (ships that way), or
#      - eMMC holding the OTHER ISA — it cannot boot, so the ROM falls through, or
#      - a bootable board with the recovery button held while plugging in.
#
# 3. START THIS SCRIPT FIRST, THEN REPLUG THE TYPE-C. This ordering is the whole game.
#    Measured 2026-07-23: the ROM enumerates exactly ONCE per replug, disconnects ~1s
#    later, and then stays silent. The upstream docs claim it re-enumerates on a timeout
#    loop with the device number climbing; it does not. usb_dl waits ~90s and will simply
#    time out with "usb device not found" if the one window already closed.
#
# 4. Type-C DIRECT to the host. Behind a hub or dock the ROM's download device fails to
#    enumerate ("device descriptor read/64, error -110", observed).
#
# 5. cdc_acm will steal the interface if you let it — see the long note further down.
#    This script disables USB driver autoprobe for the duration and restores it on exit.
#    Symptom if it gets loose: "[INFO] found usb device vid=0x3346 pid=0x1000" -> "[ERR]".
#
# 6. Success looks like "[INFO] USB download complete" after ~800 MB of
#    "updated size: N/809230635". The board then reboots by itself and comes back as
#    3346:100c "Cvitek NCM" (100c = running system; 1000 = still in download mode).
#
# 7. Verify — do not trust the flash alone:
#      lsusb | grep 3346:100c
#      ssh root@192.168.42.1        # password: milkv, over the USB network gadget
#      uname -m                     # aarch64 | riscv64
#      cat /etc/issue               # "Welcome to Milk-V DuoS ARM64 eMMC"
#    Ground truth is the debug UART (115200) first line — see the ISA table below.
#    Wired Ethernet also comes up via DHCP if a cable is in (eth0).
#
# 8. Rollback is always available: both lanes' zips live in <sdk>/out/. Flip the switch,
#    rerun this script with the other lane. Nothing about the switch is one-way.
#
# ==============================================================================
#
# The upstream docs only describe a Windows tool, but the SDK ships a Linux usb_dl. It is a
# glibc x86_64 binary, so on NixOS it cannot run on the host — we run it in the same vendor
# container the build uses, with /dev/bus/usb passed through.
#
# Both ISA lanes are supported. SG2000 carries an A53 and a C906 on one die and a physical
# slide switch picks which one boots, so an eMMC image is only ever valid for one switch
# position — the other yields a silent brick-looking no-boot. This script cannot read the
# switch, so it makes the contract explicit instead: it resolves the image's ISA from its
# name and prints the switch position and boot signature that image requires.
#
#   arm64   — dev lane (2026-07-23~): glibc, Buildroot-upstream Node.js support
#   riscv64 — product lane: SDK-native musl, C906
#
# Usage:
#   ./bsp/flash-emmc.sh                    # newest image of the default lane ($HOMEAGENT_BSP_LANE)
#   ./bsp/flash-emmc.sh arm64              # newest arm64 eMMC image in <sdk>/out/
#   ./bsp/flash-emmc.sh riscv64            # newest riscv64 eMMC image in <sdk>/out/
#   ./bsp/flash-emmc.sh path/to/image.zip  # explicit image
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
# Default lane. arm64 is the active development lane; flip this (or export the env var)
# when the product riscv64 lane comes back.
LANE="${HOMEAGENT_BSP_LANE:-arm64}"

# Board name fragment per lane, matching the SDK's target names.
lane_glob() {
  case "$1" in
    arm64)   echo "milkv-duos-glibc-arm64-emmc" ;;
    riscv64) echo "milkv-duos-musl-riscv64-emmc" ;;
    *) return 1 ;;
  esac
}

case "${1:-}" in
  arm64|riscv64) LANE="$1"; IMG="" ;;
  "")            IMG="" ;;
  *)             IMG="$1" ;;
esac

if [ -z "$IMG" ]; then
  GLOB=$(lane_glob "$LANE") || { echo "Error: unknown lane '$LANE' (want arm64 or riscv64)." >&2; exit 1; }
  IMG=$(ls -t "$SDK_DIR"/out/"$GLOB"_*.zip 2>/dev/null | head -1 || true)
  [ -n "$IMG" ] || { echo "Error: no $LANE eMMC image in $SDK_DIR/out — build one first:" >&2
                     echo "  ./bsp/build.sh $GLOB" >&2; exit 1; }
fi
[ -f "$IMG" ] || { echo "Error: image not found: $IMG" >&2; exit 1; }

# Resolve the image's ISA from its name. An image we cannot classify is refused outright:
# guessing here is exactly the mistake that looks like a bricked board.
case "$(basename "$IMG")" in
  *musl-riscv64*) IMG_ISA=riscv64; SWITCH=RV;  SIG='C.SCS/0/0.C.SCS/0/0.WD.URPL.USBI.USBW' ;;
  *glibc-arm64*)  IMG_ISA=arm64;   SWITCH=ARM; SIG='B.SCS/0/0.WD.URPL.B.SCS/0/0.WD.URPL.USBI.USBW' ;;
  *) echo "Error: cannot determine the ISA of '$(basename "$IMG")'." >&2
     echo "       Expected a name containing 'musl-riscv64' or 'glibc-arm64'." >&2
     exit 1 ;;
esac

# Only reachable when an explicit image path was given (a lane argument sets LANE itself).
if [ "$IMG_ISA" != "$LANE" ]; then
  echo "[flash] note: image ISA is $IMG_ISA but the default lane is $LANE — going with the image."
fi

# Everything below this line touches the host or the board (removes cdc_acm, restages
# out/.flash-work, runs usb_dl). HOMEAGENT_BSP_DRYRUN=1 stops here so the resolved image and
# the ISA contract can be checked without side effects.
if [ "${HOMEAGENT_BSP_DRYRUN:-0}" = 1 ]; then
  echo "[flash] image : $IMG"
  echo "[flash] ISA   : $IMG_ISA  (board switch must be: $SWITCH)"
  echo "[flash] chip  : $CHIP"
  echo "[flash] boot signature to expect: $SIG"
  echo "[flash] DRY RUN — nothing removed, staged, or flashed."
  exit 0
fi

# --- cdc_acm must not touch the ROM's download interface ------------------------------
# The ROM's download device is a CDC-ACM class device, so the kernel's cdc_acm driver claims
# it on sight and libusb can then no longer claim the interface — usb_dl prints
# "[INFO] found usb device vid=0x3346 pid=0x1000" and then dies with an empty "[ERR]".
# This is the same reason the vendor makes Windows users install a dedicated
# CviUsbDownload driver instead of the COM one.
#
# Measured 2026-07-23: cdc_acm binds 186 ms after enumeration (423106.160 enumerate →
# 423106.346 "cdc_acm 1-2:1.0: ttyACM0"). Two things that do NOT work:
#   - `modprobe -r cdc_acm` alone: the kernel autoloads it again on the next enumeration.
#   - an `install cdc_acm /bin/true` drop-in in /run/modprobe.d: udev loaded it anyway.
# What works is turning off USB driver autoprobe for the duration, so the kernel binds
# no interface driver at all and libusb gets a free interface.
AUTOPROBE=/sys/bus/usb/drivers_autoprobe
AUTOPROBE_SAVED=""
restore_autoprobe() {
  [ -n "$AUTOPROBE_SAVED" ] || return 0
  echo "$AUTOPROBE_SAVED" | sudo tee "$AUTOPROBE" >/dev/null 2>&1 || true
  AUTOPROBE_SAVED=""
}
# Restore on every exit path. This is why the docker run below is NOT exec'd — exec would
# replace this shell and the trap would never fire, leaving the host unable to bind drivers
# to newly plugged USB devices.
trap restore_autoprobe EXIT INT TERM

if [ -w "$AUTOPROBE" ] || sudo -n true 2>/dev/null; then
  AUTOPROBE_SAVED=$(cat "$AUTOPROBE")
  echo 0 | sudo tee "$AUTOPROBE" >/dev/null
  echo "[flash] USB driver autoprobe disabled for the flash (restored on exit)."
else
  echo "Warning: cannot write $AUTOPROBE — cdc_acm may steal the interface and usb_dl will [ERR]." >&2
fi

# Unbind any interface cdc_acm already holds, then drop the module. With autoprobe off it
# will not come back until we restore it.
for d in /sys/bus/usb/drivers/cdc_acm/*:*; do
  [ -e "$d" ] || continue
  basename "$d" | sudo tee /sys/bus/usb/drivers/cdc_acm/unbind >/dev/null 2>&1 || true
done
if lsmod 2>/dev/null | grep -q "^cdc_acm"; then
  echo "[flash] removing cdc_acm so it cannot claim the ROM's download interface."
  sudo modprobe -r cdc_acm 2>/dev/null || \
    echo "Warning: cdc_acm still loaded (in use?). Close anything on /dev/ttyACM* if usb_dl [ERR]s." >&2
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
echo "[flash] ISA   : $IMG_ISA"
echo "[flash] chip  : $CHIP"
echo "[flash] files : $(find "$WORK/rom" -maxdepth 1 -type f | wc -l) in rom/"
echo
echo "  ┌─ ISA contract ─────────────────────────────────────────────────────────────"
echo "  │ Board slide switch MUST be set to: $SWITCH"
echo "  │ After flashing, the debug UART (115200) first line must read:"
echo "  │   $SIG"
echo "  │ A mismatch between image and switch looks exactly like a bricked board."
echo "  └────────────────────────────────────────────────────────────────────────────"
echo
echo "  ┌─ REPLUG THE TYPE-C NOW ────────────────────────────────────────────────────"
echo "  │ The ROM enumerates ONCE per replug and goes quiet ~1s later — usb_dl has to"
echo "  │ be waiting BEFORE you replug, which is what it is doing from here on."
echo "  │ Keep the cable DIRECT to the host; a hub/dock gives 'descriptor read, -110'."
echo "  └────────────────────────────────────────────────────────────────────────────"
echo

# usb_dl gives up after ~90s. The ROM only offers one ~1s window per replug, so retry a few
# times to give the operator room to pull and reinsert the cable.
ATTEMPTS="${HOMEAGENT_BSP_ATTEMPTS:-6}"
rc=1
for n in $(seq 1 "$ATTEMPTS"); do
  echo "[flash] usb_dl attempt $n/$ATTEMPTS — replug now if you have not yet."
  # Root in-container: host /dev/bus/usb nodes are root-owned. usb_dl only reads our stage.
  # NOT exec'd: the EXIT trap above has to run to restore USB autoprobe.
  out=$(docker run --rm --privileged \
    -v /dev/bus/usb:/dev/bus/usb \
    -v "$WORK":/work \
    "$DOCKER_IMAGE" \
    /bin/bash -ec "cd /work && ./usb_dl -s linux -c '$CHIP' -i ./rom" 2>&1) || true
  printf '%s\n' "$out" | tr '\r' '\n' | grep -vE "Waiting for USB device connection" | tail -20
  if printf '%s' "$out" | grep -q "USB download complete"; then rc=0; break; fi
  if printf '%s' "$out" | grep -q "\[ERR\]"; then
    echo "[flash] usb_dl hit [ERR] — something claimed the interface before libusb could."
  fi
done

# Restore autoprobe immediately: the board reboots right after the download and its USB
# network gadget (3346:100c NCM) enumerates within seconds. If autoprobe is still off then,
# the device appears with no interfaces and no netdev, and only another replug fixes it.
restore_autoprobe

if [ "$rc" = 0 ]; then
  echo
  echo "[flash] USB download complete. The board reboots on its own."
  echo "[flash] Verify: lsusb | grep 3346:100c   (100c = running system, 1000 = download mode)"
  echo "[flash] Then:   ssh root@192.168.42.1    (password: milkv)  ->  uname -m"
  echo "[flash] UART 115200 first line must read: $SIG"
else
  echo
  echo "Error: usb_dl never completed after $ATTEMPTS attempts." >&2
  echo "       Replug the Type-C DIRECTLY to the host while this is running, and check that" >&2
  echo "       the slide switch is on $SWITCH." >&2
fi
exit "$rc"
