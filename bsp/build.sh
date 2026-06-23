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
#   ./bsp/build.sh milkv-duos-glibc-arm64-emmc    # build ARM A53 eMMC image
# Output: <sdk>/out/<board>_<date>.zip
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
SDK_DIR="${HOMEAGENT_BSP_SDK:-$REPO_DIR/bsp/sdk}"
BOARD="${1:-milkv-duos-glibc-arm64-emmc}"
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
    if [ -f "/bsp/board/$BOARD/defconfig" ]; then
      DST=$(find build/boards -name "*$(echo "$BOARD" | tr - _)_defconfig" | head -1)
      if [ -n "$DST" ]; then cp "/bsp/board/$BOARD/defconfig" "$DST"; echo "[bsp] applied defconfig -> $DST"; fi
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
