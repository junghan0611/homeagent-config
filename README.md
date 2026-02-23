# HomeAgent Config

RPi5 + Yocto + Go + Node.js + Matter + Edge AI 오픈소스 홈에이전트 플랫폼

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
                          │ CLI / API
┌─────────────────────────┴───────────────────────────────────────┐
│                Go Service Layer (컨트롤러)                       │
│  ├── HA API 호환 레이어 (WebSocket/REST)                        │
│  ├── EdgeAI Runtime (ONNX/TFLite)                               │
│  ├── State Machine (결정론적 상태 전이, Go 내부 패키지)          │
│  ├── MQTT 클라이언트 (zigbee2mqtt 연동)                         │
│  ├── Matter 클라이언트 (matterjs-server WebSocket :5580)        │
│  └── 배포: 단일 바이너리                                        │
└─────────────────────────┬───────────────────────────────────────┘
                          │ MQTT / WebSocket
┌─────────────────────────┴───────────────────────────────────────┐
│               Node.js Protocol Layer (프로토콜 엔진)             │
│  ├── zigbee2mqtt       Zigbee 디바이스 (3000+ 지원)             │
│  ├── matterjs-server   Matter 컨트롤러 (matter.js 기반)         │
│  ├── matterbridge      비-Matter → Matter 브릿지 (옵션)         │
│  └── 단일 런타임: Node.js 20+                                   │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────────┐
│               System Infrastructure (C/C++)                     │
│  ├── mosquitto         MQTT 브로커                              │
│  ├── otbr-agent        Thread Border Router (RCP)               │
│  └── avahi-daemon      mDNS/DNS-SD                              │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────────┐
│                     Yocto Linux (RPi5)                          │
│  ├── meta-raspberrypi (BSP, scarthgap 5.0 LTS)                 │
│  ├── meta-homeagent (커스텀 레이어: OTBR, 패키지 설정)          │
│  ├── meta-hailo (Edge AI NPU, 옵션)                             │
│  └── Kernel 6.6 LTS                                             │
└─────────────────────────────────────────────────────────────────┘
```

### 런타임 스택 (2026-02-09 확정)

```
RPi5 (Yocto scarthgap) — HomeAgent 허브
├── Go       HomeAgent (컨트롤러, AI 판단, 상태머신, A2A)
├── Node.js  matterjs-server + zigbee2mqtt + matterbridge (프로토콜 엔진)
├── C/C++    mosquitto, otbr-agent, avahi-daemon (시스템 인프라)
└── (없음)   Python — 허브에서는 사용하지 않음

소형 디바이스 (Zig 펌웨어)
├── Zig      센서/액추에이터 펌웨어 (Thread/Matter 엔드포인트)
│            EFR32, nRF, ESP32 등 MCU 타겟
│            런타임 없음, 결정론적, 저전력
└── 역할     에이전트에 연결되는 말단 컨트롤러
             (자체 제작 센서, 릴레이, 디스플레이 등)
```

**언어별 역할:**
- **Go (허브 컨트롤러)**: Matter/Zigbee는 I/O-bound → goroutine + channel 적합. Thread 라디오 250kbps가 물리적 병목이므로 GC 일시정지 무의미
- **Node.js (프로토콜 엔진)**: HA 2026.2에서 C++ SDK → matter.js 전환. C++ SDK 안정성 문제 (크래시, 재시작 실패) 때문에 순수 JS가 오히려 안정적
- **Zig (소형 디바이스)**: 런타임 없음 + C ABI 호환 + 크로스 컴파일 → MCU 펌웨어 최적. HomeAgent에 Thread/Matter로 연결되는 자체 센서/컨트롤러 제작용

### 개발 전략: 검증 우선

```
1. System Infra     zigbee2mqtt + MQTT + OTBR로 실제 디바이스 검증 ✅
        ↓
2. Matter 검증      chip-tool → matterjs-server로 Matter 디바이스 연동
        ↓
3. Go Controller    검증된 프로토콜 위에 컨트롤러 구현
        ↓
