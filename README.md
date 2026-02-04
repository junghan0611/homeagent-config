# HomeAgent Config

RPi5 + Yocto + Go + Flutter + Zig + Matter + Edge AI 오픈소스 홈에이전트 플랫폼

**OpenHome Foundation 기여를 위한 완전 오픈소스 프로젝트**

---

## 비전

**"Data Privacy + On-device AI + Matter Hub"**

```
┌─────────────────────────────────────────────────────────────────┐
│                     Agent Layer (A2A)                           │
├─────────────────────────────────────────────────────────────────┤
│  Master Agent ←──A2A Protocol──→ HomeAgent ←───→ User           │
│  (Cloud/PC)        (승인 기반)     (Edge)       (Human)         │
└─────────────────────────┬───────────────────────────────────────┘
                          │ CLI / API (에이전트 직관 튜닝, retry)
┌─────────────────────────┴───────────────────────────────────────┐
│                     Go Service Layer                            │
│  ├── HA API 호환 레이어 (검증된 인터페이스)                     │
│  ├── EdgeAI Runtime (ONNX/TFLite)                               │
│  ├── MQTT 브릿지 (zigbee2mqtt 연동)                             │
│  └── 배포: 단일 바이너리                                        │
└─────────────────────────┬───────────────────────────────────────┘
                          │ FFI / IPC
┌─────────────────────────┴───────────────────────────────────────┐
│                     Zig Core (State Machine)                    │
│  ├── 결정론적 100ms 루프, 순수 함수 전이                        │
│  ├── Matter Controller + Device                                 │
│  ├── Thread Border Router                                       │
│  └── 배포: 단일 바이너리                                        │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────────┐
│                     Network Layer (검증 우선)                   │
│  ├── zigbee2mqtt (ZBDongle-E) - 3000+ 디바이스                  │
│  ├── OTBR (Thread RCP)                                          │
│  └── MQTT Broker (mosquitto)                                    │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────────┐
│                     Yocto Linux (RPi5)                          │
│  ├── meta-raspberrypi (BSP)                                     │
│  ├── meta-homeagent (커스텀 레이어)                             │
│  ├── meta-hailo (Edge AI NPU, 옵션)                             │
│  └── Wayland/Weston + 동적 데이터 뷰어                          │
└─────────────────────────────────────────────────────────────────┘
```

### 개발 전략: 검증 우선

```
1. Network Layer    zigbee2mqtt + MQTT로 실제 디바이스 검증
        ↓
2. HA 호환성        검증된 데이터로 Home Assistant API 호환 확보
        ↓
3. Zig/Go Core      검증된 인터페이스 기반으로 코어 구현
        ↓
4. Agent Layer      A2A 프로토콜, CLI/API 에이전트 튜닝
```

> *하드웨어 검증에 시간 쓰지 않는다. 검증된 오픈소스로 데이터 확보 후 코어 구현.*

### 핵심 철학

1. **Data Privacy First**: 클라우드 의존 없는 온디바이스 처리
2. **완전 오픈소스**: HW(RPi5) + SW(Yocto) + 프로토콜(Matter) 모두 공개
3. **개인 에이전트 연동**: 엣지 AI가 사용자의 고성능 에이전트와 협업

### 에이전트 아키텍처: 협력적 AI

```
┌─────────────────────────────────────────────────────────────┐
│                    Master Agent (Cloud/PC)                  │
│                 고성능 추론, 인터넷 접근 권한                │
└─────────────────────────┬───────────────────────────────────┘
                          │ A2A Protocol (승인 기반)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   HomeAgent (Edge/RPi5)                     │
│              공간을 지키는 Offline-First 에이전트           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ • 카메라 접근 O, 인터넷 직접 접근 X                 │    │
│  │ • 제한된 자원에서 Best Effort                       │    │
│  │ • 추가 정보 필요 시 Master/User에게 요청            │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │   User (Human)        │
              │ 최종 승인권, 협력자    │
              └───────────────────────┘
```

**왜 하는가?**
- 인간과 에이전트의 상호협력 베이스 구축
- 프라이버시를 지키면서 AI의 혜택을 누림

**어떻게 하는가?**
- Offline-First: 기본 동작은 인터넷 없이
- Security-First: 제한된 권한의 `agent` 계정으로 실행
- A2A Protocol: 에이전트 간 협력 (승인 기반 정보 교환)

**무엇을 위해 하는가?**
- 토큰 최적화: 증류된 정보, 최적화된 API
- 자원 효율: 전기, 토큰, 정보는 증류되어 에이전트에게 제공
- 코어 로직, Matter 네트워크, 상태머신, CLI, API 모두 토큰 활용 최적화 지향

> *"구현은 언제나 쉽습니다. 이제는 한번에 다 만들어 낼수 있는 시대입니다.
> 왜 하는가? 어떻게 하는가? 무엇을 위해서 하는가?를 되새기는 것입니다."*

### UI 철학: 코드 없는 동적 인터페이스

```
┌─────────────────────────────────────────────────────────────┐
│                    기존 앱 패러다임                          │
│         [컴파일된 UI] ← 사용자 입력 대기 → [반응]           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   HomeAgent 패러다임                         │
│      [에이전트] → 동적 데이터 뷰어 → [빛과 형태로 소통]      │
│                                                             │
│  • 프론트엔드를 코드로 고정하지 않음                        │
│  • Quarto/R 대시보드처럼 동적 구성                          │
│  • 에이전트가 토큰 세이빙하며 적절히 표현                   │
│  • 디지털 아트 - 입력 대기가 아닌 능동적 표현               │
└─────────────────────────────────────────────────────────────┘
```

**핵심 전환:**
- ❌ 짜 놓은 앱을 넣고 입력 대기
- ✅ 에이전트가 상황에 맞게 동적으로 시각화
- ✅ HCI(Human-Computer Interaction) 인터페이스로 확장
- ✅ 빛, 형태, 움직임으로 공간과 소통하는 디지털 아트

> *UI는 뷰어일 뿐. 에이전트가 무엇을 어떻게 보여줄지 결정한다.*

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

- [x] flake.nix 개발 환경 (nix-environments 기반)
- [x] RPi5 Yocto 빌드 성공 (scarthgap 5.0 LTS)
- [x] 부팅 및 Weston 동작 확인
- [x] SSH 접속 (ssh-keys 레시피)
- [x] run.sh CLI (빌드/배포/SSH 통합)
- [x] zigbee2mqtt 레시피 준비
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
