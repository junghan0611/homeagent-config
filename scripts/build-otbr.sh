#!/usr/bin/env bash
#
# build-otbr.sh — ot-br-posix NDK arm64 크로스빌드
#
# 재현 가능한 빌드 스크립트. nix devShell 안에서 실행.
#
# 사용법:
#   nix develop .#dev --impure --command bash scripts/build-otbr.sh
#
# 또는 run.sh에서:
#   ./run.sh otbr-build
#
# 요구사항:
#   - nix devShell (.#dev) — NDK r27, cmake 포함
#   - ~/repos/3rd/ot-br-posix — git clone + submodules
#
# 산출물:
#   dist/otbr-arm64/otbr-agent  (6.9MB, stripped)
#   dist/otbr-arm64/ot-ctl      (12KB, stripped)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OTBR_SRC="${OTBR_SRC:-$HOME/repos/3rd/ot-br-posix}"
BUILD_DIR="$OTBR_SRC/build-android"
OUT_DIR="$PROJECT_DIR/dist/otbr-arm64"
PATCH_DIR="$PROJECT_DIR/patches/ot-br-posix"

# ─── 검증 ──────────────────────────────────────────────────
if [ -z "${ANDROID_HOME:-}" ]; then
    echo "ERROR: ANDROID_HOME not set. Run inside nix devShell:"
    echo "  nix develop .#dev --impure --command bash $0"
    exit 1
fi

