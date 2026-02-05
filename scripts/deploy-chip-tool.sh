#!/usr/bin/env bash
#
# chip-tool RPi5 배포 스크립트
# 빌드된 chip-tool 바이너리를 SSH로 RPi5에 전송
#
# 사용법: ./scripts/deploy-chip-tool.sh [IP]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CHIP_TOOL="${PROJECT_DIR}/matter/bin/chip-tool"
LIB_DIR="${PROJECT_DIR}/matter/bin/lib"
SSH_KEY="${PROJECT_DIR}/.sshkey/id_ed25519"
DEVICE_IP_FILE="${PROJECT_DIR}/.current-device-ip"
SSH_OPTS="-o StrictHostKeyChecking=no -o LogLevel=ERROR"
REMOTE_DIR="/opt/chip-tool"

# IP 결정
IP="$1"
if [[ -z "$IP" && -f "$DEVICE_IP_FILE" ]]; then
    IP=$(cat "$DEVICE_IP_FILE")
fi

if [[ -z "$IP" ]]; then
    echo -e "${RED}[ERROR]${NC} IP를 지정하세요"
    echo "  ./scripts/deploy-chip-tool.sh 192.168.0.163"
    exit 1
fi

# 바이너리 확인
if [[ ! -f "$CHIP_TOOL" ]]; then
    echo -e "${RED}[ERROR]${NC} chip-tool 바이너리 없음: $CHIP_TOOL"
    echo "  빌드: ./scripts/build-chip-tool.sh"
    exit 1
fi

# SSH 키 확인
if [[ ! -f "$SSH_KEY" ]]; then
    echo -e "${RED}[ERROR]${NC} SSH 키 없음: $SSH_KEY"
    exit 1
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  chip-tool RPi5 배포${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  대상:   root@${IP}:${REMOTE_DIR}"
echo "  바이너리: $(ls -lh "$CHIP_TOOL" | awk '{print $5}')"
echo ""

# 원격 디렉토리 생성 + 전송
echo -e "${YELLOW}[1/4]${NC} 바이너리 전송 중..."
ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" "mkdir -p ${REMOTE_DIR}/lib"
scp -i "$SSH_KEY" $SSH_OPTS "$CHIP_TOOL" root@"$IP":"${REMOTE_DIR}/chip-tool"

# 번들 라이브러리 전송 (libatomic 등)
echo -e "${YELLOW}[2/4]${NC} 라이브러리 번들 전송..."
if [[ -d "$LIB_DIR" ]] && ls "$LIB_DIR"/*.so* &>/dev/null; then
    scp -i "$SSH_KEY" $SSH_OPTS "$LIB_DIR"/*.so* root@"$IP":"${REMOTE_DIR}/lib/"
    echo "  $(ls "$LIB_DIR"/*.so* | wc -l)개 라이브러리 전송"
else
    echo "  번들 라이브러리 없음 (시스템 라이브러리 사용)"
fi

# wrapper 스크립트 생성
echo -e "${YELLOW}[3/4]${NC} wrapper 스크립트 생성..."
ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" "cat > ${REMOTE_DIR}/run-chip-tool.sh << 'WRAPPER'
#!/bin/sh
SCRIPT_DIR=\$(cd \$(dirname \$0) && pwd)
export LD_LIBRARY_PATH=\"\${SCRIPT_DIR}/lib:\${LD_LIBRARY_PATH}\"
exec \${SCRIPT_DIR}/chip-tool \"\$@\"
WRAPPER
chmod +x ${REMOTE_DIR}/run-chip-tool.sh ${REMOTE_DIR}/chip-tool"

# 검증
echo -e "${YELLOW}[4/4]${NC} 검증..."
ssh -i "$SSH_KEY" $SSH_OPTS root@"$IP" "file ${REMOTE_DIR}/chip-tool && ${REMOTE_DIR}/run-chip-tool.sh --version 2>&1 | sed -n '1p'" || true

echo ""
echo -e "${GREEN}[OK]${NC} 배포 완료!"
echo ""
echo "사용법 (RPi5에서):"
echo "  ${REMOTE_DIR}/run-chip-tool.sh --help"
echo "  ${REMOTE_DIR}/run-chip-tool.sh pairing code-thread <node-id> hex:<dataset> <setup-code>"
echo ""
echo "Thread dataset 획득:"
echo "  ot-ctl dataset active -x"
