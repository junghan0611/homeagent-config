#!/usr/bin/env bash
# install.sh — HomeAgent 보드 원터치 설치
#
# 사전 조건:
#   - adb devices로 보드가 보여야 함
#   - dist/ 안에 빌드 산출물이 있어야 함 (./run.sh android deploy 가 빌드)
#   - 또는 미리 빌드된 아티팩트를 dist/에 배치
#
# 사용:
#   ./install.sh              # 전체 설치 + 시작
#   ./install.sh --install    # 설치만 (시작 안 함)
#   ./install.sh --start      # 시작만
#   ./install.sh --status     # 상태 확인

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
REMOTE="/data/local/tmp"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[install]${NC} $*"; }
warn() { echo -e "${YELLOW}[install]${NC} $*"; }
err()  { echo -e "${RED}[install]${NC} $*" >&2; }

# ─── ADB 확인 ───

check_adb() {
    if ! command -v adb &>/dev/null; then
        err "adb not found"
        exit 1
    fi
    local count
    count=$(adb devices | grep -c "device$" || true)
    if [[ "$count" -lt 1 ]]; then
        err "보드가 연결되지 않았습니다 (adb devices 확인)"
        exit 1
    fi
    adb root 2>/dev/null && sleep 1
    log "ADB: $(adb devices | grep device$ | awk '{print $1}')"
}

# ─── 설치 ───

do_install() {
    log "=== HomeAgent 설치 시작 ==="

    # 1. Go 바이너리
    local go_bin="$DIST_DIR/homeagent-android-arm64"
    if [[ -f "$go_bin" ]]; then
        log "Go 바이너리 push..."
        adb push "$go_bin" "$REMOTE/homeagent"
        adb shell "chmod 755 $REMOTE/homeagent"
    else
        warn "Go 바이너리 없음: $go_bin (건너뜀)"
    fi

    # 2. OTBR
    if [[ -d "$DIST_DIR/otbr-arm64" ]]; then
        log "OTBR push..."
        adb shell "mkdir -p $REMOTE/otbr"
        adb push "$DIST_DIR/otbr-arm64/otbr-agent" "$REMOTE/otbr/otbr-agent"
        adb push "$DIST_DIR/otbr-arm64/ot-ctl" "$REMOTE/otbr/ot-ctl"
        adb shell "chmod 755 $REMOTE/otbr/otbr-agent $REMOTE/otbr/ot-ctl"
    else
        warn "OTBR 없음 (건너뜀)"
    fi

    # 3. UI dist
    if [[ -d "$PROJECT_DIR/ui/dist" ]]; then
        log "UI push..."
        adb shell "mkdir -p $REMOTE/ui"
        (cd "$PROJECT_DIR/ui" && tar czf /tmp/ha-ui-dist.tar.gz dist/)
        adb push /tmp/ha-ui-dist.tar.gz "$REMOTE/ui/dist.tar.gz"
        adb shell "cd $REMOTE/ui && tar xzf dist.tar.gz && rm dist.tar.gz"
    else
        warn "UI 없음 (건너뜀)"
    fi

    # 4. nodejs-bundle
    local bundle_dir="$DIST_DIR/nodejs-android-bundle"
    [[ ! -d "$bundle_dir" ]] && bundle_dir="$DIST_DIR/homeagent-bundle-arm64/nodejs-bundle"
    if [[ -d "$bundle_dir" ]]; then
        # 이미 있으면 remote-ble만 업데이트
        local remote_exists
        remote_exists=$(adb shell "test -f $REMOTE/nodejs-bundle/node && echo yes || echo no" | tr -d '\r')
        if [[ "$remote_exists" == "yes" ]]; then
            log "nodejs-bundle 이미 존재 — remote-ble만 업데이트"
        else
            log "nodejs-bundle 전체 push (~300MB)..."
            (cd "$bundle_dir/.." && tar czf /tmp/ha-nodejs-bundle.tar.gz "$(basename "$bundle_dir")")
            adb push /tmp/ha-nodejs-bundle.tar.gz "$REMOTE/nodejs-bundle/bundle.tar.gz"
            adb shell "cd $REMOTE/nodejs-bundle && tar xzf bundle.tar.gz --strip-components=1 && rm bundle.tar.gz"
        fi
        # remote-ble 항상 최신으로
        if [[ -d "$PROJECT_DIR/matterjs-server/remote-ble" ]]; then
            adb push "$PROJECT_DIR/matterjs-server/remote-ble/" \
                "$REMOTE/nodejs-bundle/matterjs-server/remote-ble/"
        fi
    else
        warn "nodejs-bundle 없음 (건너뜀)"
    fi

    # 5. aliases.json
    if [[ -f "$PROJECT_DIR/aliases.json" ]]; then
        adb push "$PROJECT_DIR/aliases.json" "$REMOTE/aliases.json"
    fi

    # 6. APK
    local apk="$PROJECT_DIR/flutter/build/app/outputs/flutter-apk/app-release.apk"
    if [[ -f "$apk" ]]; then
        log "APK 설치..."
        adb install -r "$apk"
    else
        warn "APK 없음: $apk (건너뜀)"
    fi

    log "=== 설치 완료 ==="
}

