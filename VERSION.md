# HomeAgent Config - Version Matrix

Yocto/OpenEmbedded, Raspberry Pi 5 및 Orange Pi 5 버전 호환성 정리

---

## 디바이스 스택 비교 (2026-04-30 업데이트)

| 항목 | **RPi5** | **OPi5** |
|------|---------|----------|
| **SoC** | BCM2712 (4×A76) | RK3588S (4×A76 + 4×A55) |
| **커널** | linux-raspberrypi **6.6 LTS** | linux-yocto-dev **6.14** (mainline) |
| **BSP** | meta-raspberrypi | radxa/meta-rockchip + local machine |
| **GPU** | VideoCore VII (vc4/v3d), Mesa 24.0.7 | Mali-G610 — panthor/panfrost 검증 |
| **디스플레이** | HDMI (Weston 13) | HDMI 4K@30Hz 검증 |
| **NPU** | Hailo-8 (26 TOPS, M.2) | RKNN 6 TOPS — vendor 6.1 필요, parked |
| **모드** | 풀스택 (GUI + NPU) | **lab target** (SSH/GPU 검증용) |
| **검증** | ✅ 풀스택 | 🟡 SSH/GPU 검증 완료, NPU 보류 |

---

## Yocto 릴리스 선택: Scarthgap (5.0 LTS)

| 항목 | Scarthgap (5.0) | Styhead (5.1) | Whinlatter (5.3) |
|------|-----------------|---------------|------------------|
| **릴리스** | 2024년 4월 | 2024년 10월 | 2025년 12월 |
| **지원** | LTS (2028년 4월까지) | EOL | 6개월 (2026년 5월) |
| **Linux Kernel** | 6.6 LTS | 6.10 | (TBD) |
| **GCC** | 13.2 | 14.2 | - |
| **glibc** | 2.39 | 2.40 | - |
| **BitBake** | 2.8 | 2.10 | 2.16 |

**선택 이유**: Scarthgap은 LTS이며 Raspberry Pi OS와 동일한 6.6 LTS 커널 사용

---

## Orange Pi 5 (RK3588S) Yocto 지원

### 현재: Mainline 6.14 Lab Target (2026-04-30)

OPi5는 HomeAgent의 주력 경로가 아니라 lab target으로만 유지한다. RPi5가 HomeAgent 실험에 충분하고, ESP32/Zig 계열 edge 작업은 별도 `edgeagent-config` 리포에서 진행한다.

| 항목 | 값 |
|------|-----|
| **Machine** | `orangepi-5` (custom conf) |
| **SoC** | Rockchip RK3588S (4×A76 + 4×A55) |
| **BSP Layer** | radxa/meta-rockchip 기반 |
| **Kernel** | linux-yocto-dev **6.14** (mainline) |
| **GPU** | panthor 1.3.0, Mesa 24.1.7 (panfrost + panthor kmod) |
| **Display** | HDMI 3840x2160@30Hz 검증 |
| **NPU** | RKNN은 보류 — vendor 6.1 BSP 필요 |
| **빌드 디렉토리** | `yocto/build-opi5/` (RPi5 `build/`과 분리) |

**정책**:
- 기본은 mainline 6.14로 둔다. SSH/GPU/HDMI 검증 상태를 보존한다.
- vendor 6.1 + RKNN NPU 경로는 지금 추적하지 않는다. 필요할 때 llmlog `20260331T114944`를 보고 재개한다.
- HomeAgent 핵심 검증은 RPi5에 집중한다. OPi5 작업이 RPi5 경로를 흔들지 않게 문서/레시피 수를 최소화한다.

### 보류: Vendor BSP 6.1 NPU path

- mainline 6.14에는 rknn-toolkit2와 호환되는 BSP rknpu 경로가 없다.
- vendor 6.1은 rknpu/IOMMU/DTS 경로가 있으나, 별도 recipe/patch 유지 비용이 크다.
- 따라서 vendor recipe와 임시 패치는 리포에서 제거하고, 재개 판단 자료만 llmlog에 남긴다.

