#!/usr/bin/env bash
# RK3576 원커맨드 배포 — Go + matterjs(remote-ble) + Flutter APK
# 사용: ./scripts/rk3576-deploy.sh [IP]
#   IP 생략 시 USB ADB (a9de248e89ff8063)
#
# 서브커맨드:
#   ./scripts/rk3576-deploy.sh           전체 배포
#   ./scripts/rk3576-deploy.sh start     서비스만 재시작
#   ./scripts/rk3576-deploy.sh logs      로그 확인
#   ./scripts/rk3576-deploy.sh status    상태 확인
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
REMOTE_DIR="/data/local/tmp"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[RK3576]${NC} $*"; }
warn() { echo -e "${YELLOW}[RK3576]${NC} $*"; }
err()  { echo -e "${RED}[RK3576]${NC} $*"; exit 1; }

# ADB 연결 확인
check_adb() {
    adb devices 2>/dev/null | grep -q "device$" || err "ADB 디바이스 없음"
    log "ADB 연결: $(adb devices | grep device$ | awk '{print $1}')"
}

# ─── 서브커맨드 ────────────────────────────────
cmd_start() {
    check_adb
    log "기존 프로세스 정리..."
    # Android pkill -f가 불안정 → PID 직접 kill
    adb shell "
        for pid in \$(ps -ef | grep -E 'homeagent serve|ld-linux.*node|MatterServer' | grep -v grep | awk '{print \$2}'); do
            kill \$pid 2>/dev/null
        done
    " || true
    sleep 2
    # 확인
    local REMAIN
    REMAIN=$(adb shell "ps -ef | grep -E 'homeagent serve|ld-linux.*node' | grep -v grep" 2>/dev/null || true)
    if [[ -n "$REMAIN" ]]; then
        warn "잔여 프로세스 강제 종료..."
        adb shell "
            for pid in \$(ps -ef | grep -E 'homeagent serve|ld-linux.*node|MatterServer' | grep -v grep | awk '{print \$2}'); do
                kill -9 \$pid 2>/dev/null
            done
        " || true
        sleep 1
    fi

    log "matterjs-server 시작 (remote-ble)..."
    # 시작 스크립트를 디바이스에 쓰고 실행 — adb shell 블록 방지
    adb shell "cat > $REMOTE_DIR/start-services.sh" << 'STARTEOF'
#!/system/bin/sh
RDIR=/data/local/tmp

# matterjs-server (remote-ble)
cd $RDIR/nodejs-bundle
lib/ld-linux-aarch64.so.1 --library-path lib ./node \
    --import ./matterjs-server/remote-ble/ws-bridge.js \
    matterjs-server/node_modules/matter-server/dist/esm/MatterServer.js \
    --storage-path $RDIR/matter-data \
    --port 5580 \
    --bluetooth-adapter 0 \
    > $RDIR/matterjs.log 2>&1 &

sleep 3

# Go homeagent
HOMEAGENT_HTTP_ADDR=:8080 \
HOMEAGENT_MATTER_WS=ws://localhost:5580 \
HOMEAGENT_UI_DIR=$RDIR/ui/dist \
HOMEAGENT_ALIASES_FILE=$RDIR/aliases.json \
$RDIR/homeagent serve \
    > $RDIR/homeagent.log 2>&1 &

echo "services started"
STARTEOF
    adb shell "chmod +x $REMOTE_DIR/start-services.sh"
    adb shell "nohup $REMOTE_DIR/start-services.sh > /dev/null 2>&1 &" < /dev/null
    sleep 5

    log "프로세스 확인..."
    adb shell "ps -ef | grep -E 'homeagent serve|ld-linux.*node.*Matter' | grep -v grep" || warn "프로세스 미확인"

    # BLE WS, matterjs WS, Go HTTP 포트 확인
    sleep 2
    adb shell "netstat -tlnp 2>/dev/null | grep -E '5580|5581|8080'" || true
    log "완료! matterjs(:5580) + BLE relay(:5581) + Go(:8080)"
}

