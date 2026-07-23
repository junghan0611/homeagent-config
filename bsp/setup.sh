#!/usr/bin/env bash
# bsp/setup.sh — pin-clone the SG2000 buildroot SDK into a writable working tree.
#
# Mirrors the yocto/ pattern: the upstream SDK (~5.6G) is NOT committed; it is
# cloned here, pinned to a known commit, and stays gitignored. Our customizations
# live in bsp/overlay/ (committed), layered on top before build.
#
# The build runs in-tree (build.sh writes into the SDK tree + downloads a prebuilt
# toolchain), so this must be a writable checkout — not a read-only nix store path.
set -euo pipefail

BSP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# HomeAgent fork of the Milk-V SDK. The immutable commit is the build input; the
# branch only names its lane. Two lanes, because SG2000 boots either core off one die:
#
#   arm64   — development lane (2026-07-23~). Bootlin GCC 13, Node 22, Zigbee2MQTT,
#             USB host serial in the kernel.
#   riscv64 — product lane, parked pending upstream issue #74.
#
# What is NOT in the fork: our board defconfig, Buildroot config and rootfs overlay.
# Those live in bsp/ and bsp/build.sh injects them at build time, so this repo stays
# the single source of truth for product configuration and the fork carries only what
# a patch cannot express (kernel config, Buildroot package fixes, tool permissions).
SDK_URL="${SDK_URL:-https://github.com/junghan0611/duo-buildroot-sdk-v2.git}"
LANE="${HOMEAGENT_BSP_LANE:-arm64}"
case "$LANE" in
  arm64)
    SDK_BRANCH="${SDK_BRANCH:-feat/arm64-hub-baseline}"
    SDK_COMMIT="${SDK_COMMIT:-3a50ffe28}"   # + kernel USB serial, npm cross-arch fix
    ;;
  riscv64)
    SDK_BRANCH="${SDK_BRANCH:-feat/riscv64-nodejs-pure-cross}"
    SDK_COMMIT="${SDK_COMMIT:-087547cf8}"   # pure-cross Node.js 22.22.0 for riscv64
    ;;
  *)
    echo "[bsp] ERROR: unknown lane '$LANE' (want arm64 or riscv64)." >&2
    exit 1
    ;;
esac
SDK_DIR="${HOMEAGENT_BSP_SDK:-$BSP_DIR/sdk}"

if [ -d "$SDK_DIR/.git" ]; then
  HEAD="$(git -C "$SDK_DIR" rev-parse HEAD)"
  EXPECTED="$(git -C "$SDK_DIR" rev-parse "$SDK_COMMIT^{commit}" 2>/dev/null || true)"
  echo "[bsp] SDK already present: $SDK_DIR"
  echo "[bsp] HEAD: ${HEAD:0:9}"
  if [ -z "$EXPECTED" ] || [ "$HEAD" != "$EXPECTED" ]; then
    echo "[bsp] ERROR: existing SDK is not pinned at $SDK_COMMIT" >&2
    echo "[bsp] expected branch: $SDK_BRANCH ($SDK_URL)" >&2
    exit 1
  fi
  exit 0
fi

echo "[bsp] lane   : $LANE"
echo "[bsp] cloning $SDK_URL ($SDK_BRANCH) → $SDK_DIR"
git clone --branch "$SDK_BRANCH" "$SDK_URL" "$SDK_DIR"
git -C "$SDK_DIR" checkout "$SDK_COMMIT"
echo "[bsp] pinned at $(git -C "$SDK_DIR" rev-parse --short HEAD)"
if [ "$LANE" = arm64 ]; then
  echo "[bsp] next: ./bsp/build.sh milkv-duos-glibc-arm64-emmc   (dev lane; board switch must be ARM)"
else
  echo "[bsp] next: ./bsp/build.sh milkv-duos-musl-riscv64-emmc  (product lane, parked; switch must be RV)"
fi
