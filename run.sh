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
    echo "  shell           Yocto FHS 빌드 환경 진입 (nix develop --impure)"
    echo "  status          레이어 브랜치 상태 확인"
    echo ""
    echo -e "${GREEN}레이어 설정:${NC}"
    echo "  layers          레이어 클론/링크 (setup-layers.sh)"
    echo "  layers --link   기존 클론 심볼릭 링크"
    echo ""
    echo -e "${GREEN}빌드 (FHS 환경 내에서):${NC}"
    echo "  bb [target]     bitbake 빌드 (기본: core-image-weston)"
    echo "  bb-clean [target] 클린 빌드 (tmp-glibc 삭제 후 빌드)"
    echo "  bb-resume       이전 빌드 계속"
    echo "  clean           빌드 캐시 전체 정리 (tmp-glibc, cache, sstate)"
    echo ""
    echo -e "${GREEN}이슈 관리 (br):${NC}"
    echo "  issues          이슈 목록"
    echo "  issue <id>      이슈 상세"
    echo ""
    echo -e "${GREEN}이미지:${NC}"
    echo "  image           빌드된 이미지 정보"
    echo "  flash <device>  SD 카드 플래싱 (예: /dev/sda)"
    echo "  deploy <host>   원격 호스트로 이미지 전송 후 플래싱"
    echo ""
    echo -e "${GREEN}디바이스:${NC}"
    echo "  ssh             RPi5 SSH 접속"
    echo "  set-ip <ip>     디바이스 IP 설정"
    echo ""
    echo -e "${GREEN}Git:${NC}"
    echo "  diff            변경사항 확인"
    echo "  commit          커밋 (br sync 포함)"
    echo ""
    echo "Examples:"
    echo "  ./run.sh shell              # FHS 환경 진입"
    echo "  ./run.sh bb                 # (FHS 내) 빌드"
    echo "  ./run.sh bb-clean           # (FHS 내) 클린 빌드"
    echo "  ./run.sh status             # 레이어 브랜치 확인"
    echo "  ./run.sh image              # 빌드된 이미지 확인"
    echo "  ./run.sh flash /dev/sda     # SD 카드 플래싱"
    echo "  ./run.sh deploy 192.168.0.118  # 원격 플래싱"
    echo ""
}

