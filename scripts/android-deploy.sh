#!/usr/bin/env bash
# android-deploy.sh — HomeAgent Android 보드 배포/실행/관리
#
# 범용 Android arm64 보드 지원 (RK3576, RK3588, etc.)
# ESP32-H2 외 다른 Thread RCP도 설정으로 대응.
#
# 사용:
#   ./scripts/android-deploy.sh deploy          전체 빌드+배포+시작
#   ./scripts/android-deploy.sh deploy --skip-go --skip-apk
#   ./scripts/android-deploy.sh start           서비스만 (재)시작
#   ./scripts/android-deploy.sh stop            서비스 종료
#   ./scripts/android-deploy.sh status          상태 확인
#   ./scripts/android-deploy.sh logs [target]   로그 (matter/go/otbr/all)
#   ./scripts/android-deploy.sh thread-start    OTBR + Thread 네트워크
#   ./scripts/android-deploy.sh thread-stop     OTBR 중지
#   ./scripts/android-deploy.sh thread-status   Thread 상태
#   ./scripts/android-deploy.sh install-apk     APK만 설치
#   ./scripts/android-deploy.sh push-artifacts  아티팩트만 push (시작 안 함)
#
# 환경변수 (기본값):
#   RCP_DEVICE=/dev/ttyS5       Thread RCP UART 디바이스
#   RCP_BAUDRATE=460800         UART 속도
#   BACKBONE_IF=wlan0           백본 인터페이스 (WiFi)
#   WPAN_IF=wpan0               Thread 인터페이스
#   WIFI_SSID=                  WiFi SSID (matterjs commissioning용)
#   WIFI_PASSWORD=              WiFi 비밀번호
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
REMOTE="/data/local/tmp"

# ─── 색상 ───
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[android]${NC} $*"; }
warn() { echo -e "${YELLOW}[android]${NC} $*"; }
err()  { echo -e "${RED}[android]${NC} $*" >&2; exit 1; }
info() { echo -e "${CYAN}[android]${NC} $*"; }

# ─── ADB ───
check_adb() {
    adb devices 2>/dev/null | grep -q "device$" || err "ADB 디바이스 없음. USB/WiFi 연결 확인."
    local DEV
    DEV=$(adb devices | grep "device$" | head -1 | awk '{print $1}')
    log "ADB: $DEV"
}

# 프로세스 정리 — Android pkill이 불안정하므로 PID 직접 kill
kill_services() {
    adb shell "
        for pid in \$(ps -ef | grep -E 'homeagent serve|ld-linux.*node|MatterServer|otbr-agent' | grep -v grep | awk '{print \$2}'); do
            kill \$pid 2>/dev/null
        done
    " 2>/dev/null || true
    sleep 2
    # 잔여 프로세스 강제 종료
    adb shell "
        for pid in \$(ps -ef | grep -E 'homeagent serve|ld-linux.*node|MatterServer|otbr-agent' | grep -v grep | awk '{print \$2}'); do
            kill -9 \$pid 2>/dev/null
        done
    " 2>/dev/null || true
    sleep 1
}

