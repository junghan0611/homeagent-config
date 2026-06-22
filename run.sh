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

# ============================================================================
# Tier-2 — 미니멀 허브 (Buildroot / SG2000) · 현재 주력 lane · NEW DEVICE WORK
# ----------------------------------------------------------------------------
# 새 보드(SMHUB Nano / Milk-V Duo S / THP23-ZB-X) bring-up 명령은 여기에 추가한다.
# origin lane(Yocto/Docker)과 섞지 말 것. 명명 규칙:
#   cmd_hub_build   — public Buildroot SDK 기준 이미지 빌드
#   cmd_hub_flash   — 보드 flash (SD / eMMC / U-Boot)
#   cmd_hub_radio   — 온보드 EFR32 감지 + 펌웨어 전환 (Zigbee NCP ↔ Thread RCP)
#   cmd_hub_status  — 보드 런타임 상태 (MQTT / Z2M / matter.js RSS 근거)
# 방향·acceptance: docs/TARGET_DEVICE.md · VERSION.md · NEXT.md
# 하드웨어 도착 전: SDK/문서 준비만. USB 동글은 proof 전용, 목표는 온보드 라디오.
# (아래 함수들은 보드 도착 후 채운다.)
# ============================================================================

help() {
    echo -e "${CYAN}HomeAgent Config${NC} — minimal open hub BSP"
    echo ""
    echo "Usage: ./run.sh <command> [args]"
    echo ""
    echo -e "${CYAN}■ Tier-2 — 미니멀 허브 (Buildroot / SG2000) · 현재 주력${NC}"
    echo "  새 보드 bring-up 명령은 이 lane에 추가한다 (cmd_hub_* 규칙)."
    echo "  하드웨어 도착 후 추가 예정: hub-build / hub-flash / hub-radio / hub-status"
    echo "  방향·acceptance: docs/TARGET_DEVICE.md · VERSION.md · NEXT.md"
    echo "  USB 동글은 proof 전용. 목표는 온보드 EFR32."
    echo ""
    echo -e "${GREEN}=== 코드 / 빌드 (shared) ===${NC}"
    echo "  go-build        Go arm64 크로스컴파일 (정적 바이너리)"
    echo "  go-dev [args]   Go 로컬 개발 실행"
    echo "  ui-build        Lit 프론트엔드 빌드"
    echo "  bundle          백엔드 번들 (scripts/bundle-backend.sh)"
    echo ""
    echo -e "${GREEN}=== 디바이스 ===${NC}"
    echo "  ssh [IP|name] [cmd]  SSH 접속 (opi5, rpi5, IP 직접)"
    echo "  setup-key [IP|name]  SSH 공개키 등록"
    echo "  set-ip <ip>          기본 디바이스 IP 설정"
    echo "  thread-init [IP]     Thread 네트워크 초기화 + SRP"
    echo ""
    echo -e "${GREEN}=== Git ===${NC}"
    echo "  diff / commit   변경사항 / 커밋 상태"
    echo ""
    echo -e "${YELLOW}─── Tier-1 origin lane (Yocto RPi5/OPi5 — 검증 보존, 신규 1순위 아님) ───${NC}"
    echo ""
    echo -e "${GREEN}=== Yocto 빌드 (RPi5) ===${NC}"
    echo "  bb [target]          RPi5 빌드 (기본: core-image-weston)"
    echo "  bb-cmd <args>        RPi5 bitbake 직접 실행"
    echo "  bb-clean [target]    RPi5 클린 빌드"
    echo "  bb-resume            RPi5 빌드 이어하기"
    echo "  shell / status / layers / clean   Yocto 환경/레이어/정리"
    echo "  image / flash /dev/sdX / deploy [host]   RPi5 이미지/플래시"
    echo "  npm-shrinkwrap <pkg> / npm-build <pkg>   z2m·matterjs 레시피"
    echo "  otbr-build           OTBR 빌드 (matterjs 구성)"
    echo ""
    echo -e "${GREEN}=== Yocto 빌드/배포 (OPi5 lab) ===${NC}"
    echo "  bb-opi5 [target]     OPi5 빌드 (기본: core-image-minimal)"
    echo "  bb-cmd-opi5 <args>   OPi5 bitbake 직접 실행"
    echo "  bb-clean-opi5 [target] / bb-resume-opi5"
    echo "  flash-opi5 /dev/sdX  OPi5 SD카드 플래싱 (SSH 키 자동 주입)"
    echo "  opi5-deploy / opi5-start / opi5-stop / opi5-status"
    echo ""
    echo -e "${GREEN}=== 클라이언트 / Go 배포 (origin) ===${NC}"
    echo "  flutter-run / flutter-build / flutter-exec / flutter-server / flutter-analyze"
    echo "  go-deploy [IP]  Go 바이너리만 배포"
    echo "  go-test [IP]    원격 health check"
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

# === OPi5 빌드 명령 (build-opi5 디렉토리 사용) ===
# oe-init-build-env는 yocto/ 디렉토리에서 실행, build-opi5를 인자로 전달

cmd_bb_opi5() {
    local target="${1:-core-image-minimal}"
    if ! in_fhs; then
        echo -e "${YELLOW}[INFO]${NC} FHS 환경 진입 후 OPi5 빌드..."
        cd "$SCRIPT_DIR"
        exec nix run .#yocto -- -c "export HOMEAGENT_FHS=1 && $SCRIPT_DIR/run.sh bb-opi5 $target"
    fi
    echo -e "${GREEN}[BUILD-OPi5]${NC} bitbake $target"
    cd "$YOCTO_DIR"
    source sources/poky/oe-init-build-env build-opi5 >/dev/null 2>&1
    bitbake "$target"
}

cmd_bb_cmd_opi5() {
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}[ERROR]${NC} bitbake 인자를 지정하세요"
        echo "  예: ./run.sh bb-cmd-opi5 -c cleansstate ot-br-posix"
        exit 1
    fi
    if ! in_fhs; then
        echo -e "${YELLOW}[INFO]${NC} FHS 환경 진입 후 OPi5 실행..."
        cd "$SCRIPT_DIR"
        exec nix run .#yocto -- -c "export HOMEAGENT_FHS=1 && $SCRIPT_DIR/run.sh bb-cmd-opi5 $*"
    fi
    echo -e "${GREEN}[BITBAKE-OPi5]${NC} bitbake $*"
    cd "$YOCTO_DIR"
    source sources/poky/oe-init-build-env build-opi5 >/dev/null 2>&1
    bitbake "$@"
}

