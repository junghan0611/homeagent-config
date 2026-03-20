# Build Guide — Environment, Resources, and Workflow

> What runs where, what each command needs, and how to set up from scratch.

---

## Two-Machine Setup

HomeAgent development splits across a **dev machine** (fast iteration) and a **build farm** (heavy builds). Both are NixOS.

```
Dev Machine (thinkpad/laptop)        Build Farm (gpu1i/server)
────────────────────────────         ────────────────────────────
Code (SSOT, git)                     Yocto full build (~160G)
Go cross-compile (0.5s)              AOSP/LineageOS build
Flutter APK build (12s)              sLLM training (GPU)
UI vite build (0.2s)                 SD image generation
Go tests (10s)
ADB → board deployment
Agent sessions (pi)

Cycle: seconds~minutes               Cycle: hours~days
~2G (code + devShell cache)          ~800G (build artifacts)
```

**Principle: fast iteration = local + ADB, heavy builds = remote server.**

---

## What You Need Locally (~2G)

Everything for Android + RPi5 application development — no Yocto required.

| Path | Size | Purpose |
|------|------|---------|
| `go/` | 21M | Go server source + cross-compile |
| `flutter/` | 1.3G | Flutter APK source + build cache |
| `ui/` | 50M | Lit UI + node_modules |
| `dist/` | 739M | Built artifacts (Go arm64, OTBR, nodejs-bundle) |
| `scripts/` | 124K | Deploy scripts (android-deploy.sh, etc.) |
| `matterjs-server/` | 48K | Remote BLE code |
| `docs/` | 176K | Documentation |
| `patches/` | 16K | OTBR NDK patches |
| `flake.nix` | — | nix devShell (Go, Flutter, Node, NDK) |
| `yocto/build/conf/` | 24K | Yocto config (bblayers.conf, local.conf) |
| `yocto/meta-homeagent/` | 336K | Our Yocto recipes |

### What lives on the build farm only

| Path | Size | Purpose |
|------|------|---------|
| `yocto/build/tmp-glibc/` | ~160G | Yocto build output |
| `yocto/sstate-cache/` | ~8G | Shared state cache |
| `yocto/downloads/` | ~19G | Source tarballs |
| `yocto/sources/` | ~454M | poky + meta-* layers |

---

## Build Commands — What Runs Where

### Local (dev machine)

| Command | Time | Output | Requires |
|---------|------|--------|----------|
| `go test ./...` | 10s | 106 PASS | Go (nix devShell) |
| `go build -o dist/homeagent` | 0.5s | 9.5MB arm64 binary | Go |
| `./run.sh apk-build` | 12s | 51MB APK | Flutter + Android SDK (nix) |
| `./run.sh go-build` | 0.5s | Go arm64 | Go |
| `cd ui && npm run build` | 0.2s | 40KB dist/ | Node.js |
| `./run.sh otbr-build` | 3min | 7MB OTBR arm64 | NDK (nix) |
| `./run.sh bundle` | 5min | Full arm64 bundle | Go + Node + NDK |
| `./run.sh android deploy` | 30s | Push + start | ADB connection |
| `./run.sh android status` | 1s | Service check | ADB connection |

### Build farm (SSH)

| Command | Time | Output | Requires |
|---------|------|--------|----------|
| `./run.sh shell` | 10s | Enter FHS env | Nix |
| `./run.sh bb` | 1-4h* | Yocto image | FHS env + sources |
| `bitbake <recipe>` | varies | Single recipe | Inside FHS env |

*First build from scratch. With sstate-cache: ~15min.

### Getting results from build farm

```bash
# Yocto SD image
scp gpu1i:~/repos/gh/homeagent-config/yocto/build/tmp-glibc/deploy/images/raspberrypi5/*.wic.bz2 .

# Flash
bmaptool copy core-image-weston-raspberrypi5.wic.bz2 /dev/sdX
```

---

## nix devShell — What's Inside

`flake.nix` provides two shells:

### `nix develop` (default) — Yocto FHS

FHS (Filesystem Hierarchy Standard) environment for Yocto bitbake.

```bash
./run.sh shell   # enters FHS env
./run.sh bb      # bitbake core-image-weston
```

### `nix develop .#dev` — Application Development

Go, Flutter, Node.js, Android SDK, NDK — everything for app development.

```bash
nix develop .#dev --impure   # --impure for Android SDK (unfree)
# or just use run.sh commands which wrap this automatically
```

Contains:
- Go 1.25
- Flutter 3.38.9 + Android SDK (API 35)
- Node.js 22
- NDK r27 (for OTBR cross-build)

---

## dist/ — Build Artifacts

Pre-built binaries that live locally. Rebuilt as needed.

