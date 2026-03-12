# HomeAgent 설치 가이드

RK3576 Android 보드에 HomeAgent 풀 스택을 설치하는 가이드.

## 사전 조건

| 항목 | 요구 사항 |
|------|----------|
| **보드** | RK3576 (Android 15, `adb root` 가능) |
| **Thread RCP** | ESP32-H2 (`/dev/ttyS5`, 460800bps) — Thread 디바이스 사용 시 |
| **WiFi** | 2.4GHz 네트워크 (Matter WiFi 커미셔닝용) |
| **개발 PC** | NixOS 또는 Linux (Go, Node.js, Flutter SDK) |
| **ADB** | USB 또는 WiFi ADB 연결 |

## 빠른 시작 (원커맨드)

```bash
# 1. 개발 환경 진입 (Flutter/Android SDK 포함)
nix develop .#dev --impure

# 2. 전체 빌드 + 배포 + 시작
./run.sh android deploy

# 3. Thread 네트워크 설정 (Thread 디바이스 사용 시)
./run.sh android thread-start
```

이것으로 끝입니다. APK가 자동 설치되고 서버가 시작됩니다.

## 단계별 설명

### 1. 빌드 환경 준비

```bash
# NixOS flake — Go, Node.js, Flutter, Android SDK 포함
nix develop .#dev --impure

# 또는 직접 설치 시 필요한 것:
# - Go 1.24+
# - Node.js 20+, npm
# - Flutter 3.32+ (Android SDK 35)
# - adb
```

### 2. 빌드

`deploy` 명령이 자동으로 수행하지만, 개별 빌드도 가능:

```bash
# Go 서버 (android/arm64)
./run.sh android build-go

# Lit UI (Vite → dist/)
./run.sh android build-ui

# Flutter APK
./run.sh android build-apk

# Node.js + matterjs-server 번들 (최초 1회, ~300MB)
./run.sh bundle
```

### 3. 배포

```bash
# ADB 연결 확인
adb devices

# 전체 배포 (빌드 포함)
./run.sh android deploy

# 빌드 건너뛰기 (이미 빌드된 아티팩트 재배포)
./run.sh android deploy --skip-go --skip-apk --skip-ui
```

**배포 대상 (`/data/local/tmp/`):**

| 파일/디렉토리 | 내용 |
|--------------|------|
| `homeagent` | Go 서버 바이너리 (7MB) |
| `ui/dist/` | Lit 프론트엔드 (index.html + wallpad.html) |
| `nodejs-bundle/` | Node.js + matterjs-server (~300MB) |
| `otbr/` | otbr-agent + ot-ctl |
| `aliases.json` | 디바이스 별칭/방 매핑 |

### 4. 서비스 관리

```bash
# 시작 (matterjs → Go, 기존 프로세스 자동 정리)
./run.sh android start

# 중지
./run.sh android stop

# 상태 확인 (PID + 포트 + 에러 로그)
./run.sh android status

# 로그
./run.sh android logs          # 전체
./run.sh android logs matter   # matterjs만
./run.sh android logs go       # Go만
./run.sh android logs otbr     # OTBR만
```

### 5. Thread 네트워크 (선택)

Thread 디바이스(센서, 도어락 등)를 사용할 때:

```bash
# Thread Border Router 시작
./run.sh android thread-start

# 상태 확인
./run.sh android thread-status

# 중지
./run.sh android thread-stop
```

**환경변수로 RCP 설정 변경:**

```bash
RCP_DEVICE=/dev/ttyS5 RCP_BAUDRATE=460800 ./run.sh android thread-start
```

### 6. APK 사용

1. APK 실행 → "서버 연결 중..." → 대시보드 표시
2. **디바이스 페어링**: 하단 BLE 버튼 (🔵) 탭
   - WiFi SSID / 비밀번호 입력
   - Matter Pairing Code 입력 (QR 코드 아래 11자리 또는 `MT:...`)
   - 60~120초 대기
3. 페어링 완료 → 대시보드에 디바이스 카드 자동 추가
4. **월패드 UI**: `http://<보드IP>:8080/wallpad` (1024×600 전용)

## WiFi 커미셔닝 설정

WiFi Matter 디바이스를 커미셔닝하려면 WiFi 정보를 서버에 전달:

```bash
# 방법 1: 환경변수
WIFI_SSID=MyWiFi WIFI_PASSWORD=secret123 ./run.sh android start

# 방법 2: APK 커미셔닝 화면에서 입력 (매번)
```

## 트러블슈팅

### 서버가 안 뜸

```bash
# 로그 확인
./run.sh android logs all

# 포트 확인
adb shell "netstat -tlnp 2>/dev/null | grep -E '5580|8080'"

# 수동 재시작
./run.sh android stop
./run.sh android start
```

### BLE 커미셔닝 실패

| 증상 | 확인 |
|------|------|
| "블루투스가 꺼져있습니다" | 설정 → 블루투스 켜기 |
| "BLE relay 연결 실패" | matterjs-server 실행 중인지 확인 (`./run.sh android logs matter`) |
| BTP handshake timeout | 디바이스가 페어링 모드인지, BLE 범위 내인지 확인 |
| PASE 실패 | Pairing Code 확인 |
| WiFi 연결 실패 | SSID/비밀번호 확인, 2.4GHz인지 확인 |

### Thread 디바이스 안 됨

```bash
# Thread 상태 확인
./run.sh android thread-status

# Thread 재시작
./run.sh android thread-stop
./run.sh android thread-start

# RCP 디바이스 확인
adb shell "ls -l /dev/ttyS5"
```

### APK가 서버를 못 찾음

APK는 기본적으로 `localhost:8080`에 연결합니다:

- **같은 보드**: 기본값 사용
- **다른 보드**: APK 빌드 시 `SERVER_HOST` 지정:
  ```bash
  cd flutter && flutter build apk --release --dart-define=SERVER_HOST=192.168.1.100
  ```

## 아키텍처

```
Flutter APK (WebView)
  └── http://localhost:8080 ───▶ Go HomeAgent (:8080)
                                   ├── REST API (8 commands)
                                   ├── /wallpad → 월패드 UI
                                   ├── SSE 실시간 이벤트
                                   └── WS → matterjs-server (:5580)
                                              ├── Matter 커미셔닝
                                              ├── BLE relay WS (:5581)
                                              └── Thread dataset
```

## 파일 구조

```
homeagent-config/
├── go/                    # Go 서버
├── ui/                    # Lit 프론트엔드
├── flutter/               # Flutter 앱 (WebView 셸)
├── matterjs-server/       # matterjs 설정 + remote-ble
├── scripts/
│   ├── android-deploy.sh  # 배포 스크립트
│   └── bundle-backend.sh  # 번들 빌드
├── aliases.json           # 디바이스 별칭
├── run.sh                 # 통합 명령
└── docs/INSTALL.md        # 이 문서
```