cmd_bb_clean_opi5() {
    local target="${1:-core-image-minimal}"
    echo -e "${GREEN}[CLEAN BUILD-OPi5]${NC} bitbake $target (클린)"
    echo -e "${YELLOW}[INFO]${NC} tmp-glibc 삭제 중..."
    rm -rf "${OPI5_BUILD_DIR}/tmp-glibc" 2>/dev/null || true
    if ! in_fhs; then
        echo -e "${YELLOW}[INFO]${NC} FHS 환경 진입 후 OPi5 빌드..."
        cd "$SCRIPT_DIR"
        exec nix run .#yocto -- -c "export HOMEAGENT_FHS=1 && $SCRIPT_DIR/run.sh bb-clean-opi5 $target"
    fi
    cd "$YOCTO_DIR"
    source sources/poky/oe-init-build-env build-opi5 >/dev/null 2>&1
    bitbake "$target"
}

cmd_bb_resume_opi5() {
    if ! in_fhs; then
        echo -e "${YELLOW}[INFO]${NC} FHS 환경 진입 후 OPi5 빌드..."
        cd "$SCRIPT_DIR"
        exec nix run .#yocto -- -c "export HOMEAGENT_FHS=1 && $SCRIPT_DIR/run.sh bb-resume-opi5"
    fi
    echo -e "${GREEN}[RESUME-OPi5]${NC} 이전 OPi5 빌드 계속..."
    cd "$YOCTO_DIR"
    source sources/poky/oe-init-build-env build-opi5 >/dev/null 2>&1
    bitbake
}

cmd_clean() {
    echo -e "${GREEN}[CLEAN]${NC} 빌드 캐시 정리..."
    rm -rf "${BUILD_DIR}/tmp-glibc" "${BUILD_DIR}/cache" "${BUILD_DIR}/sstate-cache" 2>/dev/null || true
    echo -e "${GREEN}[DONE]${NC} 정리 완료"
}

cmd_diff() {
    git -C "$SCRIPT_DIR" status
    echo ""
    git -C "$SCRIPT_DIR" diff --stat
}

cmd_commit() {
    echo -e "${YELLOW}[INFO]${NC} NEXT.md / CHANGELOG.md 확인 후 git add/commit 직접 실행하세요"
    git -C "$SCRIPT_DIR" status
}

