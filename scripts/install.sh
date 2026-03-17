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

    # 0. 기존 프로세스 전부 정리
    for pattern in "homeagent serve" "MatterServer" "ld-linux.*node" "otbr-agent"; do
        adb shell "pkill -9 -f '$pattern' 2>/dev/null" || true
    done
    sleep 2

    # 1. Thread HAL 중지 — 연속 8회 kill로 apex crash limit 트리거하여 재시작 방지
    log "Thread HAL 제거 (8초)..."
    adb shell "stop vendor.threadnetwork_hal 2>/dev/null; stop ot-daemon 2>/dev/null" || true
    for i in $(seq 1 8); do
        adb shell "pkill -9 -f threadnetwork-service 2>/dev/null; pkill -9 -f ot-daemon 2>/dev/null" || true
        sleep 1
    done

    # 2. SELinux + 디렉토리 + DNS
    adb shell "setenforce 0 2>/dev/null" || true
    adb shell "mount -o rw,remount / 2>/dev/null; \
        mkdir -p /run /tmp $REMOTE/otbr-data 2>/dev/null" || true

    # DNS overlay (Android에 /etc/resolv.conf 없음 → Go HTTP/TLS 필요)
    log "DNS 설정..."
    adb shell "mkdir -p $REMOTE/etc_overlay 2>/dev/null && \
        cp -a /system/etc/* $REMOTE/etc_overlay/ 2>/dev/null; \
        echo 'nameserver 192.168.0.1
nameserver 8.8.8.8' > $REMOTE/etc_overlay/resolv.conf; \
        mount --bind $REMOTE/etc_overlay /system/etc 2>/dev/null" || true

    # 3. OTBR 시작 (setsid: init cgroup 자식 정리 방지, REST: :8081)
    log "OTBR 시작..."
    if adb shell "test -f $REMOTE/otbr/otbr-agent" 2>/dev/null; then
        adb shell "sysctl -w net.ipv6.conf.all.forwarding=1 2>/dev/null" || true
        adb shell "setsid $REMOTE/otbr/otbr-agent \
            -I wpan0 -B wlan0 -d7 -v \
            --vendor-name HomeAgent --model-name OTBR \
            --data-path $REMOTE/otbr-data \
            --rest-listen-address 127.0.0.1 --rest-listen-port 8081 \
            'spinel+hdlc+uart:///dev/ttyS5?uart-baudrate=460800' \
            > $REMOTE/otbr-agent.log 2>&1 &" < /dev/null
        sleep 5

        # Thread 네트워크 구성
        local EXISTING
        EXISTING=$(adb shell "$REMOTE/otbr/ot-ctl dataset active -x 2>/dev/null | head -1" | tr -d '\r' || true)
        if [[ -z "$EXISTING" ]] || [[ "$EXISTING" == "Done" ]] || [[ "$EXISTING" == *"Error"* ]] || [[ "$EXISTING" == *"NotFound"* ]]; then
            log "새 Thread 네트워크 생성..."
            adb shell "$REMOTE/otbr/ot-ctl dataset init new"
            adb shell "$REMOTE/otbr/ot-ctl dataset commit active"
        else
            log "기존 Thread dataset 사용"
        fi
        adb shell "$REMOTE/otbr/ot-ctl ifconfig up"
        adb shell "$REMOTE/otbr/ot-ctl thread start"
        adb shell "$REMOTE/otbr/ot-ctl srp server enable"

        # Leader 대기 (최대 30초)
        log "Thread leader 대기..."
        for i in $(seq 1 10); do
            sleep 3
            local STATE
            STATE=$(adb shell "$REMOTE/otbr/ot-ctl state" 2>/dev/null | head -1 | tr -d '\r')
            [[ "$STATE" == "leader" || "$STATE" == "router" ]] && { log "Thread: $STATE (${i}x3초)"; break; }
            [[ $i -eq 10 ]] && warn "Thread: $STATE (타임아웃 30초)"
        done

        # IPv6 정책 라우팅 — wpan0 테이블 자동 감지
        log "IPv6 정책 라우팅..."
        sleep 2
        local WPAN_TABLE
        WPAN_TABLE=$(adb shell "ip -6 route show table all dev wpan0 2>/dev/null" | \
            grep "table [0-9]" | head -1 | sed 's/.*table \([0-9]*\).*/\1/' || true)
        if [[ -n "$WPAN_TABLE" ]]; then
            if ! adb shell "ip -6 rule show" 2>/dev/null | grep -q "lookup $WPAN_TABLE"; then
                adb shell "ip -6 rule add from all lookup $WPAN_TABLE prio 15000 2>/dev/null" || true
            fi
            log "정책 라우팅: table $WPAN_TABLE"
        else
            warn "wpan0 라우트 테이블 감지 실패"
        fi
    else
        warn "OTBR 없음 (건너뜀)"
    fi

    # 4. matterjs-server (setsid: init cgroup 방지, HOME: Node.js homedir 에러 방지)
    log "matterjs 시작..."
    adb shell "cd $REMOTE/nodejs-bundle && \
        HOME=$REMOTE setsid lib/ld-linux-aarch64.so.1 --library-path lib ./node \
        --import ./matterjs-server/remote-ble/ws-bridge.js \
        matterjs-server/node_modules/matter-server/dist/esm/MatterServer.js \
        --storage-path $REMOTE/matter-data --port 5580 \
        --bluetooth-adapter 0 --primary-interface wlan0 \
        > $REMOTE/matterjs.log 2>&1 &"
    sleep 5

    # 5. Go homeagent (setsid: init cgroup 방지, 스크립트 파일 방식으로 adb 블록 방지)
    log "Go 서버 시작..."
    adb shell "cat > $REMOTE/_ha_start.sh << 'GOEOF'
#!/system/bin/sh
setsid sh -c "SSL_CERT_DIR=/etc/security/cacerts \
HOMEAGENT_HTTP_ADDR=:8080 \
HOMEAGENT_MATTER_WS=ws://localhost:5580 \
HOMEAGENT_UI_DIR=/data/local/tmp/ui/dist \
HOMEAGENT_ALIASES_FILE=/data/local/tmp/aliases.json \
HOMEAGENT_OT_CTL=/data/local/tmp/otbr/ot-ctl \
HOMEAGENT_OTBR_REST=http://127.0.0.1:8081 \
/data/local/tmp/homeagent serve" > /data/local/tmp/homeagent.log 2>&1 &
echo done
GOEOF
chmod +x $REMOTE/_ha_start.sh"
    adb shell "nohup $REMOTE/_ha_start.sh > /dev/null 2>&1 &" < /dev/null
    sleep 5

    # 6. APK
    log "APK 시작..."
    adb shell "am force-stop com.homeagent.app 2>/dev/null" || true
    sleep 1
    adb shell "am start -n com.homeagent.app/com.homeagent.homeagent.MainActivity" 2>/dev/null || true

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
