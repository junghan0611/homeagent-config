# HomeAgent Config

RPi5 + Yocto + Go + Flutter + Zig + Matter + Edge AI 오픈소스 홈에이전트 플랫폼

**OpenHome Foundation 기여를 위한 완전 오픈소스 프로젝트**

---

## 비전

```
┌─────────────────────────────────────────────────────────────────┐
│  homeagent-config (Yocto 이미지)                                │
│  "Data Privacy + On-device AI + Matter Hub"                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Flutter App (meta-flutter, Wayland 네이티브)                   │
│  ├── UI: 대시보드, 디바이스 제어, AI 시각화                     │
│  └── FFI → Go Core / Zig Core                                   │
│                                                                 │
│  Go Core                                                        │
│  ├── HA API 호환 레이어                                         │
│  ├── EdgeAI Runtime (ONNX/TFLite)                               │
│  └── 컨텍스트 엔진, 패턴 학습                                   │
│                                                                 │
│  Zig Core (zigbee-hub 템플릿)                                  │
│  ├── Matter Controller + Device                                 │
│  ├── OTBR (Thread Border Router)                                │
│  ├── Zigbee Bridge (옵션)                                       │
│  └── 결정론적 100ms 상태머신                                    │
│                                                                 │
│  Yocto Linux (RPi5)                                             │
│  ├── meta-raspberrypi (BSP)                                     │
│  ├── meta-flutter (Sony)                                        │
│  ├── meta-hailo (Edge AI NPU)                                   │
│  └── Wayland/Weston                                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 핵심 철학

1. **Data Privacy First**: 클라우드 의존 없는 온디바이스 처리
2. **완전 오픈소스**: HW(RPi5) + SW(Yocto) + 프로토콜(Matter) 모두 공개
3. **개인 에이전트 연동**: 엣지 AI가 사용자의 고성능 에이전트와 협업

---

## 하드웨어

| 구성요소 | 사양 |
|----------|------|
| 메인 보드 | Raspberry Pi 5 (8GB 권장) |
| Thread RCP | USB Thread Controller |
| NPU (옵션) | Hailo AI HAT+ 시리즈 |

### Hailo AI 가속기 옵션

| 제품 | 칩셋 | 성능 | 특징 |
|------|------|------|------|
| **AI Kit** | Hailo-8L | 13 TOPS (INT8) | 컴팩트, $70 |
| **AI HAT+** | Hailo-8 | 26 TOPS (INT8) | 표준, $70 |
| **AI HAT+ 2** | Hailo-10H | 40 TOPS (INT4) | **GenAI (LLM/VLM)**, 8GB RAM, $110 |

**권장**: AI HAT+ 2 (Hailo-10H) - 음성 어시스턴트, VLM 등 GenAI 지원

---

## 기술 스택

### Layer 1: Yocto Linux Base

| 구성요소 | 역할 |
|----------|------|
| Yocto Project | 커스텀 Linux 배포판 빌드 (Scarthgap 5.0 LTS) |
| meta-raspberrypi | RPi5 BSP |
| meta-flutter | Flutter Embedded Linux (Sony) |
| meta-hailo | Hailo AI HAT+ (8/8L/10H) - HailoRT, TAPPAS |
| hailo-apps | 20+ AI 앱 (Detection, Pose, LLM, VLM, Voice) |
| Wayland/Weston | 디스플레이 서버 |

### Layer 2: Go Core (kd-wallpad-app 재사용)

| 구성요소 | 역할 |
|----------|------|
| HA API 호환 | WebSocket/REST 클라이언트 |
| EdgeAI Runtime | ONNX/TFLite 추론 엔진 |
| Context Engine | 상황 인식 (home, away, sleep) |
| Automation | 패턴 학습, 규칙 자동 생성 |
| FFI Bridge | Flutter dart:ffi 연동 |

### Layer 3: Zig Core (sks-hub-zig 템플릿)

| 구성요소 | 역할 |
|----------|------|
| State Machine | 결정론적 100ms 루프, 순수 함수 전이 |
| Matter SDK | Controller + Device 구현 |
| OTBR | Thread Border Router |
| FFI Layer | C/Go/Flutter 연동 |

### Layer 4: Flutter UI (meta-flutter)

| 구성요소 | 역할 |
|----------|------|
| Flutter eLinux | Sony meta-flutter, Wayland 네이티브 |
| 대시보드 | Matter 디바이스 제어/모니터링 |
| AI 인터랙션 | 컨텍스트 표시, 예측 제안 |

**핵심 인사이트**: 소프트센서(MLP/LSTM)는 CPU만으로 충분 (0.01-0.1 TOPS).
NPU는 음성/비전 등 서비스 확장성을 위한 것.

---

## 디렉토리 구조

```
homeagent-config/
├── AGENTS.md                 # 에이전트 지침
├── README.md                 # 프로젝트 개요 (이 파일)
├── flake.nix                 # Nix 개발 환경
│
├── docs/                     # 문서
│   ├── ARCHITECTURE.md       # 아키텍처 설계
│   └── VISION.md             # 프로젝트 비전
│
├── yocto/                    # Yocto 빌드 환경
│   ├── meta-homeagent/       # 커스텀 레이어
│   │   ├── recipes-core/     # 코어 패키지
│   │   ├── recipes-flutter/  # Flutter 앱 레시피
│   │   └── recipes-ai/       # AI 런타임 레시피
│   ├── conf/                 # 빌드 설정
│   └── scripts/              # 빌드 스크립트
│
├── go/                       # Go Core
│   ├── pkg/
│   │   ├── ha/               # HA API 호환
│   │   ├── edgeai/           # EdgeAI 런타임
│   │   └── bridge/           # Flutter FFI
│   └── go.mod
│
├── zig/                      # Zig Core
│   ├── src/
│   │   ├── config_as_ssot.zig
│   │   ├── types/
│   │   ├── core/
│   │   └── matter/
│   └── build.zig
│
├── flutter/                  # Flutter UI
│   ├── lib/
│   │   ├── features/
│   │   └── core/ffi/
│   └── pubspec.yaml
│
└── models/                   # AI 모델
    ├── context.onnx
    └── intent.tflite
