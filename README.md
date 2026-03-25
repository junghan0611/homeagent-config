# HomeAgent

**Open-source Matter smart home hub with on-device AI agent.**

RPi5 · RK3576 · Yocto · Android · Go · Matter · LLM Agent · Flutter · Thread

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Vision

**"Data Privacy + On-device AI + Matter Hub"**

HomeAgent is a **self-hosted smart home hub** — no cloud required. It combines Matter device control, real-time event streaming, and an LLM-powered agent, all in a single Go binary. Runs on RPi5 (Yocto Linux) and RK3576 (Android), same codebase.

This is not just a smart home controller. It's a **physical anchor for offline agent collaboration** — where an edge AI guards your space, cooperates with cloud agents when needed, and always keeps your data local.

```
Flutter App (ivi-homescreen / Android APK)
  └── WebView ──▶ Go HomeAgent v0.8 (:8080)
                   ├── REST API (12 endpoints + SSE)
                   ├── LLM Agent (DeepSeek / on-device sLLM)
                   ├── A2UI (server-driven UI, time-based theme)
                   ├── TUI (bubbletea terminal dashboard)
                   ├── Matter WS Client (single ReadLoop)
                   └── Matter Backend (:5580)
                        ├── matterjs-server (current)
                        ├── python-matter-server (Docker) ← current
                        ├── matterjs-server (legacy)
                        ├── BLE commissioning (WiFi + Thread)
                        └── OTBR (Docker container)
```

---

## Platform Support

HomeAgent runs on two platforms from the same codebase. See [docs/PLATFORM-MATRIX.md](docs/PLATFORM-MATRIX.md) for the full comparison.

```
                     Common Layer
  ┌──────────────────────────────────────────────────┐
  │  Flutter APK (WebView Shell)      — same code    │
  │  Go homeagent (:8080)             — same binary  │
  │  Lit UI (ui/dist/)                — same bundle  │
  │  Matter Backend (:5580)           — Docker       │
  │  OTBR (Thread Border Router)      — Docker       │
  │  matter/ (pure Dart)              — same BLE     │
  ├──────────────────────────────────────────────────┤
  │               Platform Divergence                │
  └──────────────────────────────────────────────────┘

  RPi5 (Yocto Linux)              RK3576 (Android 15)
  ─────────────────              ───────────────────
  ivi-homescreen (Wayland)       Flutter APK (WebView)
  docker-compose up -d           docker-android.sh (native Docker)
  /dev/ttyUSB0 (ZBDongle-E)     /dev/ttyS5 (ESP32-H2)
  eth0 backbone                  wlan0 backbone
  Hailo-8 NPU (optional)        —
```

| Platform | Board | OS | Thread RCP | Status |
|----------|-------|----|-----------|--------|
| RPi5 | Raspberry Pi 5 8GB | Yocto scarthgap | ZBDongle-E (USB) | ✅ Production |
| RK3576 | RK3576-EVB | Android 15 | ESP32-H2 (UART) | ✅ Verified |

### Cross-Platform Verification (2026-03-18)

Same codebase, both platforms, same devices — verified end-to-end.

| | Android (RK3576) | RPi5 (Yocto) |
|---|---|---|
| WiFi Plug (BLE→WiFi→CASE) | ✅ | ✅ |
| Thread Door Sensor (BLE→Thread→CASE) | ✅ | ✅ |
| Thread Light Bulb (BLE→Thread→CASE) | ✅ | — |
| On/Off Control + SSE realtime | ✅ | ✅ |
| Contact State + SSE realtime | ✅ | ✅ |
| LLM Agent (cloud) | ✅ | ✅ |
| sLLM on-device (Qwen3-0.6B, 379MB) | ✅ 4s/req | — |
| Flutter Native UI | ✅ | ✅ (desktop) |
| Swagger UI (/docs) | ✅ | ✅ |
| A2A Protocol (/.well-known/agent.json) | ✅ | ✅ |
| Thread auto-start on deploy | ✅ | N/A (systemd) |
| **Power-cycle resilience** | ✅ | ✅ |
| **No internet → local control** | ✅ | ✅ |

### Boot Resilience (2026-03-18)

Power off → power on → everything starts automatically. No human intervention.

