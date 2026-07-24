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
#    Run `sudo ./bsp/usb-recovery-prepare.sh` first: it installs the udev rule that stops
#    cdc_acm from ever being loaded for this device, and leaves drivers_autoprobe at 1 so the
#    kernel configures the device inside enumeration. Do NOT "fix" this by disabling
#    autoprobe — that is what caused the 2026-07-24 INVALID_PARAM loop (step 5b).
#    Symptom if cdc_acm gets loose: "[INFO] found usb device vid=0x3346 pid=0x1000" -> "[ERR]".
#
# 5b. FOUR different failures look alike, and they have nothing to do with each other:
#      -110 "device descriptor read/64"  -> the cable is behind a hub/dock (step 4).
#      plain [ERR] after "found usb device" -> cdc_acm got the interface first (step 5).
#      LIBUSB_ERROR_INVALID_PARAM        -> the device is UNCONFIGURED: it enumerated while
#         autoprobe was off, so bConfigurationValue is empty and it has no interfaces for
#         libusb to claim. Check with:
#           cat /sys/bus/usb/devices/*/bConfigurationValue
#         Leave autoprobe at 1 (step 5). Setting the configuration after the fact does not
#         fix it: libusb caches the config descriptor at open() and usb_dl opens first.
#      "config cdc(0x22) failed: TIMEOUT" repeating with NO percentage -> the ROM's state
#         machine is stale from an earlier interrupted attempt. Only a replug resets it.
#         The same TIMEOUT lines *interleaved with a rising percentage* are harmless.
#
#    Also: "set MGN1 flag" / "break" / "Connecting to ROM 2nd stage..." are printed even on
#    attempts where no device was ever found. They are not progress. The percentage is.
#
# 6. Success looks like "[INFO] USB download complete" after ~800 MB of
#    "updated size: N/809258127". Expect ~25 minutes; container CPU near zero is normal
#    (blocked on USB, not dead). DO NOT KILL IT — a flash was killed at 23% on 2026-07-24
#    on exactly that misreading. The board then reboots by itself and comes back as
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
# 423106.346 "cdc_acm 1-2:1.0: ttyACM0"). Three things that do NOT work:
#   - `modprobe -r cdc_acm` alone: the kernel autoloads it again on the next enumeration.
#   - an `install cdc_acm /bin/true` drop-in in /run/modprobe.d: udev loaded it anyway.
#   - turning off /sys/bus/usb/drivers_autoprobe. This does stop cdc_acm, but it trades one
#     failure for another: every device that enumerates while it is off is left UNCONFIGURED
#     (empty bConfigurationValue, zero interfaces), so libusb has nothing to claim and dies
#     with LIBUSB_ERROR_INVALID_PARAM. Setting the configuration afterwards does not rescue
#     it — libusb caches the config descriptor at open() and usb_dl opens within
#     milliseconds. Measured 2026-07-24: a 50 ms poller beat usb_dl once in ten minutes.
#
# What works — and this is the part that took two days to see — is LETTING cdc_acm bind and
# then taking the interface away from it, in that order. cdc_acm's probe performs the CDC
# setup (SET_LINE_CODING 0x20, SET_CONTROL_LINE_STATE 0x22) that opens the ROM's data pipe.
# Block cdc_acm entirely and usb_dl's own versions of those two control transfers time out:
#   [ERR] config cdc(0x22) failed: LIBUSB_ERROR_TIMEOUT(-7)
#   [ERR] config cdc(0x20) failed: LIBUSB_ERROR_TIMEOUT(-7)
# after which EVERY bulk write times out ("only send 524288 byte(-7)") while usb_dl happily
# keeps incrementing "updated size" and finishes with "USB download complete". Measured
# 2026-07-24: a run that reported 100% wrote nothing at all — the eMMC still held the
# filesystem from the previous day, same UUID, same mkfs time. See VERIFY at the end.
#
# So: leave drivers_autoprobe at 1, leave cdc_acm loaded, let it bind on enumeration, and
# unbind it immediately before each usb_dl attempt. Do NOT disable autoprobe and do NOT
# blacklist the module.
AUTOPROBE=/sys/bus/usb/drivers_autoprobe
if [ "$(cat "$AUTOPROBE" 2>/dev/null)" != 1 ]; then
  echo 1 | sudo tee "$AUTOPROBE" >/dev/null 2>&1 || true
  echo "[flash] drivers_autoprobe was off — set to 1 so the kernel configures the device."