# ─── START: matterjs → Go ───
cmd_start() {
    check_adb
    log "기존 서비스 정리..."
    kill_services

    # 시작 스크립트를 디바이스에 생성 — adb shell 블록 방지
    local WIFI_SSID_ARG="" WIFI_PASS_ARG="" OT_CTL_ARG=""
    [[ -n "${WIFI_SSID:-}" ]] && WIFI_SSID_ARG="HOMEAGENT_WIFI_SSID=$WIFI_SSID"
    [[ -n "${WIFI_PASSWORD:-}" ]] && WIFI_PASS_ARG="HOMEAGENT_WIFI_PASSWORD=$WIFI_PASSWORD"
    [[ -f "$DIST_DIR/otbr-arm64/ot-ctl" ]] && OT_CTL_ARG="HOMEAGENT_OT_CTL=$REMOTE/otbr/ot-ctl"

    adb shell "cat > $REMOTE/_start.sh" << STARTEOF
#!/system/bin/sh
# matterjs-server (--import로 BLE WS bridge 로드 → :5581)
cd $REMOTE/nodejs-bundle
lib/ld-linux-aarch64.so.1 --library-path lib ./node \\
    --import ./matterjs-server/remote-ble/ws-bridge.js \\
    matterjs-server/node_modules/matter-server/dist/esm/MatterServer.js \\
    --storage-path $REMOTE/matter-data \\
    --port 5580 \\
    --bluetooth-adapter 0 \\
    > $REMOTE/matterjs.log 2>&1 &
sleep 4

# Go homeagent
HOMEAGENT_HTTP_ADDR=:8080 \\
HOMEAGENT_MATTER_WS=ws://localhost:5580 \\
HOMEAGENT_UI_DIR=$REMOTE/ui/dist \\
HOMEAGENT_ALIASES_FILE=$REMOTE/aliases.json \\
${OT_CTL_ARG} \\
${WIFI_SSID_ARG} \\
${WIFI_PASS_ARG} \\
$REMOTE/homeagent serve \\
    > $REMOTE/homeagent.log 2>&1 &

echo "started"
STARTEOF
    adb shell "chmod +x $REMOTE/_start.sh"
    adb shell "nohup $REMOTE/_start.sh > /dev/null 2>&1 &" < /dev/null
    sleep 6

    log "프로세스 확인..."
    adb shell "ps -ef | grep -E 'homeagent serve|ld-linux.*node.*Matter' | grep -v grep" || warn "프로세스 미확인"
    adb shell "netstat -tlnp 2>/dev/null | grep -E '5580|8080'" || true
    log "완료! matterjs(:5580) + homeagent(:8080)"
}

# ─── STOP ───
cmd_stop() {
    check_adb
    kill_services
    log "서비스 종료"
}

# ─── STATUS ───
cmd_status() {
    check_adb
    echo "=== 프로세스 ==="
    adb shell "ps -ef | grep -E 'homeagent|node.*Matter|otbr-agent' | grep -v grep" || echo "(없음)"
    echo ""
    echo "=== 포트 ==="
    adb shell "netstat -tlnp 2>/dev/null | grep -E '5580|8080'" || echo "(없음)"
    echo ""
    echo "=== APK ==="
    adb shell "dumpsys package com.homeagent.app 2>/dev/null | grep -E 'versionName|lastUpdate'" || echo "(미설치)"
    echo ""
    echo "=== 네트워크 ==="
    adb shell "ip addr show wlan0 2>/dev/null | grep 'inet '" || echo "(WiFi 없음)"
}

# ─── LOGS ───
cmd_logs() {
    check_adb
    local target="${1:-all}"
    case "$target" in
        matter*) adb shell "tail -50 $REMOTE/matterjs.log" ;;
        go|ha)   adb shell "tail -50 $REMOTE/homeagent.log" ;;
        otbr)    adb shell "tail -50 $REMOTE/otbr-agent.log" ;;
        *)
            for svc in matterjs homeagent otbr-agent; do
                echo "=== $svc ==="
                adb shell "tail -10 $REMOTE/${svc}.log 2>/dev/null" || echo "(없음)"
                echo ""
            done
            ;;
    esac
}

# ─── THREAD ───
cmd_thread_start() {
    check_adb
    local RCP_DEVICE="${RCP_DEVICE:-/dev/ttyS5}"
    local RCP_BAUDRATE="${RCP_BAUDRATE:-460800}"
    local BACKBONE_IF="${BACKBONE_IF:-wlan0}"
    local WPAN_IF="${WPAN_IF:-wpan0}"

    log "Thread Border Router 시작..."

    # 1. Android Thread HAL 중지
    adb shell "stop vendor.threadnetwork_hal 2>/dev/null; stop ot-daemon 2>/dev/null" || true
    sleep 1

    # 2. SELinux permissive + 디바이스 권한
    adb shell "setenforce 0; chmod 666 $RCP_DEVICE" || true

    # 3. wpan0 TUN 인터페이스
    adb shell "
        ip tuntap del dev $WPAN_IF mode tun 2>/dev/null
        ip tuntap add dev $WPAN_IF mode tun
        ip link set $WPAN_IF up
        sysctl -w net.ipv6.conf.all.forwarding=1
    "

    # 4. otbr-agent 시작
    adb shell "pkill -f otbr-agent 2>/dev/null" || true
    sleep 1
    adb shell "nohup $REMOTE/otbr/otbr-agent \
        -I $WPAN_IF -B $BACKBONE_IF -d7 -v \
        'spinel+hdlc+uart://$RCP_DEVICE?uart-baudrate=$RCP_BAUDRATE' \
        > $REMOTE/otbr-agent.log 2>&1 &" < /dev/null
    sleep 3

    # 5. otbr-agent 확인
    if ! adb shell "pgrep -f otbr-agent" > /dev/null 2>&1; then
        err "otbr-agent 시작 실패. 로그: adb shell cat $REMOTE/otbr-agent.log"
    fi
    log "otbr-agent 시작됨"

    # 6. Thread 네트워크 초기화
    local EXISTING
    EXISTING=$(adb shell "$REMOTE/otbr/ot-ctl dataset active -x 2>/dev/null | head -1" || true)
    if [[ -z "$EXISTING" ]] || [[ "$EXISTING" == "Done" ]]; then
        log "새 Thread 네트워크 생성..."
        adb shell "$REMOTE/otbr/ot-ctl dataset init new"
        adb shell "$REMOTE/otbr/ot-ctl dataset commit active"
    else
        log "기존 dataset 사용"
    fi
    adb shell "$REMOTE/otbr/ot-ctl ifconfig up"
    adb shell "$REMOTE/otbr/ot-ctl thread start"
    sleep 5
    adb shell "$REMOTE/otbr/ot-ctl srp server enable"

    cmd_thread_status
}