```
  Power on
    └── sys.boot_completed=1
         └── homeagent.rc (init service)
              └── start.sh
                   ├── [1] kill Android Thread HAL (stop + 8s kill loop)
                   ├── [2] OTBR start (UART flush + 3 retries)
                   │        └── Thread dataset 3-layer protection:
                   │             1st: otbr-data restore (automatic)
                   │             2nd: dataset-backup.hex (file fallback)
                   │             3rd: new network (last resort + matter-data reset)
                   ├── [3] matterjs-server (:5580, :5581 BLE relay)
                   ├── [4] Go homeagent (:8080)
                   └── [5] APK auto-launch
```

Verified: physical power cycle → Thread leader + 3 devices reconnected in ~80 seconds.

### Test Coverage

```
  Go:      122 tests (hub, matter, otbr, agent, a2a)
  Flutter:  83 tests (api_client, device_card, ble_relay, a2ui_adapter, matter)
  Total:   205 tests, 0 failures
```

### Codebase

```
  Go server       4,286 lines     Go tests         3,295 lines
  Flutter app     3,935 lines     Flutter tests    1,149 lines
  Lit UI          1,567 lines     Scripts          2,780 lines
  Documentation   4,284 lines

  Go binary: 9.5MB (android/arm64, static)
  APK:       51MB  (Flutter + WebView shell)
  OTBR:      7MB   (NDK arm64 cross-build)
```

---

## Key Features

- 🔌 **Matter Hub** — Commission and control Thread + WiFi devices via BLE
- 📡 **Real-time Events** — SSE streaming for instant state updates
- 🤖 **LLM Agent** — Natural language → device control (DeepSeek / on-device sLLM)
- 🧵 **Thread Border Router** — OTBR on both Yocto and Android (NDK cross-build)
- 🏗️ **Reproducible Build** — Yocto image (RPi5) or NDK bundle (RK3576)
- 🔒 **Privacy First** — No cloud dependency, all processing on-device
- 📱 **Cross-platform** — Flutter WebView shell (Yocto + Android), same codebase
- 🖥️ **TUI Dashboard** — Terminal interface for fast feature validation (bubbletea)
- 🌐 **Web UI** — Lit WebComponents, works on any browser

---

## Roadmap & History

> *History without which nothing is reproducible.*

### Phase 1: Yocto + Protocol Verification ✅

The foundation. Prove that Matter works on a real RPi5.

- [x] Yocto scarthgap 5.0 LTS build + RPi5 boot
- [x] OTBR auto-init (Thread leader + SRP server)
- [x] ZBDongle-E Thread RCP firmware flash
- [x] Zigbee2MQTT verification (pre-Matter data collection)
- [x] Matter full flow: BLE → PASE → Thread → CommissioningComplete
- [x] chip-tool vs matterjs-server oracle comparison (100% match)

### Phase 2: Matter + Go Controller ✅ (v0.8)

The core. A working smart home hub.

- [x] matterjs-server WebSocket API
- [x] Go controller v0.8 (Hub, SSE, REST 8 commands, auto Thread/WiFi inject)
- [x] Lit frontend (dashboard, pairing, On/Off, event log, chat panel)
- [x] Multi-device: Thread ×2 + WiFi ×1 simultaneously
- [x] LLM agent chat (Gemini 2.5 Flash, natural language → device control)
- [x] A2UI dynamic rendering (time-based Home Surface + LLM surfaceUpdate)
- [x] `run.sh ha-deploy` one-command RPi5 deployment

### Phase 3: Cross-platform + Thread Independence ✅

Multi-platform. Same hub, different hardware.