fi
# Read /proc/modules, not `lsmod | grep -q`: under `set -o pipefail` grep exits on the first
# match, lsmod dies of SIGPIPE, and the pipeline reports failure even when the module IS
# loaded. That silently skipped this whole block for a morning on 2026-07-24.
if ! grep -q '^cdc_acm ' /proc/modules; then
  sudo modprobe cdc_acm 2>/dev/null || true
  echo "[flash] cdc_acm loaded — it has to bind once to set up the CDC line before we take over."
fi

# Take the interface away from cdc_acm, after it has done the CDC setup. Called once per
# attempt, right before usb_dl, because the board is replugged between attempts and cdc_acm
# binds again on each enumeration.
release_cdc_acm() {
  local found=0
  for d in /sys/bus/usb/drivers/cdc_acm/*:*; do
    [ -e "$d" ] || continue
    local i; i=$(basename "$d")
    case "$i" in
      *:*) ;;
      *) continue ;;
    esac
    # only ours — do not disturb other ACM devices on the machine
    local dev="/sys/bus/usb/devices/${i%%:*}"
    [ "$(cat "$dev/idVendor" 2>/dev/null)" = "3346" ] || continue
    echo "$i" | sudo tee /sys/bus/usb/drivers/cdc_acm/unbind >/dev/null 2>&1 || true
    found=1
  done
  [ "$found" = 1 ] && echo "[flash] cdc_acm released the ROM interface — libusb can claim it now."
  return 0
}

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

# Turning autoprobe off has a second effect that took a while to find. A device that
# enumerates AFTER autoprobe was disabled is left UNCONFIGURED: bConfigurationValue is empty
# and no interfaces exist at all. libusb then has nothing to claim and usb_dl dies with
#   [INFO] Error claiming interface: LIBUSB_ERROR_INVALID_PARAM
#   [ERR] usb_dl: usbi_mutex_lock: Assertion `pthread_mutex_lock(mutex) == 0' failed
# which is a THIRD failure mode, distinct from the hub's -110 and from cdc_acm's plain [ERR].
# Because this script disables autoprobe before asking for the replug, every replug lands in
# exactly that state -- the 2026-07-23 flash succeeded only because the board happened to be
# plugged in (and configured) before the script ran.
#
# The real fix is upstream of this: leave autoprobe ON (see the block above) so the kernel
# configures the device inside enumeration. This function stays as a safety net for the case
# where something else on the machine left autoprobe at 0 -- it cannot win the race on its own
# (libusb caches the descriptor at open), but it costs nothing and it names the state in the
# log when it does fire.
ensure_configured() {
  for d in /sys/bus/usb/devices/*/; do
    [ -f "$d/idVendor" ] || continue
    [ "$(cat "$d/idVendor" 2>/dev/null)" = "3346" ] || continue
    [ "$(cat "$d/idProduct" 2>/dev/null)" = "1000" ] || continue
    [ -n "$(cat "$d/bConfigurationValue" 2>/dev/null)" ] && continue
    echo "[flash] $(basename "$d") enumerated unconfigured — setting configuration 1."
    echo 1 | sudo tee "$d/bConfigurationValue" >/dev/null 2>&1 || true
    sleep 1
  done
}

