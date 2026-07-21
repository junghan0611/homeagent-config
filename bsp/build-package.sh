#!/usr/bin/env bash
# bsp/build-package.sh — build ONE Buildroot package for a board, in the vendor
# container. Buildroot-only: no kernel, no u-boot, no image, no device.
#
# This is the N0 service-image lane's workhorse. `bsp/build.sh` builds a whole
# bootable image through the SDK's own build.sh; this one stops at the Buildroot
# layer, which is where userspace packages (Node, Mosquitto, Z2M) are proven first.
#
# Usage:
#   ./bsp/build-package.sh                                  # defaults: glibc riscv64 board, nodejs
#   ./bsp/build-package.sh milkv-duos-glibc-riscv64-emmc nodejs
#   G1_CLEAN=1 ./bsp/build-package.sh                       # dirclean the package first
#
#   HOMEAGENT_BSP_SDK=~/repos/3rd/milkv/duo-buildroot-sdk-v2 ./bsp/build-package.sh
#
# WHEN TO USE G1_CLEAN=1 — this is not optional hygiene, it is correctness:
# with BR2_PER_PACKAGE_DIRECTORIES each package builds against a private host/target
# tree rsynced from its *declared* dependencies. Resuming an already-configured
# package after its recipe gained a dependency keeps the stale tree, and the new
# headers/libraries never appear. So: whenever bsp/patches/ changes a recipe, the
# affected package must start over.
#
# Output: <sdk>/buildroot/output/<board>/{build,target,per-package}/...
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
SDK_DIR="${HOMEAGENT_BSP_SDK:-$REPO_DIR/bsp/sdk}"
BOARD="${1:-milkv-duos-glibc-riscv64-emmc}"
PKG="${2:-nodejs}"
DOCKER_IMAGE="${HOMEAGENT_BSP_IMAGE:-milkvtech/milkv-duo:latest}"

if [ ! -d "$SDK_DIR" ]; then
  echo "Error: SDK not found at $SDK_DIR — run ./bsp/setup.sh first (or set HOMEAGENT_BSP_SDK)." >&2
  exit 1
fi

echo "[pkg] SDK   : $SDK_DIR"
echo "[pkg] board : $BOARD"
echo "[pkg] pkg   : $PKG"
# Provenance: record the immutable digest, never rely on the :latest tag.
DIGEST="$(docker inspect --format '{{index .RepoDigests 0}}' "$DOCKER_IMAGE" 2>/dev/null || echo "(no RepoDigest)")"
echo "[pkg] image : $DIGEST"

exec docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$SDK_DIR":/home/work \
  -v "$REPO_DIR/bsp":/bsp:ro \
  -e HOME=/tmp \
  -e FORCE_UNSAFE_CONFIGURE=1 \
  -e "BOARD=$BOARD" \
  -e "PKG=$PKG" \
  -e "G1_CLEAN=${G1_CLEAN:-0}" \
  "$DOCKER_IMAGE" \
  /bin/bash -ec '
    cd /home/work
    git config --global --add safe.directory /home/work
    echo "[pkg] container: $(head -1 /etc/issue)"
    echo "[pkg] host cc  : $(cc --version 2>/dev/null | head -1)"

    # Our committed patches, applied idempotently (same contract as bsp/build.sh).
    for p in /bsp/patches/*.patch; do
      [ -f "$p" ] || continue
      if git apply --reverse --check "$p" 2>/dev/null; then
        echo "[pkg] patch already applied: $(basename "$p")"
      elif git apply --check "$p" 2>/dev/null; then
        git apply "$p"; echo "[pkg] applied patch: $(basename "$p")"
      else
        echo "[pkg] ERROR: patch does not apply: $(basename "$p")" >&2; exit 1
      fi
    done

    # Our committed Buildroot config, for board/libc combinations the SDK lacks.
    if [ -f "/bsp/buildroot/${BOARD}_defconfig" ]; then
      cp "/bsp/buildroot/${BOARD}_defconfig" "buildroot/configs/${BOARD}_defconfig"
      echo "[pkg] installed buildroot config: ${BOARD}_defconfig"
    fi

    cd buildroot
    make "O=output/${BOARD}" "${BOARD}_defconfig"

    echo "[pkg] resolved ISA / libc:"
    grep -E "^BR2_(RISCV_ISA_|riscv|TOOLCHAIN_EXTERNAL_CUSTOM_(GLIBC|MUSL))" \
      "output/${BOARD}/.config" || true

    if [ "${G1_CLEAN:-0}" = "1" ]; then
      make "O=output/${BOARD}" "${PKG}-dirclean" "${PKG}-src-dirclean" || true
      echo "[pkg] dircleaned ${PKG}"
    fi

    make "O=output/${BOARD}" "${PKG}"
    echo "[pkg] DONE"
  '