**참고 llmlog**: `/home/junghan/sync/org/llmlog/20260331T114944--§homeagent-config-opi5-orange-pi-5-rk3588s-yocto-scarthgap-지원-리서치__gpu_homeagent_iot_llmlog_rockchip_yocto.org`

---

## Target device strategy — Hailo/RK boards

HomeAgent의 현재 실험/개발 기준은 **RPi5 + Hailo**다. 양산/확장 후보는 별도 보드 탐색으로 남기되, HomeAgent 본류를 흔들지 않는다.

| 항목 | 현재 판단 |
|------|-----------|
| 개발 기준 | RPi5 + Yocto Scarthgap |
| AI 가속 | Hailo-8 계열 우선. 내장 RKNN은 OPi5에서 parked |
| 보드 전략 | Yocto BSP가 검증된 보드만 후보 |
| RK3588 | 양산 후보군이지만 현재 HomeAgent 본류는 아님 |
| Android 월패드 | HomeAgent를 Android 전용으로 만들지 않고 연동/bridge만 제공 |

보드 후보 메모:

| 후보 | 이유 | 상태 |
|------|------|------|
| RPi5 + Hailo | 현재 개발/검증 기준 | 유지 |
| RK3588 + Hailo-8 M.2 | 양산 후보, Android 생태계와 Yocto BSP 모두 있음 | 보류 |
| Geniatech APC3588-AI | RK3588 + Hailo 옵션 산업용 후보 | 보류 |
| Banana Pi BPI-M7 / OPi5 Plus / NanoPi T6 | RK3588 + M.2 후보군 | 보류 |
| NXP iMX8M Plus | 산업용/Hailo Yocto 성숙 | 보류 |

`docs/TARGET_DEVICE.md`의 긴 조사 내용은 이 표로 압축 흡수했다. 새 보드 선정은 이 섹션과 `HARDWARE.md`의 실제 장비 상태를 먼저 확인한 뒤 진행한다.

---

## Raspberry Pi OS 비교

| 항목 | Raspberry Pi OS | Yocto Scarthgap |
|------|-----------------|-----------------|
| **Kernel** | 6.6 LTS (2024.03) → 6.12 LTS (2025.04) | 6.6 LTS |
| **Base** | Debian 12 Bookworm | Poky (OE-Core) |
| **GPU Driver** | Mesa (vc4/v3d) | Mesa (vc4/v3d) |
| **Display** | Wayland (labwc) / X11 | Wayland (Weston) |

**호환성**: 
- 커널 6.6 LTS 기준으로 드라이버/펌웨어 호환
- BCM2712 (RPi5 SoC) 지원 동일
- Mesa GPU 드라이버 동일

---

## meta-raspberrypi

| 항목 | 값 |
|------|-----|
| **브랜치** | scarthgap |
| **Machine** | raspberrypi5 |
| **SoC** | BCM2712 (Cortex-A76) |
| **Tune** | cortexa76 (armv8-2a) |
| **DTB** | bcm2712-rpi-5-b.dtb |
| **WiFi/BT FW** | bcm43455, bcm4345c0 |
| **GPU** | vc4-kms-v3d |

```
# conf/machine/raspberrypi5.conf
require conf/machine/include/arm/armv8-2a/tune-cortexa76.inc
MACHINE_FEATURES += "pci"
VC4DTBO ?= "vc4-kms-v3d"
```

---

## meta-openembedded (OTBR)

| 항목 | 값 |
|------|-----|
| **레시피** | ot-br-posix_git.bb |
| **버전** | 0.3.0+git |
| **SRCREV** | a35cc682305bb2201c314472adf06a4960536750 |
| **브랜치** | main (openthread/ot-br-posix) |