cmd_thread_stop() {
    check_adb
    adb shell "$REMOTE/otbr/ot-ctl thread stop 2>/dev/null" || true
    adb shell "$REMOTE/otbr/ot-ctl ifconfig down 2>/dev/null" || true
    adb shell "pkill -f otbr-agent 2>/dev/null" || true
    adb shell "ip tuntap del dev ${WPAN_IF:-wpan0} mode tun 2>/dev/null" || true
    log "Thread 중지"
}

cmd_thread_status() {
    check_adb
    echo "=== OTBR ==="
    adb shell "pgrep -f otbr-agent > /dev/null && echo 'running' || echo 'stopped'"
    echo "=== Thread State ==="
    adb shell "$REMOTE/otbr/ot-ctl state 2>/dev/null" || echo "N/A"
    echo "=== SRP Server ==="
    adb shell "$REMOTE/otbr/ot-ctl srp server state 2>/dev/null" || echo "N/A"
    echo "=== Dataset ==="
    adb shell "$REMOTE/otbr/ot-ctl dataset active -x 2>/dev/null" || echo "N/A"
}

# ─── BUILD: Go arm64 ───
build_go() {
    log "Go 빌드 (android/arm64)..."
    mkdir -p "$DIST_DIR"
    (cd "$PROJECT_DIR/go" && \
        GOOS=android GOARCH=arm64 CGO_ENABLED=0 \
        go build -ldflags='-s -w' -o "$DIST_DIR/homeagent-android-arm64" ./cmd/homeagent/)
    log "→ $(ls -lh "$DIST_DIR/homeagent-android-arm64" | awk '{print $5}')"
}

# ─── BUILD: Flutter APK ───
build_apk() {
    log "Flutter APK 빌드..."
    nix develop "$PROJECT_DIR#dev" --impure --command bash -c "
        cd $PROJECT_DIR/flutter && flutter build apk --release \
            --dart-define=SERVER_HOST=localhost
    "
    local APK="$PROJECT_DIR/flutter/build/app/outputs/flutter-apk/app-release.apk"
    [[ -f "$APK" ]] && log "→ $(ls -lh "$APK" | awk '{print $5}')" || warn "APK 빌드 실패"
}

