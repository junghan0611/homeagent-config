# Android Docker — python-matter-server + OTBR

Run python-matter-server and OTBR as Docker containers on Android (RK3576).
**Native Docker** — no chroot, no rootfs, direct execution.

## Quick Start

### 1. Push from PC (one command)

```bash
cd android-docker && bash setup-docker.sh
```

### 2. Run on board (adb shell, root)

```bash
/data/local/tmp/docker-android.sh all   # 전체 스택 원커맨드
```

개별 명령:
```bash
/data/local/tmp/docker-android.sh start        # Docker Engine
/data/local/tmp/docker-android.sh load         # Load images (offline)
/data/local/tmp/docker-android.sh up           # Start matter-server + OTBR
/data/local/tmp/docker-android.sh thread-init  # Thread 네트워크 자동 생성
/data/local/tmp/docker-android.sh go-start     # Go 서버 + APK
/data/local/tmp/docker-android.sh status       # Verify
```

## Prerequisites

AOSP image with patches:

| Patch | Content | Required |
|-------|---------|----------|
| 006 | Docker kernel (PID_NS, USER_NS, IPC_NS, CGROUP_PIDS, CGROUP_DEVICE, SYSVIPC) | ✅ |
| 007 | `/dev/run` tmpfs + `/dev/cg_devices` (devices cgroup v1) | ✅ |
| 010 | `/run` tmpfs (containerd/dockerd sockets) | ✅ |
| **TBD** | **`CONFIG_IPV6_MROUTE=y` + `CONFIG_IP_MROUTE=y`** | **⚠️ OTBR BBR 필수** |

## Version Matrix

| Component | Version | File |
|-----------|---------|------|
| Docker Engine | 29.3.0 | `docker-29.3.0.tgz` |
| Docker Compose | v5.1.1 | `docker-compose-linux-aarch64` |
| python-matter-server | 8.1.2 | `matter-server-8.1.2-arm64.tar.gz` |
| OTBR | 0.3.0-987e44c | `otbr-0.3.0-arm64.tar.gz` |
| containerd | v2.2.1 | (inside docker tgz) |
| runc | 1.3.4 | (inside docker tgz) |

All images loaded offline via `docker load` — no internet pull required.

## Directory Layout

```
android-docker/
├── README.md                 # This file
├── setup-docker.sh           # PC → board push (one command)
├── docker-android.sh         # Board-side Docker Engine + Thread management
├── docker-compose.yml        # Android-specific compose
├── .gitignore
└── images/                   # Binaries + images (git-ignored, manual prep)
    ├── docker-29.3.0.tgz
    ├── docker-compose-linux-aarch64
    ├── matter-server-8.1.2-arm64.tar.gz
    ├── otbr-0.3.0-arm64.tar.gz
    └── tools/
        ├── curl              # static aarch64 (8.19.0)
        └── jq                # static aarch64
```

## Commands

| Command | Description |
|---------|-------------|
| `all` | **전체 스택 원커맨드** (Docker + 이미지 + 컨테이너 + Thread + Go + APK) |
| `start` | Start Docker Engine (containerd + dockerd) |
| `stop` | Stop all (Docker + Go) |
| `status` | Show processes + containers + images |
| `load` | Load `/data/local/tmp/*.tar{.gz}` images |
| `up` | `docker-compose up -d` |
| `down` | `docker-compose down` |
| `thread-init` | Thread 네트워크 자동 생성 (dataset 없으면 생성, 있으면 복원) |
| `go-start` | Go homeagent + APK 시작 |
| `go-stop` | Go homeagent 종료 |
| `exec ...` | Docker CLI (e.g., `exec ps`, `exec logs matter-server`) |

## VFS Storage Driver

Using `--storage-driver vfs`. VFS copies entire layers per container (no layer sharing).

| Item | Size |
|------|------|
| docker-data (VFS) | ~2.4GB |
| /data partition free | ~111GB |
| Usage | ~2.7% |

Acceptable for 2 fixed containers. overlay2 is unstable on f2fs + SELinux.
Reclaim ~434MB after load: `rm /data/local/tmp/*.tar.gz`

## Key Solutions (Android-specific)

| Problem | Cause | Solution |
|---------|-------|---------|
| `Devices cgroup isn't mounted` | `/proc` hidepid=invisible blocks mountinfo | `mount -o remount,hidepid=0 /proc` |
| `Devices cgroup isn't mounted` | Android non-standard path `/dev/cg_devices` | `mount --bind /dev/cg_devices /sys/fs/cgroup/devices` |
| `runc not found in $PATH` | containerd-shim inherits PATH from containerd | Start containerd with `PATH=/data/local/tmp/docker:$PATH` |
| `/var/run/docker.sock` not found | Android has no `/var/run` | `-H unix:///run/docker.sock` |
| containerd `mkdir /run: read-only` | Android rootfs is dm-verity read-only | AOSP patch 010: `/run` tmpfs |
| `remount / invalid argument` (chroot) | mount propagation conflicts with rbind | **Abandoned chroot** → native Docker |
| overlay mount failed | f2fs + overlayfs incompatible | `--storage-driver vfs` |
| OTBR `platformConfigureTunDevice` | Container missing `/dev/net/tun` | `devices: /dev/tun:/dev/net/tun` (Android TUN 경로 매핑) |
| OTBR ipset `Kernel error` | Android kernel lacks `xt_set` module | `FIREWALL=0` environment variable |
| OTBR `InitMulticastRouterSock` crash | `CONFIG_IPV6_MROUTE` not set | **⚠️ 커널 패치 필요** — BBR 없이 `-B` 제거로 우회 시도했으나 여전히 크래시 |

## OTBR Known Issue: Multicast Routing Crash

OTBR 0.3.0의 `otbr-agent`는 Thread leader 도달 ~54초 후 `InitMulticastRouterSock()` 에서
`setsockopt(MRT6_INIT)` 호출 → `Protocol not available` → `VerifyOrDie` → 강제 종료.

**근본 원인**: Android 커널에 `CONFIG_IPV6_MROUTE=y` 없음.

- `-B` (backbone interface) 제거해도 크래시 — BBR 코드가 컴파일 타임 포함
- `FIREWALL=0`은 ipset만 우회, multicast routing과 무관
- **해결**: AOSP 커널에 `CONFIG_IPV6_MROUTE=y` + `CONFIG_IP_MROUTE=y` 추가 (패치 요청 완료)

## Thread 네트워크 영속성

- Docker volume `otbr-data:/var/lib/thread` — dataset 저장
- `docker-android.sh thread-init` — dataset 있으면 복원, 없으면 새로 생성 (NetworkName: HomeAgent, Channel: 15)
- 재부팅 후 `docker-android.sh all` 한 번이면 전체 복원

## Architecture Decision: Native > Chroot

Chroot was initially used to isolate Docker from Android's non-standard filesystem.
However, `mount --make-rshared` (required by runc) conflicts with `rbind /dev` in chroot,
causing proc and dev mounts to be overwritten. This is a structural conflict — not fixable.

**Native Docker** eliminates all mount propagation issues:
- No rootfs, no rbind, no propagation conflicts
- 3 AOSP patches provide what Docker needs (`/run`, `/dev/cg_devices`, kernel namespaces)
- Direct binary execution with explicit socket paths

```
Native:  setenforce 0 → remount proc → bind cgroup → containerd → dockerd → compose up
Chroot:  (abandoned) rootfs + rbind + proc + propagation → structural conflict
```
