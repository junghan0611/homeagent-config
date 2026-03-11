# HomeAgent 플랫폼 매트릭스

## 왜 이 문서가 필요한가

HomeAgent는 RPi5(Yocto Linux)와 RK3576(Android)에서 동일한 역할을 수행한다.
"같은 역할이면 같은 베이스에서 처리" 원칙을 지키되,
플랫폼 차이로 불가피한 분기점을 **명시적으로** 기록한다.

## 스택 비교

```
┌─────────────────────────────────────────────────────────────────┐
│                    HomeAgent 공통 계층                            │
│                                                                   │
│  Flutter APK (WebView Shell)  ← 동일 코드, 동일 APK              │
│  Go homeagent (:8080)         ← 동일 바이너리 (GOOS=linux arm64) │
│  Lit UI (ui/dist/)            ← 동일 정적 파일                    │
│  matterjs-server (:5580)      ← 동일 Node.js 번들                │
│  matter/ (pure Dart)          ← 동일 BLE commissioning 코드      │
├─────────────────────────────────────────────────────────────────┤
│              여기서부터 플랫폼 분기                                 │
└─────────────────────────────────────────────────────────────────┘

  RPi5 (Yocto Linux)                    RK3576 (Android 15)
  ──────────────────                    ───────────────────
  ivi-homescreen (Wayland)              Flutter APK (Android WebView)
  systemd services                      shell scripts (start/stop)
  │                                     │
  ├─ otbr-agent                         ├─ otbr-agent
  │  └─ Yocto bitbake 빌드              │  └─ NDK arm64 빌드 ★
  │  └─ avahi-daemon (mDNS)             │  └─ OT core mDNS (내장) ★
  │  └─ /dev/ttyUSB0 (ZBDongle-E)      │  └─ /dev/ttyS5 (ESP32-H2)
  │  └─ systemd service                 │  └─ rk3576-thread.sh
  │                                     │
  ├─ Node.js 20 (Yocto 패키지)          ├─ Node.js 20 (glibc 번들) ★
  │                                     │  └─ ld-linux-aarch64.so.1
  │                                     │
  ├─ eth0 backbone                      ├─ wlan0 backbone ★
  ├─ /etc/default/otbr-agent            ├─ rk3576-thread.sh 환경변수
  ├─ avahi-daemon                       ├─ (없음 — OT core가 대체)
  └─ Linux kernel (Yocto)              └─ Android kernel 6.1.118
```

★ = 플랫폼 분기점

## 분기점 상세

### 1. OTBR (Thread Border Router)

| 항목 | RPi5 Yocto | RK3576 Android | 공통점 |
|------|-----------|---------------|--------|
| **소스** | ot-br-posix (동일) | ot-br-posix (동일) | ✅ 동일 소스 |
| **빌드** | bitbake (OE toolchain) | NDK r27 (cmake) | ❌ 다른 툴체인 |
| **mDNS** | avahi-daemon | OT core (내장) | ❌ 다른 백엔드 |
| **init** | systemd | shell script | ❌ 다른 init |
| **RCP** | /dev/ttyUSB0 (USB) | /dev/ttyS5 (UART) | ❌ 다른 인터페이스 |
| **baudrate** | 460800 | 460800 | ✅ 동일 |
| **backbone** | eth0 | wlan0 | ❌ 다른 IF |
| **ot-ctl** | PATH에 있음 | /data/local/tmp/otbr/ | ❌ 다른 경로 |

**결론**: 소스는 동일하나 빌드/배포 방식이 다름. `scripts/build-otbr.sh`(Android), `yocto/meta-homeagent/.../ot-br-posix_git.bbappend`(Yocto)에서 각각 관리.

### 2. Go homeagent

| 항목 | RPi5 | RK3576 | 비고 |
|------|------|--------|------|
| **바이너리** | GOOS=linux GOARCH=arm64 | GOOS=linux GOARCH=arm64 | ✅ 완전 동일 |
| **ot-ctl 경로** | 기본 (`ot-ctl`) | `HOMEAGENT_OT_CTL` 환경변수 | 환경변수로 통합 |

### 3. matterjs-server

| 항목 | RPi5 | RK3576 | 비고 |
|------|------|--------|------|
| **Node.js** | Yocto nodejs 패키지 | glibc 번들 (ld-linux) | ❌ 다른 배포 |
| **BLE** | noble (Linux HCI) | `--bluetooth-adapter 0` | BLE HAL 차이 |
| **코드** | 동일 | 동일 | ✅ |

### 4. Flutter APK

| 항목 | RPi5 | RK3576 | 비고 |
|------|------|--------|------|
| **셸** | ivi-homescreen (Wayland) | Android WebView | ❌ 다른 컨테이너 |
| **APK** | 해당 없음 | com.homeagent.app | |
| **BLE** | noble (matterjs) | flutter_blue_plus | ❌ 다른 BLE 스택 |
| **UI 코드** | 동일 Lit 번들 | 동일 Lit 번들 | ✅ |

## 버전 고정

| 컴포넌트 | 버전/커밋 | 고정 위치 |
|---------|----------|----------|
| ot-br-posix | `c19319c7` | `~/repos/3rd/ot-br-posix` |
| openthread (submodule) | `0887643bf` | ot-br-posix submodule |
| NDK | r27 (27.0.12077973) | `flake.nix` ndkVersions |
| Go | 1.25.5 | `go/go.mod` |
| Node.js (dev) | 22 | `flake.nix` |
| Node.js (target) | 20.18.2 | `scripts/bundle-backend.sh` |
| Flutter | 3.38.9 | `flake.nix` |
| Android SDK | 36 (target 35) | `flake.nix` |
| matter.js | latest (npm) | `matterjs-server/package.json` |

## 빌드 명령 정리

| 대상 | 명령 | 산출물 |
|------|------|--------|
| Go arm64 | `./run.sh go-build-arm64` | `dist/homeagent` |
| Flutter APK | `./run.sh apk-build` | `flutter/build/.../app-release.apk` |
| UI | `cd ui && npm run build` | `ui/dist/` |
| matterjs 번들 | `./run.sh bundle` | `dist/homeagent-bundle-arm64/` |
| **OTBR arm64** | `./run.sh otbr-build` | `dist/otbr-arm64/` |
| Yocto 이미지 | `./run.sh bb-cmd homeagent-app` | Yocto deploy |

## 패치 관리

`patches/` 디렉토리에 third-party 소스 패치 보관:

```
patches/
└── ot-br-posix/
    └── 0001-fix-udp-sign-compare-ndk-clang.patch
```

`scripts/build-otbr.sh`가 빌드 전 자동 적용. Yocto는 `bbappend`에서 `SRC_URI += "file://..."` 패턴 사용.

## 원칙

1. **같은 역할 → 같은 소스**: ot-br-posix는 하나, 빌드 방식만 다름
2. **분기점은 명시적**: ★ 표시로 어디가 달라지는지 한눈에
3. **환경변수로 통합**: 경로/IF 차이는 코드 분기 아닌 환경변수
4. **패치는 리포에**: third-party 수정은 `patches/`에 보관, 빌드 스크립트가 자동 적용
5. **버전 고정**: 재현 가능한 빌드를 위해 커밋/버전 명시