# ─── PUSH: 아티팩트 전송 ───
cmd_push() {
    check_adb
    adb root 2>/dev/null && sleep 1

    # Go 바이너리
    if [[ -f "$DIST_DIR/homeagent-android-arm64" ]]; then
        log "Go 바이너리 push..."
        adb push "$DIST_DIR/homeagent-android-arm64" "$REMOTE/homeagent"
        adb shell "chmod 755 $REMOTE/homeagent"
    else
        warn "Go 바이너리 없음 — build 먼저"
    fi

    # OTBR
    if [[ -f "$DIST_DIR/otbr-arm64/otbr-agent" ]]; then
        log "OTBR push..."
        adb shell "mkdir -p $REMOTE/otbr"
        adb push "$DIST_DIR/otbr-arm64/otbr-agent" "$REMOTE/otbr/otbr-agent"
        adb push "$DIST_DIR/otbr-arm64/ot-ctl" "$REMOTE/otbr/ot-ctl"
        adb shell "chmod 755 $REMOTE/otbr/otbr-agent $REMOTE/otbr/ot-ctl"
    fi

    # UI
    if [[ -d "$PROJECT_DIR/ui/dist" ]]; then
        log "UI push..."
        adb shell "mkdir -p $REMOTE/ui"
        (cd "$PROJECT_DIR/ui" && tar czf /tmp/ha-ui-dist.tar.gz dist/)
        adb push /tmp/ha-ui-dist.tar.gz "$REMOTE/ui/dist.tar.gz"
        adb shell "cd $REMOTE/ui && tar xzf dist.tar.gz && rm dist.tar.gz"
        rm -f /tmp/ha-ui-dist.tar.gz
    fi

    # aliases.json
    [[ -f "$PROJECT_DIR/aliases.json" ]] && adb push "$PROJECT_DIR/aliases.json" "$REMOTE/aliases.json"

    log "push 완료"
}

# ─── INSTALL APK ───
cmd_install_apk() {
    check_adb
    local APK="$PROJECT_DIR/flutter/build/app/outputs/flutter-apk/app-release.apk"
    [[ -f "$APK" ]] || err "APK 없음: $APK — apk-build 먼저 실행"
    adb install -r "$APK"
    log "APK 설치 완료"
}

# ─── DEPLOY: 전체 ───
cmd_deploy() {
    local SKIP_GO=false SKIP_APK=false SKIP_MATTER=false
    for arg in "$@"; do
        case "$arg" in
            --skip-go) SKIP_GO=true ;;
            --skip-apk) SKIP_APK=true ;;
            --skip-matter) SKIP_MATTER=true ;;
        esac
    done

    check_adb
    adb root 2>/dev/null && sleep 1

    [[ "$SKIP_GO" == false ]] && build_go
    [[ "$SKIP_APK" == false ]] && build_apk

    cmd_push

    [[ "$SKIP_APK" == false ]] && cmd_install_apk

    cmd_start
    log "🎉 배포 완료"
}

# ─── MAIN ───
case "${1:-help}" in
    deploy)       shift; cmd_deploy "$@" ;;
    start)        cmd_start ;;
    stop)         cmd_stop ;;
    status)       cmd_status ;;
    logs)         shift; cmd_logs "${1:-all}" ;;
    thread-start) cmd_thread_start ;;
    thread-stop)  cmd_thread_stop ;;
    thread-status) cmd_thread_status ;;
    push|push-artifacts) cmd_push ;;
    install-apk)  cmd_install_apk ;;
    build-go)     build_go ;;
    build-apk)    build_apk ;;
    help|-h|*)
        echo "HomeAgent Android 배포"
        echo ""
        echo "사용: ./scripts/android-deploy.sh <command> [options]"
        echo ""
        echo "배포:"
        echo "  deploy [--skip-go] [--skip-apk] [--skip-matter]  전체 빌드+배포+시작"
        echo "  push-artifacts     아티팩트만 push (시작 안 함)"
        echo "  install-apk        APK만 설치"
        echo ""
        echo "서비스:"
        echo "  start              matterjs + Go 시작"
        echo "  stop               전체 중지"
        echo "  status             상태 확인"
        echo "  logs [target]      로그 (matter/go/otbr/all)"
        echo ""
        echo "Thread:"
        echo "  thread-start       OTBR + Thread 네트워크 시작"
        echo "  thread-stop        OTBR 중지"
        echo "  thread-status      Thread 상태"
        echo ""
        echo "빌드만:"
        echo "  build-go           Go arm64 빌드"
        echo "  build-apk          Flutter APK 빌드"
        echo ""
        echo "환경변수:"
        echo "  RCP_DEVICE         Thread RCP UART (기본: /dev/ttyS5)"
        echo "  RCP_BAUDRATE       UART 속도 (기본: 460800)"
        echo "  BACKBONE_IF        백본 인터페이스 (기본: wlan0)"
        echo "  WIFI_SSID          WiFi SSID"
        echo "  WIFI_PASSWORD      WiFi 비밀번호"
        ;;
esac
