# Android Docker — python-matter-server + Native OTBR

Android (RK3576)에서 python-matter-server를 Docker로, OTBR은 네이티브 빌드로 실행.
CHIP SDK AAR로 BLE 커미셔닝 후 python-matter-server에 multi-admin handoff.

## Architecture

```
Flutter APK (CHIP SDK AAR)
  └── BLE commissioning → Thread/WiFi device
       └── openCommissioningWindow → setupPinCode
            └── POST /api/commission-on-network {pin_code}

Go homeagent (:8080)
  ├── REST API + SSE
  ├── /api/thread/dataset → ot-ctl dataset active -x
  └── WS → python-matter-server (:5580)
             └── commission_on_network(pin) → CASE → Complete

Docker: python-matter-server (:5580)
  └── network_mode: host → wpan0 직접 접근

Native: OTBR (build-otbr.sh, BBR=ON)
  └── -B wlan0 → mDNS/SRP proxy → Thread↔WiFi
       └── /dev/ttyS5 (ESP32-H2 RCP)
```

## Quick Start

```bash
# 1. PC에서 (one command)
cd android-docker && bash setup-docker.sh

# 2. 보드에서 (one command)
/data/local/tmp/docker-android.sh all
```

## Prerequisites

AOSP image with patches:

| Patch | Content | Required |
|-------|---------|----------|
| 004+005 | `/dev/ttyS5` UART | ✅ |
| 006 | Docker kernel + `CONFIG_IPV6_MROUTE` + `CONFIG_IP_MROUTE` | ✅ |
| 007 | `/dev/run` tmpfs + `/dev/cg_devices` | ✅ |
| 009 | Screen always on | ✅ |
| 010 | `/run` tmpfs | ✅ |
| **011** | **MRT6 소켓 선점 방지** (Thread HAL 없으면 MulticastRoutingCoordinator skip) | ✅ |

011 패치 없으면 `system_server`가 MRT6 소켓을 선점 → OTBR BBR crash.

## Version Matrix

| Component | Version |
|-----------|---------|
| Docker Engine | 29.3.0 (static binary) |
| Docker Compose | v5.1.1 |
| python-matter-server | 8.1.2 (Docker image) |
| OTBR | 네이티브 빌드 (`build-otbr.sh`, BBR=ON) |
| CHIP SDK AAR | connectedhomeip (Flutter android/app/libs/) |

## OTBR Build

```bash
# matterjs 구성 (BBR OFF, 기본값)
./run.sh otbr-build

# python-matter-server 구성 (BBR ON, AOSP 011 패치 필수)
OTBR_BBR=on ./run.sh otbr-build
```

## Commands

| Command | Description |
|---------|-------------|
| `all` | 전체 스택 원커맨드 (Docker + matter-server + OTBR + Thread + Go + APK) |
| `start` | Docker Engine |
| `stop` | 전체 종료 |
| `status` | 상태 (Docker + OTBR + Thread state) |
| `load` | Docker 이미지 로드 (offline) |
| `up` | matter-server 컨테이너 시작 |
| `down` | matter-server 컨테이너 종료 |
| `otbr-start` | 네이티브 OTBR + Thread 네트워크 |
| `otbr-stop` | OTBR 종료 |
| `go-start` | Go 서버 + APK |
| `go-stop` | Go 서버 종료 |

## Key Solutions (Android-specific)

| Problem | Solution |
|---------|---------|
| `/proc` hidepid blocks dockerd | `mount -o remount,hidepid=0 /proc` |
| devices cgroup non-standard | `mount --bind /dev/cg_devices /sys/fs/cgroup/devices` |
| containerd-shim can't find runc | `PATH=/data/local/tmp/docker:$PATH` |
| No `/var/run` | `-H unix:///run/docker.sock` |
| Read-only rootfs | AOSP patch 010: `/run` tmpfs |
| f2fs + overlayfs incompatible | `--storage-driver vfs` |
| system_server MRT6 소켓 선점 | AOSP 011 패치: Thread HAL 없으면 skip |
| OTBR `ot-ctl` output `\r\n` | Go: `strings.ReplaceAll(dataset, "\r", "")` |
| OpenCommissioningCallback `onSuccess(deviceId, ...)` | 첫 파라미터는 deviceId, PIN 아님 |
| BLE scan filter too strict | filter=NONE + FFF6 serviceData 체크 |
| Thread HAL UART 경합 | `stop vendor.threadnetwork_hal` + 8s kill loop |

## Why Hybrid (Docker + Native)?

Docker OTBR 이미지(`openthread/otbr:latest`)는 `OTBR_BACKBONE_ROUTER=ON`으로 빌드됨.
BBR ON이면 `InitMulticastRouterSock()` → `setsockopt(MRT6_INIT)` 호출.
AOSP 011 패치 전에는 system_server와 충돌 → crash.

네이티브 빌드(`build-otbr.sh`)는 cmake 옵션으로 BBR on/off 제어 가능.
matterjs 버전(오픈소스)과 동일한 OTBR 빌드 → 일관성.

| | matterjs 버전 | python-matter-server 버전 |
|---|---|---|
| Matter 서버 | Native matterjs | Docker python-matter-server |
| OTBR | Native (BBR=OFF) | Native (BBR=ON) |
| BLE 커미셔닝 | matterjs WS relay | CHIP SDK AAR |
| Go | Native | Native |

## Commissioning Flow (Thread device)

```
1. Flutter: QR/Manual code 입력
2. CHIP SDK: BLE scan → GATT → PASE → NOC → ThreadSetup → ThreadEnable
3. CHIP SDK: Operational Discovery (mDNS via BBR)
4. CHIP SDK: CASE → CommissioningComplete (error=0)
5. CHIP SDK: openCommissioningWindow → setupPinCode
6. Flutter → Go: POST /api/commission-on-network {pin_code}
7. Go → python-matter-server: commission_on_network(pin)
8. python-matter-server: CASE → fabric 등록 → node_added
9. Flutter: SSE → "커미셔닝 완료!"
```