- [x] **Flutter cross-platform app** — Linux Desktop ✅, Android APK ✅ (43.7MB)
- [x] **Yocto flutter-engine** — 3.38.3 build success
- [x] **REST API 8 commands** — on/off/level/color/color_temp/thermostat/lock/unlock
- [x] **Go TUI dashboard** — cobra + bubbletea (device view, control, SSE events)
- [x] **RK3576 full stack** — Go + matterjs + APK running independently (no RPi5)
- [x] **Matter BLE commissioning (pure Dart)** — BTP + PASE + TLV + Spake2+ (39 tests)
- [x] **OTBR NDK arm64 build** — ot-br-posix cross-compiled for Android (7MB)
- [x] **Reproducible build script** — `./run.sh otbr-build` (patches auto-applied)
- [x] **Platform Matrix doc** — RPi5 vs RK3576 divergence points documented
- [x] **BLE commissioning on Android** — Flutter BLE relay (bd-3cw)
- [x] **Thread on RK3576** — OTBR + ESP32-H2 + IPv6 policy routing (bd-277.1)
- [x] **A2UI theme invariant** — CSS variable single path, 0 violations (ha-2y3)
- [x] **Cross-platform verification** — WiFi + Thread devices on both RPi5 and RK3576
- [x] **Thread dataset persistence** — 3-layer protection: auto-restore, backup file, new+reset
- [x] **OTBR boot resilience** — UART flush + 3 retries (Android HAL conflict solved)
- [x] **Power-cycle auto-start** — init service, ~80s to full stack, no human intervention
- [x] **One-command deployment** — `./run.sh android deploy` or `install.sh` for field use
- [ ] **Yocto homeagent recipe** — SD flash → boot → works (ha-2ua)

### Phase 4: HA Ecosystem + Flutter-first ← **current**

The platform. Docker-based Matter+OTBR, Go as extension layer, Flutter as the universal client.

**Principle**: Linux (RPi5) first → Android second. Never Android-locked.

- [x] **Docker-based deployment** — RPi5: `docker-compose up -d`, Android: `docker-android.sh start/load/up`
- [x] **python-matter-server 8.1.2** — HA 공식 Matter 컨트롤러, Go 코드 변경 0줄로 호환
- [x] **Android native Docker** — chroot 폐기 → 네이티브 실행. AOSP 3개 패치로 완결
- [x] **Android Docker 컨테이너 실행** — matter-server + OTBR 컨테이너 동작 확인 ✅
- [x] **Swagger UI** — OpenAPI 3.0 spec + /docs endpoint
- [x] **REST API 12 endpoints** — devices, commission, command, chat, home, events, system, thread
- [ ] **Flutter Linux app** — RPi5 ivi-homescreen native UI (not WebView), matterjs WS direct
- [ ] **HA protocol compat** — Flutter app speaks OHF WebSocket API to matterjs-server
- [ ] **HA Kotlin→Dart port** — Core logic (WS subscription, state management) from ha-android
- [ ] **Go extension API** — Custom REST for clients (aliases, sLLM, A2UI, OTBR integration)
- [ ] **Yocto homeagent recipe** — SD flash → boot → works (ha-2ua)

### Phase 5: Agent Intelligence

The mind. AI that understands context.

- [x] **A2A Phase 0+1** — AgentCard + JSON-RPC + Task lifecycle + SSE streaming
- [x] **sLLM benchmark** — Qwen3-0.6B: baseline 42% → LoRA 88% (action 100%)
- [x] **GGUF pipeline** — LoRA merge → f16 → Q4_K_M (379MB, ARM 4s/req)
- [ ] sLLM Go integration — llama-server HTTP → agent.go fallback chain (ha-17d)
- [ ] A2UI native renderer — JSON Surface → Flutter Widget (bd-i6o)
- [ ] OpenClaw integration — TTS/Telegram/chat delegated (ha-3nc)
- [ ] EdgeAI Runtime: Hailo-8 + ONNX/TFLite (ha-3lu)

### Phase 6: Production + Scale

The product. Ship it.

- [ ] RK3588 Yocto port (production target)
- [ ] Hailo-8 M.2 NPU on RPi5 — object detection, presence sensing
- [ ] Zig firmware for custom Thread sensors
- [ ] Client branding APK (bd-2jt)

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
│  Go HomeAgent (single binary, 9.5MB)        │
│  ├── Hub: state, SSE, REST 12 endpoints     │
│  ├── Agent: LLM → action/surfaceUpdate      │
│  ├── Surface: A2UI time-based theme         │
│  ├── Matter: WS client, single ReadLoop     │
│  ├── Config: Thread dataset + WiFi inject   │
│  └── TUI: bubbletea terminal dashboard      │
└─────────────────┬───────────────────────────┘
                  │ WebSocket (:5580)
┌─────────────────┴───────────────────────────┐
│  Matter Backend (Docker)                    │
│  ├── python-matter-server 8.1.2 (current)   │
│  └── matterjs-server (legacy)               │
│  BLE commissioning · Thread · WiFi · Events │
└─────────────────┬───────────────────────────┘
                  │ Spinel HDLC (UART)