IMAGE_DIR="${BUILD_DIR}/tmp-glibc/deploy/images/raspberrypi5"
IMAGE_NAME="core-image-weston-raspberrypi5.rootfs.wic.bz2"

# OPi5 이미지
OPI5_BUILD_DIR="${YOCTO_DIR}/build-opi5"
OPI5_IMAGE_DIR="${OPI5_BUILD_DIR}/tmp-glibc/deploy/images/orangepi-5"
OPI5_IMAGE_NAME="core-image-minimal-orangepi-5.rootfs.wic"
OPI5_IMAGE_BZ2="core-image-minimal-orangepi-5.rootfs.wic.bz2"

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

# OPi5 SD카드 플래싱 (SSH 키 + sshd 설정 자동 주입)
cmd_flash_opi5() {
    local device="$1"
    if [[ -z "$device" ]]; then
        echo -e "${RED}[ERROR]${NC} 디바이스를 지정하세요"
        echo "  예: ./run.sh flash-opi5 /dev/sdb"
        echo ""
        echo -e "${CYAN}현재 블록 디바이스:${NC}"
        lsblk -d -o NAME,SIZE,MODEL | grep -v loop
        exit 1
    fi
    local wic_file="${OPI5_IMAGE_DIR}/${OPI5_IMAGE_NAME}"
    if [[ ! -f "$wic_file" ]]; then
        echo -e "${RED}[ERROR]${NC} OPi5 이미지가 없습니다: ${OPI5_IMAGE_NAME}"
        echo "  빌드: nix run .#yocto -- -c 'cd yocto && source sources/poky/oe-init-build-env build-opi5 && bitbake core-image-minimal'"
        exit 1
    fi
    if [[ ! -b "$device" ]]; then
        echo -e "${RED}[ERROR]${NC} 블록 디바이스가 아닙니다: $device"
        exit 1
    fi

    check_ssh_key
    local PUBKEY="${SSH_KEY}.pub"
    if [[ ! -f "$PUBKEY" ]]; then
        ssh-keygen -y -f "$SSH_KEY" >"$PUBKEY" 2>/dev/null
    fi

    echo -e "${YELLOW}[WARNING]${NC} $device 의 모든 데이터가 삭제됩니다!"
    echo -e "이미지: ${OPI5_IMAGE_NAME}"
    read -p "계속하시겠습니까? (y/N) " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "취소됨"
        exit 0
    fi

    # 1. rootfs에 SSH 키 + sshd 설정 주입
    echo -e "${GREEN}[1/3]${NC} rootfs에 SSH 키 + sshd 설정 주입..."
    local mnt_dir="/tmp/opi5-rootfs-$$"
    sudo mkdir -p "$mnt_dir"
    # wic rootfs 파티션 자동 감지 (가장 큰 Linux 파티션)
    local rootfs_start=$(fdisk -l "$wic_file" 2>/dev/null | awk '/Linux/ {start=$2} END {print start}')
    if [[ -z "$rootfs_start" ]]; then
        echo -e "${RED}[ERROR]${NC} rootfs 파티션을 찾을 수 없습니다"
        exit 1
    fi
    echo -e "${CYAN}rootfs offset: sector ${rootfs_start}${NC}"
    sudo mount -o loop,offset=$(($rootfs_start * 512)) "$wic_file" "$mnt_dir"

    sudo mkdir -p "$mnt_dir/root/.ssh"
    sudo cp "$PUBKEY" "$mnt_dir/root/.ssh/authorized_keys"
    sudo chmod 600 "$mnt_dir/root/.ssh/authorized_keys"
    sudo chmod 700 "$mnt_dir/root/.ssh"
    sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' "$mnt_dir/etc/ssh/sshd_config"

    sudo umount "$mnt_dir"
    sudo rmdir "$mnt_dir"

    # 2. SD카드 플래싱
    echo -e "${GREEN}[2/3]${NC} SD카드 플래싱... ($device)"
    sudo umount ${device}* 2>/dev/null || true
    sudo dd if="$wic_file" of="$device" bs=4M conv=fsync status=progress

    # 3. 완료
    echo -e "${GREEN}[3/3]${NC} 완료!"
    echo ""
    echo -e "  SD카드 분리 → OPi5에 꼽고 부팅"
    echo -e "  60초 후: ${CYAN}./run.sh ssh opi5${NC}"
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

# 디바이스별 IP 파일: .current-device-ip (기본=rpi5), .current-device-ip.opi5 등
get_device_ip() {
    local arg="$1"
    # IP 직접 지정
    if [[ "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$arg"
        return
    fi
    # 디바이스 이름으로 IP 파일 조회 (opi5, rpi5 등)
    if [[ -n "$arg" ]] && [[ -f "${DEVICE_IP_FILE}.${arg}" ]]; then
        cat "${DEVICE_IP_FILE}.${arg}"
        return
    fi
    # 기본 디바이스
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
        echo -e "${RED}[ERROR]${NC} IP 또는 디바이스 이름을 지정하세요"
        echo "  ./run.sh setup-key 192.168.0.163"
        echo "  ./run.sh setup-key opi5"
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
        # IP 직접 지정
        IP="$first_arg"
        shift
        CMD="$*"
    elif [[ -n "$first_arg" ]] && [[ -f "${DEVICE_IP_FILE}.${first_arg}" ]]; then
        # 디바이스 이름 (opi5, rpi5 등)
        IP=$(get_device_ip "$first_arg")
        shift
        CMD="$*"
    else
        # 기본 디바이스
        IP=$(get_device_ip)
        CMD="$*"
    fi

    if [[ -z "$IP" ]]; then
        echo -e "${RED}[ERROR]${NC} 디바이스 IP가 설정되지 않았습니다."
        echo "  ./run.sh set-ip <ip>"
        echo "  ./run.sh ssh opi5 [cmd]  (디바이스 이름)"
        echo "  ./run.sh ssh 192.168.0.163 [cmd]"
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

# ─── HomeAgent 통합 배포 ───

cmd_ui_build() {
    echo -e "${GREEN}[UI-BUILD]${NC} Lit 프론트엔드 빌드..."
    cd "$SCRIPT_DIR/ui"
    npx vite build
    echo -e "${GREEN}[DONE]${NC} ui/dist/ ($(du -sh dist | awk '{print $1}'))"
}

# ─── Go 빌드/배포 (기존) ───

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

# ─── OPi5 Yocto 네이티브 배포 (Docker 불필요) ───
# OPi5는 matterjs-server + otbr-agent가 systemd 서비스로 동작
# Go 서버 + UI + aliases만 배포하면 됨

cmd_opi5_deploy() {
    local IP=$(get_device_ip "opi5")
    if [[ -z "$IP" ]]; then
        echo -e "${RED}[ERROR]${NC} .current-device-ip.opi5 파일이 없습니다"
        echo "  echo '192.168.0.177' > .current-device-ip.opi5"
        exit 1
    fi
    check_ssh_key

    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${CYAN}  OPi5 배포 (Yocto 네이티브) → $IP${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"

    # 1. Go 빌드
    cmd_go_build

    # 2. UI 빌드
    cmd_ui_build

    # 3. 기존 Go 프로세스 정지
    cmd_opi5_stop 2>/dev/null || true

    # 4. 파일 전송
    echo -e "${GREEN}[UPLOAD]${NC} Go + UI + aliases + env..."
    ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" "mkdir -p /opt/homeagent/ui"
    scp -i "$SSH_KEY" $SSH_OPTS "$SCRIPT_DIR/go/bin/homeagent" root@"$IP":/opt/homeagent/homeagent
    scp -i "$SSH_KEY" $SSH_OPTS "$SCRIPT_DIR/aliases.json" root@"$IP":/opt/homeagent/aliases.json
    ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" "rm -rf /opt/homeagent/ui/*"
    scp -i "$SSH_KEY" $SSH_OPTS -r "$SCRIPT_DIR/ui/dist/"* root@"$IP":/opt/homeagent/ui/

    # env 파일 전송
    scp -i "$SSH_KEY" $SSH_OPTS "$SCRIPT_DIR/.env.opi5" root@"$IP":/opt/homeagent/.env

    # .env에 LLM 키 추가
    if [[ -f "$HOME/.env.local" ]]; then
        local _key
        _key=$(grep -m1 '^export OPENROUTER_API_KEY=' "$HOME/.env.local" 2>/dev/null | sed 's/^export //' || true)
        [[ -n "$_key" ]] && ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" "echo '$_key' >> /opt/homeagent/.env"
    fi

    # 5. 시작
    cmd_opi5_start

    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${GREEN}[DONE]${NC} OPi5 배포 완료! http://$IP:8080"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
}

cmd_opi5_start() {
    local IP=$(get_device_ip "opi5")
    if [[ -z "$IP" ]]; then
        echo -e "${RED}[ERROR]${NC} .current-device-ip.opi5 파일이 없습니다"; exit 1
    fi
    check_ssh_key

    echo -e "${GREEN}[START]${NC} OPi5 Go 서버 시작 ($IP)..."
    ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" bash -s <<'OPI5_START'
set -e
HA_DIR="/opt/homeagent"
log()  { echo -e "\033[0;32m[opi5]\033[0m $*"; }

# systemd 서비스 확인
log "systemd 서비스 확인..."
for svc in matterjs-server otbr-agent avahi-daemon; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        log "  $svc: ✅"
    else
        log "  $svc: ❌ (시작 시도)"
        systemctl start $svc 2>/dev/null || true
    fi
done

# matterjs-server WS 준비 대기
log "matterjs-server WS 대기..."
for i in $(seq 1 30); do
    wget -qO- http://localhost:5580 >/dev/null 2>&1 && break
    sleep 1
done

# Go HomeAgent
if pidof homeagent > /dev/null 2>&1; then
    log "homeagent 이미 실행 중"
else
    log "homeagent 시작..."
    cd "$HA_DIR"
    [ -f "$HA_DIR/.env" ] && { set -a; . "$HA_DIR/.env"; set +a; }

    HOMEAGENT_HTTP_ADDR="${HOMEAGENT_HTTP_ADDR:-:8080}" \
    HOMEAGENT_MATTER_WS="${HOMEAGENT_MATTER_WS:-ws://localhost:5580}" \
    HOMEAGENT_UI_DIR="${HOMEAGENT_UI_DIR:-$HA_DIR/ui}" \
    HOMEAGENT_ALIASES_FILE="${HOMEAGENT_ALIASES_FILE:-$HA_DIR/aliases.json}" \
    nohup ./homeagent > /tmp/homeagent.log 2>&1 &
    sleep 3
fi

log "=== 완료 ==="
grep "connected:\|listening" /tmp/homeagent.log 2>/dev/null | tail -3 || true
OPI5_START
}

cmd_opi5_stop() {
    local IP=$(get_device_ip "opi5")
    if [[ -z "$IP" ]]; then
        echo -e "${RED}[ERROR]${NC} .current-device-ip.opi5 파일이 없습니다"; exit 1
    fi
    check_ssh_key
    echo -e "${YELLOW}[STOP]${NC} OPi5 Go 서버 종료 ($IP)..."
    ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" \
        'kill $(pidof homeagent) 2>/dev/null && echo "homeagent stopped" || echo "homeagent not running"'
}

cmd_opi5_status() {
    local IP=$(get_device_ip "opi5")
    if [[ -z "$IP" ]]; then
        echo -e "${RED}[ERROR]${NC} .current-device-ip.opi5 파일이 없습니다"; exit 1
    fi
    check_ssh_key
    echo -e "${CYAN}[STATUS]${NC} OPi5 ($IP)"
    ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" bash -s <<'OPI5_STATUS'
echo "=== systemd 서비스 ==="
for svc in matterjs-server otbr-agent avahi-daemon mosquitto; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        echo "  $svc: ✅"
    else
        echo "  $svc: ❌"
    fi
done

echo ""
echo "=== Go HomeAgent ==="
pidof homeagent > /dev/null 2>&1 && echo "  homeagent: ✅" || echo "  homeagent: ❌"

echo ""
echo "=== Thread ==="
STATE=$(ot-ctl state 2>/dev/null | grep -v Done | tr -d '\r' || echo "unknown")
echo "  state: $STATE"
ot-ctl srp server state 2>/dev/null | grep -v Done | tr -d '\r' | sed 's/^/  SRP: /' || true

echo ""
echo "=== 네트워크 ==="
ip -br addr show end0 2>/dev/null || echo "  end0 not found"

echo ""
echo "=== 디바이스 ==="
wget -qO- http://localhost:8080/api/devices 2>/dev/null || echo "  (API 응답 없음)"

echo ""
echo "=== 시스템 ==="
df -h / | tail -1 | awk '{print "  disk: "$3"/"$2" ("$5")"}'
echo -n "  mem: "; free -m 2>/dev/null | awk '/Mem/{print $3"/"$2"M"}' || echo "(N/A)"
echo -n "  uptime: "; uptime | sed 's/.*up //' | sed 's/,.*//' 
echo -n "  temp: "; cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f°C\n", $1/1000}' || echo "N/A"
OPI5_STATUS
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

cmd_thread_init() {
    local IP=$(get_device_ip "$1")
    if [[ -z "$IP" ]]; then
        echo -e "${RED}[ERROR]${NC} IP를 지정하세요"
        echo "  ./run.sh thread-init 192.168.0.163"
        exit 1
    fi

    check_ssh_key

    echo -e "${CYAN}[THREAD]${NC} Thread 네트워크 초기화 + SRP 활성화..."
    ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" bash -s <<'REMOTE_EOF'
# Thread init + SRP enable 원커맨드
/usr/sbin/otbr-thread-init.sh
systemctl restart otbr-srp-enable.service
echo ""
echo "=== 최종 상태 ==="
echo -n "Thread: "; ot-ctl state 2>&1 | sed -n '1p' | tr -d '\r'
echo -n "SRP:    "; ot-ctl srp server state 2>&1 | sed -n '1p' | tr -d '\r'
echo -n "avahi:  "; systemctl is-active avahi-daemon
REMOTE_EOF
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
    bb-opi5)
        shift
        cmd_bb_opi5 "$@"
        ;;
    bb-cmd-opi5)
        shift
        cmd_bb_cmd_opi5 "$@"
        ;;
    bb-clean-opi5)
        shift
        cmd_bb_clean_opi5 "$@"
        ;;
    bb-resume-opi5)
        cmd_bb_resume_opi5
        ;;
    clean)
        cmd_clean
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
    flash-opi5)
        cmd_flash_opi5 "$2"
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
    thread-init)
        cmd_thread_init "$2"
        ;;
    npm-shrinkwrap)
        cmd_npm_shrinkwrap "$2"
        ;;
    npm-build)
        cmd_npm_build "$2"
        ;;
    ui-build)
        cmd_ui_build
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
    opi5-deploy)
        cmd_opi5_deploy
        ;;
    opi5-start)
        cmd_opi5_start
        ;;
    opi5-stop)
        cmd_opi5_stop
        ;;
    opi5-status)
        cmd_opi5_status
        ;;
    flutter-run)
        echo -e "${GREEN}Flutter Linux Desktop — hot reload${NC}"
        echo "Go 서버가 :8080에서 실행 중이어야 합니다 (./run.sh flutter-server)"
        nix develop "${SCRIPT_DIR}#dev" --command bash -c "cd ${SCRIPT_DIR}/flutter && flutter run -d linux"
        ;;
    flutter-build)
        echo -e "${GREEN}Flutter Linux Desktop — release 빌드${NC}"
        nix develop "${SCRIPT_DIR}#dev" --command bash -c "cd ${SCRIPT_DIR}/flutter && flutter build linux"
        echo -e "${GREEN}빌드 완료:${NC} flutter/build/linux/x64/release/bundle/homeagent"
        ;;
    flutter-exec)
        FLUTTER_BIN="${SCRIPT_DIR}/flutter/build/linux/x64/release/bundle/homeagent"
        if [ ! -f "$FLUTTER_BIN" ]; then
            echo -e "${RED}[ERROR]${NC} 빌드 먼저: ./run.sh flutter-build"
            exit 1
        fi
        echo -e "${GREEN}Flutter 앱 실행${NC} (Go 서버: localhost:8080)"
        DISPLAY="${DISPLAY:-:0}" "$FLUTTER_BIN"
        ;;
    flutter-server)
        echo -e "${GREEN}Go 서버 로컬 실행${NC} (Flutter 개발용, :8080)"
        echo "Matter 연결 없이 HTTP/healthz만 동작합니다"
        cd "${SCRIPT_DIR}/go"
        HOMEAGENT_UI_DIR="${SCRIPT_DIR}/ui/dist" \
        HOMEAGENT_ALIASES_FILE="${SCRIPT_DIR}/aliases.json" \
            go run ./cmd/homeagent/
        ;;
    flutter-analyze)
        nix develop "${SCRIPT_DIR}#dev" --command bash -c "cd ${SCRIPT_DIR}/flutter && flutter analyze"
        ;;
    otbr-build)
        # matterjs 구성 OTBR 빌드 (python-matter-server BBR 경로는 폐기됨)
        exec nix develop .#dev --impure --command bash "${SCRIPT_DIR}/scripts/build-otbr.sh"
        ;;
    bundle)
        shift
        "${SCRIPT_DIR}/scripts/bundle-backend.sh" "$@"
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} 알 수 없는 명령: $1"
        echo "도움말: ./run.sh help"
        exit 1
        ;;
esac