**의존성:**
- Build: autoconf-archive, dbus, avahi, jsoncpp, boost, protobuf
- Runtime: iproute2, ipset, avahi-daemon
- Systemd: otbr-agent.service

**알려진 이슈:**
- OTBR_WEB=ON 빌드 시 npm 타임아웃 (Web UI 비활성화 권장)
- RCP 펌웨어 버전 호환성 확인 필요

---

## Matter 컨트롤러 — matter.js 단일 본류 (2026-04-30)

### 아키텍처

```text
Flutter/Linux UI → Go REST(:8080) → matterjs-server WS(:5580) → OTBR → Thread
                         │
                         └─ A2A / A2UI / sLLM / aliases / SSE
```

**본류는 Linux/Yocto + matter.js다.** HomeAgent는 RPi5 Yocto에서 재현 가능한 로컬 허브를 만드는 프로젝트이며, Matter backend는 `matterjs-server`를 기준으로 유지한다.

### 현재 사용 버전

| 컴포넌트 | 버전 | 비고 |
|----------|------|------|
| **matterjs-server (matter-server)** | 0.3.5 | matter.js 기반, Yocto systemd / glibc 번들 |
| **@matter/main** | 0.16.9-alpha | matter.js SDK |
| **Node.js** | 20.18.2 | matterjs 런타임 |
| **OTBR** | 0.3.0+git | Yocto 레시피 / Android NDK 검증 이력 |

### python-matter-server / Android Docker — deprecated reference

`python-matter-server`와 Android Docker 포장은 **경동/Android 호환성 검증을 위해 억지로 해본 경로**다. 경험과 스크립트는 `deprecated/android-docker/`에 보존하지만, HomeAgent 본류가 아니다.

| 항목 | 상태 |
|------|------|
| python-matter-server 8.1.2 | deprecated reference. 본류 backend 아님 |
| Docker Engine/Compose arm64 bundle | deprecated Android packaging 자료 |
| Android Docker/AOSP 패치 | 실험/호환성 기록. 메인 지원 경로 아님 |
| Android 지원 | Flutter 앱 호환/검증 수준. 서버 본류는 Linux/Yocto |

Go `client.go`가 python-matter-server WS와도 연결된다는 것은 **호환성 검증 결과**이지, 듀얼 백엔드를 계속 제품 경로로 운영한다는 뜻이 아니다.

### matterjs-server 릴리즈 타임라인

```
v0.3.0  2026-01-28   matter.js 0.16 기반
v0.3.5  2026-02-04   ← 우리 matterjs 버전
v0.4.0  2026-02-19   대시보드 개선, WS API 확장
v0.5.0  2026-03-05   OTA, 새 Controller API 시작
v0.5.7  2026-03-13   ← 최신 안정 (matter.js 0.17-alpha)
```

### matter.js 릴리즈 타임라인

| matter.js | 날짜 | Matter 스펙 | matterjs-server |
|-----------|------|------------|---------------|
| 0.15 | 2025-06 | 1.4.2 | — |
| 0.16 | 2026-01 | 1.4.2 | 0.3.x (우리) |
| **0.17-alpha** | **2026-03** | **1.5.0 준비** | **0.5.x (최신)** |
| 0.17 (예상) | 2026 Q2-Q3 | 1.5.0 | — |

> HA도 matter.js 방향으로 이동 중이다. HomeAgent는 Linux/Yocto + matter.js를 본류로 둔다.
> python-matter-server는 Android/Docker 호환성 검증 이력으로만 보존한다.

> 상세: [docs/MATTER.md](docs/MATTER.md)

---

## OTBR 빌드 옵션 비교 — Yocto (RPi5) vs NDK (Android)

동일 ot-br-posix 소스에서 플랫폼별로 빌드. Android에 없는 시스템 라이브러리(avahi, dbus, netfilter)를 OT core 내장 기능으로 대체.

### 버전