4. Agent Layer      A2A 프로토콜, Constitutional AI, CLI/API
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

### Constitutional AI: 에이전트의 정체성

HomeAgent는 단순 조건문 엔진이 아니다.
**컨텍스트를 이해하고, 원칙에 따라 판단하는 에이전트**다.

```
constitution.md (정체성)     context.json (환경)
        │                         │
        └────────┬────────────────┘
                 ↓
         HomeAgent 판단 엔진
                 │
    ┌────────────┼────────────┐
    ↓            ↓            ↓
  가정         요양원       사무실
"생활 에이전트" "돌봄 에이전트" "시설 관리"
```

**핵심 원칙:**
1. 생명과 안전이 최우선
2. 거주자의 존엄성 존중
3. 확실하지 않으면 사람에게 묻기

> *자세한 내용: [docs/A2A.md](docs/A2A.md) - Constitutional AI 섹션*

### UI 철학: A2UI — 에이전트가 그리는 동적 인터페이스

```
┌─────────────────────────────────────────────────────────────┐
│                    기존 앱 패러다임                          │
│         [컴파일된 UI] ← 사용자 입력 대기 → [반응]           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│              HomeAgent 패러다임 (A2UI)                       │
│      [에이전트] → 선언적 JSON → [뷰어가 렌더링]             │
│                                                             │
│  • 프론트엔드를 코드로 고정하지 않음                        │
│  • A2UI: 실행 코드가 아닌 데이터로 UI를 기술               │
│  • JSONL 스트리밍으로 점진적 렌더링                         │
│  • 에이전트가 토큰 세이빙하며 적절히 표현                   │
│  • 디지털 아트 - 입력 대기가 아닌 능동적 표현               │
└─────────────────────────────────────────────────────────────┘
```

