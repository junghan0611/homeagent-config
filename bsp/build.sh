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
# PROFILES — one board, two package sets, selected by HOMEAGENT_BSP_PROFILE:
#   full     (default)  Node 22 + Zigbee2MQTT + mosquitto. The hub image; artifact name
#                       is unchanged, so every existing command keeps its meaning.
#   minimal             the same board and BSP with Node/ICU/Z2M/mosquitto off, via
#                       bsp/buildroot/profiles/<board>_minimal.fragment appended to the
#                       Buildroot defconfig. V8 is 85% of a laptop build (1h16m of
#                       1h29m), so this proves the BSP surface — hostapd, stable MAC,
#                       serial by-id — in minutes. Its artifact is named
#                       <board>-minimal_<date> so flash-emmc.sh's `<board>_*.zip`
#                       auto-pick cannot mistake it for a hub image.
# Both profiles write out/<artifact>.manifest.txt recording the repo commit, the SDK
# pin, and the resolved package set — an image on disk can always say what it is.
#
# Usage:
#   ./bsp/setup.sh                                # clone+pin SDK (or set HOMEAGENT_BSP_SDK)
#   ./bsp/build.sh milkv-duos-glibc-arm64-emmc    # ARM A53,    eMMC — current DEV lane
#   HOMEAGENT_BSP_PROFILE=minimal \
#     ./bsp/build.sh milkv-duos-glibc-arm64-emmc  # same board, no Node/Z2M
#   ./bsp/build.sh milkv-duos-musl-riscv64-sd     # RISC-V C906, microSD (script default)
#   ./bsp/build.sh milkv-duos-musl-riscv64-emmc   # RISC-V C906, eMMC    (product lane, parked)
# Two lanes, one die: SG2000 carries an A53 and a C906 and a physical slide switch picks one.
#   arm64/glibc  — development lane since 2026-07-23. BR2_aarch64 is a first-class arch for
#                  Buildroot's nodejs package, so Node 22 builds with no downstream patches.
#   riscv64/musl — still the product ISA, parked while Node support sits with upstream.
# The image ISA and the board switch must agree or nothing boots. See bsp/README.md.
# (This is a dev-board image — it is not, and cannot become, a hub-product image.)
# Output: <sdk>/out/<board>_<date>.{img,zip}   (sd -> .img dd-able; emmc -> .zip for usb_dl)
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
SDK_DIR="${HOMEAGENT_BSP_SDK:-$REPO_DIR/bsp/sdk}"
BOARD="${1:-milkv-duos-musl-riscv64-sd}"
DOCKER_IMAGE="${HOMEAGENT_BSP_IMAGE:-milkvtech/milkv-duo:latest}"
# HUB_MINIMAL skips the CVITEK camera/ISP/RTSP/AI vision stack (patch 0001). It is about
# the SDK's build logic and is unrelated to PROFILE below, which is about our package set.
HUB_MINIMAL="${HOMEAGENT_HUB_MINIMAL:-1}"
# Package-set profile. `full` is the hub image and the default, so an unset environment
# reproduces exactly what this repo built before profiles existed.
PROFILE="${HOMEAGENT_BSP_PROFILE:-full}"

if [ ! -d "$SDK_DIR" ]; then
  echo "Error: SDK not found at $SDK_DIR — run ./bsp/setup.sh first (or set HOMEAGENT_BSP_SDK)." >&2
  exit 1
fi

# Fail on an unknown profile here rather than inside the container, where the only
# symptom would be a silently `full` image. `full` needs no fragment by definition.
FRAGMENT="$REPO_DIR/bsp/buildroot/profiles/${BOARD}_${PROFILE}.fragment"
if [ "$PROFILE" != "full" ] && [ ! -f "$FRAGMENT" ]; then
  echo "Error: profile '$PROFILE' has no fragment for board '$BOARD'." >&2
  echo "       expected: bsp/buildroot/profiles/${BOARD}_${PROFILE}.fragment" >&2
  echo "       available:" >&2
  ls "$REPO_DIR/bsp/buildroot/profiles/" 2>/dev/null | sed 's/^/         /' >&2 || echo "         (none)" >&2
  exit 1
fi

# Recorded in the manifest so an image can name the commit that produced it. A dirty
# tree is marked, not refused — local iteration is normal, silently losing it is not.
REPO_COMMIT="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if ! git -C "$REPO_DIR" diff --quiet HEAD -- bsp 2>/dev/null; then
  REPO_COMMIT="$REPO_COMMIT-dirty"
fi

# The build container is the one input this repo pins by TAG, not by content:
# milkvtech/milkv-duo:latest moves whenever the vendor pushes. Everything else
# (SDK commit, board config, overlay, Buildroot package versions) is pinned, so the
# digest is what closes the gap between "same commands" and "same bytes". Recorded
# rather than enforced — pinning the tag is a separate decision with its own cost.
IMAGE_DIGEST="$(docker image inspect "$DOCKER_IMAGE" --format '{{index .RepoDigests 0}}' 2>/dev/null \
  || docker image inspect "$DOCKER_IMAGE" --format '{{.Id}}' 2>/dev/null \
  || echo unknown)"