# ─── 시작 ───

do_start() {
    log "=== 서비스 시작 ==="

    # 1. 기존 프로세스 정리
    adb shell "pkill -f MatterServer 2>/dev/null" || true
    adb shell "pkill -f 'homeagent serve' 2>/dev/null" || true
    sleep 1

    # 2. matterjs-server
    log "matterjs 시작..."
    adb shell "cd $REMOTE/nodejs-bundle && \
        nohup lib/ld-linux-aarch64.so.1 --library-path lib ./node \
        --import ./matterjs-server/remote-ble/ws-bridge.js \
        matterjs-server/node_modules/matter-server/dist/esm/MatterServer.js \
        --storage-path $REMOTE/matter-data --port 5580 \
        --bluetooth-adapter 0 --primary-interface wlan0 \
        > $REMOTE/matterjs.log 2>&1 &"
    sleep 4

    # 3. Go homeagent
    log "Go 서버 시작..."
    adb shell "cd $REMOTE && \
        HOMEAGENT_MATTER_WS=ws://localhost:5580 \
        HOMEAGENT_ALIASES_FILE=$REMOTE/aliases.json \
        HOMEAGENT_UI_DIR=$REMOTE/ui/dist \
        nohup ./homeagent serve > $REMOTE/homeagent.log 2>&1 &"
    sleep 2

    # 4. APK
    log "APK 시작..."
    adb shell "am force-stop com.homeagent.app 2>/dev/null" || true
    adb shell "am start -n com.homeagent.app/com.homeagent.homeagent.MainActivity"

    do_status
    log "=== 시작 완료 ==="
}

# ─── 상태 ───

do_status() {
    log "=== 상태 확인 ==="
    echo "--- 프로세스 ---"
    adb shell "ps -ef | grep -E 'MatterServer|homeagent|otbr-agent|com.homeagent' | grep -v grep" || echo "(없음)"
    echo ""
    echo "--- 포트 ---"
    adb shell "netstat -tlnp 2>/dev/null | grep -E '5580|5581|8080'" || echo "(없음)"
    echo ""
    echo "--- Thread ---"
    adb shell "$REMOTE/otbr/ot-ctl state 2>/dev/null" || echo "(OTBR 미실행)"
    echo ""
    echo "--- API ---"
    local ip
    ip=$(adb shell "ip addr show wlan0 | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" | tr -d '\r')
    if [[ -n "$ip" ]]; then
        curl -s --connect-timeout 2 "http://$ip:8080/healthz" 2>/dev/null || echo "(API 응답 없음)"
    else
        echo "(wlan0 IP 없음)"
    fi
}

# ─── MAIN ───

case "${1:-all}" in
    --install|-i)  check_adb; do_install ;;
    --start|-s)    check_adb; do_start ;;
    --status|-t)   check_adb; do_status ;;
    all|"")        check_adb; do_install; do_start ;;
    -h|--help|*)
        echo "HomeAgent 보드 설치 스크립트"
        echo ""
        echo "사용: ./install.sh [옵션]"
        echo ""
        echo "  (없음)       전체 설치 + 시작"
        echo "  --install    설치만"
        echo "  --start      시작만"
        echo "  --status     상태 확인"
        ;;
esac
