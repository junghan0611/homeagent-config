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
/data/local/tmp/docker-android.sh start   # Docker Engine
/data/local/tmp/docker-android.sh load    # Load images (offline)
/data/local/tmp/docker-android.sh up      # Start matter-server + OTBR
/data/local/tmp/docker-android.sh status  # Verify
```

All at once:
```bash
adb shell '/data/local/tmp/docker-android.sh start && /data/local/tmp/docker-android.sh load && /data/local/tmp/docker-android.sh up'
```

## Prerequisites

AOSP image with patches:

| Patch | Content | Required |
|-------|---------|----------|
| 006 | Docker kernel (PID_NS, USER_NS, IPC_NS, CGROUP_PIDS, CGROUP_DEVICE, SYSVIPC) | ✅ |
| 007 | `/dev/run` tmpfs + `/dev/cg_devices` (devices cgroup v1) | ✅ |
| 010 | `/run` tmpfs (containerd/dockerd sockets) | ✅ |

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
├── docker-android.sh         # Board-side Docker Engine management
├── docker-compose.yml        # Android-specific (no dbus, no BLE)
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
| `start` | Start Docker Engine (containerd + dockerd) |
| `stop` | Stop Docker Engine |
| `status` | Show processes + containers + images |
| `load` | Load `/data/local/tmp/*.tar{.gz}` images |
| `up` | `docker-compose up -d` |
| `down` | `docker-compose down` |
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