cmd_logs() {
    check_adb
    local target="${1:-all}"
    case "$target" in
        matter*) adb shell "tail -50 $REMOTE_DIR/matterjs.log" ;;
        go|ha)   adb shell "tail -50 $REMOTE_DIR/homeagent.log" ;;
        *)
            echo "=== matterjs ===" 
            adb shell "tail -20 $REMOTE_DIR/matterjs.log"
            echo ""
            echo "=== homeagent ==="
            adb shell "tail -20 $REMOTE_DIR/homeagent.log"
            ;;
    esac
}

cmd_status() {
    check_adb
    echo "=== 프로세스 ==="
    adb shell "ps -ef | grep -E 'homeagent|node.*Matter' | grep -v grep" || echo "(없음)"
    echo ""
    echo "=== 포트 ==="
    adb shell "netstat -tlnp 2>/dev/null | grep -E '5580|5581|8080'" || echo "(없음)"
    echo ""
    echo "=== matterjs 마지막 로그 ==="
    adb shell "tail -5 $REMOTE_DIR/matterjs.log 2>/dev/null" || echo "(없음)"
    echo ""
    echo "=== Flutter APK ==="
    adb shell "dumpsys package com.homeagent.app 2>/dev/null | grep -E 'versionName|lastUpdate'" || echo "(미설치)"
}

