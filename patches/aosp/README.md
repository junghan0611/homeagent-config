# RK3576 Android 15 SDK Patches

SDK: `Rockchip_Android15.0_SDK_RELEASE_20251111` (AP4A.250205.002.C1, r14+)

## 현재 패치 (5개)

```
patches/
├── 004-kernel-uart5-enable.patch       # UART5 DTS 활성화 (ESP32-H2 RCP)
├── 005-ueventd-uart5-permission.patch  # /dev/ttyS5 퍼미션 (system:system 0660)
├── 006-kernel-docker-support.patch     # Docker 커널: PID_NS, USER_NS, CGROUP_PIDS, CGROUP_DEVICE
├── 007-init-docker-infra.patch         # /dev/run tmpfs + devices cgroup v1
├── 009-screen-always-on.patch          # 화면 항상 켜짐 (월패드, timeout=MAX_INT)
└── README.md                           # This file
```

## 패치 상세

| 패치 | 대상 파일 | 설명 |
|------|-----------|------|
| **004** | `kernel-6.1/.../rk3576-evb.dtsi` | UART5 pinctrl + status="okay" |
| **005** | `device/rockchip/rk3576/ueventd.rc` | `/dev/ttyS5 0660 system system` |
| **006** | `kernel-6.1/.../rockchip_defconfig` | `CONFIG_PID_NS=y`, `CONFIG_USER_NS=y`, `CONFIG_CGROUP_PIDS=y`, `CONFIG_CGROUP_DEVICE=y` |
| **007** | `device/rockchip/rk3576/init.rk3576.rc` | `mkdir+mount /dev/run` (tmpfs), `mkdir+mount /dev/cg_devices` (cgroup devices) |
| **009** | `device/rockchip/rk3576/overlay/.../defaults.xml` | `def_screen_off_timeout` → 2147483647 |

## 제거된 패치 (2026-03-23 deprecated)

HAL 기반 Thread 스택은 우리 Docker OTBR과 UART 충돌. 제거됨:
- ~~001-thread-hal-device-mk.patch~~ (HAL+APEX+ot-daemon)
- ~~002-thread-hal-rc.patch~~ (HAL UART5 설정)
- ~~003-thread-hal-sepolicy.patch~~ (SELinux)
- ~~003b-hal-threadnetwork-te.patch~~ (SELinux TE)

## 적용 방법

`docker-build.sh`가 자동 적용 → 빌드 → 자동 롤백. 수동 적용 불필요.

```bash
# gpu1i에서
cd /home/goqual/repos/work/kyungdong-rockchip
./docker-build.sh        # incremental
./docker-build.sh -c     # clean build
```

## 검증 (플래싱 후 보드에서)

```bash
adb shell ls -la /dev/ttyS5                            # 004+005: system:system 660
adb shell ps -A | grep -E "threadnetwork|ot-daemon"    # (없어야 정상)
adb shell mount | grep -E "/dev/run|cg_devices"        # 007: tmpfs + cgroup
adb shell settings get system screen_off_timeout       # 009: 2147483647
```