```
dist/
├── homeagent-android-arm64       9.5MB   Go server (android/arm64)
├── otbr-arm64/
│   ├── otbr-agent                9.8MB   Thread Border Router
│   └── ot-ctl                    12KB    OTBR CLI
├── nodejs-android-bundle/        335MB   Node.js + matterjs (glibc bundle)
│   ├── node                              Node.js binary
│   ├── lib/                              glibc + ld-linux
│   └── matterjs-server/                  matter-server + remote-ble
├── homeagent-bundle-arm64/       346MB   Full RPi5 bundle
│   ├── homeagent                         Go binary
│   ├── node/                             Node.js
│   ├── matterjs-server/                  matter-server
│   ├── ui/                               Lit frontend
│   └── start.sh                          One-command start
└── llama-arm64/                  16MB    llama.cpp (sLLM inference)
```

### nodejs-bundle — Why 335MB?

```
Node.js binary:     45MB
glibc + ld-linux:   30MB   (Android has Bionic, not glibc)
matterjs-server:    23MB   (matter-server + @matter/nodejs)
node_modules:      237MB   (dependencies)
```

Android doesn't have glibc, so we bundle it with `ld-linux` shim.
This is the same technique used by Electron and VS Code on Linux.

---

## Android Deploy Flow

```
./run.sh android deploy
  │
  ├── [1] go build (android/arm64)        → dist/homeagent-android-arm64
  ├── [2] vite build                      → ui/dist/
  ├── [3] flutter build apk --release     → flutter/build/.../app-release.apk
  ├── [4] adb push (Go + UI + OTBR + nodejs-bundle + aliases.json)
  ├── [5] adb install -r app-release.apk
  ├── [6] thread-start (OTBR + Thread network)
  └── [7] start (matterjs + Go server)
```

Skip flags: `--skip-go`, `--skip-apk`, `--skip-ui`, `--skip-matter`

---

## RPi5 Deploy Flow

```
./run.sh ha-deploy <IP>
  │
  ├── [1] go build (linux/arm64)
  ├── [2] vite build
  ├── [3] bundle (Go + Node + matterjs + UI)
  └── [4] scp + ssh start
```

Or for Yocto image: build on farm, flash SD card, boot.

---

## Build Farm Setup (from scratch)

### Prerequisites

- NixOS with flakes enabled
- SSH access configured
- Same git repo cloned

### Initial setup

```bash
ssh build-farm
cd ~/repos/gh/homeagent-config
git pull

# Yocto sources (meta-* layers)
# Option A: rsync from dev machine
rsync -avP dev-machine:~/repos/gh/homeagent-config/yocto/sources/ yocto/sources/

# Option B: clone fresh
cd yocto/sources
git clone -b scarthgap https://git.yoctoproject.org/poky
git clone -b scarthgap https://github.com/openembedded/meta-openembedded
git clone -b scarthgap https://github.com/agherzan/meta-raspberrypi
git clone -b scarthgap https://github.com/siemens/meta-clang
git clone -b scarthgap https://github.com/nicknisi/meta-flutter

# Build config
# Edit yocto/build/conf/local.conf:
#   BB_NUMBER_THREADS = "14"    # adjust to CPU cores - 2
#   PARALLEL_MAKE = "-j 14"
```

### Tuning for your hardware

| CPU cores | BB_NUMBER_THREADS | PARALLEL_MAKE |
|-----------|------------------|---------------|
| 4 (laptop) | 4 | -j 4 |
| 8 | 6 | -j 8 |
| 16 (server) | 14 | -j 14 |
| 32+ | 24 | -j 24 |

Rule: `BB_NUMBER_THREADS` ≤ cores - 2, `PARALLEL_MAKE` ≤ cores.
For clang-native: cap at `-j 8` (uses ~4GB RAM per thread).

---

## Disk Budget

### Dev machine (minimal)

```
Code + configs:           ~50M
Flutter build cache:    ~1.2G
dist/ (pre-built):      ~740M
nix store (devShell):   ~2-4G (shared with system)
─────────────────────────────
Total:                  ~2-4G
```

### Build farm (Yocto + AOSP)

```
Yocto build:           ~160G
Yocto sstate-cache:      ~8G
Yocto downloads:        ~19G
Yocto sources:         ~454M
AOSP/LineageOS:        ~329G  (if applicable)
─────────────────────────────
Total:                ~500-800G
```

---

## Reproducibility

Every build path is reproducible:

| Build | Reproducible via |
|-------|-----------------|
| Go binary | `GOOS=android GOARCH=arm64 CGO_ENABLED=0 go build` |
| Flutter APK | `flutter build apk --release` (nix devShell pins SDK) |
| UI | `npm run build` (package-lock.json) |
| OTBR | `./scripts/build-otbr.sh` (patches auto-applied) |
| nodejs-bundle | `./scripts/bundle-backend.sh` (Node version pinned) |
| Yocto image | `bitbake core-image-weston` (layer revisions in bblayers.conf) |

All nix inputs are locked in `flake.lock`. All Yocto layers pinned to specific commits.