**[A2UI](https://a2ui.org)** (Agent-to-User Interface, Google): 에이전트가 선언적 JSON으로 UI를 기술하면, 클라이언트가 렌더링하는 프로토콜. 실행 코드가 아닌 데이터이므로 UI 인젝션 방지. [OpenClaw](https://github.com/openclaw/openclaw)가 Canvas에 A2UI v0.8을 내장하여 macOS/iOS/Android/Web에서 동작하는 구현체를 보여주고 있다.

```
HomeAgent (에이전트)
    │ A2UI JSONL (선언적 JSON)
    ▼
뷰어 (RPi5 디스플레이 / 웹 / 모바일)
    │ 동일 프로토콜, 다중 클라이언트
    ├→ RPi5 로컬 디스플레이 (Weston/Wayland)
    ├→ 웹 브라우저 (CopilotKit / AG-UI)
    └→ 모바일 (네이티브 브릿지)
```

**핵심 전환:**
- ❌ 짜 놓은 앱을 넣고 입력 대기
- ✅ 에이전트가 상황에 맞게 동적으로 시각화 (surfaceUpdate)
- ✅ HCI(Human-Computer Interaction) 인터페이스로 확장
- ✅ 빛, 형태, 움직임으로 공간과 소통하는 디지털 아트
- ✅ 동일 A2UI 프로토콜로 RPi5 디스플레이와 웹/모바일 동시 지원

> *UI는 뷰어일 뿐. 에이전트가 무엇을 어떻게 보여줄지 결정한다.*

---

## 하드웨어

| 구성요소 | 사양 |
|----------|------|
| 메인 보드 | Raspberry Pi 5 (8GB 권장) |
| Zigbee NCP | ZBDongle-E (USB, zigbee2mqtt용) |
| Thread RCP | ZBDongle-E (USB3 블루포트, OTBR용) |
| NPU (옵션) | Hailo AI HAT+ 시리즈 |
| 전원 | 5V/5A USB-C (동글 안정성 필수) |

### 듀얼 동글 구성

```
RPi5 USB Ports
├── USB2 (검정)  ZBDongle-E #1  →  zigbee2mqtt (Zigbee NCP)
└── USB3 (파랑)  ZBDongle-E #2  →  otbr-agent (Thread RCP)
```

> 전원 부족 시 CP210x 타임아웃 발생. 5V/5A 이상 전원 공급기 필수.

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
| meta-raspberrypi | RPi5 BSP (Kernel 6.6 LTS) |
| meta-homeagent | OTBR 설정, 패키지 커스텀, opkg |
| meta-hailo | Hailo AI HAT+ (8/8L/10H) - HailoRT, TAPPAS |

### Layer 2: System Infrastructure (C/C++)

| 구성요소 | 역할 |
|----------|------|
| mosquitto | MQTT 브로커 |
| otbr-agent | Thread Border Router (RCP over UART) |
| avahi-daemon | mDNS/DNS-SD (Matter 디스커버리) |

### Layer 3: Node.js Protocol Engine

| 구성요소 | 역할 |
|----------|------|
| zigbee2mqtt | Zigbee 디바이스 제어 (3000+ 지원, MQTT 퍼블리시) |
| matterjs-server | Matter 컨트롤러 (matter.js 기반, WebSocket :5580) |
| matterbridge | 비-Matter 디바이스를 Matter로 노출 (옵션, Apple/Google Home 연동) |

### Layer 4: Go Controller (HomeAgent)

| 구성요소 | 역할 |
|----------|------|
| HA API 호환 | WebSocket/REST 클라이언트 (HA 생태계 호환) |
| State Machine | 결정론적 상태 전이 (Go 내부 패키지) |
| EdgeAI Runtime | ONNX/TFLite 추론 엔진 |
| Context Engine | 상황 인식 (home, away, sleep) |
| MQTT Client | zigbee2mqtt 데이터 소비 |
| Matter Client | matterjs-server WebSocket 연동 |
| A2A Server | Agent2Agent 프로토콜 엔드포인트 |

### Zig: 소형 디바이스 펌웨어

허브가 아닌 **말단 디바이스**에 사용:

| 구성요소 | 역할 |
|----------|------|
| Thread 엔드포인트 | Matter over Thread 센서/액추에이터 |
| 타겟 MCU | EFR32, nRF52/53, ESP32 |
| 특징 | 런타임 없음, C ABI 호환, 결정론적, 저전력 |

**핵심 인사이트**: 소프트센서(MLP/LSTM)는 CPU만으로 충분 (0.01-0.1 TOPS).
NPU는 음성/비전 등 서비스 확장성을 위한 것.

---

## 디렉토리 구조

```
homeagent-config/
├── AGENTS.md                 # 에이전트 지침
├── README.md                 # 프로젝트 개요 (이 파일)
├── VERSION.md                # 버전 매트릭스 (Yocto/RPi5/Hailo 호환성)
├── flake.nix                 # Nix 개발 환경
├── run.sh                    # 빌드/배포/SSH 통합 CLI
│
├── docs/                     # 문서
│   ├── A2A.md                # A2A 프로토콜, Constitutional AI, 런타임 스택
│   ├── MQTT-HA.md            # Matter/HA 호환 아키텍처
│   ├── TARGET_DEVICE.md      # 타겟 디바이스 정보
│   ├── YOCTO-OFFLINE-FIRST.md  # Yocto 오프라인 빌드 전략
│   └── ZIGBEE2MQTT_UPSTREAM_GUIDE.md  # z2m 업스트림 가이드
│
├── yocto/                    # Yocto 빌드 환경
│   ├── meta-homeagent/       # 커스텀 레이어
│   │   ├── conf/             # 레이어 설정
│   │   ├── recipes-core/     # 코어 패키지 (ssh-keys, opkg 설정)
│   │   └── recipes-connectivity/  # OTBR bbappend, zigbee2mqtt, matterjs-server
│   ├── conf/                 # 빌드 설정 (local.conf, bblayers.conf)
│   └── sources/              # 레이어 소스 (심볼릭 링크)
│
├── go/                       # Go 컨트롤러
│   ├── cmd/homeagent/        # 메인 바이너리
│   ├── internal/matter/      # matterjs-server WebSocket 클라이언트
│   ├── internal/hub/         # 중앙 코디네이터 (상태머신, SSE)
│   ├── internal/config/      # 설정
│   └── bin/                  # 크로스 컴파일 결과물 (aarch64)
│
├── ui/                       # Lit 프론트엔드
│   ├── src/app.ts            # 메인 대시보드 (ha-app)
│   ├── src/device-card.ts    # 디바이스 상태 카드
│   ├── src/commission-dialog.ts  # 페어링 다이얼로그
│   ├── src/api.ts            # API 클라이언트 (REST + SSE)
│   └── dist/                 # 빌드 결과물
│
├── matter/                   # Matter 도구
│   ├── bin/                  # chip-tool 바이너리 + 런타임 라이브러리
│   └── connectedhomeip/     # chip-tool 빌드 환경 (Docker)
│
├── firmware/                 # 펌웨어
│   └── zbdonglee/            # ZBDongle-E RCP 펌웨어
│
├── scripts/                  # 유틸리티 스크립트
│   ├── build-chip-tool.sh    # chip-tool 크로스 컴파일 (v1.4.0.0)
│   ├── deploy-chip-tool.sh   # RPi5에 chip-tool 배포
│   └── flash-thread-rcp.sh   # Thread RCP 펌웨어 플래싱
│
└── .beads/                   # 이슈 트래커 (beads_rust)
    └── issues.jsonl
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
# 기본 이미지 (Weston + OTBR + mosquitto + Node.js)
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

### Phase 1: Yocto 기반 + 프로토콜 검증 ✅

- [x] flake.nix 개발 환경 (nix-environments 기반)
- [x] RPi5 Yocto 빌드 성공 (scarthgap 5.0 LTS)
- [x] 부팅 및 Weston 동작 확인
- [x] SSH 접속 (ssh-keys 레시피)
- [x] run.sh CLI (빌드/배포/SSH 통합)
- [x] Node.js 20 + mosquitto 설치
- [x] ZBDongle-E 듀얼 동글 인식 (Zigbee NCP + Thread RCP)
- [x] OTBR (ot-br-posix) 동작 확인 (Thread Leader, SRP server)
- [x] chip-tool v1.4.0.0 크로스 컴파일 + 배포
- [x] **Matter commissioning 전체 흐름 검증** (2026-02-09)
  - BLE → PASE → NOC → Thread → SRP → mDNS → CASE → CommissioningComplete
  - Eve 도어센서 BooleanState 데이터 읽기 성공
- [x] **OTBR 부팅 완전 자동화** (2026-02-20)
  - Thread 네트워크 + SRP server: reflash 후 수동 작업 없이 부팅만으로 동작
  - systemd 부팅 체인: otbr-agent → otbr-thread-init → otbr-srp-enable
- [ ] zigbee2mqtt 설정 및 동작 확인

### Phase 2: Matter 안정화 + Go 컨트롤러 ◐

- [x] matterjs-server Yocto 레시피 작성 (v0.3.5, npm-shrinkwrap, systemd)
- [x] **matterjs-server WebSocket API 검증** (2026-02-23)
  - commissioning, attribute read, start_listening 모두 chip-tool oracle과 100% 일치
  - 도어센서 실시간 이벤트 수신 확인
- [x] **Go HomeAgent 컨트롤러 v0.3.0** (2026-02-23)
  - Matter WS 클라이언트 (connect, get_nodes, commission_with_code, start_listening)
  - Hub 코디네이터 (DeviceState 관리, 이벤트 브로드캐스트)
  - REST API: GET /api/devices, POST /api/commission, GET /api/events (SSE)
  - RPi5 배포: 단일 바이너리 (aarch64 정적 링크, ~6MB)
- [x] **Lit 프론트엔드** (2026-02-23)
  - 대시보드: 디바이스 카드, 에이전트 메시지바, 실시간 이벤트 로그
  - 페어링 다이얼로그: Setup Code 입력 → Matter commissioning
  - SSE 실시간 업데이트: 도어 열림/닫힘 즉시 반영
  - RPi5 서빙: http://192.168.69.6:8080/
- [ ] A2UI 프로토콜 통합 (surfaceUpdate JSONL)
- [ ] OpenClaw Gateway 연동 (에이전트 채팅)
- [ ] npmsw 오프라인 빌드 환경 구축 (디퍼)
- [ ] zigbee2mqtt 2.8.0 업그레이드 (디퍼)

### Phase 3: AI + 에이전트 + A2UI

- [ ] A2A 프로토콜 구현 (Go SDK)
- [ ] Constitutional AI 판단 프레임워크
- [ ] EdgeAI Runtime (Hailo + ONNX/TFLite)
- [ ] TTS 에이전트 (디바이스 상태 음성 안내)
- [ ] sLLM 온디바이스 튜닝 (Hailo-10H GenAI)
- [ ] 풀패키지 Yocto 이미지 배포

---

## 문서

| 문서 | 내용 |
|------|------|
| [HOWTO.md](HOWTO.md) | 클린 상태에서 동작하는 RPi5까지 재현하는 세팅 가이드 |
| [HARDWARE.md](HARDWARE.md) | RPi5 하드웨어 정보 (네트워크, USB, Thread, 온도) |
| [VERSION.md](VERSION.md) | Yocto/RPi5/Hailo 버전 매트릭스, RCP 정보, Matter 검증 기록 |
| [docs/A2A.md](docs/A2A.md) | A2A 프로토콜, Constitutional AI, 런타임 스택 결정 근거 |
| [docs/A2UI.md](docs/A2UI.md) | A2UI 동적 UI 프로토콜, OpenClaw 참조, 뷰어 아키텍처 |
| [docs/MATTER-VERIFY.md](docs/MATTER-VERIFY.md) | chip-tool(oracle) vs matterjs-server 검증 기록 |
| [docs/MQTT-HA.md](docs/MQTT-HA.md) | Matter/HA 호환 아키텍처, matterjs-server 전환 배경 |
| [docs/TARGET_DEVICE.md](docs/TARGET_DEVICE.md) | 타겟 디바이스 상세 정보 |

---

## 참조 프로젝트

이 프로젝트의 방향에 영향을 준 프로젝트들. 개별 기능보다 **만든 사람의 철학이 아키텍처에 담겨 있는** 것들을 중심으로.

| 프로젝트 | 관계 | 핵심 |
|----------|------|------|
| [OpenClaw](https://github.com/openclaw/openclaw) | A2UI 구현체 | 에이전트 → 선언적 JSON → 뷰어. Canvas에 A2UI v0.8 내장. 멀티플랫폼 |
| [pi-mono](https://github.com/badlogic/pi-mono) | 에이전트 인프라 | coding agent CLI + unified LLM API + TUI/Web UI. TypeScript 모노레포 |
| [be-more-agent](https://github.com/brenpoly/be-more-agent) | RPi5 비서 비교 | Ollama + Whisper + Piper TTS + 얼굴 애니메이션. 빌딩블록 조합형 |
| [A2UI](https://a2ui.org) | UI 프로토콜 | Google의 Agent-to-User Interface 스펙. 선언적 JSON, UI 인젝션 방지 |
| [CopilotKit](https://github.com/CopilotKit/CopilotKit) | 프론트엔드 | AG-UI 프로토콜로 에이전트 연결. A2UI + React 렌더링 |

**HomeAgent와의 차이점**: 위 프로젝트들은 각자의 레이어에서 뛰어나지만, **재현 가능한 프로덕션 빌드 세트** (Yocto 이미지 → SD 카드 → 부팅 → 즉시 동작)를 제공하지는 않는다. HomeAgent는 Zigbee/Matter 허브 기능 + sLLM 튜닝 + 동적 UI를 **하나의 배포 가능한 이미지**로 묶는 것이 목표다.

---

## 라이선스

MIT / Apache 2.0