┌─────────────────┴───────────────────────────┐
│  Thread Border Router (Docker)               │
│  wpan0 · SRP Server · Border Routing        │
│  RPi5: docker-compose / RK3576: native Docker│
└─────────────────┬───────────────────────────┘
                  │
              ESP32-H2 / ZBDongle-E (Thread RCP)
```

---

## Agent Architecture: Cooperative AI

HomeAgent is not a rule engine. It's an **agent with context, principles, and judgment**.

```
┌─────────────────────────────────────────┐
│         Master Agent (Cloud/PC)         │
│    High-performance reasoning, internet │
└───────────────┬─────────────────────────┘
                │ A2A Protocol (approval-based)
                ▼
┌─────────────────────────────────────────┐
│        HomeAgent (Edge/RPi5/RK3576)     │
│    Offline-first agent guarding space   │
│  • Camera access ✓, direct internet ✗  │
│  • Best effort on limited resources     │
│  • Ask human when uncertain             │
└───────────────┬─────────────────────────┘
                │
         ┌──────┴──────┐
         │ User (Human)│
         │ Final say   │
         └─────────────┘
```

### Constitutional AI — Agent Identity

1. Life and safety come first
2. Respect the dignity of residents
3. When uncertain, ask a human

> *Details: [docs/A2A.md](docs/A2A.md)*

---

## A2UI — Agent-Driven Dynamic Interface

```
❌ Traditional: [Compiled UI] ← waits for input → [reacts]
✅ A2UI:        [Agent] → declarative JSON → [Viewer renders]
```

**[A2UI](https://a2ui.org)** (Agent-to-User Interface): The agent describes UI in declarative JSON; the client renders it. Data, not executable code — preventing UI injection.

> *The UI is just a viewer. The agent decides what to show and how.*
> *Details: [docs/A2UI.md](docs/A2UI.md)*

---

## Runtime Stack

```
RPi5 (Yocto) / RK3576 (Android) — HomeAgent Hub
├── Docker   containerd + dockerd (static binary, both platforms)
│   ├── python-matter-server (Matter protocol engine, Docker container)
│   └── otbr-agent (Thread Border Router, Docker container)
├── Go       HomeAgent (controller, AI, state machine, A2A, Swagger UI)
├── Dart     Flutter Native UI / WebView Shell + BLE commissioning
├── C/C++    llama.cpp (sLLM on-device inference)
└── (none)   Python — not used on the hub (training only on GPU cluster)

Dev environment (NixOS host)
├── Go 1.25  go build / GOOS=linux GOARCH=arm64
├── Flutter  3.38.9 (APK build, Linux desktop)
├── Docker   28.x (image pull/save for offline deploy)
├── NDK r27  ot-br-posix cross-compile (legacy native build)
└── Node 22  matterjs-server development (legacy)
```

---

## Quick Start

### Option A: Deploy to RPi5

```bash
# Flash Yocto image
bmaptool copy core-image-weston-raspberrypi5.wic.bz2 /dev/sdX

# SSH in and start
ssh root@<rpi5-ip>
OPENROUTER_API_KEY=sk-... /opt/homeagent/homeagent
```

### Option B: Flutter Development (Linux Desktop)

```bash
./run.sh flutter-server   # Go server (no Matter)
./run.sh flutter-run       # Flutter hot reload
```

### Option C: Build Everything

```bash
./run.sh go-build          # Go arm64 binary
./run.sh apk-build         # Flutter Android APK
./run.sh otbr-build        # OTBR arm64 (NDK)
./run.sh bundle            # Full bundle (Go+Node+matterjs+UI)
```

### Option D: Deploy to Android Board — Docker (RK3576)

```bash
# PC (one command — push binaries + images + scripts)
cd android-docker && bash setup-docker.sh

