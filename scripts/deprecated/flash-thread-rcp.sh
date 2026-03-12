#!/usr/bin/env bash
# ZBDongle-E Thread RCP 펌웨어 플래시 스크립트
# EFR32MG21 Gecko Bootloader + Xmodem 전송
#
# 전략: 동글 2개 운용 (MultiPAN deprecated)
#   ZBDongle-E #1 → Zigbee NCP (ncp-uart) → zigbee2mqtt
#   ZBDongle-E #2 → Thread RCP (ot-rcp)   → OTBR → Matter
#
# 사용법: ./scripts/flash-thread-rcp.sh [디바이스] [펌웨어]
# 기본값: /dev/ttyUSB0, 자동 다운로드

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DEVICE="${1:-/dev/ttyUSB0}"
FIRMWARE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_FW_DIR="${SCRIPT_DIR}/../firmware/zbdonglee"
FIRMWARE_DIR="/tmp/homeagent-firmware"
FIRMWARE_URL="https://github.com/darkxst/silabs-firmware-builder/releases/download/20250627/zbdonglee_openthread_rcp_2.5.3.0_GitHub-1fceb225b_gsdk_2024.6.3_no_flow_460800.gbl"
FIRMWARE_FILE="zbdonglee_openthread_rcp_2.5.3.0_no_flow_460800.gbl"
# 롤백용 Zigbee NCP 펌웨어
ZIGBEE_URL="https://github.com/darkxst/silabs-firmware-builder/releases/download/20250627/zbdonglee_zigbee_ncp_8.0.3.0_sw_flow_115200.gbl"
ZIGBEE_FILE="zbdonglee_zigbee_ncp_8.0.3.0_sw_flow_115200.gbl"
BAUD_RATE=115200

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}  ZBDongle-E Thread RCP 펌웨어 플래시${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""
echo "펌웨어: ot-rcp-v2.5.3.0-zbdonglee-460800"
echo "대상:   $DEVICE"
echo ""

# ── 1. 필수 도구 확인 ──
echo -e "${YELLOW}[1/5]${NC} 필수 도구 확인..."

missing=()
for cmd in minicom sx; do
    if ! command -v "$cmd" &>/dev/null; then
        missing+=("$cmd")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}[ERROR]${NC} 필수 도구 없음: ${missing[*]}"
    echo ""
    echo "설치 방법:"
    echo "  NixOS:   nix-shell -p minicom lrzsz"
    echo "  Ubuntu:  sudo apt install minicom lrzsz"
    echo "  Arch:    sudo pacman -S minicom lrzsz"
    echo ""
    echo "또는 nix-shell로 임시 환경 진입 후 재실행:"
    echo "  nix-shell -p minicom lrzsz --run './scripts/flash-thread-rcp.sh'"
    exit 1
fi

echo -e "${GREEN}  minicom$(NC) $(minicom --version 2>/dev/null | head -1 || echo 'OK')"
echo -e "${GREEN}  sx (lrzsz)${NC} OK"
echo ""

# ── 2. 펌웨어 파일 준비 ──
echo -e "${YELLOW}[2/5]${NC} 펌웨어 파일 확인..."

if [[ -n "$FIRMWARE" && -f "$FIRMWARE" ]]; then
    echo -e "${GREEN}  지정 펌웨어:${NC} $FIRMWARE"
elif [[ -f "${REPO_FW_DIR}/${FIRMWARE_FILE}" ]]; then
    FIRMWARE="${REPO_FW_DIR}/${FIRMWARE_FILE}"
    echo -e "${GREEN}  리포 펌웨어:${NC} $FIRMWARE"
