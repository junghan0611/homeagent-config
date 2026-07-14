#!/usr/bin/env bash
# bsp/build.sh — reproducible SG2000 image build (official Milk-V Docker).
#
# The upstream SDK is "Ubuntu 22.04 only, otherwise Docker" (milkv docs). We build
# in the vendor image milkvtech/milkv-duo:latest — the same path AOSP-class vendor
# SDKs take. Our customizations stay committed in this repo and are injected onto
# the (gitignored) SDK clone INSIDE the container (as root, same as the build), so
# there is no host/root ownership conflict:
#   - bsp/board/<board>/defconfig   → SDK board defconfig
#   - bsp/patches/*.patch           → SDK build logic (e.g. skip vision stack)
#
# Usage:
#   ./bsp/setup.sh                                # clone+pin SDK (or set HOMEAGENT_BSP_SDK)
#   ./bsp/build.sh milkv-duos-musl-riscv64-sd     # RISC-V C906, microSD  (default, product ISA)
#   ./bsp/build.sh milkv-duos-musl-riscv64-emmc   # RISC-V C906, eMMC     (usb_dl recovery flash)
#   ./bsp/build.sh milkv-duos-glibc-arm64-emmc    # ARM A53, eMMC         (historical, NOT the product)
# Our runtime targets riscv64 + musl; the arm64 boards exist only because SG2000 can boot
# either core. Build RISC-V unless you know why you want ARM. (This is a dev-board image —
# it is not, and cannot become, a hub-product image. See bsp/README.md.)
# Output: <sdk>/out/<board>_<date>.{img,zip}   (sd -> .img dd-able; emmc -> .zip for usb_dl)
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
SDK_DIR="${HOMEAGENT_BSP_SDK:-$REPO_DIR/bsp/sdk}"
BOARD="${1:-milkv-duos-musl-riscv64-sd}"
DOCKER_IMAGE="${HOMEAGENT_BSP_IMAGE:-milkvtech/milkv-duo:latest}"
HUB_MINIMAL="${HOMEAGENT_HUB_MINIMAL:-1}"

if [ ! -d "$SDK_DIR" ]; then
  echo "Error: SDK not found at $SDK_DIR — run ./bsp/setup.sh first (or set HOMEAGENT_BSP_SDK)." >&2
  exit 1
fi

echo "[bsp] SDK   : $SDK_DIR"
echo "[bsp] board : $BOARD"
echo "[bsp] image : $DOCKER_IMAGE"

# Run as the host UID/GID (GLG's AOSP-build pattern) so all build outputs and any
# SDK-tree mutations are host-owned — no root contamination, clean re-runs. The SDK
# clone must be host-owned for this; bsp/setup.sh clones it as the host user.
# Everything that touches the SDK tree runs INSIDE the container; our repo's bsp/ is
# mounted read-only at /bsp.
exec docker run --rm --privileged \
  --user "$(id -u):$(id -g)" \
  -v "$SDK_DIR":/home/work \
  -v "$REPO_DIR/bsp":/bsp:ro \
  -e HOME=/tmp \
  -e FORCE_UNSAFE_CONFIGURE=1 \
  -e "HOMEAGENT_HUB_MINIMAL=$HUB_MINIMAL" \
  -e "BOARD=$BOARD" \
  "$DOCKER_IMAGE" \
  /bin/bash -ec '
    cd /home/work
    git config --global --add safe.directory /home/work
    cat /etc/issue | head -1

    # Inject our committed board config (reproducible SSOT).
    # The board name matches THREE files: the board defconfig (<chip>_<board>_defconfig)
    # and the kernel/u-boot ones (cvitek_<chip>_<board>_defconfig, under linux/ + u-boot/).
    # Only the board-level one is ours; excluding cvitek_* keeps us off the kernel config.
    if [ -f "/bsp/board/$BOARD/defconfig" ]; then
      U=$(echo "$BOARD" | tr - _)
      mapfile -t HITS < <(find build/boards -name "*${U}_defconfig" -not -name "cvitek_*")
      if [ "${#HITS[@]}" -ne 1 ]; then
        echo "[bsp] ERROR: expected exactly 1 board defconfig for $BOARD, found ${#HITS[@]}: ${HITS[*]:-none}" >&2
        exit 1
      fi
      cp "/bsp/board/$BOARD/defconfig" "${HITS[0]}"
      echo "[bsp] applied defconfig -> ${HITS[0]}"
    fi

    # Apply our committed patches idempotently.
    for p in /bsp/patches/*.patch; do
      [ -f "$p" ] || continue
      if git apply --reverse --check "$p" 2>/dev/null; then echo "[bsp] patch already applied: $(basename "$p")";
      elif git apply --check "$p" 2>/dev/null; then git apply "$p"; echo "[bsp] applied patch: $(basename "$p")";
      else echo "[bsp] WARN: patch does not apply: $(basename "$p")" >&2; fi
    done

    ./build.sh "$BOARD"
  '
