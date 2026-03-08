#!/usr/bin/env bash
# Node.js glibc 번들 for Android arm64
# chip-tool 검증 패턴: ld-linux + glibc libs로 Android에서 glibc 바이너리 실행
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_DIR="${SCRIPT_DIR}/../dist/nodejs-android-bundle"
NODE_SRC="${SCRIPT_DIR}/../dist/homeagent-bundle-arm64/node/bin/node"

# nix store 경로 (nix build로 미리 fetch)
GLIBC="/nix/store/dmmzzfpnwis83x3xyk1ib2sg3yyki7f9-glibc-aarch64-unknown-linux-gnu-2.40-218"
GCCLIB="/nix/store/pnla0j7a2x52h3bw9nnq7d1qakar7jv6-aarch64-unknown-linux-gnu-gcc-14.3.0-lib"

echo "[nodejs-bundle] 번들 생성..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/lib"

cp "$NODE_SRC" "$BUNDLE_DIR/node"
cp -L "$GLIBC/lib/ld-linux-aarch64.so.1" "$BUNDLE_DIR/lib/"
cp -L "$GLIBC/lib/libc.so.6" "$BUNDLE_DIR/lib/"
cp -L "$GLIBC/lib/libm.so.6" "$BUNDLE_DIR/lib/"
cp -L "$GLIBC/lib/libdl.so.2" "$BUNDLE_DIR/lib/"
cp -L "$GLIBC/lib/libpthread.so.0" "$BUNDLE_DIR/lib/"
cp -L "$GCCLIB/lib/libstdc++.so.6" "$BUNDLE_DIR/lib/"
cp -L "$GCCLIB/lib/libgcc_s.so.1" "$BUNDLE_DIR/lib/"

cat > "$BUNDLE_DIR/run-node.sh" << 'EOF'
#!/system/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/lib/ld-linux-aarch64.so.1" --library-path "$DIR/lib" "$DIR/node" "$@"
EOF
chmod +x "$BUNDLE_DIR/run-node.sh"

echo "[nodejs-bundle] 완료: $(du -sh "$BUNDLE_DIR" | cut -f1)"
ls -lh "$BUNDLE_DIR/lib/"
