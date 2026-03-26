#!/system/bin/sh
# docker-android.sh — Android에서 Docker 실행 (chroot 방식)
#
# 참고: kyungdong-rockchip/docs/DOCKER-ON-ANDROID-GUIDE.md
#
# 전제조건 (AOSP 이미지):
#   - 패치 006: Docker 커널 (PID_NS, USER_NS, CGROUP)
#   - 패치 007: /dev/run tmpfs + /dev/cg_devices (devices cgroup v1)
#
# 원칙: chroot 안에서만 Docker 조작. 안팎 섞지 않는다.
#
# 사용:
#   docker-android.sh start     Docker Engine 시작
#   docker-android.sh stop      Docker Engine 종료
#   docker-android.sh status    상태 확인
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

    # bind mount (umount 후 재마운트 — Android에 fstab 없어서 mountpoint 사용 불가)
    umount -R $R/dev 2>/dev/null || true; mount --rbind /dev  $R/dev
    umount $R/proc 2>/dev/null || true;   mount --bind /proc  $R/proc
    umount -R $R/sys 2>/dev/null || true; mount --rbind /sys  $R/sys
    umount $R/run 2>/dev/null || true;    mount --bind /dev/run $R/run
    umount $R/tmp 2>/dev/null || true;    mount -t tmpfs tmpfs $R/tmp
    umount $R/opt/docker-data 2>/dev/null || true; mount --bind $DOCKER_DATA $R/opt/docker-data

    mkdir -p $R/run/containerd $R/run/docker

    # mount propagation — runc가 MS_REC|MS_PRIVATE 할 수 있게
    # chroot 안에 mount 바이너리가 없으므로, 밖에서 $R 자체를 mount point로 설정
    mount --bind $R $R
    mount --make-rshared $R

    # docker binaries (static)
    cp $DOCKER_BIN/* $R/opt/docker/ 2>/dev/null || true
    chmod 755 $R/opt/docker/*

    # DNS + hosts
    echo -e "nameserver 8.8.8.8\nnameserver 168.126.63.1" > $R/etc/resolv.conf
    echo "127.0.0.1 localhost" > $R/etc/hosts

    # CA 인증서 (docker pull TLS)
    cat /system/etc/security/cacerts/* > $R/etc/ssl/certs/ca-certificates.crt 2>/dev/null || true

    # daemon.json — vfs driver (f2fs overlay 호환 이슈 회피)
    echo '{"storage-driver":"vfs"}' > $R/etc/docker/daemon.json

    log "rootfs 준비 완료"
}

# ─── chroot 안에서 명령 실행 (PATH 포함) ───
in_chroot() {
    chroot $R /opt/docker/containerd --version > /dev/null 2>&1 || true  # static binary 테스트
    # static binary는 sh 없이 직접 실행 가능
    # sh가 필요한 명령은 이 함수 대신 직접 chroot $R /opt/docker/XXX 사용
    "$@"
}

# ─── Docker Engine 시작 ───
cmd_start() {
    # 런타임 설정 (SELinux가 init.rc에서 차단하는 것들)
    setenforce 0 2>/dev/null || true
    echo -e "nameserver 8.8.8.8\nnameserver 168.126.63.1" > /dev/run/resolv.conf 2>/dev/null || true
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || true

    # 기존 프로세스 정리
    pkill -f containerd 2>/dev/null || true
    pkill -f dockerd 2>/dev/null || true
    sleep 2

    setup_rootfs

    # PATH 설정 — BuildKit이 runc를 exec.LookPath로 찾음
    export PATH=/opt/docker:/usr/bin:/usr/local/bin:/bin:/sbin:$PATH
    export TMPDIR=/tmp
    export DOCKER_BUILDKIT=0
    export SSL_CERT_DIR=/etc/ssl/certs

    # containerd (chroot, static binary 직접 실행)
    log "containerd 시작..."
    chroot $R /opt/docker/containerd \
        --root /opt/docker-data/containerd \
        --state /run/containerd \
        > $D/containerd.log 2>&1 &
    sleep 4

    if ! pgrep containerd > /dev/null; then
        err "containerd 시작 실패. 로그: $D/containerd.log"
    fi
    log "containerd OK"

    # dockerd (chroot, static binary 직접 실행)
    log "dockerd 시작..."
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

    if ! pgrep dockerd > /dev/null; then
        err "dockerd 시작 실패. 로그: $D/dockerd.log"
    fi
    log "dockerd OK"

    # 확인 (chroot 안에서)
    chroot $R /opt/docker/docker info > $D/docker-info.txt 2>&1
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

    # ⚠️ unmount 순서 중요! rbind된 /dev를 해제 안 하고 rm하면 디바이스 노드 삭제됨
    # rootfs 자체는 절대 rm -rf 하지 않는다
    log "unmount..."
    umount $R/opt/docker-data 2>/dev/null || true
    umount $R/tmp 2>/dev/null || true
    umount $R/run 2>/dev/null || true
    umount -l $R/sys 2>/dev/null || true     # lazy — busy여도 해제
    umount -l $R/proc 2>/dev/null || true
    umount -l $R/dev 2>/dev/null || true     # ★ /dev rbind 해제 필수
    umount $R 2>/dev/null || true            # rootfs bind

    log "종료 완료"
}

# ─── 상태 확인 ───
cmd_status() {
    echo "=== Docker ==="
    if pgrep dockerd > /dev/null 2>&1; then
        echo "  dockerd: running (PID $(pgrep dockerd))"
        chroot $R /opt/docker/docker ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null || true
    else
        echo "  dockerd: not running"
    fi
    pgrep containerd > /dev/null 2>&1 && echo "  containerd: running" || echo "  containerd: not running"
}

# ─── chroot 안에서 docker CLI 실행 ───
cmd_exec() {
    export PATH=/opt/docker:$PATH
    export TMPDIR=/tmp
    chroot $R /opt/docker/docker "$@"
}

# ─── Main ───
case "${1:-help}" in
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    status)  cmd_status ;;
    exec)    shift; cmd_exec "$@" ;;
    *)
        echo "Usage: $0 {start|stop|status|exec} [args]"
        echo ""
        echo "  start    Docker Engine 시작 (chroot)"
        echo "  stop     Docker Engine 종료"
        echo "  status   상태 확인"
        echo "  exec     chroot 안에서 docker CLI (예: $0 exec ps)"
        ;;
esac
