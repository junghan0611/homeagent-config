# HomeAgent

**Open-source Matter smart home platform with on-device AI agent.**

RPi5 · Yocto · Go · Matter · LLM Agent · Flutter · Lit Frontend

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Vision

**"Data Privacy + On-device AI + Matter Hub"**

HomeAgent is a **self-hosted smart home hub** that runs entirely on a Raspberry Pi 5. No cloud required. It combines Matter device control, real-time event streaming, and an LLM-powered agent — all in a single Go binary.

This is not just a smart home controller. It's a **physical anchor for offline agent collaboration** — where an edge AI guards your space, cooperates with cloud agents when needed, and always keeps your data local.

```
Flutter App (ivi-homescreen / Android APK)
  └── WebView ──▶ Go HomeAgent v0.8 (:8080)
                   ├── REST API (devices, commission, command, chat, home)
                   ├── LLM Agent (OpenRouter / on-device sLLM)
                   ├── A2UI (server-driven UI, time-based theme)
                   ├── Matter WS Client (single ReadLoop)
                   └── Lit Frontend (dashboard, pairing, chat, A2UI renderer)
                            │
                   matterjs-server (:5580)
                   ├── Thread devices (OTBR)
                   └── WiFi devices
```

### Why?

- **Privacy**: 카메라, 센서 데이터가 집 밖으로 나가지 않는다
- **Cooperation**: 인간과 에이전트의 상호협력 베이스 구축
- **Reproducibility**: SD 카드 플래싱 → 부팅 → 즉시 동작하는 재현 가능한 이미지

> *"구현은 언제나 쉽습니다. 이제는 한번에 다 만들어 낼 수 있는 시대입니다.
> 왜 하는가? 어떻게 하는가? 무엇을 위해서 하는가?를 되새기는 것입니다."*

---

## Key Features

- 🔌 **Matter Hub** — Commission and control Thread + WiFi devices via BLE
- 📡 **Real-time Events** — SSE streaming for instant state updates
- 🤖 **LLM Agent** — Natural language → device control (Gemini Flash, ~$0.02/day)
- 🏗️ **Yocto Image** — Reproducible: flash SD card → boot → works
- 🔒 **Privacy First** — No cloud dependency, on-device processing
- 📱 **Cross-platform App** — Flutter WebView shell (Yocto + Android), same codebase
- 🌐 **Web UI** — Lit WebComponents, works on any browser

---

## Agent Architecture: Cooperative AI

HomeAgent는 단순 조건문 엔진이 아니다. **컨텍스트를 이해하고, 원칙에 따라 판단하는 에이전트**다.

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
│  • 카메라 접근 O, 인터넷 직접 접근 X                       │
│  • 제한된 자원에서 Best Effort                             │
│  • 확실하지 않으면 사람에게 묻기                           │
└─────────────────────────┬───────────────────────────────────┘
                          │
              ┌───────────┴───────────┐
              │   User (Human)        │
              │ 최종 승인권, 협력자    │
              └───────────────────────┘
```

### Constitutional AI — 에이전트의 정체성

1. 생명과 안전이 최우선
2. 거주자의 존엄성 존중
3. 확실하지 않으면 사람에게 묻기

> *자세한 내용: [docs/A2A.md](docs/A2A.md)*

---

## A2UI — 에이전트가 그리는 동적 인터페이스

```
❌ 기존: [컴파일된 UI] ← 사용자 입력 대기 → [반응]
✅ A2UI: [에이전트] → 선언적 JSON → [뷰어가 렌더링]
```

**[A2UI](https://a2ui.org)** (Agent-to-User Interface): 에이전트가 선언적 JSON으로 UI를 기술하면, 클라이언트가 렌더링하는 프로토콜. 실행 코드가 아닌 데이터이므로 UI 인젝션 방지.

- 에이전트가 상황에 맞게 동적으로 시각화 (surfaceUpdate)
- 동일 프로토콜로 RPi5 디스플레이, 웹, 모바일 동시 지원
- 빛, 형태, 움직임으로 공간과 소통하는 디지털 아트

> *UI는 뷰어일 뿐. 에이전트가 무엇을 어떻게 보여줄지 결정한다.*
> *자세한 내용: [docs/A2UI.md](docs/A2UI.md)*

---

## Runtime Stack

```
RPi5 (Yocto scarthgap) — HomeAgent 허브
├── Go       HomeAgent (컨트롤러, AI 판단, 상태머신, A2A)
├── Node.js  matterjs-server (Matter 프로토콜 엔진)
├── Dart     Flutter WebView Shell (ivi-homescreen on Weston)
├── C/C++    mosquitto, otbr-agent, avahi-daemon (시스템 인프라)
└── (없음)   Python — 허브에서는 사용하지 않음