cmd_shell() {
    echo -e "${GREEN}[SHELL]${NC} Yocto FHS 빌드 환경 진입..."
    cd "$SCRIPT_DIR"
    nix develop --impure
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

# FHS 환경 체크 (HOMEAGENT_FHS 환경 변수)
in_fhs() {
    [[ "${HOMEAGENT_FHS:-}" == "1" ]]
}

cmd_bb() {
    local target="${1:-core-image-weston}"
    if ! in_fhs; then
        echo -e "${YELLOW}[INFO]${NC} FHS 환경 진입 후 빌드..."
        cd "$SCRIPT_DIR"
        exec nix develop --impure --command "./run.sh bb $target"
    fi
    echo -e "${GREEN}[BUILD]${NC} bitbake $target"
    cd "$BUILD_DIR"
    source ../sources/poky/oe-init-build-env . >/dev/null 2>&1
    bitbake "$target"
}

cmd_bb_clean() {
    local target="${1:-core-image-weston}"
    echo -e "${GREEN}[CLEAN BUILD]${NC} bitbake $target (클린)"
    echo -e "${YELLOW}[INFO]${NC} tmp-glibc 삭제 중..."
    rm -rf "${BUILD_DIR}/tmp-glibc" 2>/dev/null || true
    if ! in_fhs; then
        echo -e "${YELLOW}[INFO]${NC} FHS 환경 진입 후 빌드..."
        cd "$SCRIPT_DIR"
        exec nix develop --impure --command "./run.sh bb $target"
    fi
    cd "$BUILD_DIR"
    source ../sources/poky/oe-init-build-env . >/dev/null 2>&1
    bitbake "$target"
}

cmd_bb_resume() {
    if ! in_fhs; then
        echo -e "${YELLOW}[INFO]${NC} FHS 환경 진입 후 빌드..."
        cd "$SCRIPT_DIR"
        exec nix develop --impure --command "./run.sh bb-resume"
    fi
    echo -e "${GREEN}[RESUME]${NC} 이전 빌드 계속..."
    cd "$BUILD_DIR"
    source ../sources/poky/oe-init-build-env . >/dev/null 2>&1
    bitbake
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

IMAGE_DIR="${BUILD_DIR}/tmp-glibc/deploy/images/raspberrypi5"
IMAGE_NAME="core-image-weston-raspberrypi5.rootfs.wic.bz2"

cmd_image() {
    echo -e "${CYAN}=== 빌드 이미지 정보 ===${NC}"
    if [[ -f "${IMAGE_DIR}/${IMAGE_NAME}" ]]; then
        ls -lh "${IMAGE_DIR}/${IMAGE_NAME}"
        echo ""
        echo -e "${GREEN}플래싱:${NC} ./run.sh flash /dev/sdX"
    else
        echo -e "${YELLOW}[INFO]${NC} 이미지가 없습니다. 빌드를 먼저 실행하세요."
        echo "  ./run.sh bb"
    fi
}

cmd_flash() {
    local device="$1"
    if [[ -z "$device" ]]; then
        echo -e "${RED}[ERROR]${NC} 디바이스를 지정하세요"
        echo "  예: ./run.sh flash /dev/sda"
        echo ""
        echo -e "${CYAN}현재 블록 디바이스:${NC}"
        lsblk -d -o NAME,SIZE,MODEL | grep -v loop
        exit 1
    fi
    if [[ ! -f "${IMAGE_DIR}/${IMAGE_NAME}" ]]; then
        echo -e "${RED}[ERROR]${NC} 이미지가 없습니다: ${IMAGE_NAME}"
        echo "  빌드를 먼저 실행하세요: ./run.sh bb"
        exit 1
    fi
    if [[ ! -b "$device" ]]; then
        echo -e "${RED}[ERROR]${NC} 블록 디바이스가 아닙니다: $device"
        exit 1
    fi
    echo -e "${YELLOW}[WARNING]${NC} $device 의 모든 데이터가 삭제됩니다!"
    echo -e "이미지: ${IMAGE_NAME}"
    read -p "계속하시겠습니까? (y/N) " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "취소됨"
        exit 0
    fi
    echo -e "${GREEN}[FLASH]${NC} bmaptool로 플래싱 중..."
    sudo bmaptool copy "${IMAGE_DIR}/${IMAGE_NAME}" "$device"
    echo -e "${GREEN}[DONE]${NC} 플래싱 완료. SD 카드를 분리하세요."
}

cmd_deploy() {
    local host="$1"
    local remote_device="${2:-/dev/sdb}"
    if [[ -z "$host" ]]; then
        echo -e "${RED}[ERROR]${NC} 호스트를 지정하세요"
        echo "  예: ./run.sh deploy 192.168.0.118"
        echo "  예: ./run.sh deploy 192.168.0.118 /dev/sdc"
        exit 1
    fi
    if [[ ! -f "${IMAGE_DIR}/${IMAGE_NAME}" ]]; then
        echo -e "${RED}[ERROR]${NC} 이미지가 없습니다: ${IMAGE_NAME}"
        echo "  빌드를 먼저 실행하세요: ./run.sh bb"
        exit 1
    fi
    local bmap_file="${IMAGE_DIR}/${IMAGE_NAME%.bz2}.bmap"

    echo -e "${GREEN}[DEPLOY]${NC} 원격 배포: $host -> $remote_device"
    echo ""

    # 이미지 전송
    echo -e "${CYAN}[1/3]${NC} 이미지 전송 중..."
    rsync -avhL --progress "${IMAGE_DIR}/${IMAGE_NAME}" "$host:/tmp/"
    if [[ -f "$bmap_file" ]]; then
        rsync -avhL "${bmap_file}" "$host:/tmp/"
    fi

    # 원격 디바이스 확인
    echo ""
    echo -e "${CYAN}[2/3]${NC} 원격 디바이스 확인..."
    ssh "$host" "lsblk $remote_device" || {
        echo -e "${RED}[ERROR]${NC} 디바이스를 찾을 수 없습니다: $remote_device"
        exit 1
    }

    echo ""
    echo -e "${YELLOW}[WARNING]${NC} $host:$remote_device 의 모든 데이터가 삭제됩니다!"
    read -p "계속하시겠습니까? (y/N) " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "취소됨"
        exit 0
    fi

    # 플래싱
    echo ""
    echo -e "${CYAN}[3/3]${NC} 플래싱 중..."
    ssh "$host" "nix-shell -p bmaptool --run 'sudo bmaptool copy /tmp/${IMAGE_NAME} $remote_device'"

    echo ""
    echo -e "${GREEN}[DONE]${NC} 원격 플래싱 완료. SD 카드를 분리하세요."
}

SSH_KEY="${SCRIPT_DIR}/.sshkey/id_rsa_sks_gateway"
DEVICE_IP_FILE="${SCRIPT_DIR}/.current-device-ip"

cmd_ssh() {
    if [[ ! -f "$DEVICE_IP_FILE" ]]; then
        echo -e "${RED}[ERROR]${NC} 디바이스 IP가 설정되지 않았습니다."
        echo "  ./run.sh set-ip <ip>"
        exit 1
    fi
    local ip=$(cat "$DEVICE_IP_FILE")
    if [[ ! -f "$SSH_KEY" ]]; then
        echo -e "${YELLOW}[INFO]${NC} SSH 키 없음, 기본 인증 사용"
        ssh root@"$ip"
    else
        ssh -i "$SSH_KEY" root@"$ip"
    fi
}

cmd_set_ip() {
    local ip="$1"
    if [[ -z "$ip" ]]; then
        echo -e "${RED}[ERROR]${NC} IP를 지정하세요"
        echo "  예: ./run.sh set-ip 192.168.0.163"
        exit 1
    fi
    echo "$ip" > "$DEVICE_IP_FILE"
    echo -e "${GREEN}[DONE]${NC} 디바이스 IP 설정: $ip"
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
    bb)
        shift
        cmd_bb "$@"
        ;;
    bb-clean)
        shift
        cmd_bb_clean "$@"
        ;;
    bb-resume)
        cmd_bb_resume
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
    image)
        cmd_image
        ;;
    flash)
        cmd_flash "$2"
        ;;
    deploy)
        cmd_deploy "$2" "$3"
        ;;
    ssh)
        cmd_ssh
        ;;
    set-ip)
        cmd_set_ip "$2"
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} 알 수 없는 명령: $1"
        echo "도움말: ./run.sh help"
        exit 1
        ;;
esac
