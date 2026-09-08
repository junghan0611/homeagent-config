#!/usr/bin/env bash
# smhub/pack-ipk.sh — package the cross-built domoticz as a riscv64 .ipk.
#
# The bundle list is not hardcoded. It is DERIVED, in two steps:
#   1. the binary's own NEEDED closure (readelf, transitively over what we built)
#   2. minus whatever the live device already has in its rootfs
# Step 2 asks the device over SSH instead of trusting a list in a document,
# because "the rootfs has it" is exactly the kind of claim that rots. Without
# SSH the script stops rather than guessing: shipping a library the vendor
# already owns risks two copies of one soname in one process.
#
# Layout produced (install surface = p7 only, docs/SMHUB.md §3.7):
#   /opt/domoticz/domoticz         the binary
#   /opt/domoticz/{www,Config,...} static assets from the build
#   /opt/domoticz/lib/             only the libraries the device lacks
#   /etc/init.d/domoticz           OpenRC service (overlay upper = p7)
# LD_LIBRARY_PATH in the init script points at /opt/domoticz/lib, so no
# patchelf/RPATH rewrite is needed and the binary stays exactly as built.
#
# Usage:
#   ./smhub/pack-ipk.sh                       # uses SMHUB_SSH below
#   SMHUB_SSH="smlight@192.168.0.124" ./smhub/pack-ipk.sh
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
TREE="${HOMEAGENT_SMHUB_BR:-$REPO_DIR/smhub/sdk}"
OUT_DIR="${HOMEAGENT_SMHUB_OUT:-$REPO_DIR/smhub/out}"
# Live device (LAN coordinate stays out of the public tree: see PRIVATE.md).
SMHUB_SSH="${SMHUB_SSH:-}"
SMHUB_SSH_KEY="${SMHUB_SSH_KEY:-$REPO_DIR/.sshkey/id_ed25519}"
# opkg metadata. Required-OS-Version is the vendor's own gate field, spelled as
# it appears in their feed index (NOT "Require-", which is how the release notes
# write it).
PKG_NAME="domoticz"
PKG_REV="${HOMEAGENT_SMHUB_PKG_REV:-1}"
PKG_ARCH="riscv64"
# The binary is pinned to the ABI we MEASURED (§3), so the floor is the profile
# we actually built against -- not the oldest OS that would accept the file.
PKG_OS_MIN="${HOMEAGENT_SMHUB_OS_MIN:-1.0.2}"
# HTTP port is a build-time input, not something to hand-edit on the device:
# a device-side edit is silently reverted by the next ipk. 8080 is taken by the
# vendor's zigbee2mqtt frontend, so the default is 8081. Verify per unit (§3.5).
HTTP_PORT="${HOMEAGENT_SMHUB_HTTP_PORT:-8081}"

STAGING="$TREE/output/target"
BIN="$STAGING/opt/domoticz/domoticz"
[ -x "$BIN" ] || { echo "[pack] ERROR: no binary at $BIN — run ./smhub/build.sh first." >&2; exit 1; }

READELF="$(echo "$TREE"/output/host/bin/riscv64-*-readelf | cut -d' ' -f1)"
[ -x "$READELF" ] || { echo "[pack] ERROR: no cross readelf in $TREE/output/host/bin" >&2; exit 1; }

DOMO_VERSION="$(sed -n 's/^DOMOTICZ_VERSION = //p' "$REPO_DIR/smhub/package/domoticz/domoticz.mk")"
PKG_VERSION="${DOMO_VERSION}-${PKG_REV}"