else
    mkdir -p "$FIRMWARE_DIR"
    FIRMWARE="${FIRMWARE_DIR}/${FIRMWARE_FILE}"

    if [[ -f "$FIRMWARE" ]]; then
        echo -e "${GREEN}  캐시됨:${NC} $FIRMWARE"
    else
        echo "  다운로드 중..."
        echo ""
        echo -e "  ${CYAN}펌웨어 종류 참고:${NC}"
        echo "    ot-rcp-*    : Thread 전용 RCP (이 스크립트)"
        echo "    rcp-uart-*  : MultiPAN Zigbee+Thread (deprecated, HA 공식 폐기)"
        echo "    ncp-uart-*  : Zigbee 전용 (EmberZNet)"
        echo ""
        if command -v wget &>/dev/null; then
            wget -O "$FIRMWARE" "$FIRMWARE_URL"
        elif command -v curl &>/dev/null; then
            curl -L -o "$FIRMWARE" "$FIRMWARE_URL"
        else
            echo -e "${RED}[ERROR]${NC} wget 또는 curl 필요"
            exit 1
        fi
    fi

    # minicom xmodem에서 파일 접근 편의를 위해 /root에 복사
    echo "  /root에 펌웨어 복사 (minicom xmodem 접근용)..."
    sudo cp "$FIRMWARE" /root/
    echo -e "${GREEN}  /root/${FIRMWARE_FILE}${NC} 에서도 접근 가능"

    # 롤백용 Zigbee NCP 펌웨어도 함께 다운로드
    ZIGBEE_FW="${FIRMWARE_DIR}/${ZIGBEE_FILE}"
    if [[ ! -f "$ZIGBEE_FW" ]]; then
        echo ""
        echo "  롤백용 Zigbee NCP 펌웨어 다운로드 중..."
        if command -v wget &>/dev/null; then
            wget -q -O "$ZIGBEE_FW" "$ZIGBEE_URL"
        elif command -v curl &>/dev/null; then
            curl -sL -o "$ZIGBEE_FW" "$ZIGBEE_URL"
        fi
        sudo cp "$ZIGBEE_FW" /root/
        echo -e "${GREEN}  롤백용:${NC} /root/${ZIGBEE_FILE}"
    else
        echo -e "${GREEN}  롤백용 캐시됨:${NC} $ZIGBEE_FW"
    fi
fi

if [[ ! -f "$FIRMWARE" ]]; then
    echo -e "${RED}[ERROR]${NC} 펌웨어 다운로드 실패"
    exit 1
fi

file_size=$(stat -c %s "$FIRMWARE" 2>/dev/null || stat -f %z "$FIRMWARE")
echo -e "${GREEN}  준비됨:${NC} $(basename "$FIRMWARE") (${file_size} bytes)"
echo ""

# ── 3. USB 디바이스 확인 ──
echo -e "${YELLOW}[3/5]${NC} USB 디바이스 확인..."

if [[ ! -e "$DEVICE" ]]; then
    echo -e "${RED}[ERROR]${NC} 디바이스 없음: $DEVICE"
    echo ""
    echo "연결된 USB 시리얼 디바이스:"
    ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "  (없음)"
    echo ""
    echo "ZBDongle-E를 연결하세요."
    echo "  Zigbee 펌웨어: /dev/ttyUSB0 (CP2102N)"
    echo "  Thread 펌웨어: /dev/ttyACM0 (CDC ACM)"
    exit 1
fi

echo -e "${GREEN}  확인됨:${NC} $DEVICE"
echo ""

# ── 4. 하드웨어 준비 안내 ──
echo -e "${YELLOW}[4/5]${NC} 하드웨어 준비"
echo ""
echo -e "  ${CYAN}ZBDongle-E 분해 및 버튼 위치:${NC}"
echo "  1. 금속 케이스 분해 (안테나 측면 나사 2개 제거)"
echo "  2. PCB에서 Boot 버튼과 Reset 버튼 확인"
echo "     ┌─────────────────────┐"
echo "     │  [Boot]    [Reset]  │"
echo "     │                     │"
echo "     │      EFR32MG21      │"
echo "     │                     │"
echo "     └──────┤USB├──────────┘"
echo ""
echo -e "  ${CYAN}부트로더 진입 방법:${NC}"
echo "  1. Boot 버튼을 누르고 유지"
echo "  2. Reset 버튼을 한 번 누름"
echo "  3. 두 버튼 동시에 놓기"
echo "  4. Gecko Bootloader 메뉴가 나타나면 성공"
echo ""
read -p "  준비 완료 시 Enter... "

