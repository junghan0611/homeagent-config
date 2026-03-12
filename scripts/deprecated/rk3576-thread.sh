#!/system/bin/sh
# RK3576 Thread Border Router 시작
# Usage: adb shell sh /data/local/tmp/rk3576-thread.sh [start|stop|status]
#
# 전제: otbr-agent, ot-ctl이 /data/local/tmp/otbr/ 에 있어야 함

OTBR_DIR="/data/local/tmp/otbr"
OTBR_AGENT="$OTBR_DIR/otbr-agent"
OT_CTL="$OTBR_DIR/ot-ctl"
RCP_DEVICE="/dev/ttyS5"
RCP_BAUDRATE="460800"
BACKBONE_IF="wlan0"
WPAN_IF="wpan0"
LOG_FILE="/data/local/tmp/otbr-agent.log"

case "${1:-start}" in
start)
    echo "[OTBR] Thread Border Router 시작..."

    # 1. Android Thread HAL 중지 (ttyS5 독점 방지)
    echo "[OTBR] Android Thread HAL 중지..."
    stop vendor.threadnetwork_hal 2>/dev/null
    stop ot-daemon 2>/dev/null
    sleep 1

    # HAL이 ttyS5 놓았는지 확인
    if fuser "$RCP_DEVICE" 2>/dev/null | grep -q .; then
        echo "[OTBR] ERROR: $RCP_DEVICE 아직 사용 중"
        fuser -v "$RCP_DEVICE" 2>/dev/null
        exit 1
    fi

    # 2. SELinux permissive
    echo "[OTBR] SELinux permissive..."
    setenforce 0

    # 3. ttyS5 권한
    chmod 666 "$RCP_DEVICE"

    # 4. wpan0 TUN 인터페이스
    echo "[OTBR] wpan0 TUN 생성..."
    ip tuntap del dev "$WPAN_IF" mode tun 2>/dev/null
    ip tuntap add dev "$WPAN_IF" mode tun
    ip link set "$WPAN_IF" up

    # 5. IPv6 forwarding
    sysctl -w net.ipv6.conf.all.forwarding=1

    # 6. otbr-agent 시작
    echo "[OTBR] otbr-agent 시작..."
    "$OTBR_AGENT" \
        -I "$WPAN_IF" \
        -B "$BACKBONE_IF" \
        -d7 \
        -v \
        "spinel+hdlc+uart://$RCP_DEVICE?uart-baudrate=$RCP_BAUDRATE" \
        > "$LOG_FILE" 2>&1 &

    AGENT_PID=$!
    sleep 3

    # otbr-agent 생존 확인
    if ! kill -0 "$AGENT_PID" 2>/dev/null; then
        echo "[OTBR] ERROR: otbr-agent 시작 실패"
        cat "$LOG_FILE"
        exit 1
    fi
    echo "[OTBR] otbr-agent PID=$AGENT_PID"

    # 7. Thread 네트워크 초기화
    echo "[OTBR] Thread 네트워크 초기화..."

    # 기존 dataset 확인
    EXISTING=$("$OT_CTL" dataset active -x 2>/dev/null | head -1)
    if [ -z "$EXISTING" ] || [ "$EXISTING" = "Done" ]; then
        echo "[OTBR] 새 Thread 네트워크 생성..."
        "$OT_CTL" dataset init new
        "$OT_CTL" dataset commit active
    else
        echo "[OTBR] 기존 dataset 사용: ${EXISTING:0:40}..."
    fi

    "$OT_CTL" ifconfig up
    "$OT_CTL" thread start

    sleep 5

    # 8. SRP server
    "$OT_CTL" srp server enable

    # 9. 상태 확인
    echo ""
    echo "=== Thread State ==="
    "$OT_CTL" state
    echo "=== SRP Server ==="
    "$OT_CTL" srp server state
    echo "=== Dataset (hex) ==="
    "$OT_CTL" dataset active -x
    echo "=== wpan0 ==="
    ip addr show "$WPAN_IF" | grep inet6 | head -3
    echo ""
    echo "[OTBR] ✅ Thread Border Router 시작 완료"
    echo "[OTBR] 로그: tail -f $LOG_FILE"
    ;;

stop)
    echo "[OTBR] Thread Border Router 중지..."
    "$OT_CTL" thread stop 2>/dev/null
    "$OT_CTL" ifconfig down 2>/dev/null
    killall otbr-agent 2>/dev/null
    ip tuntap del dev "$WPAN_IF" mode tun 2>/dev/null
    echo "[OTBR] 중지 완료"
    ;;

status)
    echo "=== otbr-agent ==="
    ps -A | grep otbr-agent | grep -v grep || echo "not running"
    echo ""
    echo "=== Thread State ==="
    "$OT_CTL" state 2>/dev/null || echo "not available"
    echo "=== SRP Server ==="
    "$OT_CTL" srp server state 2>/dev/null || echo "not available"
    echo "=== Dataset ==="
    "$OT_CTL" dataset active -x 2>/dev/null || echo "not available"
    echo "=== wpan0 ==="
    ip addr show "$WPAN_IF" 2>/dev/null | grep inet6 | head -3 || echo "no wpan0"
    ;;

*)
    echo "Usage: $0 [start|stop|status]"
    ;;
esac
