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

# ─── Thread 네트워크 초기화 ───
cmd_thread_init() {
    log "Thread 네트워크 초기화..."

    # OTBR REST 대기 (최대 30초)
    local state=""
    for i in $(seq 1 30); do
        state=$($D/curl -s http://localhost:8081/node/state 2>/dev/null | tr -d '"')
        [ -n "$state" ] && break
        sleep 1
    done

    if [ -z "$state" ]; then
        log "WARNING: OTBR REST 응답 없음 — Thread 초기화 건너뜀"
        return 0
    fi

    log "Thread state: $state"

    if [ "$state" != "disabled" ]; then
        log "Thread 이미 활성: $state"
        return 0
    fi

    # 기존 dataset 확인 (Docker volume에 남아있을 수 있음)
    local dataset=$($DOCKER_BIN/docker exec otbr ot-ctl dataset active 2>/dev/null)
    if echo "$dataset" | grep -q "Network Key"; then
        log "기존 dataset 발견 — 복원"
    else
        log "새 dataset 생성..."
        $DOCKER_BIN/docker exec otbr ot-ctl dataset init new
        $DOCKER_BIN/docker exec otbr ot-ctl dataset networkname HomeAgent
        $DOCKER_BIN/docker exec otbr ot-ctl dataset commit active
    fi

    $DOCKER_BIN/docker exec otbr ot-ctl ifconfig up
    $DOCKER_BIN/docker exec otbr ot-ctl thread start
    sleep 3

    state=$($D/curl -s http://localhost:8081/node/state 2>/dev/null | tr -d '"')
    log "Thread state: $state"

    # dataset 출력
    $DOCKER_BIN/docker exec otbr ot-ctl dataset active 2>/dev/null | grep -E "Network|Channel|Pan" || true
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
    cmd_up          # 컨테이너 시작
    sleep 5         # OTBR + matter-server 초기화 대기
    cmd_thread_init # Thread 네트워크
    cmd_go_start    # Go + APK
    log "=== 전체 스택 기동 완료 ==="
    cmd_status
}

# ─── docker CLI ───
cmd_exec() {
    $DOCKER_BIN/docker "$@"
}

# ─── Main ───
case "${1:-help}" in
    start)    cmd_start ;;
    stop)     cmd_stop; cmd_go_stop ;;
    status)   cmd_status ;;
    load)     cmd_load ;;
    up)       cmd_up ;;
    down)     cmd_down ;;
    thread-init) cmd_thread_init ;;
    go-start) cmd_go_start ;;
    go-stop)  cmd_go_stop ;;
    all)      cmd_all ;;
    exec)     shift; cmd_exec "$@" ;;
    *)
        echo "Usage: $0 {all|start|stop|status|load|up|down|go-start|go-stop|exec}"
        echo ""
        echo "  all        전체 스택 원커맨드 (Docker + 이미지 + 컨테이너 + Go + APK)"
        echo "  start      Docker Engine 시작"
        echo "  stop       전체 종료 (Docker + Go)"
        echo "  status     상태 확인"
        echo "  load       이미지 로드"
        echo "  up         docker-compose up -d"
        echo "  down       docker-compose down"
        echo "  go-start   Go + APK 시작"
        echo "  go-stop    Go 종료"
        echo "  exec       docker CLI"
        ;;
esac