# Board (adb shell, root)
/data/local/tmp/docker-android.sh start   # Docker Engine (native, no chroot)
/data/local/tmp/docker-android.sh load    # Load images (offline, no pull)
/data/local/tmp/docker-android.sh up      # matter-server + OTBR containers
/data/local/tmp/docker-android.sh status  # Verify
```

### Option E: Deploy to Android Board — Native (legacy)

```bash
./run.sh android deploy    # Build + push + start (one command)
./run.sh android status    # Verify: processes, ports, Thread state
```

---

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/devices` | GET | List all devices with state |
| `/api/devices/:node_id` | GET | Single device detail |
| `/api/commission` | POST | Pair new device `{"code": "0000-000-0000"}` |
| `/api/commission-on-network` | POST | On-network commissioning |
| `/api/devices/command` | POST | Control: on/off/level/color/color_temp/thermostat/lock/unlock |
| `/api/chat` | POST | LLM agent `{"message": "turn off the plug"}` |
| `/api/home` | GET | A2UI Home Surface |
| `/api/events` | GET | SSE stream |
| `/api/thread/status` | GET | Thread network status |
| `/api/system` | GET | System info (versions, uptime, Thread) |
| `/api/wifi-credentials` | POST | WiFi credential injection |
| `/api/wifi-info` | GET | Current WiFi info |
| `/healthz` | GET | Health check |
| `/docs` | GET | Swagger UI |

> *Full spec: [docs/API.md](docs/API.md)*

---

## Demo (2026-03-18)

RK3576 Android board, power-cycle resilient. 3 Matter devices:

| Device | Protocol | Features |
|--------|----------|----------|
| Tuya Door Sensor | Matter over Thread | Real-time open/close events via SSE |
| Tapo Smart Plug | Matter over WiFi | On/Off toggle control |
| Matter Light Bulb | Matter over Thread | On/Off + Brightness + Color temp |

**No internet required** for device control. LLM chat: cloud (DeepSeek) or on-device (Qwen3-0.6B, 4s/req).

```
Power off → Power on → 80 seconds → All devices reconnected
No adb, no SSH, no human — just plug in power.
```

LLM Agent:
```
User: "플러그 꺼줘" → Agent: {action: "off", node_id: 8} → Plug turns off
User: "문 열려있어?" → Agent: "Node 7의 문이 열려있습니다."
```

---

## Project Structure

```
homeagent-config/
├── go/                    # Go controller
│   ├── cmd/homeagent/     # CLI: serve, tui, devices, control
│   └── internal/          # hub, matter, agent, config
├── flutter/               # Flutter WebView shell
│   ├── lib/main.dart      # Platform-aware shell
│   ├── lib/matter/        # Pure Dart: BTP, PASE, TLV, Spake2+
│   └── test/matter/       # 39 unit tests
├── ui/                    # Lit frontend (Vite)
├── android-docker/        # Android Docker deploy (Phase 4)
│   ├── docker-android.sh  # Native Docker Engine management
│   ├── docker-compose.yml # Android-specific compose (no dbus)
│   └── setup-docker.sh    # PC → board one-command setup
├── docker-compose.yml     # RPi5 Docker compose
├── scripts/
│   ├── android-deploy.sh  # Android 네이티브 배포 (legacy)
│   ├── build-otbr.sh      # OTBR NDK arm64 build (reproducible)
│   └── bundle-backend.sh  # Full arm64 bundle
├── patches/               # Third-party source patches
│   └── ot-br-posix/       # NDK build fixes (auto-applied)
├── yocto/                 # Yocto build config
│   └── meta-homeagent/    # Recipes: homeagent, matterjs, OTBR
├── docs/
│   ├── PLATFORM-MATRIX.md # RPi5 vs RK3576 stack comparison
│   ├── ARCHITECTURE.md    # ADR — why Go, Flutter, matterjs, Docker
│   ├── THREAD.md          # Thread Border Router guide
│   ├── API.md             # REST API spec (12 endpoints)
│   ├── FLUTTER.md         # Flutter shell architecture
│   ├── A2UI.md            # Agent-driven UI strategy
│   └── A2A.md             # Agent protocol, Constitutional AI
└── aliases.json           # Device name/room mapping
```

---

## Build Commands

