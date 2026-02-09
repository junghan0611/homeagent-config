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
    echo "  bb-cmd <args>   bitbake 명령 직접 실행 (예: -c cleansstate ncurses-native)"
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
    echo -e "${GREEN}npm 레시피 (FHS 환경 내에서):${NC}"
    echo "  npm-shrinkwrap <pkg> devtool로 npm-shrinkwrap.json 생성"
    echo "                       pkg: zigbee2mqtt | matterjs-server"
    echo "  npm-build <pkg>     bitbake 빌드 검증"
    echo ""
    echo -e "${GREEN}Go 앱:${NC}"
    echo "  go-build        Go 크로스 컴파일 (aarch64 정적 바이너리)"
    echo "  go-deploy [IP]  RPi5에 배포"
    echo "  go-test [IP]    RPi5 health check 테스트"
    echo "  go-dev [args]   로컬 개발 실행"
    echo ""
    echo -e "${GREEN}펌웨어/Matter:${NC}"
    echo "  flash-rcp [dev] ZBDongle-E Thread RCP 펌웨어 플래시"
    echo "  build-chip-tool  chip-tool 크로스 컴파일 (Docker)"
    echo "  deploy-chip-tool [IP]  chip-tool RPi5 배포"
    echo ""
    echo -e "${GREEN}디바이스:${NC}"
    echo "  ssh [IP] [cmd]  RPi5 SSH 접속/명령 실행"
    echo "  setup-key [IP]  SSH 공개키 최초 등록 (비밀번호 입력)"
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
    nix develop
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
        exec nix run .#yocto -- -c "export HOMEAGENT_FHS=1 && $SCRIPT_DIR/run.sh bb $target"
    fi
    echo -e "${GREEN}[BUILD]${NC} bitbake $target"
    cd "$BUILD_DIR"
    source ../sources/poky/oe-init-build-env . >/dev/null 2>&1
    bitbake "$target"
}

cmd_bb_cmd() {
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}[ERROR]${NC} bitbake 인자를 지정하세요"
        echo "  예: ./run.sh bb-cmd -c cleansstate ncurses-native parted-native"
        echo "  예: ./run.sh bb-cmd -e nodejs"
        exit 1
    fi
    if ! in_fhs; then
        echo -e "${YELLOW}[INFO]${NC} FHS 환경 진입 후 실행..."
        cd "$SCRIPT_DIR"
        exec nix run .#yocto -- -c "export HOMEAGENT_FHS=1 && $SCRIPT_DIR/run.sh bb-cmd $*"
    fi
    echo -e "${GREEN}[BITBAKE]${NC} bitbake $*"
    cd "$BUILD_DIR"
    source ../sources/poky/oe-init-build-env . >/dev/null 2>&1
    bitbake "$@"
}

cmd_bb_clean() {
    local target="${1:-core-image-weston}"
    echo -e "${GREEN}[CLEAN BUILD]${NC} bitbake $target (클린)"
    echo -e "${YELLOW}[INFO]${NC} tmp-glibc 삭제 중..."
    rm -rf "${BUILD_DIR}/tmp-glibc" 2>/dev/null || true
    if ! in_fhs; then
        echo -e "${YELLOW}[INFO]${NC} FHS 환경 진입 후 빌드..."
        cd "$SCRIPT_DIR"
        exec nix run .#yocto -- -c "export HOMEAGENT_FHS=1 && $SCRIPT_DIR/run.sh bb-clean $target"
    fi
    cd "$BUILD_DIR"
    source ../sources/poky/oe-init-build-env . >/dev/null 2>&1
    bitbake "$target"
}