소형 디바이스 (Zig 펌웨어)
└── Zig      센서/액추에이터 펌웨어 (Thread/Matter 엔드포인트)
```

**언어별 역할:**
- **Go**: I/O-bound Matter/Zigbee에 goroutine+channel 적합. Thread 250kbps가 물리적 병목이므로 GC 무의미
- **Node.js**: HA 2026.2에서 C++ SDK → matter.js 전환. C++ 크래시 문제로 순수 JS가 오히려 안정적
- **Flutter/Dart**: 크로스플랫폼 앱 셸. Yocto(ivi-homescreen) + Android(APK) 동일 코드베이스
- **Zig**: 런타임 없음 + C ABI 호환 → MCU 펌웨어 최적

---

## Demo (2026-02-23)

**3 devices managed simultaneously**, all from a web browser:

| Device | Protocol | Features |
|--------|----------|----------|
| Tuya Door Sensor ×2 | Matter over Thread | Real-time open/close events |
| Tapo Smart Plug ×1 | Matter over WiFi | On/Off toggle control |

**LLM Agent chat** — natural language device control:
```
User: "플러그 꺼줘" (Turn off the plug)
Agent: → Executes {action: "off", node_id: 8} → Plug turns off

User: "문 열려있어?" (Is the door open?)
Agent: "Node 7의 문이 열려있습니다." (Node 7's door is open.)
```

---

## Architecture

```
┌─────────────────────────────────────────────┐
│  Flutter WebView Shell (ivi-homescreen/APK) │
│  Same codebase: Yocto + Android             │
└─────────────────┬───────────────────────────┘
                  │ WebView → localhost:8080
┌─────────────────┴───────────────────────────┐
│  Lit Frontend (Vite build, ~40KB)           │
│  Dashboard · Device Cards · Chat Panel      │
│  Commission Dialog · A2UI Renderer          │
└─────────────────┬───────────────────────────┘
                  │ REST + SSE
┌─────────────────┴───────────────────────────┐
│  Go HomeAgent (single binary, ~7MB)         │
│  ├── Hub: state management, SSE broadcast   │
│  ├── Agent: LLM → action extraction         │
│  ├── Surface: A2UI time-based theme         │
│  ├── Matter: WS client, single ReadLoop     │
│  └── Config: Thread dataset + WiFi inject   │
└─────────────────┬───────────────────────────┘
                  │ WebSocket
┌─────────────────┴───────────────────────────┐
│  matterjs-server (matter.js, Node.js)       │
│  BLE commissioning · Thread · WiFi · Events │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────┴───────────────────────────┐
│  System (Yocto Linux, RPi5)                 │
│  OTBR · mosquitto · avahi · Kernel 6.6 LTS  │
└─────────────────────────────────────────────┘
```

---

## Quick Start

### Option A: Deploy to RPi5 (pre-built Yocto image)

```bash
# Flash Yocto image
bmaptool copy core-image-weston-raspberrypi5.wic.bz2 /dev/sdX

# SSH in and start HomeAgent
ssh root@<rpi5-ip>
OPENROUTER_API_KEY=sk-... \
HOMEAGENT_WIFI_SSID="YourWiFi" \
HOMEAGENT_WIFI_PASSWORD="password" \
HOMEAGENT_UI_DIR=/opt/homeagent/ui \
/opt/homeagent/homeagent
```

### Option B: Flutter Development (Linux Desktop)

```bash
# 터미널 1 — Go 서버 (Matter 없이 HTTP만)
./run.sh flutter-server

# 터미널 2 — Flutter 앱 (hot reload)
./run.sh flutter-run

# 또는 빌드 후 실행
./run.sh flutter-build
./run.sh flutter-exec
```

Linux Desktop에서는 **ShellNative** (Flutter 네이티브 위젯)로 Go API를 직접 호출합니다.
Android/Yocto에서는 **ShellWebView** (WebView → A2UI + Lit UI)로 렌더링합니다.

### Option C: Cross-compile + Deploy to RPi5

```bash
# Go binary
./run.sh go-build

# UI
cd ui && npm install && npx vite build

# Deploy
./run.sh go-deploy

# 또는 전체 번들 (Go + Node.js + matterjs + UI)
./run.sh bundle
```

---

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/devices` | GET | List all devices with current state |
| `/api/commission` | POST | Pair new device `{"code": "0000-000-0000"}` |
| `/api/devices/command` | POST | Control device `{"node_id": 8, "command": "on"}` |
| `/api/chat` | POST | LLM agent `{"message": "turn off the plug"}` |
| `/api/home` | GET | A2UI Home Surface (time-based theme + device status) |
| `/api/events` | GET | SSE stream (real-time state changes) |
| `/healthz` | GET | Health check |

---

## Roadmap

### Phase 1: Yocto + Protocol Verification ✅
- Yocto build (scarthgap 5.0 LTS) + RPi5 boot
- OTBR auto-init (Thread leader + SRP server)
- Matter full flow: BLE → PASE → Thread → CommissioningComplete

### Phase 2: Matter + Go Controller ✅ (v0.8)
- [x] matterjs-server WebSocket API (100% match with chip-tool oracle)
- [x] Go controller v0.8 (Hub, SSE, REST, auto Thread/WiFi inject, auto-reconnect)
- [x] Lit frontend (dashboard, pairing, On/Off toggle, event log, chat panel)
- [x] Multi-device: Thread ×2 + WiFi ×1 simultaneously
- [x] LLM agent chat (Gemini 2.5 Flash, natural language → device control)
- [x] A2UI dynamic rendering (time-based Home Surface + LLM surfaceUpdate)
- [x] `run.sh ha-deploy` one-command build + deploy

### Phase 3: Agent Intelligence + Cross-platform ← **current**
- [ ] **Flutter cross-platform app** — ivi-homescreen(Yocto) + APK(Android), WebView shell (ha-1uk)
- [ ] **A2A protocol + Constitutional AI** — agent identity & cooperation (ha-2h5)
- [ ] **OpenClaw integration** — TTS/Telegram/chat bots delegated to Claw ecosystem (ha-3nc)
- [ ] **Yocto image: homeagent recipe** — SD flash → boot → works (ha-2ua)
- [ ] On-device sLLM fine-tuning pipeline (ha-17d)
- [ ] EdgeAI Runtime: Hailo + ONNX/TFLite (ha-3lu)

### Phase 4: Production + Scale
- [ ] RK3588 Yocto port (production target)
- [ ] Hailo-8 M.2 NPU support
- [ ] Zig firmware for custom Thread sensors

---

## Project Structure

```
homeagent-config/
├── go/                    # Go controller (homeagent binary)
│   ├── cmd/homeagent/     # Entry point
│   ├── internal/hub/      # Hub coordinator (state, SSE, REST)
│   ├── internal/matter/   # matterjs-server WS client
│   └── internal/agent/    # LLM agent (OpenRouter)
├── flutter/               # Flutter WebView shell (Android + Yocto)
│   ├── lib/main.dart      # WebView → Go server UI
│   └── android/           # Android APK target
├── ui/                    # Lit frontend (Vite)
│   └── src/               # app, device-card, chat-panel, a2ui-renderer
├── yocto/                 # Yocto build
│   ├── meta-homeagent/    # Custom recipes (matterjs-server, homeagent-app)
│   └── sources/           # Layer symlinks (meta-flutter, meta-clang, ...)
├── docs/                  # Architecture docs
│   ├── A2A.md             # Agent protocol, Constitutional AI
│   ├── A2UI.md            # Agent-to-User Interface strategy
│   └── MATTER-VERIFY.md   # chip-tool vs matterjs-server comparison
└── matter/                # chip-tool binaries
```

---

## Development Strategy

```
1. System Infra     Zigbee/MQTT/OTBR로 실제 디바이스 검증 ✅
        ↓
2. Matter 검증      chip-tool → matterjs-server로 Matter 디바이스 연동 ✅
        ↓
3. Go Controller    검증된 프로토콜 위에 컨트롤러 + LLM 에이전트 ✅
        ↓
4. Cross-platform   Flutter WebView Shell (Yocto + Android) ← current
        ↓
5. Agent Layer      A2A 프로토콜, Constitutional AI, sLLM
```

> *하드웨어 검증에 시간 쓰지 않는다. 검증된 오픈소스로 데이터 확보 후 코어 구현.*

---

## Hardware

| Component | Spec |
|-----------|------|
| Main Board | Raspberry Pi 5 (8GB recommended) |
| Thread RCP | ZBDongle-E (USB3 blue port, OTBR) |
| NPU (optional) | Hailo AI HAT+ series |
| Power | 5V/5A USB-C (USB dongle stability requires adequate power) |

---

## Documentation

| Doc | Content |
|-----|---------|
| [HOWTO.md](HOWTO.md) | Full setup guide (clean state → working RPi5) |
| [VERSION.md](VERSION.md) | Yocto/RPi5/Hailo version matrix |
| [docs/A2A.md](docs/A2A.md) | Agent protocol, Constitutional AI |
| [docs/A2UI.md](docs/A2UI.md) | Dynamic UI strategy, LLM → surfaceUpdate |
| [docs/MATTER-VERIFY.md](docs/MATTER-VERIFY.md) | Matter verification (chip-tool oracle vs matterjs-server) |

---

## Reference Projects

이 프로젝트의 방향에 영향을 준 프로젝트들. 개별 기능보다 **만든 사람의 철학이 아키텍처에 담겨 있는** 것들을 중심으로.

| Project | Relation | Key Insight |
|---------|----------|-------------|
| [A2UI](https://a2ui.org) | UI protocol | Google's Agent-to-User Interface. Declarative JSON, no code injection |
| [OpenClaw](https://github.com/openclaw/openclaw) | A2UI implementation | Agent → JSON → Viewer. Multi-platform canvas with A2UI v0.8 |
| [pi-mono](https://github.com/badlogic/pi-mono) | Agent infra | Coding agent CLI + unified LLM API. TypeScript monorepo |
| [CopilotKit](https://github.com/CopilotKit/CopilotKit) | Frontend | AG-UI protocol for agent connection. A2UI + React rendering |

**HomeAgent의 차이점**: 위 프로젝트들은 각자의 레이어에서 뛰어나지만, **재현 가능한 프로덕션 빌드 세트** (Yocto 이미지 → SD 카드 → 부팅 → 즉시 동작)를 제공하지는 않는다. HomeAgent는 Matter 허브 + sLLM + 동적 UI를 **하나의 배포 가능한 이미지**로 묶는 것이 목표다.

---

## Philosophy

- **Being to Being** — AI as a collaborator, not a tool
- **Privacy by default** — No cloud, no data leaving your home
- **Reproducible** — Yocto image → SD card → boot → works
- **Agent-first UI** — The agent decides what to show ([A2UI](https://a2ui.org))
- **Focus + Delegate** — HomeAgent owns Matter + AI core; external channels delegated to [OpenClaw](https://github.com/openclaw/openclaw)

---

## License

MIT