| Target | Command | Output |
|--------|---------|--------|
| Go arm64 | `./run.sh go-build` | `go/bin/homeagent` (9.5MB) |
| Flutter APK | `./run.sh apk-build` | `app-release.apk` (51MB) |
| OTBR arm64 | `./run.sh otbr-build` | `dist/otbr-arm64/` (7MB) |
| UI | `cd ui && npm run build` | `ui/dist/` (40KB) |
| Full bundle | `./run.sh bundle` | `dist/homeagent-bundle-arm64/` |
| RPi5 deploy | `./run.sh ha-deploy <IP>` | Build + SCP + start |
| Android deploy | `./run.sh android deploy` | Build + adb push + start |
| Android Thread | `./run.sh android thread-start` | OTBR + Thread network |

---

## Documentation

| Doc | Content |
|-----|---------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture Decision Records — why Go, Flutter, matterjs |
| [docs/MATTER.md](docs/MATTER.md) | Matter SDK strategy — why matter.js, runtime analysis, roadmap |
| [docs/BUILD.md](docs/BUILD.md) | Build guide — environment, resources, two-machine workflow |
| [docs/PLATFORM-MATRIX.md](docs/PLATFORM-MATRIX.md) | RPi5 vs RK3576 stack comparison |
| [docs/THREAD.md](docs/THREAD.md) | Thread Border Router (Yocto + Android NDK) |
| [docs/API.md](docs/API.md) | REST API spec (8 commands, OHF compatible) |
| [docs/FLUTTER.md](docs/FLUTTER.md) | Flutter shell architecture + NixOS build |
| [docs/A2UI.md](docs/A2UI.md) | Agent-to-User Interface strategy |
| [docs/A2A.md](docs/A2A.md) | Agent protocol, Constitutional AI |
| [android-docker/README.md](android-docker/README.md) | Android Docker 배포 가이드 + 핵심 해법 |
| [HOWTO.md](HOWTO.md) | Full setup guide (clean state → working hub) |
| [VERSION.md](VERSION.md) | Version matrix (Yocto/Flutter/Node/NDK/Docker) |

---

## Hardware

| Platform | Board | Thread RCP | NPU |
|----------|-------|-----------|-----|
| RPi5 | Raspberry Pi 5 (8GB) | ZBDongle-E (USB) | Hailo-8 M.2 (준비 중) |
| RK3576 | RK3576-EVB | ESP32-H2 (UART) | — |

### Hailo-8 NPU (RPi5)

Hailo-8 M.2 AI 가속기를 RPi5에 장착하여 on-device object detection, presence sensing 등 EdgeAI 추론에 활용 예정.
Hailo-8을 선택한 이유: Yocto meta-hailo 레이어가 활발히 유지보수되고 있고, RPi5 M.2 HAT+에 바로 장착 가능.

관련 3rd-party 리포 (`~/repos/3rd/homeagent-config/`):

| 리포 | 설명 |
|------|------|
| `meta-hailo` | Yocto Hailo BSP 레이어 (HailoRT, TAPPAS) |
| `meta-hailo-soc` | Hailo SoC 지원 레이어 |
| `hailo-apps` | Hailo 샘플 앱 (detection, segmentation) |
| `meta-flutter` | Yocto Flutter engine 레이어 |
| `meta-flutter-sony` | Sony Flutter embedded 레이어 |
| `meta-raspberrypi` | RPi Yocto BSP 레이어 |

---

## Reference Projects

Projects whose **philosophy shaped the architecture**, not just features.

| Project | Relation | Key Insight |
|---------|----------|-------------|
| [A2UI](https://a2ui.org) | UI protocol | Declarative JSON, no code injection |
| [OpenClaw](https://github.com/openclaw/openclaw) | A2UI impl | Agent → JSON → Viewer. Multi-platform |
| [pi-mono](https://github.com/badlogic/pi-mono) | Agent infra | Coding agent CLI + unified LLM API |
| [CopilotKit](https://github.com/CopilotKit/CopilotKit) | Frontend | AG-UI protocol for agent UIs |

**HomeAgent's difference**: These projects excel at their layers, but none provides a **reproducible production build set** — flash an SD card, boot, and it works. HomeAgent unifies Matter hub + sLLM + dynamic UI into **one deployable image**.

---

## Philosophy

- **Being to Being** — AI as a collaborator, not a tool
- **Privacy by default** — No cloud, no data leaving your home
- **Reproducible** — Same source → same build → same result
- **Agent-first UI** — The agent decides what to show ([A2UI](https://a2ui.org))
- **Same role, same base** — Platform divergence is explicit, minimal, documented

---

## License

MIT