| | Yocto (RPi5) | NDK (Android) |
|---|---|---|
| **SRCREV** | a35cc68 | c19319c7 (더 최신) |
| **openthread** | (해당 시점) | 0887643bf |
| **빌드 도구** | OE cross-toolchain | NDK r27 clang 18 |
| **바이너리 크기** | (시스템 패키지) | 9.9MB (stripped) |

### CMake 옵션 비교

| 옵션 | Yocto (RPi5) | NDK (Android) | 차이 이유 |
|------|:---:|:---:|---|
| **OTBR_MDNS** | avahi | openthread | Android에 avahi 없음 → OT core mDNS |
| **OTBR_DBUS** | ON | OFF | Android에 dbus 없음 |
| **OTBR_REST** | ON | ON | HTTP API (:8081) — JSON 조회 |
| **OTBR_BACKBONE_ROUTER** | ON | ON | Thread↔Infra mDNS 브릿징 |
| **OTBR_BORDER_ROUTING** | ON | ON | — |
| **OTBR_BORDER_AGENT** | ON | ON | — |
| **OTBR_SRP_ADVERTISING_PROXY** | ON | **OFF** | OT_SRP_ADV_PROXY(자동ON)와 충돌 |
| **OTBR_DNSSD_DISCOVERY_PROXY** | ON | **OFF** | OT_DISCOVERY_PROXY(자동ON)와 충돌 |
| **OTBR_DUA_ROUTING** | ON | **OFF** | libnetfilter_queue 없음 |
| **OT_TREL** | ON | **OFF** | 외부 mDNS daemon 없이 불필요 |
| **OT_BORDER_ROUTING_NAT64** | ON | **OFF** | Android iptables 제한 |
| **OT_SRP_SERVER** | ON | ON | — |
| **OT_ECDSA** | ON | ON | — |
| **OT_SERVICE** | ON | ON | — |
| **OT_DUA** | ON | ON | — |
| **OT_MLR** | ON | ON | — |
| **OT_SPINEL_RESET_CONNECTION** | ON | ON | — |
| **OT_DHCP6_CLIENT/SERVER** | ON | ON | Thread 내 DHCPv6 주소 할당 |
| **OT_REFERENCE_DEVICE** | ON | ON | 인증 테스트 + CLI 디버깅 명령 |
| **OT_ANDROID_NDK** | — | ON | -lutil 제외 |
| **OTBR_INFRA_IF_NAME** | eth0 | wlan0 | 네트워크 인터페이스 |

### Android 전용 (NDK만 해당)

| 옵션 | 값 | 이유 |
|---|---|---|
| `OT_ANDROID_NDK` | ON | `-lutil` 링크 제외 (bionic에 없음) |
| `OPENTHREAD_CONFIG_ANDROID_NDK_ENABLE` | 1 (CXX_FLAGS) | `sys/system_properties.h` 경로 |
| `OPENTHREAD_POSIX_CONFIG_DAEMON_SOCKET_BASENAME` | `/data/local/tmp/ot-%s` | Android root FS readonly |
| `CMAKE_POLICY_VERSION_MINIMUM` | 3.5 | cJSON cmake_minimum_required 호환 |
| `ANDROID_STL` | c++_static | 정적 링크 (시스템 libc++ 버전 무관) |

### NDK 패치 (Yocto 불필요)

| 패치 | 대상 | 내용 |
|---|---|---|
| `0001-fix-udp-sign-compare-ndk-clang.patch` | openthread udp.cpp | signed/unsigned 비교 경고→에러 수정 |
| `0002-fix-rest-vla-pthread-ndk.patch` | ot-br-posix rest/ | VLA→vector + pthread 조건부 링크 |

### 핵심 원리: OT core가 대체

`OTBR_MDNS=openthread`이면 OT core가 자동으로:
- `OT_SRP_ADV_PROXY=ON` → SRP Advertising Proxy (avahi 대체)
- `OT_DISCOVERY_PROXY=ON` → DNS-SD Discovery Proxy (avahi 대체)
- `OT_MDNS=ON` → Multicast DNS on infra-if (avahi-daemon 대체)

