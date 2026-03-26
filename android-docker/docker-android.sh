#!/system/bin/sh
# docker-android.sh — Android RK3576 네이티브 Docker 실행
#
# chroot 없음. Docker 바이너리를 직접 실행.
#
# 전제조건 (AOSP 이미지 패치):
#   006: Docker 커널 (PID_NS, USER_NS, IPC_NS, CGROUP_PIDS, CGROUP_DEVICE, SYSVIPC)
#   007: /dev/run tmpfs + /dev/cg_devices (devices cgroup v1)
#   010: /run tmpfs (containerd/dockerd 소켓)
#
# 파일 배치 (setup-docker.sh가 처리):
#   /data/local/tmp/docker/         Docker static binaries (29.3.0)
#   /data/local/tmp/docker-compose.yml
#   /data/local/tmp/*.tar.gz        Docker 이미지 (오프라인)
#
# 사용:
#   docker-android.sh start    Docker Engine 시작
#   docker-android.sh stop     Docker Engine 종료
#   docker-android.sh status   상태 확인
#   docker-android.sh load     이미지 로드
#   docker-android.sh up       docker-compose up -d
#   docker-android.sh down     docker-compose down
#   docker-android.sh exec     docker CLI (예: exec ps, exec logs matter-server)

set -euo pipefail

D="/data/local/tmp"
DOCKER_BIN="$D/docker"
DOCKER_DATA="$D/docker-data"
DOCKER_SOCK="/run/docker.sock"
export DOCKER_HOST="unix://$DOCKER_SOCK"
export PATH="$DOCKER_BIN:$PATH"

log()  { echo "[docker-android] $*"; }
err()  { echo "[docker-android] ERROR: $*" >&2; exit 1; }

# ─── Docker Engine 시작 ───
cmd_start() {
    log "=== Docker Engine 시작 (네이티브) ==="

    # SELinux permissive
    setenforce 0 2>/dev/null || true

    # ★ /proc hidepid 제거 — dockerd가 /proc/self/mountinfo 읽어야 함
    mount -o remount,hidepid=0 /proc
    log "/proc hidepid=0 OK"

    # ★ devices cgroup v1 → 표준 경로 bind
    # dockerd가 /sys/fs/cgroup/devices를 기대, Android는 /dev/cg_devices
    mkdir -p /sys/fs/cgroup/devices
    mount --bind /dev/cg_devices /sys/fs/cgroup/devices 2>/dev/null || true
    log "devices cgroup OK"

    # DNS + IPv6
    echo -e "nameserver 8.8.8.8\nnameserver 168.126.63.1" > /dev/run/resolv.conf 2>/dev/null || true
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || true
    log "network OK"

    # 기존 프로세스 정리
    pgrep -f containerd | xargs kill -9 2>/dev/null || true
    pgrep -f dockerd | xargs kill -9 2>/dev/null || true
    sleep 2

    # 디렉토리 준비
    mkdir -p /run/containerd /run/docker $DOCKER_DATA

    # ─── containerd ───
    # ★ PATH에 docker 바이너리 경로 포함 — containerd-shim이 runc를 찾음
    log "containerd 시작..."
    $DOCKER_BIN/containerd \
        --root $DOCKER_DATA/containerd \
        --state /run/containerd \
        --address /run/containerd/containerd.sock \
        > /run/containerd.log 2>&1 &
    sleep 4

    if ! pgrep -f "containerd" > /dev/null; then
        log "containerd 로그:"
        tail -10 /run/containerd.log 2>/dev/null
        err "containerd 시작 실패"
    fi
    log "containerd OK (PID $(pgrep -f containerd | head -1))"

    # ─── dockerd ───
    # ★ -H unix:///run/docker.sock — /var/run 없으므로 소켓 경로 명시
    # ★ --containerd /run/... — containerd 소켓 경로
    # ★ SSL_CERT_DIR — Android CA 인증서 경로 (docker pull TLS용)
    log "dockerd 시작..."
    SSL_CERT_DIR=/system/etc/security/cacerts \
    $DOCKER_BIN/dockerd \
        --data-root $DOCKER_DATA \
        --exec-root /run/docker \
        --pidfile /run/docker.pid \
        --containerd /run/containerd/containerd.sock \
        -H unix://$DOCKER_SOCK \
        --iptables=false \
        --dns 8.8.8.8 \
        --dns 168.126.63.1 \
        --exec-opt native.cgroupdriver=cgroupfs \
        --storage-driver vfs \
        > /run/dockerd.log 2>&1 &
    sleep 12

    if ! pgrep -f "dockerd" > /dev/null; then
        log "dockerd 로그:"
        tail -20 /run/dockerd.log 2>/dev/null
        err "dockerd 시작 실패"
    fi
    log "dockerd OK (PID $(pgrep -f dockerd | head -1))"

    # 확인
    $DOCKER_BIN/docker info > /run/docker-info.txt 2>&1 || true
    log "=== Docker Engine Ready ==="
    head -15 /run/docker-info.txt
}

