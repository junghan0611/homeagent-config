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

# Upstream pin (Milk-V Duo series buildroot SDK V2, develop lane — ARM A53 boot).
SDK_URL="${SDK_URL:-https://github.com/milkv-duo/duo-buildroot-sdk-v2.git}"
SDK_BRANCH="${SDK_BRANCH:-develop}"
SDK_COMMIT="${SDK_COMMIT:-ad920f839}"   # cvi_mpi: support st7701sn 2 lane lcd
SDK_DIR="${HOMEAGENT_BSP_SDK:-$BSP_DIR/sdk}"

if [ -d "$SDK_DIR/.git" ]; then
  echo "[bsp] SDK already present: $SDK_DIR"
  echo "[bsp] HEAD: $(git -C "$SDK_DIR" rev-parse --short HEAD)"
  exit 0
fi

echo "[bsp] cloning $SDK_URL ($SDK_BRANCH) → $SDK_DIR"
git clone --branch "$SDK_BRANCH" "$SDK_URL" "$SDK_DIR"
git -C "$SDK_DIR" checkout "$SDK_COMMIT"
echo "[bsp] pinned at $(git -C "$SDK_DIR" rev-parse --short HEAD)"
echo "[bsp] next: nix develop .#buildroot  then  ./bsp/build.sh milkv-duos-glibc-arm64-emmc"