따라서 OTBR 레벨의 `SRP_ADVERTISING_PROXY`, `DNSSD_DISCOVERY_PROXY`는 OFF 필수 (동시 활성화 → CMake FATAL_ERROR).

### REST API 엔드포인트 (포트 8081)

| 경로 | 메서드 | 용도 |
|---|---|---|
| `/node/state` | GET | Thread 상태 (leader/router/child/detached) |
| `/node/dataset/active` | GET | Active dataset (JSON) |
| `/node/network-name` | GET | Thread 네트워크 이름 |
| `/node/ext-panid` | GET | Extended PAN ID |
| `/node/rloc16` | GET | RLOC16 주소 |
| `/api/devices` | GET | Thread 네트워크 디바이스 목록 |
| `/api/diagnostics` | GET/POST | 네트워크 진단 |

`ot-ctl` exec + stdout 파싱 대신 HTTP JSON 조회 → Go에서 안정적.

---

## RCP 정보
  - USB포트: RPi5 블루(USB3) 포트에 연결 (전원 부족 시 CP210x 타임아웃 발생)
  - 펌웨어: SL-OPENTHREAD/2.5.3.0_GitHub-1fceb225b; EFR32; Jun 27 2025
  - EUI64: 08b95ffffeb52ac1
  - Spinel API: v10
  - Baudrate: 460800, no flow control
  - Spinel URL: `spinel+hdlc+uart:///dev/ttyUSB0?uart-baudrate=460800`

## Matter Commissioning 검증 완료 (2026-02-09)
  - Eve 도어센서: BLE→PASE→NOC→Thread→SRP→mDNS→CASE→CommissioningComplete ✅
  - BooleanState 클러스터 데이터 읽기 성공
  - chip-tool v1.4.0.0 + `--bypass-attestation-verifier true`

---

## Node.js 버전 — 개발 vs 타겟 (빌드/런타임 분리)

| 환경 | Node 버전 | 용도 |
|------|-----------|------|
| **devShell** (NixOS 로컬) | Node 22 (nodejs_22) | 로컬 개발/테스트 |
| **Yocto 타겟** (RPi5 이미지) | Node 20.18.2 | matterjs-server 런타임 |

**왜 달라도 괜찮은가:**
- devShell ≠ 크로스컴파일 도구체인. Yocto는 자체 도구체인으로 이미지를 빌드함
- Go 백엔드 → 정적 바이너리. Node 무관
- Lit UI → `vite build` 정적 HTML/JS. 빌드 후 Node 불필요
- Flutter 앱 → Dart AOT 컴파일. Node 무관
- **matterjs-server만** Node 런타임 의존. Yocto 레시피가 Node 20을 타겟에 설치
- matterjs-server engines: `>=20.19.0 <22.0.0 || >=22.13.0` → 양쪽 다 범위 안

**결론:** devShell 노드 버전은 Yocto 타겟 이미지에 영향 없음. 각각 독립.

---

## Flutter/Clang 버전 — 최신과의 갭 (2026-03-06)

| 구성요소 | Yocto (현재) | 최신 안정 | 갭 | Android 15 호환 |
|---|---|---|---|---|
| **Flutter** | 3.38.3 | 3.41.4 | 3개 마이너 | ✅ API 35 지원 |
| **Dart** | 3.10.1 | 3.13.x | 3개 마이너 | — |
| **Clang** | 18.1.8 | 20.x | 2개 메이저 | — (Yocto 빌드용) |

