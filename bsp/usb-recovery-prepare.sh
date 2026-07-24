#!/usr/bin/env bash
# bsp/usb-recovery-prepare.sh — put the host USB stack in the state usb_dl needs before
# flashing a Milk-V Duo S. Idempotent; run before ./bsp/flash-emmc.sh.
#
# The counter-intuitive part
# --------------------------
# The obvious move is to keep cdc_acm away from the ROM's download interface, because
# cdc_acm binding it is what makes libusb fail with an empty "[ERR]". Both obvious ways of
# doing that make things worse, and it took two days to see why:
#
#   - Turning off /sys/bus/usb/drivers_autoprobe stops cdc_acm, but then every device that
#     enumerates afterwards is left UNCONFIGURED (empty bConfigurationValue, zero
#     interfaces), so libusb has nothing to claim: LIBUSB_ERROR_INVALID_PARAM. Setting the
#     configuration afterwards does not rescue it -- libusb caches the config descriptor at
#     open() and usb_dl opens within milliseconds of enumeration.
#
#   - Blocking the module (blacklist, or a udev rule clearing MODALIAS) does keep the
#     interface free, and libusb claims it happily... and then every 512 KiB bulk write
#     times out. cdc_acm's probe is what performs the CDC setup -- SET_LINE_CODING (0x20)
#     and SET_CONTROL_LINE_STATE (0x22) -- that opens the ROM's data pipe. Without it,
#     usb_dl's own versions of those two control transfers time out and nothing can be
#     written. Worse, usb_dl does not notice: it counts every chunk it hands to libusb,
#     reaches "updated size: .../...(100%)", and prints "USB download complete".
#     Measured 2026-07-24: a run that reported 100% left the eMMC byte-identical to the
#     day before -- same ext4 UUID, same mkfs timestamp.
#
# So the correct order is LET IT BIND, THEN TAKE IT AWAY: autoprobe on, cdc_acm loaded,
# let it bind on enumeration and do the CDC setup, then unbind it immediately before usb_dl.
# flash-emmc.sh does the unbind per attempt; this script just makes sure the host is in the
# state where the bind can happen at all.
#
# Usage:
#   sudo ./bsp/usb-recovery-prepare.sh            # get the host ready
#   sudo ./bsp/usb-recovery-prepare.sh --revert   # remove the rule installed here
set -euo pipefail

if [ "$(id -u)" != 0 ]; then
  echo "Error: run with sudo — this writes a udev rule and loads a kernel module." >&2
  exit 1
fi

# On NixOS /etc/udev/rules.d is a read-only store path, so fall back to /run/udev/rules.d,
# which udev reads with higher precedence anyway. /run is cleared on reboot — that is fine,
# this script is idempotent and meant to be rerun before each flash.
RULES_DIR=/etc/udev/rules.d
if ! mkdir -p "$RULES_DIR" 2>/dev/null || ! touch "$RULES_DIR/.wtest" 2>/dev/null; then
  RULES_DIR=/run/udev/rules.d
  mkdir -p "$RULES_DIR"
  echo "[prepare] /etc/udev/rules.d is read-only (NixOS) — using $RULES_DIR."
else
  rm -f "$RULES_DIR/.wtest"
fi
CONFIGURE="$RULES_DIR/99-cvitek-rom-configure.rules"
# The harmful rule may have been dropped in either location by an earlier session.
STALE_BLOCKS="/etc/udev/rules.d/79-cvitek-rom-no-modalias.rules /run/udev/rules.d/79-cvitek-rom-no-modalias.rules"

if [ "${1:-}" = "--revert" ]; then
  # shellcheck disable=SC2086
  rm -f "$CONFIGURE" $STALE_BLOCKS
  udevadm control --reload
  echo 1 > /sys/bus/usb/drivers_autoprobe
  echo "[prepare] reverted: rules removed, autoprobe=1."
  exit 0
fi

# A rule blocking cdc_acm is actively harmful (see the header). Remove it if an earlier
# attempt at this problem left one behind.
for f in $STALE_BLOCKS; do
  [ -f "$f" ] || continue
  rm -f "$f" && echo "[prepare] removed $f — blocking cdc_acm breaks the CDC setup."
done

cat > "$CONFIGURE" <<'RULE'
# Safety net only. With drivers_autoprobe=1 the kernel configures the device during
# enumeration and this does nothing. It fires only if something left autoprobe at 0, in which
# case the device would enumerate with no configuration and no interfaces at all and usb_dl
# would die with LIBUSB_ERROR_INVALID_PARAM.
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="3346", ATTR{idProduct}=="1000", ATTR{bConfigurationValue}=="", ATTR{bConfigurationValue}="1"
RULE
udevadm control --reload
echo "[prepare] udev safety-net rule installed: $CONFIGURE"

echo 1 > /sys/bus/usb/drivers_autoprobe
echo "[prepare] drivers_autoprobe=1 (kernel configures the device during enumeration)."

modprobe cdc_acm 2>/dev/null || true
# Read /proc/modules rather than piping lsmod into grep: under `set -o pipefail`, `grep -q`
# exits on the first match and lsmod dies of SIGPIPE (141), so the pipeline reports failure
# even though the module is loaded. That exact trap silently skipped the cdc_acm handling in
# flash-emmc.sh for a whole morning on 2026-07-24.
if grep -q '^cdc_acm ' /proc/modules; then
  echo "[prepare] cdc_acm loaded — it must bind once to set up the CDC line."
else
  echo "Warning: cdc_acm could not be loaded. usb_dl will claim the interface fine and then" >&2
  echo "         every bulk write will time out. Check that the module exists." >&2
fi

echo
echo "[prepare] ready. Start ./bsp/flash-emmc.sh FIRST, then plug the board in."
echo "[prepare] after plugging, BOTH of these must be true:"
echo "[prepare]   lsusb | grep 3346          ->  3346:1000  (100c = booted; replug holding recovery)"
echo "[prepare]   dmesg | tail               ->  'cdc_acm <dev>: ttyACM0: USB ACM device'"
echo "[prepare] no ttyACM line means the CDC setup did not happen and the write will silently"
echo "[prepare] fail while reporting 100 percent."
