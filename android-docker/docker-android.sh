#!/system/bin/sh
# docker-android.sh — Android RK3576에서 Docker Engine 실행 (chroot 방식)
#
# 참고: kyungdong-rockchip/docs/DOCKER-ON-ANDROID-GUIDE.md
#
# 전제조건 (AOSP 이미지):
#   - 패치 006: Docker 커널 (PID_NS, USER_NS, CGROUP)
#   - 패치 007: /dev/run tmpfs + /dev/cg_devices (devices cgroup v1)
#
# Android 특성:
#   - chroot 안에 mount/sh 바이너리 없음 → 밖에서 mount, static binary 직접 실행
#   - mountpoint -q 불안정 → umount 후 재마운트
#   - / 는 dm-verity read-only → /data 에만 쓰기 가능
#
# 사용:
#   docker-android.sh start     Docker Engine 시작
#   docker-android.sh stop      Docker Engine 종료
#   docker-android.sh status    상태 확인
#   docker-android.sh load      Docker 이미지 로드
#   docker-android.sh exec ...  chroot 안에서 docker CLI 실행

set -euo pipefail

R="/data/local/tmp/rootfs"
D="/data/local/tmp"
DOCKER_BIN="$D/docker"
DOCKER_DATA="$D/docker-data"

log()  { echo "[docker-android] $*"; }
err()  { echo "[docker-android] ERROR: $*" >&2; exit 1; }

