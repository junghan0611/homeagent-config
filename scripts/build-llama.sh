#!/usr/bin/env bash
#
# build-llama.sh — llama.cpp NDK arm64 크로스빌드
#
# HomeAgent sLLM 온디바이스 추론을 위한 llama-cli arm64 바이너리.
# build-otbr.sh 패턴 참고.
#
# 사용법:
#   nix develop .#dev --impure --command bash scripts/build-llama.sh
#
# 또는 run.sh에서:
#   ./run.sh llama-build
#
# 요구사항:
#   - nix devShell (.#dev) — NDK r27, cmake 포함
#   - ~/repos/3rd/llama.cpp — git clone (depth 1이면 충분)
#
# 산출물:
#   dist/llama-arm64/llama-cli      (추론 CLI)
#   dist/llama-arm64/llama-server   (HTTP 서버, 선택)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LLAMA_SRC="${LLAMA_SRC:-$HOME/repos/3rd/llama.cpp}"
BUILD_DIR="$LLAMA_SRC/build-android"
OUT_DIR="$PROJECT_DIR/dist/llama-arm64"

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

if [ ! -d "$LLAMA_SRC" ]; then
    echo "llama.cpp not found at $LLAMA_SRC"
    echo "  git clone --depth 1 https://github.com/ggml-org/llama.cpp.git $LLAMA_SRC"
    exit 1
fi

log() { echo "[llama-build] $1"; }

# ─── 버전 정보 ────────────────────────────────────────────
log "=== 버전 ==="
log "NDK: $(basename "$NDK_DIR")"
log "llama.cpp: $(cd "$LLAMA_SRC" && git log --oneline -1)"
echo ""

# ─── 클린 빌드 ────────────────────────────────────────────
if [ -d "$BUILD_DIR" ]; then
    log "기존 build-android/ 삭제"
    rm -rf "$BUILD_DIR"
fi

# ─── CMake Configure ──────────────────────────────────────
#
# 핵심 옵션:
#   GGML_CUDA=OFF     → ARM 타겟, GPU 없음
#   GGML_OPENMP=OFF   → NDK OpenMP 링크 이슈 회피
#   GGML_CPU_AARCH64=ON → ARM NEON/dotprod/i8mm 최적화
#   LLAMA_CURL=OFF    → libcurl 의존 없음 (오프라인 장비)
#   BUILD_SHARED_LIBS=OFF → static 링크 (단일 바이너리)
#
log "=== CMake Configure ==="
cmake -B "$BUILD_DIR" -S "$LLAMA_SRC" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-28 \
  -DANDROID_STL=c++_static \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DGGML_CUDA=OFF \
  -DGGML_OPENMP=OFF \
  -DGGML_CPU_AARCH64=ON \
  -DLLAMA_CURL=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_BUILD_TYPE=Release

# ─── Build ─────────────────────────────────────────────────
log "=== Build llama-cli (j$(nproc)) ==="
cmake --build "$BUILD_DIR" --target llama-cli -j"$(nproc)"

# llama-server도 빌드 (선택 — HTTP API로 Go 통합에 유용)
log "=== Build llama-server ==="
cmake --build "$BUILD_DIR" --target llama-server -j"$(nproc)" 2>/dev/null || {
    log "llama-server 빌드 실패 (curl 의존 가능). llama-cli만 사용."
}

# ─── Strip & Copy ─────────────────────────────────────────
log "=== Strip & 복사 ==="
mkdir -p "$OUT_DIR"

if [ -f "$BUILD_DIR/bin/llama-cli" ]; then
    cp "$BUILD_DIR/bin/llama-cli" "$OUT_DIR/llama-cli"
    "$STRIP" "$OUT_DIR/llama-cli"
    log "✅ llama-cli"
fi

if [ -f "$BUILD_DIR/bin/llama-server" ]; then
    cp "$BUILD_DIR/bin/llama-server" "$OUT_DIR/llama-server"
    "$STRIP" "$OUT_DIR/llama-server"
    log "✅ llama-server"
fi

# ─── 검증 ──────────────────────────────────────────────────
log "=== 결과 ==="
file "$OUT_DIR"/*
ls -lh "$OUT_DIR"/*
log ""
log "배포:"
log "  adb push $OUT_DIR/llama-cli /data/local/tmp/llama/"
log "  adb push homeagent-intent-q4km.gguf /data/local/tmp/llama/"
log ""
log "추론 테스트:"
log "  adb shell '/data/local/tmp/llama/llama-cli \\"
log "    -m /data/local/tmp/llama/homeagent-intent-q4km.gguf \\"
log "    -p \"거실 불 켜줘\" --n-predict 80 --temp 0'"