**GUI 호환성**: 문제 없음.
- Flutter 3.38.3은 Android API 21~35 지원 → Android 15(API 35) 완전 호환
- 경동 프로젝트: compileSdk=35, targetSdk=35, minSdk=31 → Flutter 3.38.3으로 빌드 가능
- webview_flutter 4.13.1: OS 제공 WebView 사용, Flutter 버전 무관
- Clang 18: ivi-homescreen 빌드용. Android APK는 NDK 자체 clang 사용하므로 무관
- **Yocto와 Android의 Flutter 버전이 같다(3.38.3)** → 동일 코드베이스 양쪽 빌드 시 Dart API 호환 보장

---

## Flutter 개발 환경 — Linux Desktop (2026-03-06)

| 항목 | 값 |
|------|-----|
| **Flutter** | 3.38.9 (NixOS devShell) |
| **Dart** | 3.10.8 |
| **타겟** | Linux x64 (GTK3) |
| **디스플레이** | X11 (i3wm) 확인됨, Wayland도 지원 |
| **빌드 성공** | `flutter build linux` ✅ |
| **실행 확인** | GTK3 창 실행 ✅ |

**플랫폼별 UI 전략:**

| 플랫폼 | UI 모드 | 렌더링 |
|---|---|---|
| **Linux Desktop** (개발) | `NavShell` (네이티브) | Flutter 네이티브 위젯, Go API 직접 호출 |
| **Android** (APK 배포) | `NavShell` (네이티브) | Flutter 네이티브 위젯 — 기본값. WebView 쓰지 않음 |
| **Yocto RPi5** (ivi-homescreen) | `ShellWebView` | WebView → Lit UI (RPi5 전용) |

**왜 Linux에서 WebView 안 쓰는가:**
- `webview_flutter`는 Linux 미지원 (Android/iOS/Web만 공식)
- Linux에서 `WebViewController` 생성 시 null crash
- 대신 `ShellNative`로 Go REST API를 Flutter 위젯에서 직접 호출
- 개발 시 hot reload 지원, 프로덕션과 동일 API 사용

**개발 워크플로:**
```bash
# 터미널 1: Go 서버
./run.sh flutter-server

# 터미널 2: Flutter 앱 (hot reload)
./run.sh flutter-run

# 또는 빌드 후 실행
./run.sh flutter-build
./run.sh flutter-exec
```

**devShell 진입 필요:** Flutter 명령은 `nix develop .#dev` 환경에서 실행됨.
`run.sh` 명령들이 자동으로 devShell을 감싸므로 직접 진입 불필요.

---

## meta-flutter (커뮤니티)

| 항목 | 값 |
|------|-----|
| **리포** | https://github.com/meta-flutter/meta-flutter |
| **브랜치** | scarthgap |
| **Flutter Engine** | 3.38.3 (Dart 3.10.1) |
| **embedder** | ivi-homescreen 2.0 (Toyota, Wayland) |
| **의존성** | meta-clang (scarthgap) |
| **LAYERSERIES_COMPAT** | nanbield scarthgap |

**변경 이력 (2026-03-06):**
- ~~meta-flutter-sony (kirkstone)~~ → meta-flutter 커뮤니티 (scarthgap)로 전환
- 이유: scarthgap 호환 + ivi-homescreen WebView 플러그인 필요
- flutter-pi(DRM 직접)는 WebView 미지원이므로 ivi-homescreen(Wayland) 선택
- 경동 프로젝트 APK와 동일 Flutter 코드베이스 유지를 위한 결정

**ivi-homescreen vs flutter-pi:**

| | ivi-homescreen | flutter-pi |
|---|---|---|
| 디스플레이 | Wayland (Weston 위) | DRM 직접 (Weston 불필요) |
| WebView | ✅ webview_flutter_view | ❌ 미지원 |
| 빌드 의존 | meta-clang (clang 도구체인) | GCC로 충분 |
| 용도 | **선택됨** — WebView Shell | RPi 전용 경량 |

---

## 커널 버전 타임라인

