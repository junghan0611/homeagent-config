#!/usr/bin/env bash
# HomeAgent Config - 프로젝트 CLI
# Usage: ./run.sh <command> [args]

set -e

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YOCTO_DIR="${SCRIPT_DIR}/yocto"
SOURCES_DIR="${YOCTO_DIR}/sources"
BUILD_DIR="${YOCTO_DIR}/build"

help() {
    echo -e "${CYAN}HomeAgent Config${NC} - RPi5 + Yocto + Hailo AI 플랫폼"
    echo ""
    echo "Usage: ./run.sh <command> [args]"
    echo ""
    echo -e "${GREEN}개발 환경:${NC}"
    echo "  shell           Yocto FHS 빌드 환경 진입 (nix run)"
    echo "  status          레이어 브랜치 상태 확인"
    echo ""
    echo -e "${GREEN}레이어 설정:${NC}"
    echo "  layers          레이어 클론/링크 (setup-layers.sh)"
    echo "  layers --link   기존 클론 심볼릭 링크"
    echo ""
    echo -e "${GREEN}빌드:${NC}"
    echo "  build [target]  Yocto 빌드 (기본: core-image-weston)"
    echo "  clean           빌드 캐시 정리"
    echo ""
    echo -e "${GREEN}이슈 관리 (br):${NC}"
    echo "  issues          이슈 목록"
    echo "  issue <id>      이슈 상세"
    echo ""
    echo -e "${GREEN}Git:${NC}"
    echo "  diff            변경사항 확인"
    echo "  commit          커밋 (br sync 포함)"
    echo ""
    echo "Examples:"
    echo "  ./run.sh shell              # FHS 환경 진입 후 bitbake"
    echo "  ./run.sh status             # 레이어 브랜치 확인"
    echo "  ./run.sh build              # core-image-weston 빌드"
    echo ""
}

cmd_shell() {
    echo -e "${GREEN}[SHELL]${NC} Yocto FHS 빌드 환경 진입..."
    cd "$SCRIPT_DIR"
    nix run
}

cmd_status() {
    echo -e "${CYAN}=== 레이어 브랜치 상태 ===${NC}"
    cd "$SOURCES_DIR"
    for dir in poky meta-openembedded meta-clang meta-raspberrypi; do
        if [[ -d "$dir" ]]; then
            printf "  %-20s: " "$dir"
            cd "$dir" && git branch --show-current && cd ..
        fi
    done
    # meta-hailo는 심볼릭 링크일 수 있음
    if [[ -L "meta-hailo" ]]; then
        local target=$(readlink -f meta-hailo)
        printf "  %-20s: " "meta-hailo"
        cd "$target" && git branch --show-current
    elif [[ -d "meta-hailo" ]]; then
        printf "  %-20s: " "meta-hailo"
        cd meta-hailo && git branch --show-current
    fi
}

cmd_layers() {
    echo -e "${GREEN}[LAYERS]${NC} 레이어 설정..."
    cd "$SOURCES_DIR"
    ./setup-layers.sh "$@"
}

cmd_build() {
    local target="${1:-core-image-weston}"
    echo -e "${GREEN}[BUILD]${NC} bitbake $target"
    echo -e "${YELLOW}[INFO]${NC} FHS 환경에서 실행해야 합니다:"
    echo ""
    echo "  cd $BUILD_DIR"
    echo "  source ../sources/poky/oe-init-build-env ."
    echo "  bitbake $target"
    echo ""
}

cmd_clean() {
    echo -e "${GREEN}[CLEAN]${NC} 빌드 캐시 정리..."
    rm -rf "${BUILD_DIR}/tmp-glibc" "${BUILD_DIR}/cache" "${BUILD_DIR}/sstate-cache" 2>/dev/null || true
    echo -e "${GREEN}[DONE]${NC} 정리 완료"
}

cmd_issues() {
    br list
}

cmd_issue() {
    br show "$1"
}

cmd_diff() {
    git -C "$SCRIPT_DIR" status
    echo ""
    git -C "$SCRIPT_DIR" diff --stat
}

cmd_commit() {
    br sync --flush-only 2>/dev/null || true
    echo -e "${YELLOW}[INFO]${NC} git add/commit 직접 실행하세요"
    git -C "$SCRIPT_DIR" status
}

# 메인
case "${1:-help}" in
    help|--help|-h|"")
        help
        ;;
    shell)
        cmd_shell
        ;;
    status)
        cmd_status
        ;;
    layers)
        shift
        cmd_layers "$@"
        ;;
    build)
        shift
        cmd_build "$@"
        ;;
    clean)
        cmd_clean
        ;;
    issues)
        cmd_issues
        ;;
    issue)
        cmd_issue "$2"
        ;;
    diff)
        cmd_diff
        ;;
    commit)
        cmd_commit
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} 알 수 없는 명령: $1"
        echo "도움말: ./run.sh help"
        exit 1
        ;;
esac