# ─── Docker Engine 종료 ───
cmd_stop() {
    log "Docker 종료..."
    kill -9 $(pgrep -f dockerd) 2>/dev/null || true
    sleep 2
    kill -9 $(pgrep -f containerd) 2>/dev/null || true
    sleep 1
    umount /sys/fs/cgroup/devices 2>/dev/null || true
    log "종료 완료"
}

# ─── 상태 확인 ───
cmd_status() {
    echo "=== Docker Engine ==="
    pgrep -f dockerd > /dev/null 2>&1 \
        && echo "  dockerd:    running (PID $(pgrep -f dockerd | head -1))" \
        || echo "  dockerd:    not running"
    pgrep -f containerd > /dev/null 2>&1 \
        && echo "  containerd: running (PID $(pgrep -f containerd | head -1))" \
        || echo "  containerd: not running"
    echo ""
    echo "=== Containers ==="
    $DOCKER_BIN/docker ps -a --format "  {{.Names}}: {{.Status}}" 2>/dev/null \
        || echo "  (docker 실행 불가)"
    echo ""
    echo "=== OTBR (native) ==="
    pgrep -f otbr-agent > /dev/null 2>&1 \
        && echo "  otbr-agent: running (PID $(pgrep -f otbr-agent | head -1))" \
        || echo "  otbr-agent: not running"
    local _state=$($D/otbr/ot-ctl state 2>/dev/null | head -1)
    [ -n "$_state" ] && echo "  thread:     $_state" || echo "  thread:     (unknown)"
    echo ""
    echo "=== Images ==="
    $DOCKER_BIN/docker images --format "  {{.Repository}}:{{.Tag}} ({{.Size}})" 2>/dev/null \
        || echo "  (docker 실행 불가)"
}

