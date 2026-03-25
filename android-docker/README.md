# Android Docker 배포 — python-matter-server + OTBR

## 원커맨드 설치

```bash
# PC에서 (adb 연결 상태)
./setup-docker.sh
```

## 보드에서 실행

```bash
# adb shell (root)
/data/local/tmp/docker-android.sh start   # Docker Engine 시작
/data/local/tmp/docker-android.sh load    # 이미지 로드
/data/local/tmp/docker-android.sh up      # matter-server + OTBR 시작
/data/local/tmp/docker-android.sh status  # 상태 확인
```

전부 한 번에:
```bash
adb shell '/data/local/tmp/docker-android.sh start && /data/local/tmp/docker-android.sh load && /data/local/tmp/docker-android.sh up'
```

## 전제조건

- AOSP 이미지: 패치 006 (Docker 커널) + 007 (/dev/run, /dev/cg_devices)
- 커널: CONFIG_SYSVIPC, CONFIG_IPC_NS, CONFIG_POSIX_MQUEUE 포함

## 폴더 구조

```
android-docker/
├── README.md                 # 이 문서
├── setup-docker.sh           # PC → 보드 원커맨드 설치
├── docker-android.sh         # 보드 안 Docker Engine 관리
├── docker-compose.yml        # Android 전용 (dbus 없음, BLE 비활성)
├── .gitignore
└── images/                   # 바이너리 + 이미지 (git 제외, 수동 준비)
    ├── docker-29.3.0.tgz
    ├── docker-compose-linux-aarch64
    ├── matter-server-arm64.tar.gz
    ├── otbr-arm64.tar.gz
    └── tools/
        ├── curl              # static aarch64
        └── jq                # static aarch64
```

## docker-android.sh 명령

| 명령 | 설명 |
|------|------|
| `start` | Docker Engine 시작 (chroot + containerd + dockerd) |
| `stop` | Docker Engine 종료 + unmount |
| `status` | 프로세스 + 컨테이너 상태 |
| `load` | /data/local/tmp/*.tar{.gz} 이미지 로드 |
| `up` | docker-compose up -d |
| `down` | docker-compose down |
| `exec ...` | chroot 안 docker CLI (예: `exec ps`) |

## Android Docker 핵심 해법 (기록)

| 문제 | 원인 | 해법 |
|------|------|------|
| dockerd "Devices cgroup isn't mounted" | /proc hidepid=invisible → mountinfo 못 읽음 | `mount -t proc proc $R/proc` (새 인스턴스) |
| dockerd "Devices cgroup isn't mounted" | Android cgroup 비표준 경로 /dev/cg_devices | `mount --bind /dev/cg_devices $R/sys/fs/cgroup/devices` |
| runc not found in $PATH | containerd-shim이 chroot 상속 안 함 | containerd에 `PATH=/opt/docker:...` + runc를 /usr/bin에 복사 |
| mount --make-rshared "bad fstab" | Android에 /etc/fstab 없음 | 경고만, 동작에 지장 없음 |
| overlay mount failed | f2fs + overlayfs 호환 | `{"storage-driver":"vfs"}` |