needed_of() { "$READELF" -d "$1" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'; }

# --- 1. NEEDED closure over the libraries that exist in our own build ---------
declare -A SEEN=()
QUEUE=()
while IFS= read -r so; do QUEUE+=("$so"); done < <(needed_of "$BIN")
CLOSURE=()
while [ ${#QUEUE[@]} -gt 0 ]; do
  so="${QUEUE[0]}"; QUEUE=("${QUEUE[@]:1}")
  [ -n "${SEEN[$so]:-}" ] && continue
  SEEN[$so]=1
  CLOSURE+=("$so")
  # Follow only what we built; system sonames resolve on the device.
  path="$(find "$STAGING/usr/lib" "$STAGING/lib" -maxdepth 1 -name "$so" 2>/dev/null | head -1)"
  [ -n "$path" ] || continue
  while IFS= read -r dep; do QUEUE+=("$dep"); done < <(needed_of "$path")
done
echo "[pack] NEEDED closure (${#CLOSURE[@]}):"
printf '  %s\n' "${CLOSURE[@]}"

# --- 2. subtract what the device already provides -----------------------------
if [ -z "$SMHUB_SSH" ]; then
  cat >&2 <<'EOS'
[pack] ERROR: SMHUB_SSH is not set.
       The bundle list is derived by asking the live device which sonames it
       already has; guessing it would risk two copies of one soname in one
       process. Set SMHUB_SSH=user@host (key: .sshkey/id_ed25519) and retry.
EOS
  exit 1
fi
# Capture the profile this .ipk is being cut against. The bundle list is a
# function of THIS device, so the artifact is only valid for a device that
# reports the same ABI -- record it or the ipk is unfalsifiable later.
echo "[pack] capturing device profile from $SMHUB_SSH"
DEVICE_PROFILE="$(ssh -i "$SMHUB_SSH_KEY" -o BatchMode=yes "$SMHUB_SSH" '
  . /etc/os-release 2>/dev/null
  echo "os_version=$VERSION_ID"
  echo "buildroot=$VERSION"
  echo "arch=$(uname -m)"
  echo "glibc=$(/lib/libc.so.6 2>/dev/null | head -1 | sed "s/.*version //; s/\.$//")"
  echo "libstdcxx=$(readlink -f /usr/lib/libstdc++.so.6 2>/dev/null | xargs -r basename)"
  echo "python=$(python3 -V 2>&1)"
  echo "nproc=$(nproc)"
')"
echo "$DEVICE_PROFILE" | sed 's/^/  /'
DEV_OS_VERSION="$(printf '%s\n' "$DEVICE_PROFILE" | sed -n 's/^os_version=//p')"
if [ -n "$DEV_OS_VERSION" ] && [ "$DEV_OS_VERSION" != "$PKG_OS_MIN" ]; then
  echo "[pack] WARNING: device runs OS '$DEV_OS_VERSION' but Required-OS-Version is '$PKG_OS_MIN'." >&2
  echo "[pack]          Set HOMEAGENT_SMHUB_OS_MIN deliberately if that is intended." >&2
fi

echo "[pack] asking $SMHUB_SSH which sonames the rootfs already provides"
DEVICE_LIBS="$(printf '%s\n' "${CLOSURE[@]}" | ssh -i "$SMHUB_SSH_KEY" -o BatchMode=yes "$SMHUB_SSH" \
  'while read -r so; do [ -e "/usr/lib/$so" ] || [ -e "/lib/$so" ] && echo "$so"; done')"

BUNDLE=()
for so in "${CLOSURE[@]}"; do
  if printf '%s\n' "$DEVICE_LIBS" | grep -qxF "$so"; then continue; fi
  path="$(find "$STAGING/usr/lib" "$STAGING/lib" -maxdepth 1 -name "$so" 2>/dev/null | head -1)"
  if [ -z "$path" ]; then
    echo "[pack] ERROR: '$so' is neither on the device nor in our build — unresolvable." >&2
    exit 1
  fi
  BUNDLE+=("$path")
done
echo "[pack] device provides: $(printf '%s\n' "$DEVICE_LIBS" | tr '\n' ' ')"
echo "[pack] bundling ${#BUNDLE[@]}: $(printf '%s ' "${BUNDLE[@]##*/}")"

# --- 3. assemble the ipk ------------------------------------------------------
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/data/opt/domoticz" "$WORK/data/etc/init.d" "$WORK/control"
cp -a "$STAGING/opt/domoticz/." "$WORK/data/opt/domoticz/"
if [ ${#BUNDLE[@]} -gt 0 ]; then
  mkdir -p "$WORK/data/opt/domoticz/lib"
  for p in "${BUNDLE[@]}"; do cp -aL "$p" "$WORK/data/opt/domoticz/lib/"; done
fi

cat > "$WORK/data/etc/init.d/domoticz" <<EOS
#!/sbin/openrc-run

description="Domoticz home automation server"

# /opt/bin is not on PATH on this OS and the vendor's own services use absolute
# paths, so we do too.
command="/opt/domoticz/domoticz"
# Port 8080 is NOT free: the vendor's own zigbee2mqtt frontend listens there
# (measured 2026-09-08, \`/opt/bin/node /opt/bin/zigbee2mqtt\`). Set with
# HOMEAGENT_SMHUB_HTTP_PORT at pack time, never by editing this file on the box.
command_args="-www $HTTP_PORT -sslwww 0 -userdata /opt/domoticz -wwwroot /opt/domoticz/www"
command_background=yes
pidfile="/run/domoticz.pid"
directory="/opt/domoticz"
# Libraries the vendor rootfs does not carry ride inside the package.
export LD_LIBRARY_PATH="/opt/domoticz/lib"

depend() {
	need net
	after mosquitto
}

# NOTE: this service does NOT touch /dev/ttyS1. The MG24 radio is held by the
# vendor's zigbee2mqtt, and one radio takes one host stack. Z4D (Domoticz's
# Zigbee plugin) can only own that port once z2m is stopped -- a deliberate
# decision, not something this package makes for you.
EOS
chmod 0755 "$WORK/data/etc/init.d/domoticz"

INSTALLED_SIZE="$(du -sb "$WORK/data" | cut -f1)"
cat > "$WORK/control/control" <<EOS
Package: $PKG_NAME
Version: $PKG_VERSION
Architecture: $PKG_ARCH
Maintainer: homeagent
Section: utils
Priority: optional
Required-OS-Version: $PKG_OS_MIN
Installed-Size: $INSTALLED_SIZE
Description: Domoticz $DOMO_VERSION built for SMHUB (riscv64, glibc 2.42).
 Cross-built from upstream Buildroot $(cd "$TREE" && git describe --tags --always) with
 USE_PYTHON=ON so Zigbee for Domoticz can load. Installs to /opt (p7), the only
 surface that survives an OTA.
EOS

mkdir -p "$OUT_DIR"
IPK="$OUT_DIR/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.ipk"
( cd "$WORK/data" && tar --numeric-owner --owner=0 --group=0 -czf ../data.tar.gz . )
( cd "$WORK/control" && tar --numeric-owner --owner=0 --group=0 -czf ../control.tar.gz . )
echo "2.0" > "$WORK/debian-binary"
( cd "$WORK" && ar -r "$IPK" debian-binary control.tar.gz data.tar.gz 2>/dev/null )

echo "[pack] wrote $IPK ($(du -h "$IPK" | cut -f1))"
{
  echo "artifact: $(basename "$IPK")"
  echo "sha256:   $(sha256sum "$IPK" | cut -d' ' -f1)"
  echo "domoticz: $DOMO_VERSION"
  echo "buildroot: $(cd "$TREE" && git describe --tags --always)"
  echo "repo:     $(cd "$REPO_DIR" && git describe --always --dirty)"
  echo "br-commit: $(cd "$TREE" && git rev-parse HEAD)"
  # Buildroot caches a git checkout as a tarball, so the build tree has no .git
  # and the tag name alone is not provenance. The archive hash is: it covers the
  # superproject AND the five submodule revisions the gitlinks pinned.
  echo "domoticz-src: $(sha256sum "$TREE/dl/domoticz/domoticz-$DOMO_VERSION-git"*.tar.gz 2>/dev/null | head -1 | cut -d" " -f1 || echo unknown)"
  echo "build-image: ${HOMEAGENT_SMHUB_IMAGE:-milkvtech/milkv-duo:latest}"
  echo "build-image-digest: $(docker image inspect --format '{{index .RepoDigests 0}}' "${HOMEAGENT_SMHUB_IMAGE:-milkvtech/milkv-duo:latest}" 2>/dev/null || echo unknown)"
  echo "http-port: $HTTP_PORT"
  echo "required-os: $PKG_OS_MIN"
  echo "bundled:  ${BUNDLE[*]##*/}"
  echo "from-rootfs: $(printf '%s\n' "$DEVICE_LIBS" | tr '\n' ' ')"
  echo "--- device profile this ipk was cut against ---"
  printf '%s\n' "$DEVICE_PROFILE"
} | tee "$OUT_DIR/$(basename "$IPK").manifest.txt"