# ── 5. 플래시 실행 ──
echo ""
echo -e "${YELLOW}[5/5]${NC} 펌웨어 플래시"
echo ""
echo -e "${CYAN}=== 수동 플래시 절차 ===${NC}"
echo ""
echo "  1. minicom 실행 (아래 명령 자동 실행):"
echo "     minicom -D $DEVICE -b $BAUD_RATE"
echo ""
echo "  2. 부트로더 진입 (위의 버튼 조작)"
echo "     'Gecko Bootloader' 메뉴가 보여야 함"
echo ""
echo "  3. '1' 입력 → Xmodem 수신 모드 진입"
echo "     'begin upload' 또는 'C' 문자가 출력됨"
echo ""
echo "  4. 파일 전송:"
echo "     Ctrl+A → S → xmodem → 파일 선택:"
echo "     ${FIRMWARE}"
echo ""
echo "  5. 전송 완료 후 '2' 입력 → 펌웨어 부팅"
echo ""
echo "  6. Ctrl+A → X → minicom 종료"
echo ""
echo -e "${YELLOW}[NOTE]${NC} 전송 완료 후:"
echo "  - ZBDongle-E는 CP2102N 칩 → 항상 /dev/ttyUSB0 유지"
echo "  - 펌웨어 확인: 460800 baudrate 연결 시 응답 없음 = Thread RCP"
echo ""

read -p "  minicom을 실행하시겠습니까? (Y/n): " run_minicom

if [[ "$run_minicom" == "n" || "$run_minicom" == "N" ]]; then
    echo ""
    echo "수동 실행:"
    echo "  minicom -D $DEVICE -b $BAUD_RATE"
    echo ""
    echo "펌웨어 위치:"
    echo "  $FIRMWARE"
    exit 0
fi

echo ""
echo -e "${GREEN}[START]${NC} minicom 실행 (sudo)..."
echo -e "${YELLOW}[TIP]${NC} 부트로더 진입 후 1 → Ctrl+A S → xmodem → /root/${FIRMWARE_FILE}"
echo ""

sudo minicom -D "$DEVICE" -b "$BAUD_RATE"

# ── 완료 확인 ──
echo ""
echo -e "${CYAN}=== 플래시 후 확인 ===${NC}"
echo ""

sleep 2

if [[ -e "/dev/ttyUSB0" ]]; then
    echo -e "${GREEN}[OK]${NC} /dev/ttyUSB0 확인됨 (ZBDongle-E는 CP2102N → 항상 ttyUSB0)"
    echo ""
    echo "펌웨어 확인 방법:"
    echo "  minicom -D /dev/ttyUSB0 -b 460800"
    echo "  → 아무 응답 없음 = Thread RCP (Spinel 바이너리 프로토콜)"
    echo "  → 텍스트 응답 = 아직 Zigbee NCP"
    echo ""
    echo "다음 단계:"
    echo "  1. ZBDongle-E를 RPi5에 연결"
    echo "  2. OTBR 설정: otbr-agent -I wpan0 -B eth0 spinel+hdlc+uart:///dev/ttyUSB0?uart-baudrate=460800"
    echo "  3. Thread 네트워크 형성: ot-ctl dataset init new && ot-ctl dataset commit active"
else
    echo -e "${YELLOW}[INFO]${NC} USB 디바이스 없음"
    echo "  동글을 분리 후 다시 연결하세요."
fi

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}  플래시 완료${NC}"
echo -e "${CYAN}==========================================${NC}"
