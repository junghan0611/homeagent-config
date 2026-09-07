#!/usr/bin/env bash
# smhub/build.sh — cross-build the SMHub payload (domoticz 2026.3, riscv64).
#
# The vendor OS owns the image; we own one .ipk. So this does not build a
# rootfs: it builds a toolchain matched to the device ABI, then `make domoticz`,
# and leaves the artifacts in the tree for smhub/pack-ipk.sh.
#
# Inputs are injected from this repo, which stays the single source of truth:
#   smhub/buildroot/<cfg>_defconfig  -> <tree>/configs/
#   smhub/package/domoticz/*         -> <tree>/package/domoticz/
# The upstream .hash is removed with the override: a git checkout has no tarball
# to hash, and its revision is pinned by the tag's gitlinks instead.
#
# Usage:
#   ./smhub/setup.sh            # clone+pin Buildroot 2026.02 (once)
#   ./smhub/build.sh            # inject + build domoticz
#   ./smhub/build.sh menuconfig # any make target works
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
TREE="${HOMEAGENT_SMHUB_BR:-$REPO_DIR/smhub/sdk}"
CFG="${HOMEAGENT_SMHUB_CFG:-smhub-nano-riscv64}"
TARGET="${1:-domoticz}"
JOBS="${HOMEAGENT_SMHUB_JOBS:-$(nproc)}"

if [ ! -d "$TREE" ]; then
  echo "[smhub] ERROR: tree not found at $TREE — run ./smhub/setup.sh first." >&2
  exit 1
fi

DEFCONFIG="$REPO_DIR/smhub/buildroot/${CFG}_defconfig"
[ -f "$DEFCONFIG" ] || { echo "[smhub] ERROR: no defconfig $DEFCONFIG" >&2; exit 1; }

echo "[smhub] injecting repo inputs into $TREE"
install -m 0644 "$DEFCONFIG" "$TREE/configs/${CFG}_defconfig"
install -m 0644 "$REPO_DIR/smhub/package/domoticz/domoticz.mk" "$TREE/package/domoticz/domoticz.mk"
rm -f "$TREE/package/domoticz/domoticz.hash"

# Buildroot hard-requires /usr/bin/file (support/dependencies/dependencies.sh),
# which NixOS does not have, so the make itself runs in a container — the same
# pattern bsp/build.sh uses, with the same image, UID-matched so the tree keeps
# host ownership. Buildroot builds its own cross toolchain, so the container is
# only a POSIX host: it contributes nothing to the artifact's ABI.
DOCKER_IMAGE="${HOMEAGENT_SMHUB_IMAGE:-milkvtech/milkv-duo:latest}"
run_make() {
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "$TREE":/br \
    -e HOME=/tmp \
    -e FORCE_UNSAFE_CONFIGURE=1 \
    -w /br \
    "$DOCKER_IMAGE" \
    make "$@"
}

cd "$TREE"
# Reconfigure only when the resolved .config would change: Buildroot's defconfig
# target rewrites .config wholesale, and that alone can trigger long rebuilds.
if [ ! -f .config ] || ! cmp -s <(sed 's/#.*//' "configs/${CFG}_defconfig") <(sed 's/#.*//' .config.smhub-stamp 2>/dev/null); then
  echo "[smhub] make ${CFG}_defconfig"
  run_make "${CFG}_defconfig"
  cp "configs/${CFG}_defconfig" .config.smhub-stamp
fi

echo "[smhub] make $TARGET  (-j$JOBS, in $DOCKER_IMAGE)"
time run_make -j"$JOBS" "$TARGET"

BIN="$TREE/output/target/opt/domoticz/domoticz"
if [ -x "$BIN" ]; then
  echo "[smhub] built: $BIN"
  file "$BIN" || true
  echo "[smhub] shared deps of the binary (what the .ipk must satisfy):"
  READELF="$(echo "$TREE"/output/host/bin/riscv64-*-readelf | cut -d' ' -f1)"
  if [ -x "$READELF" ]; then
    "$READELF" -d "$BIN" | sed -n 's/.*NEEDED.*\[\(.*\)\]/  \1/p'
  fi
  echo "[smhub] next: ./smhub/pack-ipk.sh"
else
  echo "[smhub] note: no domoticz binary at $BIN (target '$TARGET' may not produce one)"
fi