cmd_bb_resume() {
    if ! in_fhs; then
        echo -e "${YELLOW}[INFO]${NC} FHS 환경 진입 후 빌드..."
        cd "$SCRIPT_DIR"
        exec nix run .#yocto -- -c "export HOMEAGENT_FHS=1 && $SCRIPT_DIR/run.sh bb-resume"
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
    if command -v bmaptool &>/dev/null; then
        sudo bmaptool copy "${IMAGE_DIR}/${IMAGE_NAME}" "$device"
    else
        # bmaptool이 없으면 nix-shell로 실행
        nix-shell -p bmaptool --run "sudo bmaptool copy '${IMAGE_DIR}/${IMAGE_NAME}' '$device'"
    fi
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

SSH_KEY="${SCRIPT_DIR}/.sshkey/id_ed25519"
DEVICE_IP_FILE="${SCRIPT_DIR}/.current-device-ip"
SSH_OPTS="-o StrictHostKeyChecking=no -o LogLevel=ERROR"

get_device_ip() {
    local arg_ip="$1"
    if [[ "$arg_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$arg_ip"
        return
    fi
    if [[ -f "$DEVICE_IP_FILE" ]]; then
        cat "$DEVICE_IP_FILE"
    else
        echo ""
    fi
}

check_ssh_key() {
    # 1. 로컬 키 존재 확인
    if [[ ! -f "$SSH_KEY" ]]; then
        echo -e "${RED}[ERROR]${NC} SSH 키 없음: $SSH_KEY"
        echo "  키 생성: ssh-keygen -t ed25519 -f $SSH_KEY -C homeagent-deploy"
        exit 1
    fi

    # 2. 권한 확인 (600 필요)
    local perms
    perms=$(stat -c %a "$SSH_KEY" 2>/dev/null || stat -f %Lp "$SSH_KEY")
    if [[ "$perms" != "600" && "$perms" != "400" ]]; then
        chmod 600 "$SSH_KEY"
        echo -e "${YELLOW}[INFO]${NC} SSH 키 권한 수정됨 (600)"
    fi
}

# SSH 공개키 최초 등록 (비밀번호 입력 필요)
cmd_setup_key() {
    local IP=$(get_device_ip "$1")
    if [[ -z "$IP" ]]; then
        echo -e "${RED}[ERROR]${NC} IP를 지정하세요"
        echo "  ./run.sh setup-key 192.168.0.163"
        exit 1
    fi

    check_ssh_key

    local PUBKEY="${SSH_KEY}.pub"

    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}  SSH 공개키 설정${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo "대상: $IP"
    echo ""

    # 공개키 존재 확인/생성
    if [[ ! -f "$PUBKEY" ]]; then
        echo -e "${YELLOW}[INFO]${NC} 공개키 생성 중..."
        ssh-keygen -y -f "$SSH_KEY" >"$PUBKEY" 2>/dev/null
        if [[ ! -f "$PUBKEY" ]]; then
            echo -e "${RED}[ERROR]${NC} 공개키 생성 실패"
            exit 1
        fi
    fi

    # 이미 키가 등록되어 있는지 확인
    if ssh -i "$SSH_KEY" $SSH_OPTS -o BatchMode=yes -o ConnectTimeout=3 root@"$IP" "echo ok" &>/dev/null; then
        echo -e "${GREEN}[OK]${NC} SSH 키 이미 등록됨"
        return 0
    fi

    # known_hosts 초기화 (이전 키 충돌 방지)
    echo -e "${YELLOW}[INFO]${NC} known_hosts 초기화..."
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP" 2>/dev/null || true

    echo -e "${YELLOW}[INFO]${NC} 비밀번호 입력 필요 (기본: homeagent)"
    echo ""

    # 수동 복사 (OpenSSH)
    cat "$PUBKEY" | ssh \
        -o StrictHostKeyChecking=no \
        root@"$IP" \
        "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

    # 확인
    if ssh -i "$SSH_KEY" $SSH_OPTS -o BatchMode=yes -o ConnectTimeout=3 root@"$IP" "echo ok" &>/dev/null; then
        echo ""
        echo -e "${GREEN}[OK]${NC} SSH 키 등록 완료!"
        echo "  이제 비밀번호 없이 접속 가능: ./run.sh ssh"
    else
        echo -e "${RED}[ERROR]${NC} SSH 키 등록 실패"
        echo "  수동 확인: ssh root@$IP 'cat ~/.ssh/authorized_keys'"
        exit 1
    fi
}

cmd_ssh() {
    local first_arg="$1"
    local IP CMD

    if [[ "$first_arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        IP="$first_arg"
        shift
        CMD="$*"
    else
        IP=$(get_device_ip)
        CMD="$*"
    fi

    if [[ -z "$IP" ]]; then
        echo -e "${RED}[ERROR]${NC} 디바이스 IP가 설정되지 않았습니다."
        echo "  ./run.sh set-ip <ip>"
        echo "  또는: ./run.sh ssh 192.168.0.163 [cmd]"
        exit 1
    fi

    check_ssh_key

    if [[ -z "$CMD" ]]; then
        ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP"
    else
        ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" "$CMD"
    fi
}

META_DIR="${YOCTO_DIR}/meta-homeagent/recipes-connectivity"

# npm 패키지명 → 레시피 디렉토리 매핑
_npm_recipe_info() {
    local pkg="$1"
    case "$pkg" in
        zigbee2mqtt)
            NPM_NAME="zigbee2mqtt"
            NPM_VERSION="2.8.0"
            RECIPE_DIR="${META_DIR}/zigbee2mqtt"
            SHRINKWRAP_DIR="${RECIPE_DIR}/zigbee2mqtt"
            ;;
        matterjs-server)
            NPM_NAME="matter-server"
            NPM_VERSION="0.3.5"
            RECIPE_DIR="${META_DIR}/matterjs-server"
            SHRINKWRAP_DIR="${RECIPE_DIR}/matterjs-server"
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} 알 수 없는 패키지: $pkg"
            echo "  지원: zigbee2mqtt, matterjs-server"
            exit 1
            ;;
    esac
}

cmd_npm_shrinkwrap() {
    local pkg="$1"
    if [[ -z "$pkg" ]]; then
        echo -e "${RED}[ERROR]${NC} 패키지를 지정하세요"
        echo "  ./run.sh npm-shrinkwrap zigbee2mqtt"
        echo "  ./run.sh npm-shrinkwrap matterjs-server"
        exit 1
    fi

    _npm_recipe_info "$pkg"

    if ! in_fhs; then
        echo -e "${YELLOW}[INFO]${NC} FHS 환경 진입 후 실행..."
        cd "$SCRIPT_DIR"
        exec nix run .#yocto -- -c "export HOMEAGENT_FHS=1 && $SCRIPT_DIR/run.sh npm-shrinkwrap $pkg"
    fi

    echo -e "${GREEN}[NPM-SHRINKWRAP]${NC} devtool로 ${NPM_NAME}@${NPM_VERSION} shrinkwrap 생성..."

    cd "$BUILD_DIR"
    source ../sources/poky/oe-init-build-env . >/dev/null 2>&1

    # 기존 workspace에 있으면 제거 후 재생성
    if devtool status 2>/dev/null | grep -q "$NPM_NAME"; then
        echo -e "${YELLOW}[INFO]${NC} 기존 workspace 제거..."
        devtool reset "$NPM_NAME" 2>/dev/null || true
    fi

    echo -e "${CYAN}[1/3]${NC} devtool add 실행 (npm registry에서 다운로드)..."
    devtool add "npm://registry.npmjs.org;package=${NPM_NAME};version=${NPM_VERSION}"

    local GENERATED="workspace/recipes/${NPM_NAME}/${NPM_NAME}/npm-shrinkwrap.json"
    if [[ ! -f "$GENERATED" ]]; then
        echo -e "${RED}[ERROR]${NC} shrinkwrap 생성 실패: $GENERATED"
        exit 1
    fi

    echo -e "${CYAN}[2/3]${NC} shrinkwrap 복사..."
    cp "$GENERATED" "$SHRINKWRAP_DIR/npm-shrinkwrap.json"
    local lines
    lines=$(wc -l < "$SHRINKWRAP_DIR/npm-shrinkwrap.json")
    echo -e "${GREEN}[OK]${NC} ${SHRINKWRAP_DIR}/npm-shrinkwrap.json (${lines} lines)"

    # devtool에서 생성한 레시피의 LIC_FILES_CHKSUM도 확인
    echo -e "${CYAN}[3/3]${NC} LIC_FILES_CHKSUM 확인..."
    local generated_bb="workspace/recipes/${NPM_NAME}/${NPM_NAME}_${NPM_VERSION}.bb"
    if [[ -f "$generated_bb" ]]; then
        local lic_line
        lic_line=$(grep "LIC_FILES_CHKSUM" "$generated_bb" || true)
        if [[ -n "$lic_line" ]]; then
            echo -e "${CYAN}[INFO]${NC} devtool 생성 레시피의 LIC_FILES_CHKSUM:"
            echo "  $lic_line"
            echo "  → 기존 레시피와 비교해서 필요시 업데이트하세요"
        fi
    fi

    echo -e "${GREEN}[DONE]${NC} ${pkg} npm-shrinkwrap.json 생성 완료"

    # workspace 정리
    devtool reset "$NPM_NAME" 2>/dev/null || true
}

cmd_npm_build() {
    local pkg="$1"
    if [[ -z "$pkg" ]]; then
        echo -e "${RED}[ERROR]${NC} 패키지를 지정하세요"
        echo "  ./run.sh npm-build zigbee2mqtt"
        echo "  ./run.sh npm-build matterjs-server"
        exit 1
    fi

    _npm_recipe_info "$pkg"

    if ! in_fhs; then
        echo -e "${YELLOW}[INFO]${NC} FHS 환경 진입 후 빌드..."
        cd "$SCRIPT_DIR"
        exec nix run .#yocto -- -c "export HOMEAGENT_FHS=1 && $SCRIPT_DIR/run.sh npm-build $pkg"
    fi

    # placeholder 체크
    if grep -q "PLACEHOLDER" "$SHRINKWRAP_DIR/npm-shrinkwrap.json" 2>/dev/null; then
        echo -e "${RED}[ERROR]${NC} npm-shrinkwrap.json이 placeholder입니다"
        echo "  먼저 실행: ./run.sh npm-shrinkwrap $pkg"
        exit 1
    fi

    echo -e "${GREEN}[NPM-BUILD]${NC} bitbake $pkg..."
    cd "$BUILD_DIR"
    source ../sources/poky/oe-init-build-env . >/dev/null 2>&1
    bitbake "$pkg"
}

cmd_go_build() {
    echo -e "${GREEN}[GO-BUILD]${NC} aarch64 정적 바이너리 빌드..."
    cd "$SCRIPT_DIR/go"
    local ver
    ver=$(git -C "$SCRIPT_DIR" describe --tags --always --dirty 2>/dev/null || echo "dev")
    GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
      go build -ldflags="-s -w -X main.version=${ver}" \
      -o bin/homeagent ./cmd/homeagent
    echo -e "${GREEN}[DONE]${NC} go/bin/homeagent ($(ls -lh bin/homeagent | awk '{print $5}'))"
    file bin/homeagent
}

cmd_go_deploy() {
    local IP=$(get_device_ip "$1")
    if [[ -z "$IP" ]]; then
        echo -e "${RED}[ERROR]${NC} IP를 지정하세요"
        echo "  ./run.sh go-deploy 192.168.0.163"
        exit 1
    fi

    local BIN="$SCRIPT_DIR/go/bin/homeagent"
    if [[ ! -f "$BIN" ]]; then
        echo -e "${YELLOW}[INFO]${NC} 바이너리 없음, 빌드 먼저 실행..."
        cmd_go_build
    fi

    check_ssh_key

    echo -e "${GREEN}[GO-DEPLOY]${NC} $IP 에 배포..."
    ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" "mkdir -p /opt/homeagent"
    scp -i "$SSH_KEY" $SSH_OPTS "$BIN" root@"$IP":/opt/homeagent/homeagent
    ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" "chmod +x /opt/homeagent/homeagent"

    echo -e "${CYAN}[VERIFY]${NC} 버전 확인:"
    ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" "/opt/homeagent/homeagent -version"
    echo -e "${GREEN}[DONE]${NC} 배포 완료"
}

cmd_go_test() {
    local IP=$(get_device_ip "$1")
    if [[ -z "$IP" ]]; then
        echo -e "${RED}[ERROR]${NC} IP를 지정하세요"
        echo "  ./run.sh go-test 192.168.0.163"
        exit 1
    fi

    check_ssh_key

    echo -e "${GREEN}[GO-TEST]${NC} $IP health check..."
    local result
    result=$(ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" "wget -qO- http://localhost:8080/healthz" 2>&1) || {
        echo -e "${RED}[FAIL]${NC} health check 실패 (서버가 실행 중인지 확인)"
        echo "  시작: ./run.sh ssh $IP '/opt/homeagent/homeagent &'"
        exit 1
    }
    echo -e "${GREEN}[OK]${NC} $result"
}

cmd_go_dev() {
    cd "$SCRIPT_DIR/go"
    go run ./cmd/homeagent "$@"
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
    bb-cmd)
        shift
        cmd_bb_cmd "$@"
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
        shift
        cmd_ssh "$@"
        ;;
    setup-key)
        cmd_setup_key "$2"
        ;;
    set-ip)
        cmd_set_ip "$2"
        ;;
    npm-shrinkwrap)
        cmd_npm_shrinkwrap "$2"
        ;;
    npm-build)
        cmd_npm_build "$2"
        ;;
    go-build)
        cmd_go_build
        ;;
    go-deploy)
        cmd_go_deploy "$2"
        ;;
    go-test)
        cmd_go_test "$2"
        ;;
    go-dev)
        shift
        cmd_go_dev "$@"
        ;;
    flash-rcp)
        shift
        "${SCRIPT_DIR}/scripts/flash-thread-rcp.sh" "$@"
        ;;
    build-chip-tool)
        shift
        "${SCRIPT_DIR}/scripts/build-chip-tool.sh" "$@"
        ;;
    deploy-chip-tool)
        shift
        "${SCRIPT_DIR}/scripts/deploy-chip-tool.sh" "$@"
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} 알 수 없는 명령: $1"
        echo "도움말: ./run.sh help"
        exit 1
        ;;
esac