```
2024.03  Raspberry Pi OS → Kernel 6.6 LTS
2024.04  Yocto Scarthgap → Kernel 6.6 LTS
2024.10  Yocto Styhead   → Kernel 6.10
2025.04  Raspberry Pi OS → Kernel 6.12 LTS
2025.12  Yocto Whinlatter → (TBD)
```

**결론**: 
- Scarthgap (6.6 LTS)은 2024년 Raspberry Pi OS와 완벽 호환
- 2025년 이후 RPi OS가 6.12로 업그레이드되어도 6.6 LTS는 안정적

---

## 권장 구성

### Option A: Hailo-8/8L (scarthgap LTS)

```
Yocto Branch: scarthgap (5.0 LTS)
├── poky                    : scarthgap
├── meta-openembedded       : scarthgap
├── meta-raspberrypi        : scarthgap
├── meta-clang              : scarthgap
├── meta-hailo              : hailo8-scarthgap
│   └── HailoRT 4.23.0, TAPPAS 5.1.0
└── meta-flutter            : scarthgap (커뮤니티)

Kernel: 6.6 LTS | Machine: raspberrypi5
```

### Option B: Hailo-10H GenAI (kirkstone)

```
Yocto Branch: kirkstone (4.0)
├── poky                    : kirkstone
├── meta-openembedded       : kirkstone
├── meta-raspberrypi        : kirkstone (RPi5 지원 ✅)
├── meta-clang              : kirkstone
├── meta-hailo              : kirkstone-v5.2.0
│   └── HailoRT 5.2.0, TAPPAS 5.2.0, GenAI ✅
└── meta-flutter            : kirkstone (Sony)

Kernel: 6.1 | Machine: raspberrypi5
```

**Current: Option A** (Hailo-8, scarthgap). Verified 2026-03-27.

**Selection criteria:**
- Vision AI only → **Option A** (LTS, stable, **verified**)
- GenAI (LLM/VLM/Voice) needed → **Option B** (Hailo-10H required)
- Wait for meta-hailo scarthgap support for 10H before switching to kirkstone

### Hailo-8 vs Hailo-10H — What changes at SW level

| Area | Hailo-8 (now) | Hailo-10H (future) | SW change needed |
|------|--------------|-------------------|-----------------|
| Vision AI pipeline | ✅ 398 FPS (YOLOv8s) | Faster | None (swap HEF only) |
| GStreamer elements | ✅ hailonet + hailotools | Same | None |
| Go ↔ HailoRT integration | ✅ Build now | Same API | None |
| presence → Matter | ✅ Build now | Same | None |
| Multi-model scheduler | ✅ hailonet scheduling | Same | None |
| sLLM on CPU | ✅ 5.2s (Qwen3-0.6B f16) | Same | None |
| sLLM on NPU | ❌ On-chip memory limit | ✅ 8GB LPDDR4 | HEF conversion only |
| GenAI apps (LLM/VLM/Voice) | ❌ | ✅ | New app layer |
| Yocto branch | scarthgap (5.0) | kirkstone (4.0) ⚠️ | **Build fork** |
| HailoRT version | 4.23.0 | 5.2.0+ | **Minor API migration** |

**Strategy: Do everything on Hailo-8 first.** All Go integration, GStreamer pipelines,
Matter occupancy, sLLM fallback chain — identical code carries over to 10H.
Only HEF model files need recompilation for 10H architecture.

### Benchmark (RPi5 + Hailo-8, 2026-03-27)

| Model | Task | HEF | FPS (HW) | Latency | Context |
|-------|------|-----|----------|---------|---------|
| YOLOv8n | Detection (nano) | 4.9M | 420 | 3.5ms | Single |
| YOLOv8s | Detection (small) | 10M | 398 | 6.7ms | Single |
| YOLOv8m | Detection (medium) | 29M | 29 | 28ms | Multi(3) |
| YOLOv8l | Detection (large) | 37M | 19 | 45ms | Multi(4) |
| YOLOv8s Pose | Pose estimation | 9.8M | 326 | 7.5ms | Single |
| SCRFD 2.5G | Face detection | 3.0M | 575 | 2.8ms | Single |
| FastDepth | Depth estimation | 2.8M | 770 | 2.8ms | Single |

