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
PKG_OS_MIN="${HOMEAGENT_SMHUB_OS_MIN:-1.0.0}"

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

cat > "$WORK/data/etc/init.d/domoticz" <<'EOS'
#!/sbin/openrc-run

description="Domoticz home automation server"

# /opt/bin is not on PATH on this OS and the vendor's own services use absolute
# paths, so we do too.
command="/opt/domoticz/domoticz"
command_args="-www 8080 -sslwww 0 -userdata /opt/domoticz -wwwroot /opt/domoticz/www"
command_background=yes
pidfile="/run/domoticz.pid"
directory="/opt/domoticz"
# Libraries the vendor rootfs does not carry ride inside the package.
export LD_LIBRARY_PATH="/opt/domoticz/lib"

depend() {
	need net
	after mosquitto
}
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
  echo "bundled:  ${BUNDLE[*]##*/}"
  echo "from-rootfs: $(printf '%s\n' "$DEVICE_LIBS" | tr '\n' ' ')"
} | tee "$OUT_DIR/$(basename "$IPK").manifest.txt"
