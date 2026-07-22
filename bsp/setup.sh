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

# HomeAgent fork: upstream ad920f839 plus the measured riscv64 pure-cross Node
# support. The immutable commit is the build input; the branch names its lane.
SDK_URL="${SDK_URL:-https://github.com/junghan0611/duo-buildroot-sdk-v2.git}"
SDK_BRANCH="${SDK_BRANCH:-feat/riscv64-nodejs-pure-cross}"
SDK_COMMIT="${SDK_COMMIT:-087547cf8}"   # pure-cross Node.js 22.22.0 for riscv64
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

echo "[bsp] cloning $SDK_URL ($SDK_BRANCH) → $SDK_DIR"
git clone --branch "$SDK_BRANCH" "$SDK_URL" "$SDK_DIR"
git -C "$SDK_DIR" checkout "$SDK_COMMIT"
echo "[bsp] pinned at $(git -C "$SDK_DIR" rev-parse --short HEAD)"
echo "[bsp] next: ./bsp/build.sh milkv-duos-musl-riscv64-sd   (RISC-V = product ISA; arm64 boards are historical)"