Note: Requires 5V/5A+ power adapter. Underpowered PSU causes shutdown under full NPU load.

---

## Hailo AI 가속기

### 지원 모델

| 모델 | 성능 | 인터페이스 | 용도 |
|------|------|-----------|------|
| **Hailo-8** | 26 TOPS (INT8) | M.2 / PCIe | AI HAT+ |
| **Hailo-8L** | 13 TOPS (INT8) | M.2 | AI Kit (컴팩트) |
| **Hailo-10H** | 40 TOPS (INT4) | M.2 / PCIe | AI HAT+ 2 (**GenAI 지원**) |

### Raspberry Pi AI HAT+ 시리즈

| 제품 | 칩셋 | RAM | GenAI | 가격대 |
|------|------|-----|-------|--------|
| **AI HAT+** | Hailo-8 (26 TOPS) | - | ❌ | $70 |
| **AI HAT+ 2** | Hailo-10H (40 TOPS) | 8GB | ✅ LLM/VLM | $110 |
| **AI Kit** | Hailo-8L (13 TOPS) | - | ❌ | $70 |

### meta-hailo (Yocto 레이어)

| 칩셋 | 브랜치 | HailoRT | Yocto | RPi5 |
|------|--------|---------|-------|------|
| **Hailo-8/8L** | `hailo8-scarthgap` | 4.23.0 | scarthgap ✅ | ✅ |
| **Hailo-10H** | `kirkstone-v5.2.0` | 5.2.0 | kirkstone ⚠️ | ✅ |

**⚠️ Hailo-10H 사용 시 주의:**
- Hailo-10H (AI HAT+ 2)는 **kirkstone 브랜치만 지원**
- meta-raspberrypi kirkstone에서 RPi5 지원 ✅
- GenAI (LLM/VLM) 사용하려면 kirkstone으로 빌드 필요

**레이어 구성:**
```
meta-hailo/
├── meta-hailo-accelerator   # PCIe 드라이버, 펌웨어
├── meta-hailo-libhailort    # HailoRT, pyHailoRT, GStreamer
└── meta-hailo-tappas        # TAPPAS 프레임워크
```

**GitHub**: https://github.com/hailo-ai/meta-hailo

### hailo-apps (AI 앱)

| 카테고리 | 앱 | Hailo-8/8L | Hailo-10H |
|----------|-----|-----------|-----------|
| **Vision** | Detection, Pose, Segmentation, Face, Depth, OCR | ✅ | ✅ |
| **GenAI** | LLM Chat, VLM Chat, Whisper, Voice Assistant | ❌ | ✅ |
| **통합** | Ollama (Open WebUI), Agent Tools | ❌ | ✅ |

**GitHub**: https://github.com/hailo-ai/hailo-apps

---

## 참고 링크

- [Yocto Releases](https://wiki.yoctoproject.org/wiki/Releases)
- [meta-raspberrypi](https://github.com/agherzan/meta-raspberrypi)
- [meta-openembedded](https://github.com/openembedded/meta-openembedded)
- [ot-br-posix recipe (scarthgap)](https://git.openembedded.org/meta-openembedded/tree/meta-networking/recipes-connectivity/openthread/ot-br-posix_git.bb?h=scarthgap)
- [Raspberry Pi OS Release Notes](https://www.raspberrypi.com/software/operating-systems/)
- [meta-hailo](https://github.com/hailo-ai/meta-hailo)
- [hailo-apps](https://github.com/hailo-ai/hailo-apps)
- [hailo-rpi5-examples](https://github.com/hailo-ai/hailo-rpi5-examples)
- [Raspberry Pi AI HAT+](https://www.raspberrypi.com/products/ai-hat-plus/)