# usb_dl gives up after ~90s. The ROM only offers one ~1s window per replug, so retry a few
# times to give the operator room to pull and reinsert the cable.
ATTEMPTS="${HOMEAGENT_BSP_ATTEMPTS:-6}"
rc=1
for n in $(seq 1 "$ATTEMPTS"); do
  echo "[flash] usb_dl attempt $n/$ATTEMPTS — replug now if you have not yet."
  ensure_configured
  release_cdc_acm
  # Root in-container: host /dev/bus/usb nodes are root-owned. usb_dl only reads our stage.
  # Stream, do not capture. A full eMMC write takes ~25 min and usb_dl reports
  # "updated size: N/809258127(P%)" as it goes; capturing into a variable hides every
  # line until the attempt ends, so the run looks hung. It is not — the LIBUSB_ERROR_TIMEOUT
  # lines interleaved with the progress are retried and non-fatal, and container CPU sits
  # near zero because the process is blocked on USB, not because it died. A flash was killed
  # at 23% on 2026-07-24 for exactly that misreading. Watch the percentage, nothing else.
  ATTEMPT_LOG="$WORK/usb_dl-$n.log"
  docker run --rm --privileged \
    -v /dev/bus/usb:/dev/bus/usb \
    -v "$WORK":/work \
    "$DOCKER_IMAGE" \
    /bin/bash -ec "cd /work && ./usb_dl -s linux -c '$CHIP' -i ./rom" 2>&1 \
    | tr '\r' '\n' | grep -vE "Waiting for USB device connection" | tee "$ATTEMPT_LOG" || true
  # "USB download complete" is NOT proof of a write. usb_dl increments "updated size" for
  # every chunk it hands to libusb, whether or not the write succeeded, and prints the
  # completion line once the counter reaches the total. On 2026-07-24 a run reported 100%
  # with every single chunk having failed. Count the failures before believing the banner.
  FAILED_CHUNKS=$(grep -c "only send .* byte(-7)" "$ATTEMPT_LOG" 2>/dev/null || echo 0)
  if grep -q "USB download complete" "$ATTEMPT_LOG" 2>/dev/null; then
    if [ "$FAILED_CHUNKS" -gt 4 ]; then
      echo "[flash] usb_dl claims 'USB download complete' but $FAILED_CHUNKS chunks timed out."
      echo "[flash] That is the LYING PROGRESS mode — nothing was written. Retrying."
      echo "[flash] Root cause is almost always that cdc_acm never bound, so the CDC line was"
      echo "[flash] never set up. Look for 'config cdc(0x22) failed' near the start."
      continue
    fi
    rc=0; break
  fi
  if grep -q "\[ERR\]" "$ATTEMPT_LOG" 2>/dev/null; then
    echo "[flash] usb_dl hit [ERR] — see the lines above for which of the four modes it was."
  fi
done

# The board reboots right after the download and comes back as its USB network gadget
# (3346:100c NCM) within seconds. Autoprobe is left at 1 throughout, so that device gets
# configured and cdc_ncm binds it normally -- nothing to restore here.

# Ground truth for "did this actually write": the rootfs ext4 superblock UUID. Read it out of
# the image so the operator can compare it against the board instead of trusting a banner.
IMG_UUID=""
if command -v python3 >/dev/null 2>&1 && [ -f "$WORK/rom/rootfs_ext4.emmc" ]; then
  IMG_UUID=$(python3 - "$WORK/rom/rootfs_ext4.emmc" <<'PY' 2>/dev/null || true
import sys
# The vendor wraps the partition in a 64-byte "CIMG" header, and the ext4 image inside starts
# at a small offset after that, so locate the superblock by its magic instead of assuming.
d = open(sys.argv[1], 'rb').read(1 << 16)
for off in range(0, (1 << 16) - 0x440, 64):   # off = start of the ext4 partition
    if d[off + 0x438:off + 0x43a] == b'\x53\xef':
        sb = off + 1024               # the superblock sits 1024 bytes into the partition
        u = d[sb + 0x68:sb + 0x78].hex()
        print('-'.join([u[:8], u[8:12], u[12:16], u[16:20], u[20:]]))
        break
PY
)
fi

if [ "$rc" = 0 ]; then
  echo
  echo "[flash] USB download complete. The board reboots on its own."
  echo "[flash] Verify: lsusb | grep 3346:100c   (100c = running system, 1000 = download mode)"
  echo "[flash] Then:   ssh root@192.168.42.1    (password: milkv)  ->  uname -m"
  echo "[flash] UART 115200 first line must read: $SIG"
  if [ -n "$IMG_UUID" ]; then
    echo
    echo "  ┌─ PROVE THE WRITE LANDED ───────────────────────────────────────────────────"
    echo "  │ The banner above is not evidence. Compare the rootfs filesystem identity:"
    echo "  │   image:  $IMG_UUID"
    echo "  │   board:  ssh root@192.168.42.1 'dumpe2fs -h /dev/mmcblk0p4 | grep -i uuid'"
    echo "  │ If they differ, the eMMC still holds the old image and the flash did nothing,"
    echo "  │ no matter what percentage you watched."
    echo "  └────────────────────────────────────────────────────────────────────────────"
  fi
else
  echo
  echo "Error: usb_dl never completed after $ATTEMPTS attempts." >&2
  echo "       Replug the Type-C DIRECTLY to the host while this is running, and check that" >&2
  echo "       the slide switch is on $SWITCH." >&2
fi
exit "$rc"