NDK_DIR=$(ls -d "$ANDROID_HOME/ndk"/*/ 2>/dev/null | head -1)
if [ -z "$NDK_DIR" ]; then
    echo "ERROR: NDK not found in $ANDROID_HOME/ndk/"
    exit 1
fi
TOOLCHAIN="$NDK_DIR/build/cmake/android.toolchain.cmake"
STRIP="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"

if [ ! -d "$OTBR_SRC" ]; then
    echo "ERROR: ot-br-posix not found at $OTBR_SRC"
    echo "  git clone --recurse-submodules https://github.com/openthread/ot-br-posix.git $OTBR_SRC"
    exit 1
fi

log() { echo "[otbr-build] $1"; }

# ─── 버전 정보 ────────────────────────────────────────────
log "=== 버전 ==="
log "NDK: $(basename "$NDK_DIR")"
log "ot-br-posix: $(cd "$OTBR_SRC" && git log --oneline -1)"
log "openthread:  $(cd "$OTBR_SRC/third_party/openthread/repo" && git log --oneline -1)"
echo ""

# ─── 패치 적용 ────────────────────────────────────────────
log "=== 패치 적용 ==="
for patch in "$PATCH_DIR"/*.patch; do
    [ -f "$patch" ] || continue
    PATCH_NAME=$(basename "$patch")
    APPLIED=false
    # ot-br-posix 루트에서 먼저 시도
    cd "$OTBR_SRC"
    if git apply --check "$patch" 2>/dev/null; then
        git apply "$patch"
        log "  적용 (ot-br-posix): $PATCH_NAME"
        APPLIED=true
    fi
    # openthread submodule에서 시도
    if [ "$APPLIED" = false ]; then
        cd "$OTBR_SRC/third_party/openthread/repo"
        if git apply --check "$patch" 2>/dev/null; then
            git apply "$patch"
            log "  적용 (openthread): $PATCH_NAME"
            APPLIED=true
        fi
    fi
    if [ "$APPLIED" = false ]; then
        log "  이미 적용됨: $PATCH_NAME"
    fi
done
cd "$OTBR_SRC"

# ─── 클린 빌드 ────────────────────────────────────────────
if [ -d "$BUILD_DIR" ]; then
    log "기존 build-android/ 삭제"
    rm -rf "$BUILD_DIR"
fi

# ─── CMake Configure ──────────────────────────────────────
#
# 핵심 옵션 설명:
#   OPENTHREAD_CONFIG_ANDROID_NDK_ENABLE=1  → cutils/properties.h 대신 sys/system_properties.h 사용
#   OT_ANDROID_NDK=ON                       → -lutil 링크 제외 (Android에 없음)
#   OTBR_MDNS=openthread                    → dns_sd.h (mDNSResponder) 불필요, OT core mDNS 사용
#   OTBR_BACKBONE_ROUTER=ON                 → Thread↔Infra mDNS 브릿징 (DUA_ROUTING=OFF로 netfilter 의존 제거)
#   OTBR_SRP_ADVERTISING_PROXY=OFF          → MDNS=openthread 시 OT_SRP_ADV_PROXY(자동ON)와 충돌 → OFF 필수
#   OTBR_DNSSD_DISCOVERY_PROXY=OFF          → MDNS 있으면 OT_DISCOVERY_PROXY(자동ON)와 충돌 → OFF 필수
#   ※ OT core proxy (OT_SRP_ADV_PROXY + OT_DISCOVERY_PROXY)가 자동으로 대체
#   OTBR_DBUS=OFF                           → Android에 dbus 없음
#   OT_TREL=OFF                             → DNS-SD 기반 TREL, 외부 mDNS 없이 불필요
#
log "=== CMake Configure ==="
cmake -B "$BUILD_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-35 \
  -DANDROID_STL=c++_static \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_CXX_FLAGS="-DOPENTHREAD_CONFIG_ANDROID_NDK_ENABLE=1 -DOPENTHREAD_POSIX_CONFIG_DAEMON_SOCKET_BASENAME=\\\"/data/local/tmp/ot-%s\\\"" \
  -DCMAKE_C_FLAGS="-DOPENTHREAD_CONFIG_ANDROID_NDK_ENABLE=1 -DOPENTHREAD_POSIX_CONFIG_DAEMON_SOCKET_BASENAME=\\\"/data/local/tmp/ot-%s\\\"" \
  -DOT_ANDROID_NDK=ON \
  -DBUILD_TESTING=OFF \
  -DOTBR_DBUS=OFF \
  -DOTBR_REST=ON \
  -DOTBR_WEB=OFF \
  -DOTBR_MDNS=openthread \
  -DOTBR_BACKBONE_ROUTER=ON \
  -DOTBR_DUA_ROUTING=OFF \
  -DOTBR_SRP_ADVERTISING_PROXY=OFF \
  -DOTBR_DNSSD_DISCOVERY_PROXY=OFF \
  -DOTBR_BORDER_ROUTING=ON \
  -DOTBR_BORDER_AGENT=ON \
  -DOT_SPINEL_RESET_CONNECTION=ON \
  -DOT_TREL=OFF \
  -DOT_MLR=ON \
  -DOT_SRP_SERVER=ON \
  -DOT_ECDSA=ON \
  -DOT_SERVICE=ON \
  -DOT_DUA=ON \
  -DOT_BORDER_ROUTING_NAT64=OFF \
  -DOTBR_INFRA_IF_NAME=wlan0 \
  -DOTBR_NO_AUTO_ATTACH=1

# ─── Build ─────────────────────────────────────────────────
log "=== Build (j$(nproc)) ==="
cmake --build "$BUILD_DIR" -j"$(nproc)"

# ─── Strip & Copy ─────────────────────────────────────────
log "=== Strip & 복사 ==="
mkdir -p "$OUT_DIR"

cp "$BUILD_DIR/src/agent/otbr-agent" "$OUT_DIR/otbr-agent"
cp "$BUILD_DIR/third_party/openthread/repo/src/posix/ot-ctl" "$OUT_DIR/ot-ctl"
"$STRIP" "$OUT_DIR/otbr-agent"
"$STRIP" "$OUT_DIR/ot-ctl"

# ─── 검증 ──────────────────────────────────────────────────
log "=== 결과 ==="
file "$OUT_DIR/otbr-agent"
file "$OUT_DIR/ot-ctl"
ls -lh "$OUT_DIR/otbr-agent" "$OUT_DIR/ot-ctl"
log ""
log "배포: adb push $OUT_DIR/otbr-agent /data/local/tmp/otbr/"
log "      adb push $OUT_DIR/ot-ctl /data/local/tmp/otbr/"
