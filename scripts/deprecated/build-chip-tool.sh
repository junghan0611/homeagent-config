#!/usr/bin/env bash
#
# chip-tool CLI 크로스 컴파일 (Docker 기반)
# 타겟: linux-arm64-chip-tool-clang (RPi5 aarch64)
# 원본: kyungdong-rockchip/matter/build-chiptool-cli.sh
#
# 사용법: ./scripts/build-chip-tool.sh [clone|build|all]
#   clone  - connectedhomeip 소스 클론
#   build  - Docker 크로스 컴파일
#   all    - clone + build (기본)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MATTER_DIR="${PROJECT_DIR}/matter"
CHIP_SRC="${MATTER_DIR}/connectedhomeip"
CHIP_VERSION="v1.4.0.0"
BUILD_TARGET="linux-arm64-chip-tool-clang"
OUTPUT_DIR="${MATTER_DIR}/bin"
# tag 81 = Ubuntu 22.04 sysroot (glib 2.72) → Yocto Scarthgap glib 2.78 호환
# tag 177 = Ubuntu 24.04 sysroot (glib 2.80) → Scarthgap 비호환 (g_once_init_enter_pointer 누락)
DOCKER_IMAGE="ghcr.io/project-chip/chip-build-crosscompile:81"

cmd_clone() {
    if [[ -d "$CHIP_SRC" ]]; then
        echo -e "${YELLOW}[SKIP]${NC} connectedhomeip 이미 존재: $CHIP_SRC"
        echo "  삭제 후 재클론: rm -rf $CHIP_SRC"
        return 0
    fi

    echo -e "${CYAN}[CLONE]${NC} connectedhomeip ${CHIP_VERSION}..."
    echo "  (depth=1, submodule init 포함 - 수 분 소요)"
    echo ""

    git clone --depth 1 --branch "$CHIP_VERSION" \
        https://github.com/project-chip/connectedhomeip.git "$CHIP_SRC"

    cd "$CHIP_SRC"
    echo -e "${CYAN}[SUBMODULE]${NC} 서브모듈 초기화..."
    git submodule update --init --recursive --depth 1

    echo -e "${GREEN}[OK]${NC} 클론 완료"
}

cmd_build() {
    if [[ ! -d "$CHIP_SRC" ]]; then
        echo -e "${RED}[ERROR]${NC} connectedhomeip 소스 없음"
        echo "  클론: ./scripts/build-chip-tool.sh clone"
        exit 1
    fi

    if ! command -v docker &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} Docker 필요"
        echo "  NixOS: nix-shell -p docker"
        exit 1
    fi

    mkdir -p "$OUTPUT_DIR"

    cat << EOF

${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
  chip-tool 크로스 컴파일 (Docker)
${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
  Target:  ${BUILD_TARGET}
  SDK:     ${CHIP_VERSION}
  Output:  ${OUTPUT_DIR}/chip-tool
  Docker:  ${DOCKER_IMAGE}
${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

EOF

    # Docker 이미지 확인
    if ! docker image inspect "$DOCKER_IMAGE" &>/dev/null; then
        echo -e "${YELLOW}[INFO]${NC} Docker 이미지 다운로드 (~5GB)..."
        docker pull "$DOCKER_IMAGE"
    fi

    local start_time
    start_time=$(date +%s)

    echo -e "${CYAN}[BUILD]${NC} Docker 빌드 시작..."

    local uid gid
    uid=$(id -u)
    gid=$(id -g)

    docker run --rm \
        -v "$CHIP_SRC:/workspace" \
        -w /workspace \
        "$DOCKER_IMAGE" \
        bash -c "
            set -e
            git config --global --add safe.directory '*'
            source scripts/activate.sh
            echo '=== ARM64 크로스 컴파일 ==='
            ./scripts/build/build_examples.py --target $BUILD_TARGET build
            echo '=== 권한 복원 ==='
            chown -R ${uid}:${gid} /workspace/out /workspace/.environment 2>/dev/null || true
        "

    local end_time elapsed minutes seconds
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    minutes=$((elapsed / 60))
    seconds=$((elapsed % 60))

    # 바이너리 복사
    local binary
    binary=$(find "$CHIP_SRC/out/$BUILD_TARGET" -name "chip-tool" -type f 2>/dev/null | sed -n '1p')

    if [[ -n "$binary" && -f "$binary" ]]; then
        cp "$binary" "$OUTPUT_DIR/chip-tool"
        chmod +x "$OUTPUT_DIR/chip-tool"

        # sysroot에서 번들 라이브러리 추출 (Yocto에 없을 수 있는 것들)
        echo -e "${CYAN}[LIB]${NC} 번들 라이브러리 추출..."
        mkdir -p "$OUTPUT_DIR/lib"
        local sysroot_lib="/opt/ubuntu-22.04.1-aarch64-sysroot/lib/aarch64-linux-gnu"
        local bundle_libs="libatomic.so.1"
        for lib in $bundle_libs; do
            docker run --rm "$DOCKER_IMAGE" \
                cat "${sysroot_lib}/${lib}" > "$OUTPUT_DIR/lib/${lib}" 2>/dev/null \
                && echo "  추출: ${lib}" || echo "  건너뜀: ${lib}"
        done

        echo ""
        echo -e "${GREEN}[OK]${NC} 빌드 완료! (${minutes}m ${seconds}s)"
        echo -e "  바이너리: ${OUTPUT_DIR}/chip-tool"
        echo -e "  라이브러리: ${OUTPUT_DIR}/lib/"
        ls -lh "$OUTPUT_DIR/chip-tool"
        ls -lh "$OUTPUT_DIR/lib/" 2>/dev/null || true
        file "$OUTPUT_DIR/chip-tool"
        echo ""
        echo "배포: ./scripts/deploy-chip-tool.sh [IP]"
    else
        echo -e "${RED}[ERROR]${NC} 바이너리를 찾을 수 없습니다"
        find "$CHIP_SRC/out/" -name "*chip*" -type f 2>/dev/null
        exit 1
    fi
}

# 메인
case "${1:-all}" in
    clone)
        cmd_clone
        ;;
    build)
        cmd_build
        ;;
    all)
        cmd_clone
        cmd_build
        ;;
    *)
        echo "Usage: $0 [clone|build|all]"
        exit 1
        ;;
esac