# ─── 전체 배포 ────────────────────────────────
cmd_deploy() {
    check_adb
    local SKIP_GO=false SKIP_MATTER=false SKIP_APK=false
    for arg in "$@"; do
        case "$arg" in
            --skip-go) SKIP_GO=true ;;
            --skip-matter) SKIP_MATTER=true ;;
            --skip-apk) SKIP_APK=true ;;
        esac
    done

    # 1. Go 빌드 + 배포
    if [[ "$SKIP_GO" == false ]]; then
        log "1/3 Go 빌드 (android/arm64)..."
        mkdir -p "$DIST_DIR"
        (cd "$PROJECT_DIR/go" && \
            GOOS=android GOARCH=arm64 CGO_ENABLED=0 \
            go build -ldflags='-s -w' -o "$DIST_DIR/homeagent-android-arm64" ./cmd/homeagent/)
        log "  → $(ls -lh "$DIST_DIR/homeagent-android-arm64" | awk '{print $5}')"

        adb push "$DIST_DIR/homeagent-android-arm64" "$REMOTE_DIR/homeagent"
        adb shell "chmod +x $REMOTE_DIR/homeagent"
    fi

    # 2. matterjs 번들 업데이트 (remote-ble + 더미 패키지)
    if [[ "$SKIP_MATTER" == false ]]; then
        log "2/3 matterjs remote-ble 배포..."

        # remote-ble 디렉토리
        adb shell "mkdir -p $REMOTE_DIR/nodejs-bundle/matterjs-server/remote-ble"
        for f in "$PROJECT_DIR/matterjs-server/remote-ble/"*.js "$PROJECT_DIR/matterjs-server/remote-ble/package.json"; do
            adb push "$f" "$REMOTE_DIR/nodejs-bundle/matterjs-server/remote-ble/" 2>/dev/null
        done

        # 더미 @matter/nodejs-ble (noble 방지)
        local REMOTE_BLE="$REMOTE_DIR/nodejs-bundle/matterjs-server/node_modules/@matter/nodejs-ble"
        adb shell "rm -rf $REMOTE_BLE && mkdir -p $REMOTE_BLE/dist/esm $REMOTE_BLE/dist/cjs"
        adb push "$PROJECT_DIR/matterjs-server/remote-ble/dummy-nodejs-ble-index.js" \
                 "$REMOTE_BLE/dist/esm/index.js"
        adb push "$PROJECT_DIR/matterjs-server/remote-ble/dummy-nodejs-ble-index.js" \
                 "$REMOTE_BLE/dist/cjs/index.js"

        # 더미 package.json
        local TMP_PKG=$(mktemp)
        cat > "$TMP_PKG" << 'DPKG'
{"name":"@matter/nodejs-ble","version":"0.0.0-dummy","type":"module","main":"dist/cjs/index.js","exports":{".":{"import":"./dist/esm/index.js","require":"./dist/cjs/index.js"}}}
DPKG
        adb push "$TMP_PKG" "$REMOTE_BLE/package.json"
        rm -f "$TMP_PKG"

        # @stoprocent/noble 제거
        adb shell "rm -rf $REMOTE_DIR/nodejs-bundle/matterjs-server/node_modules/@stoprocent" 2>/dev/null || true

        # @matter/nodejs 확인 (optional dep)
        local HAS_NODEJS
        HAS_NODEJS=$(adb shell "ls $REMOTE_DIR/nodejs-bundle/matterjs-server/node_modules/@matter/nodejs/package.json 2>/dev/null" || true)
        if [[ -z "$HAS_NODEJS" ]]; then
            warn "@matter/nodejs 없음 — 로컬 번들에서 복사..."
            if [[ -d "$DIST_DIR/homeagent-bundle-arm64/matterjs-server/node_modules/@matter/nodejs" ]]; then
                adb push "$DIST_DIR/homeagent-bundle-arm64/matterjs-server/node_modules/@matter/nodejs" \
                         "$REMOTE_DIR/nodejs-bundle/matterjs-server/node_modules/@matter/nodejs/"
            else
                warn "@matter/nodejs 로컬 번들에도 없음! bundle-backend.sh 먼저 실행 필요"
            fi
        fi

        # ws 패키지 확인
        local HAS_WS
        HAS_WS=$(adb shell "ls $REMOTE_DIR/nodejs-bundle/matterjs-server/node_modules/ws/package.json 2>/dev/null" || true)
        if [[ -z "$HAS_WS" ]]; then
            warn "ws 패키지 없음 — 로컬 번들에서 복사..."
            if [[ -d "$DIST_DIR/homeagent-bundle-arm64/matterjs-server/node_modules/ws" ]]; then
                adb push "$DIST_DIR/homeagent-bundle-arm64/matterjs-server/node_modules/ws" \
                         "$REMOTE_DIR/nodejs-bundle/matterjs-server/node_modules/ws/"
            fi
        fi

        log "  → remote-ble 6 files + dummy nodejs-ble + noble 제거"
    fi

    # 3. Flutter APK 빌드 + 설치
    if [[ "$SKIP_APK" == false ]]; then
        log "3/3 Flutter APK 빌드..."
        # RK3576 IP (Go 서버 = localhost, 앱이 같은 기기에서 실행)
        local SERVER_HOST="localhost"
        nix develop "$PROJECT_DIR#dev" --impure --command bash -c "
            cd $PROJECT_DIR/flutter && flutter build apk --release \
                --dart-define=SERVER_HOST=$SERVER_HOST
        "
        local APK="$PROJECT_DIR/flutter/build/app/outputs/flutter-apk/app-release.apk"
        if [[ -f "$APK" ]]; then
            log "  → $(ls -lh "$APK" | awk '{print $5}')"
            adb install -r "$APK"
            log "  APK 설치 완료"
        else
            warn "APK 빌드 실패"
        fi
    fi

    # 4. 서비스 (재)시작
    cmd_start
}

# ─── 메인 ────────────────────────────────
case "${1:-deploy}" in
    start)   cmd_start ;;
    logs)    shift; cmd_logs "${1:-all}" ;;
    status)  cmd_status ;;
    stop)
        check_adb
        adb shell "pkill -f 'homeagent serve' 2>/dev/null; pkill -f 'ld-linux.*node.*MatterServer' 2>/dev/null" || true
        log "프로세스 종료"
        ;;
    deploy|"")
        shift 2>/dev/null || true
        cmd_deploy "$@"
        ;;
    help|-h)
        echo "사용: ./scripts/rk3576-deploy.sh [명령] [옵션]"
        echo ""
        echo "명령:"
        echo "  deploy         전체 배포 (기본값)"
        echo "  start          서비스만 (재)시작"
        echo "  stop           서비스 종료"
        echo "  status         상태 확인"
        echo "  logs [target]  로그 (matter/go/all)"
        echo ""
        echo "옵션:"
        echo "  --skip-go      Go 빌드 건너뜀"
        echo "  --skip-matter  matterjs 업데이트 건너뜀"
        echo "  --skip-apk     Flutter APK 건너뜀"
        ;;
    *) err "알 수 없는 명령: $1" ;;
esac