echo "[bsp] SDK    : $SDK_DIR"
echo "[bsp] board  : $BOARD"
echo "[bsp] profile: $PROFILE"
echo "[bsp] image  : $DOCKER_IMAGE"
echo "[bsp] digest : $IMAGE_DIGEST"
echo "[bsp] commit : $REPO_COMMIT"

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
  -e "PROFILE=$PROFILE" \
  -e "REPO_COMMIT=$REPO_COMMIT" \
  -e "IMAGE_DIGEST=$IMAGE_DIGEST" \
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

    # Inject the Buildroot userspace config as well as the outer SDK board config.
    # Package proofs and complete images must resolve the same target package set.
    if [ -f "/bsp/buildroot/${BOARD}_defconfig" ]; then
      cp "/bsp/buildroot/${BOARD}_defconfig" "buildroot/configs/${BOARD}_defconfig"
      echo "[bsp] installed Buildroot config: ${BOARD}_defconfig"

      # Append the profile fragment. kconfig reads a defconfig top-to-bottom and keeps the
      # LAST value for a symbol, so appending overrides the base rather than conflicting
      # with it — that is why this is a fragment and not a rival defconfig. The host side
      # already refused an unknown profile; a fragment missing HERE would mean the mount
      # is wrong, so fail rather than emit a full image under a minimal name.
      FRAG="/bsp/buildroot/profiles/${BOARD}_${PROFILE}.fragment"
      if [ "$PROFILE" != "full" ]; then
        if [ ! -f "$FRAG" ]; then
          echo "[bsp] ERROR: profile fragment not readable in container: $FRAG" >&2
          exit 1
        fi
        {
          echo ""
          echo "# --- profile: ${PROFILE} (appended by bsp/build.sh) ---"
          cat "$FRAG"
        } >> "buildroot/configs/${BOARD}_defconfig"
        echo "[bsp] applied profile fragment: $(basename "$FRAG")"
      fi
    fi

    # Apply our committed patches idempotently and fail closed. Continuing after a
    # rejected Node/V8 patch could produce a plausible image without our contract.
    for p in /bsp/patches/*.patch; do
      [ -f "$p" ] || continue
      if git apply --reverse --check "$p" 2>/dev/null; then
        echo "[bsp] patch already applied: $(basename "$p")"
      elif git apply --check "$p" 2>/dev/null; then
        git apply "$p"
        echo "[bsp] applied patch: $(basename "$p")"
      else
        echo "[bsp] ERROR: patch does not apply: $(basename "$p")" >&2
        exit 1
      fi
    done

    # Marker for "which artifacts did THIS run produce". out/ accumulates every previous
    # build and both lanes, so a plain `ls -t` would happily rename someone elses image.
    MARK=$(mktemp)
    ./build.sh "$BOARD"

    # ---- receipts -----------------------------------------------------------------
    # A profile that silently did not apply is the failure worth catching: the build
    # succeeds, the image looks right, and it carries a package set nobody asked for.
    CFG="buildroot/output/${BOARD}/.config"
    if [ "$PROFILE" != "full" ] && [ -f "$CFG" ]; then
      if grep -q "^BR2_PACKAGE_NODEJS=y" "$CFG"; then
        echo "[bsp] ERROR: profile ${PROFILE} did not take — BR2_PACKAGE_NODEJS is still y in $CFG" >&2
        exit 1
      fi
      echo "[bsp] profile verified in .config: BR2_PACKAGE_NODEJS is off"
    fi

    # Name the artifact after the profile so it cannot be mistaken for a hub image.
    # `full` keeps the historical name — every existing command and doc stays true.
    if [ "$PROFILE" != "full" ]; then
      find out -maxdepth 1 -name "${BOARD}_*" -newer "$MARK" 2>/dev/null | while read -r f; do
        b=$(basename "$f")
        mv "$f" "out/${BOARD}-${PROFILE}_${b#${BOARD}_}"
        echo "[bsp] artifact: ${BOARD}-${PROFILE}_${b#${BOARD}_}"
      done
    fi

    # One manifest per artifact. The point is that an image sitting in out/ months from
    # now can still say which commit, which SDK pin, and which package set produced it.
    SDK_PIN=$(git -C /home/work rev-parse --short HEAD 2>/dev/null || echo unknown)
    find out -maxdepth 1 \( -name "*.zip" -o -name "*.img" \) -newer "$MARK" 2>/dev/null | while read -r f; do
      {
        echo "artifact:    $(basename "$f")"
        echo "board:       ${BOARD}"
        echo "profile:     ${PROFILE}"
        echo "repo commit: ${REPO_COMMIT}"
        echo "sdk pin:     ${SDK_PIN}"
        echo "container:   ${IMAGE_DIGEST}"
        echo "built (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "sha256:      $(sha256sum "$f" | cut -d" " -f1)"
        echo ""
        echo "resolved package set:"
        for s in BR2_PACKAGE_NODEJS BR2_PACKAGE_ICU BR2_PACKAGE_MOSQUITTO BR2_PACKAGE_HOSTAPD BR2_PACKAGE_WPA_SUPPLICANT; do
          v=$(grep -E "^${s}=|^# ${s} is not set" "$CFG" 2>/dev/null | head -1)
          echo "  ${v:-# ${s} absent from .config}"
        done
        grep -E "^BR2_PACKAGE_NODEJS_MODULES_ADDITIONAL=" "$CFG" 2>/dev/null | sed "s/^/  /"
        grep -E "^BR2_ROOTFS_OVERLAY=" "$CFG" 2>/dev/null | sed "s/^/  /"
      } > "${f}.manifest.txt"
      echo "[bsp] manifest: $(basename "$f").manifest.txt"
    done
    rm -f "$MARK"
  '