# ─── Docker 이미지 로드 (오프라인) ───
cmd_load() {
    log "Docker 이미지 로드..."
    local loaded=0

    for tarfile in $D/*.tar $D/*.tar.gz; do
        [ -f "$tarfile" ] || continue
        log "로드: $(basename $tarfile)"
        case "$tarfile" in
            *.tar.gz) gunzip -c "$tarfile" | $DOCKER_BIN/docker load ;;
            *.tar)    cat "$tarfile" | $DOCKER_BIN/docker load ;;
        esac
        loaded=$((loaded + 1))
    done

    if [ $loaded -eq 0 ]; then
        log "로드할 이미지 없음."
    else
        log "$loaded 개 이미지 로드 완료"
        $DOCKER_BIN/docker images
    fi
}

# ─── docker-compose up ───
cmd_up() {
    log "docker-compose up -d..."
    $DOCKER_BIN/docker-compose -f $D/docker-compose.yml up -d
}

# ─── docker-compose down ───
cmd_down() {
    log "docker-compose down..."
    $DOCKER_BIN/docker-compose -f $D/docker-compose.yml down
}

# ─── 네이티브 OTBR 시작 ───
cmd_otbr_start() {
    local RCP_DEVICE="${RCP_DEVICE:-/dev/ttyS5}"
    local RCP_BAUDRATE="${RCP_BAUDRATE:-460800}"
    local WPAN_IF="wpan0"
    local OTBR_DIR="$D/otbr"
    local OTBR_DATA="$D/otbr-data"

    log "=== 네이티브 OTBR 시작 ==="

    # Android Thread HAL 제거 (UART 경합 방지)
    stop vendor.threadnetwork_hal 2>/dev/null || true
    stop ot-daemon 2>/dev/null || true
    for i in $(seq 1 5); do
        pkill -9 -f "threadnetwork\|ot-daemon" 2>/dev/null || true
        sleep 1
    done

    # SELinux + 디바이스 권한
    setenforce 0 2>/dev/null || true
    chmod 666 $RCP_DEVICE 2>/dev/null || true
    mkdir -p $OTBR_DATA

    # IPv6 forwarding
    ip tuntap del dev $WPAN_IF mode tun 2>/dev/null || true
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding

    # 기존 otbr-agent 정리
    pkill -f otbr-agent 2>/dev/null || true
    sleep 1

    # otbr-agent 시작 (최대 3회 재시도)
    local OTBR_STARTED=false
    for _try in $(seq 1 3); do
        # UART 초기화
        stty -F $RCP_DEVICE $RCP_BAUDRATE raw -echo -echoe -echok -echoctl 2>/dev/null || true
        printf '\x7e\x7e\x7e\x7e\x7e\x7e\x7e\x7e\x7e\x7e' > $RCP_DEVICE 2>/dev/null || true
        sleep 1

        setsid $OTBR_DIR/otbr-agent \
            -I $WPAN_IF -B wlan0 -d7 -v \
            --vendor-name HomeAgent --model-name OTBR \
            --data-path $OTBR_DATA \
            --rest-listen-address 127.0.0.1 --rest-listen-port 8081 \
            "spinel+hdlc+uart://$RCP_DEVICE?uart-baudrate=$RCP_BAUDRATE" \
            > /run/otbr-agent.log 2>&1 &
        sleep 5

        if pgrep -f otbr-agent > /dev/null; then
            OTBR_STARTED=true
            break
        fi
        log "otbr-agent 시작 실패 (시도 $_try/3) — 재시도..."
        pkill -f otbr-agent 2>/dev/null || true
        sleep 3
    done

    if [ "$OTBR_STARTED" != "true" ]; then
        log "ERROR: otbr-agent 3회 시도 모두 실패"
        tail -20 /run/otbr-agent.log 2>/dev/null
        return 1
    fi
    log "otbr-agent OK (시도 $_try/3)"

    # Thread dataset — 영속성 보장
    log "Thread dataset 로드 대기..."
    local EXISTING=""
    for _try in $(seq 1 5); do
        EXISTING=$($OTBR_DIR/ot-ctl dataset active -x 2>/dev/null | head -1)
        case "$EXISTING" in
            *Error*|*NotFound*|Done|"") sleep 2 ;;
            *) break ;;
        esac
    done

    if [ -n "$EXISTING" ] && [ "$EXISTING" != "Done" ]; then
        log "기존 dataset 사용 (otbr-data에서 복원)"
    elif [ -f "$OTBR_DATA/dataset-backup.hex" ]; then
        local BACKUP_HEX=$(cat $OTBR_DATA/dataset-backup.hex)
        if [ ${#BACKUP_HEX} -gt 20 ]; then
            log "백업에서 dataset 복원..."
            $OTBR_DIR/ot-ctl dataset set active "$BACKUP_HEX"
            $OTBR_DIR/ot-ctl dataset commit active
        else
            log "새 Thread 네트워크 생성 (백업 손상)..."
            $OTBR_DIR/ot-ctl dataset init new
            $OTBR_DIR/ot-ctl dataset networkname HomeAgent
            $OTBR_DIR/ot-ctl dataset commit active
        fi
    else
        log "새 Thread 네트워크 생성..."
        $OTBR_DIR/ot-ctl dataset init new
        $OTBR_DIR/ot-ctl dataset networkname HomeAgent
        $OTBR_DIR/ot-ctl dataset commit active
        # 새 dataset 백업
        sleep 1
        $OTBR_DIR/ot-ctl dataset active -x 2>/dev/null | head -1 > $OTBR_DATA/dataset-backup.hex
    fi

    $OTBR_DIR/ot-ctl ifconfig up
    $OTBR_DIR/ot-ctl thread start

    # leader 대기 (최대 30초)
    log "Thread leader 대기..."
    for i in $(seq 1 10); do
        sleep 3
        local STATE=$($OTBR_DIR/ot-ctl state 2>/dev/null | head -1)
        case "$STATE" in
            leader|router)
                log "Thread state: $STATE (${i}x3초)"
                break ;;
        esac
        [ $i -eq 10 ] && log "WARNING: Thread state: $STATE (타임아웃 30초)"
    done

    $OTBR_DIR/ot-ctl srp server enable 2>/dev/null || true

    # IPv6 라우팅은 Go homeagent가 시작 시 자동 설정 (ensureThreadRouting)
    # Android 정책 라우팅에서 wpan0 테이블을 ip -6 rule로 연결

    # dataset 출력
    $OTBR_DIR/ot-ctl dataset active 2>/dev/null | grep -E "Network|Channel|Pan" || true
    log "=== OTBR 시작 완료 ==="
}

# ─── 네이티브 OTBR 종료 ───
cmd_otbr_stop() {
    local OTBR_DIR="$D/otbr"
    $OTBR_DIR/ot-ctl thread stop 2>/dev/null || true
    $OTBR_DIR/ot-ctl ifconfig down 2>/dev/null || true
    pkill -f otbr-agent 2>/dev/null || true
    ip tuntap del dev wpan0 mode tun 2>/dev/null || true
    log "OTBR 종료"
}

# ─── Go homeagent + APK 시작 ───
# _start.sh가 setup-docker.sh(PC)에서 생성되어 보드에 있어야 함
cmd_go_start() {
    log "Go homeagent + APK 시작..."
    pgrep -f "homeagent serve" | xargs kill -9 2>/dev/null || true
    sleep 1

    if [ ! -f "$D/_start.sh" ]; then
        err "_start.sh 없음. setup-docker.sh를 먼저 실행하세요."
    fi

    nohup $D/_start.sh > /dev/null 2>&1 &
    sleep 5

    local go_pid=$(pgrep -f "homeagent serve" || true)
    if [ -z "$go_pid" ]; then
        log "homeagent 로그:"
        tail -10 /run/homeagent.log 2>/dev/null
        err "homeagent 시작 실패"
    fi
    log "homeagent OK (PID $go_pid, :8080)"
}

# ─── Go homeagent 서버 종료 ───
cmd_go_stop() {
    pgrep -f "homeagent serve" | xargs kill -9 2>/dev/null || true
    umount /system/etc/resolv.conf 2>/dev/null || true
    log "homeagent 종료"
}

# ─── 전체 스택 원커맨드 ───
cmd_all() {
    cmd_start       # Docker Engine
    cmd_load        # 이미지 로드
    cmd_otbr_start  # OTBR + Thread 먼저 (wpan0 + 라우팅 준비)
    cmd_go_start    # Go (ensureThreadRouting → IPv6 rule 설정)
    cmd_up          # matter-server 마지막 (Thread 라우팅 준비된 상태에서 시작)
    log "=== 전체 스택 기동 완료 ==="
    cmd_status
}

# ─── 부팅 자동시작 (init.rc → 이 커맨드 호출) ───
# init oneshot이 종료되면 cgroup 안의 자식 프로세스도 kill됨.
# 감시 루프로 프로세스를 유지하고, homeagent 죽으면 재시작.
cmd_boot() {
    cmd_all
    # 전체 스택 감시 — 죽은 프로세스 자동 재시작
    while true; do
        sleep 30
        pgrep -f "homeagent serve" > /dev/null || { log "homeagent 죽음 — 재시작"; cmd_go_start; }
        pgrep -f otbr-agent > /dev/null        || { log "otbr-agent 죽음 — 재시작"; cmd_otbr_start; }
        DOCKER_HOST=unix:///run/docker.sock $DOCKER_BIN/docker ps --filter name=matter-server --filter status=running -q 2>/dev/null | grep -q . \
            || { log "matter-server 죽음 — 재시작"; cmd_up; }
    done
}

# ─── docker CLI ───
cmd_exec() {
    $DOCKER_BIN/docker "$@"
}

# ─── Main ───
case "${1:-help}" in
    start)    cmd_start ;;
    stop)     cmd_stop; cmd_otbr_stop; cmd_go_stop ;;
    status)   cmd_status ;;
    load)     cmd_load ;;
    up)       cmd_up ;;
    down)     cmd_down ;;
    otbr-start)  cmd_otbr_start ;;
    otbr-stop)   cmd_otbr_stop ;;
    go-start)    cmd_go_start ;;
    go-stop)     cmd_go_stop ;;
    all)         cmd_all ;;
    boot)        cmd_boot ;;
    exec)     shift; cmd_exec "$@" ;;
    *)
        echo "Usage: $0 {all|start|stop|status|load|up|down|otbr-start|otbr-stop|go-start|go-stop|exec}"
        echo ""
        echo "  all         전체 스택 원커맨드 (Docker + 이미지 + matter-server + OTBR + Go + APK)"
        echo "  start       Docker Engine 시작"
        echo "  stop        전체 종료 (Docker + OTBR + Go)"
        echo "  status      상태 확인"
        echo "  load        이미지 로드"
        echo "  up          docker-compose up -d (matter-server)"
        echo "  down        docker-compose down"
        echo "  otbr-start  네이티브 OTBR 시작 + Thread 네트워크"
        echo "  otbr-stop   OTBR 종료"
        echo "  go-start    Go + APK 시작"
        echo "  go-stop     Go 종료"
        echo "  exec        docker CLI"
        ;;
esac