```

---

## 빠른 시작 (Yocto 빌드)

### 1. 개발 환경 진입

```bash
cd homeagent-config
nix develop  # Yocto FHS devshell
```

### 2. 레이어 설정

```bash
cd yocto/sources

# 기존 클론 심볼릭 링크 + 나머지 클론
./setup-layers.sh --link

# 빌드 환경 초기화
source poky/oe-init-build-env ../build
```

### 3. 설정 파일 복사

```bash
cp ../conf/local.conf.sample conf/local.conf
cp ../conf/bblayers.conf.sample conf/bblayers.conf
```

### 4. 빌드

```bash
# 기본 이미지 (Weston + OTBR)
bitbake core-image-weston

# 결과물
ls tmp/deploy/images/raspberrypi5/*.wic.bz2
```

### 5. SD 카드 플래싱

```bash
bmaptool copy tmp/deploy/images/raspberrypi5/core-image-weston-raspberrypi5.wic.bz2 /dev/sdX
```

---

## 로드맵

### Phase 1: Yocto 기반 구축 (현재)

- [x] flake.nix 개발 환경
- [ ] RPi5 Yocto 빌드 성공
- [ ] 부팅 및 Weston 동작 확인
- [ ] OTBR (ot-br-posix) 동작 확인
- [ ] meta-flutter 통합 → Flutter 앱 표시

### Phase 2: Matter/Thread 통합

- [ ] Thread RCP USB 연결 검증
- [ ] Matter Controller (Zig)
- [ ] Software Matter Device

### Phase 3: AI + 앱 통합

- [ ] Go Core EdgeAI Runtime
- [ ] Flutter UI 개발
- [ ] 풀패키지 Yocto 이미지 배포

---

## 라이선스

MIT / Apache 2.0
