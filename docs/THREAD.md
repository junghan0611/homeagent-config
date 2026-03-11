# Thread Border Router — HomeAgent

The Android NDK build works on **any Android arm64 board** with UART Thread RCP access.
RK3576-EVB is the verified reference board; other boards (RK3588, Amlogic, MediaTek) follow the same steps.

## 아키텍처

```
ESP32-H2 (Thread RCP)
  └─ Spinel HDLC (UART)
       └─ otbr-agent
            ├─ wpan0 (TUN interface)
            ├─ SRP Server (Thread mDNS proxy)
            ├─ Border Routing (IPv6)
            └─ ot-ctl (CLI)
                 └─ Go Hub getOTBRDataset()
                      └─ matterjs set_thread_dataset
                           └─ BLE commissioning → Thread join
```

## 플랫폼별 구성

| 항목 | RPi5 (Yocto) | RK3576 (Android) |
|------|-------------|-----------------|
| RCP 디바이스 | /dev/ttyUSB0 | /dev/ttyS5 |
| RCP baudrate | 460800 | 460800 |
| backbone IF | eth0 | wlan0 |
| mDNS | avahi-daemon | OT core (내장) |
| init system | systemd | scripts/rk3576-thread.sh |
| otbr-agent | Yocto 패키지 | NDK arm64 빌드 |

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `HOMEAGENT_OT_CTL` | `ot-ctl` | ot-ctl 바이너리 경로 |

RPi5: `ot-ctl`이 PATH에 있으므로 기본값 사용.
RK3576: `HOMEAGENT_OT_CTL=/data/local/tmp/otbr/ot-ctl`

## RPi5 (Yocto)

systemd 서비스로 자동 시작:
- `otbr-agent.service` — Thread Border Router
- `otbr-thread-init.service` — Thread 네트워크 초기화
- `otbr-srp-enable.service` — SRP Server 활성화

설정 파일: `yocto/meta-homeagent/recipes-connectivity/openthread/ot-br-posix/`

## RK3576 (Android)

### NDK 빌드 — 검증된 CMake 옵션 (2026-03-11)

```bash
# devShell 진입
cd ~/repos/gh/homeagent-config
nix develop .#dev --impure

# ot-br-posix 빌드 (udp.cpp sign-compare 패치 필요 — 아래 표 참고)
cd ~/repos/3rd/ot-br-posix
NDK=$ANDROID_HOME/ndk/27.0.12077973
TOOLCHAIN=$NDK/build/cmake/android.toolchain.cmake

cmake -B build-android \
  -DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-35 \
  -DANDROID_STL=c++_static \
  -DCMAKE_CXX_FLAGS="-DOPENTHREAD_CONFIG_ANDROID_NDK_ENABLE=1" \
  -DCMAKE_C_FLAGS="-DOPENTHREAD_CONFIG_ANDROID_NDK_ENABLE=1" \
  -DOT_ANDROID_NDK=ON \
  -DBUILD_TESTING=OFF \
  -DOTBR_DBUS=OFF -DOTBR_REST=OFF -DOTBR_WEB=OFF \
  -DOTBR_MDNS=openthread \
  -DOTBR_BACKBONE_ROUTER=OFF \
  -DOTBR_SRP_ADVERTISING_PROXY=OFF \
  -DOTBR_BORDER_ROUTING=ON \
  -DOTBR_BORDER_AGENT=ON \
  -DOT_SPINEL_RESET_CONNECTION=ON \
  -DOT_TREL=OFF -DOT_MLR=ON \
  -DOT_SRP_SERVER=ON -DOT_ECDSA=ON -DOT_SERVICE=ON \
  -DOT_DUA=ON -DOT_BORDER_ROUTING_NAT64=OFF \
  -DOTBR_INFRA_IF_NAME=wlan0 \
  -DOTBR_NO_AUTO_ATTACH=1

cmake --build build-android -j$(nproc)

# strip
STRIP=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip
$STRIP build-android/src/agent/otbr-agent
$STRIP build-android/third_party/openthread/repo/src/posix/ot-ctl
```

#### 빌드 중 만난 이슈와 해결

| 이슈 | 원인 | 해결 |
|------|------|------|
| `cutils/properties.h` not found | Android NDK에 없는 system 헤더 | `-DOPENTHREAD_CONFIG_ANDROID_NDK_ENABLE=1` |
| `Only one Discovery Proxy` | OT_DISCOVERY_PROXY(기본ON) + DNSSD 충돌 | `DNSSD_DISCOVERY_PROXY` 제거 |
| `Only one Advertising Proxy` | MDNS=openthread에서 OT_SRP_ADV_PROXY 자동ON | `SRP_ADVERTISING_PROXY=OFF` |
| `-lutil` not found | glibc 전용 라이브러리 | `-DOT_ANDROID_NDK=ON` |
| `sign-compare` fatal error | NDK clang -Werror | udp.cpp `static_cast<unsigned int>` 패치 |
| `libnetfilter_queue.h` not found | Android에 없음 | `BACKBONE_ROUTER=OFF` |
| `dns_sd.h` not found | mDNSResponder 미포함 | `MDNS=openthread` |

#### 빌드 산출물 (strip 후)

| 바이너리 | 크기 |
|---------|------|
| otbr-agent | 6.9MB |
| ot-ctl | 12KB |

### 배포

```bash
adb push otbr-agent /data/local/tmp/otbr/
adb push ot-ctl /data/local/tmp/otbr/
```

### 실행

```bash
# Thread 시작
./run.sh rk-thread-start

# 상태 확인
./run.sh rk-thread status

# 중지
./run.sh rk-thread-stop
```

또는 직접:
```bash
adb shell sh /data/local/tmp/rk3576-thread.sh start
```

### 주의사항

1. **Android Thread HAL 중지 필수** — `/dev/ttyS5` 독점 방지
   ```bash
   adb shell stop vendor.threadnetwork_hal
   ```

2. **SELinux permissive** — otbr-agent가 TUN/UART 접근 필요
   ```bash
   adb shell setenforce 0
   ```

3. **baudrate** — HAL rc 기준 460800. 안 되면 115200 시도.

## Go 통합

`hub.go`가 자동으로:
1. `ot-ctl dataset active -x`로 Thread dataset 추출
2. matterjs `set_thread_dataset`으로 주입
3. BLE commissioning 시 Thread credentials 자동 전달

```go
// config.go
OtCtlPath: envOr("HOMEAGENT_OT_CTL", "ot-ctl"),

// hub.go
getOTBRDataset(h.cfg.OtCtlPath)
```