# ─── chroot rootfs 구성 ───
setup_rootfs() {
    log "rootfs 구성..."

    # 디렉토리 구조
    mkdir -p $R/{run,dev,proc,sys,tmp,etc,opt/docker,opt/docker-data}
    mkdir -p $R/{etc/docker,etc/ssl/certs}
    mkdir -p $DOCKER_DATA

    # bind mount — umount 후 재마운트 (Android에 mountpoint -q 불안정)
    umount -R $R/dev 2>/dev/null || true;          mount --rbind /dev  $R/dev
    umount -R $R/sys 2>/dev/null || true;          mount --rbind /sys  $R/sys
    umount    $R/run 2>/dev/null || true;          mount --bind /dev/run $R/run
    umount    $R/tmp 2>/dev/null || true;          mount -t tmpfs tmpfs $R/tmp
    umount    $R/opt/docker-data 2>/dev/null || true; mount --bind $DOCKER_DATA $R/opt/docker-data

    # ★ /proc — mount -t proc (hidepid=invisible 제거)
    # Android 기본 proc는 hidepid=invisible → chroot에서 /proc/self/mountinfo 못 읽음
    # dockerd가 cgroup 경로 탐지에 mountinfo 필수 → 새 proc 인스턴스 마운트
    umount $R/proc 2>/dev/null || true
    mount -t proc proc $R/proc

    # ★ devices cgroup v1 — dockerd가 /sys/fs/cgroup/devices 경로 기대
    # Android는 /dev/cg_devices에 마운트 (AOSP 패치 007)
    # rbind /sys만으로는 /sys/fs/cgroup/devices에 안 잡힘 → 직접 bind
    mkdir -p $R/sys/fs/cgroup/devices
    umount $R/sys/fs/cgroup/devices 2>/dev/null || true
    mount --bind /dev/cg_devices $R/sys/fs/cgroup/devices

    mkdir -p $R/run/containerd $R/run/docker

    # mount propagation — runc가 MS_REC|MS_PRIVATE 할 수 있게
    # ★ chroot 안에 mount 바이너리가 없으므로 밖에서 $R 자체를 설정
    mount --bind $R $R 2>/dev/null || true
    mount --make-rshared $R

    # Docker 바이너리 (static binary — sh 없이 직접 실행)
    if [ -d "$DOCKER_BIN" ]; then
        cp $DOCKER_BIN/* $R/opt/docker/ 2>/dev/null || true
        chmod 755 $R/opt/docker/*
    else
        log "WARNING: $DOCKER_BIN 디렉토리 없음. 바이너리가 이미 rootfs에 있어야 합니다."
    fi

    # ★ runc를 표준 PATH 경로에 복사 — containerd-shim이 chroot 상속 안 함
    # shim이 fork될 때 $PATH에서 runc를 찾으므로 /usr/bin, /sbin에 있어야 함
    mkdir -p $R/usr/bin $R/sbin
    cp $R/opt/docker/runc $R/usr/bin/runc 2>/dev/null || true
    cp $R/opt/docker/runc $R/sbin/runc 2>/dev/null || true
    cp $R/opt/docker/containerd-shim-runc-v2 $R/usr/bin/containerd-shim-runc-v2 2>/dev/null || true

    # DNS + hosts
    echo -e "nameserver 8.8.8.8\nnameserver 168.126.63.1" > $R/etc/resolv.conf
    echo "127.0.0.1 localhost" > $R/etc/hosts

    # CA 인증서 (docker pull TLS)
    cat /system/etc/security/cacerts/* > $R/etc/ssl/certs/ca-certificates.crt 2>/dev/null || true

    # daemon.json — vfs driver (f2fs overlay 호환 이슈 회피)
    cat > $R/etc/docker/daemon.json <<'EOF'
{
  "storage-driver": "vfs",
  "features": {"buildkit": false}
}
EOF

    # docker-compose.yml → chroot 안으로 복사
    mkdir -p $R/opt/compose
    cp $D/docker-compose.yml $R/opt/compose/ 2>/dev/null || true

    log "rootfs 준비 완료"
}

# ─── Docker Engine 시작 ───
cmd_start() {
    log "=== Docker Engine 시작 ==="

    # 런타임 설정 (SELinux가 init.rc에서 차단하는 것들)
    setenforce 0 2>/dev/null || true
    echo -e "nameserver 8.8.8.8\nnameserver 168.126.63.1" > /dev/run/resolv.conf 2>/dev/null || true
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || true

    # 기존 프로세스 정리
    pkill -f containerd 2>/dev/null || true
    pkill -f dockerd 2>/dev/null || true
    sleep 2

    setup_rootfs

    # ─── containerd (chroot, static binary 직접 실행) ───
    # ★ PATH 필수 — containerd가 shim을 fork할 때 이 PATH를 상속
    #   shim이 runc를 $PATH에서 찾음 (chroot 상속 안 함)
    log "containerd 시작..."
    PATH=/opt/docker:/usr/bin:/usr/local/bin:/sbin:/bin \
    chroot $R /opt/docker/containerd \
        --root /opt/docker-data/containerd \
        --state /run/containerd \
        > $D/containerd.log 2>&1 &
    sleep 4

    if ! pgrep -f "containerd" > /dev/null; then
        log "containerd 로그:"
        tail -20 $D/containerd.log 2>/dev/null
        err "containerd 시작 실패"
    fi
    log "containerd OK (PID $(pgrep -f containerd | head -1))"

    # ─── dockerd (chroot, static binary 직접 실행) ───
    log "dockerd 시작..."
    PATH=/opt/docker:/usr/bin:/usr/local/bin:/sbin:/bin \
    TMPDIR=/tmp \
    SSL_CERT_DIR=/etc/ssl/certs \
    DOCKER_BUILDKIT=0 \
    chroot $R /opt/docker/dockerd \
        --data-root /opt/docker-data \
        --userland-proxy-path /opt/docker/docker-proxy \
        --init-path /opt/docker/docker-init \
        --iptables=false \
        --dns 8.8.8.8 \
        --dns 168.126.63.1 \
        --exec-opt native.cgroupdriver=cgroupfs \
        > $D/dockerd.log 2>&1 &
    sleep 10

    if ! pgrep -f "dockerd" > /dev/null; then
        log "dockerd 로그:"
        tail -30 $D/dockerd.log 2>/dev/null
        err "dockerd 시작 실패"
    fi
    log "dockerd OK (PID $(pgrep -f dockerd | head -1))"

    # 확인
    chroot $R /opt/docker/docker info > $D/docker-info.txt 2>&1 || true
    log "=== Docker Engine Ready ==="
    head -20 $D/docker-info.txt
}

# ─── Docker Engine 종료 ───
cmd_stop() {
    log "Docker 종료..."
    pkill -f dockerd 2>/dev/null || true
    sleep 2
    pkill -f containerd 2>/dev/null || true
    sleep 1

    # ⚠️ unmount 순서 중요!
    # rbind된 /dev를 해제 안 하고 rm하면 실제 디바이스 노드 삭제됨
    # rootfs 자체는 절대 rm -rf 하지 않는다
    log "unmount..."
    umount $R/opt/docker-data 2>/dev/null || true
    umount $R/tmp 2>/dev/null || true
    umount $R/run 2>/dev/null || true
    umount $R/sys/fs/cgroup/devices 2>/dev/null || true  # devices cgroup bind
    umount -l $R/sys 2>/dev/null || true     # lazy — busy여도 해제
    umount -l $R/proc 2>/dev/null || true
    umount -l $R/dev 2>/dev/null || true     # ★ /dev rbind 해제 필수
    umount $R 2>/dev/null || true            # rootfs bind (propagation)

    log "종료 완료"
}

# ─── 상태 확인 ───
cmd_status() {
    echo "=== Docker Engine ==="
    if pgrep -f dockerd > /dev/null 2>&1; then
        echo "  dockerd:    running (PID $(pgrep -f dockerd | head -1))"
    else
        echo "  dockerd:    not running"
    fi
    if pgrep -f containerd > /dev/null 2>&1; then
        echo "  containerd: running (PID $(pgrep -f containerd | head -1))"
    else
        echo "  containerd: not running"
    fi

    echo ""
    echo "=== Containers ==="
    chroot $R /opt/docker/docker ps -a --format "  {{.Names}}: {{.Status}}" 2>/dev/null || echo "  (docker CLI 실행 불가)"

    echo ""
    echo "=== Images ==="
    chroot $R /opt/docker/docker images --format "  {{.Repository}}:{{.Tag}} ({{.Size}})" 2>/dev/null || echo "  (docker CLI 실행 불가)"
}

# ─── Docker 이미지 로드 (오프라인) ───
cmd_load() {
    log "Docker 이미지 로드..."
    local loaded=0

    for tarfile in $D/*.tar $D/*.tar.gz; do
        [ -f "$tarfile" ] || continue
        log "로드: $tarfile"
        case "$tarfile" in
            *.tar.gz) gunzip -c "$tarfile" | chroot $R /opt/docker/docker load ;;
            *.tar)    cat "$tarfile" | chroot $R /opt/docker/docker load ;;
        esac
        loaded=$((loaded + 1))
    done

    if [ $loaded -eq 0 ]; then
        log "로드할 이미지 없음. $D/*.tar 또는 $D/*.tar.gz 파일을 올려주세요."
    else
        log "$loaded 개 이미지 로드 완료"
        chroot $R /opt/docker/docker images
    fi
}

# ─── docker-compose up ───
cmd_up() {
    log "docker-compose up -d..."
    chroot $R /opt/docker/docker-compose \
        -f /opt/compose/docker-compose.yml \
        up -d
}

# ─── docker-compose down ───
cmd_down() {
    log "docker-compose down..."
    chroot $R /opt/docker/docker-compose \
        -f /opt/compose/docker-compose.yml \
        down
}

# ─── chroot 안에서 docker CLI 실행 ───
cmd_exec() {
    chroot $R /opt/docker/docker "$@"
}

# ─── Main ───
case "${1:-help}" in
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    status)  cmd_status ;;
    load)    cmd_load ;;
    up)      cmd_up ;;
    down)    cmd_down ;;
    exec)    shift; cmd_exec "$@" ;;
    *)
        echo "Usage: $0 {start|stop|status|load|up|down|exec} [args]"
        echo ""
        echo "  start    Docker Engine 시작 (chroot)"
        echo "  stop     Docker Engine 종료 + unmount"
        echo "  status   상태 확인 (프로세스 + 컨테이너)"
        echo "  load     /data/local/tmp/*.tar{.gz} 이미지 로드"
        echo "  up       docker-compose up -d (서비스 시작)"
        echo "  down     docker-compose down (서비스 종료)"
        echo "  exec     chroot 안에서 docker CLI (예: $0 exec ps)"
        ;;
esac
