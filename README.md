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
                   ├── REST API (8 device commands + commission + chat + SSE)
                   ├── LLM Agent (OpenRouter / on-device sLLM)
                   ├── A2UI (server-driven UI, time-based theme)
                   ├── TUI (bubbletea terminal dashboard)
                   ├── Matter WS Client (single ReadLoop)
                   └── matterjs-server (:5580)
                        ├── BLE commissioning (WiFi + Thread)
                        └── OTBR integration (Thread Border Router)
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
  │  matterjs-server (:5580)          — same Node.js │
  │  matter/ (pure Dart)              — same BLE     │
  ├──────────────────────────────────────────────────┤
  │               Platform Divergence                │
  └──────────────────────────────────────────────────┘

  RPi5 (Yocto Linux)              RK3576 (Android 15)
  ─────────────────              ───────────────────
  ivi-homescreen (Wayland)       Flutter APK (WebView)
  systemd services               shell scripts
  otbr-agent (bitbake)           otbr-agent (NDK build)
  avahi mDNS                     OT core mDNS (built-in)
  /dev/ttyUSB0 (ZBDongle-E)     /dev/ttyS5 (ESP32-H2)
  eth0 backbone                  wlan0 backbone
```

| Platform | Board | OS | Thread RCP | Status |
|----------|-------|----|-----------|--------|
| RPi5 | Raspberry Pi 5 8GB | Yocto scarthgap | ZBDongle-E (USB) | ✅ Production |
| RK3576 | RK3576-EVB | Android 15 | ESP32-H2 (UART) | ✅ Verified |

### Cross-Platform Verification (2026-03-16)

Same codebase, both platforms, same devices — verified end-to-end.

| | Android (RK3576) | RPi5 (Yocto) |
|---|---|---|
| WiFi Plug (BLE→WiFi→CASE) | ✅ | ✅ |
| Thread Door Sensor (BLE→Thread→CASE) | ✅ | ✅ |
| On/Off Control + SSE realtime | ✅ | ✅ |
| Contact State + SSE realtime | ✅ | ✅ |
| LLM Agent (cloud) | ✅ | ✅ |
| sLLM on-device (Qwen3-0.6B, 379MB) | ✅ 4s/req | — |
| Flutter Native UI | ✅ | ✅ (desktop) |
| Swagger UI (/docs) | ✅ | ✅ |
| A2A Protocol (/.well-known/agent.json) | ✅ | ✅ |
| Thread auto-start on deploy | ✅ | N/A (systemd) |

### Test Coverage

```
  Go:      85 tests (hub 48, matter 11, otbr 9, a2a 6, config 0)
  Flutter: 67 tests (api_client 24, device_card 15, widget 2, ble_relay 26)
  Total:   152 tests, 0 failures
```

### Codebase Sharing — 96% Common

```
  Shared (96%)                    Platform-specific (4%)
  ────────────────────            ────────────────────
  Go server      4,900+ lines    Flutter Android   804 lines
  Go tests       2,000+ lines      (BLE relay + WebView)
  Lit UI         1,418 lines     Flutter Linux     201 lines
  matterjs WS      766 lines       (native widgets)

  Go server:  0 lines of platform-specific code
  Lit UI:     0 lines of platform-specific code
```

---

## Key Features

- 🔌 **Matter Hub** — Commission and control Thread + WiFi devices via BLE
- 📡 **Real-time Events** — SSE streaming for instant state updates
- 🤖 **LLM Agent** — Natural language → device control (Gemini Flash, ~$0.02/day)
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

### Phase 3: Cross-platform + Thread Independence ← **current**

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
- [ ] **Yocto homeagent recipe** — SD flash → boot → works (ha-2ua)

### Phase 4: Agent Intelligence ← **current**

The mind. AI that understands context.

- [x] **A2A Phase 0+1** — AgentCard + JSON-RPC + Task lifecycle + SSE streaming
- [x] **sLLM benchmark** — Qwen3-0.6B: baseline 42% → LoRA 88% (action 100%)
- [x] **GGUF pipeline** — LoRA merge → f16 → Q4_K_M (379MB, ARM 4s/req)
- [x] **Swagger UI** — OpenAPI 3.0 spec + /docs endpoint
- [ ] sLLM Go integration — llama-server HTTP → agent.go fallback chain (ha-17d)
- [ ] A2UI native renderer — JSON Surface → Flutter Widget (bd-i6o)
- [ ] OpenClaw integration — TTS/Telegram/chat delegated (ha-3nc)
- [ ] EdgeAI Runtime: Hailo + ONNX/TFLite (ha-3lu)

### Phase 5: Production + Scale

The product. Ship it.

- [ ] RK3588 Yocto port (production target)
- [ ] Hailo-8 M.2 NPU support
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
│  Go HomeAgent (single binary, ~7MB)         │
│  ├── Hub: state, SSE, REST 8 commands       │
│  ├── Agent: LLM → action/surfaceUpdate      │
│  ├── Surface: A2UI time-based theme         │
│  ├── Matter: WS client, single ReadLoop     │
│  ├── Config: Thread dataset + WiFi inject   │
│  └── TUI: bubbletea terminal dashboard      │
└─────────────────┬───────────────────────────┘
                  │ WebSocket
┌─────────────────┴───────────────────────────┐
│  matterjs-server (matter.js, Node.js)       │
│  BLE commissioning · Thread · WiFi · Events │
└─────────────────┬───────────────────────────┘
                  │ Spinel HDLC (UART)
┌─────────────────┴───────────────────────────┐
│  Thread Border Router (otbr-agent)          │
│  wpan0 · SRP Server · Border Routing        │
│  RPi5: Yocto bitbake / RK3576: NDK build   │
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
├── Go       HomeAgent (controller, AI, state machine, A2A, Swagger UI)
├── Node.js  matterjs-server (Matter protocol engine)
├── Dart     Flutter Native UI / WebView Shell + BLE commissioning
├── C/C++    otbr-agent (Thread Border Router) + llama.cpp (sLLM)
└── (none)   Python — not used on the hub (training only on GPU cluster)

Dev environment (NixOS host)
├── Go 1.25  go build / GOOS=linux GOARCH=arm64
├── Flutter  3.38.9 (APK build, Linux desktop)
├── NDK r27  ot-br-posix cross-compile
└── Node 22  matterjs-server development
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

### Option D: Deploy to Android Board (RK3576/RK3588/etc.)

```bash
./run.sh android deploy    # Build + push + start (one command)
# or step by step:
./run.sh apk-build         # Build APK
./run.sh otbr-build        # Build OTBR (NDK arm64)
./run.sh android start     # Start matterjs + Go
./run.sh android thread-start  # Start OTBR + Thread
```

---

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/devices` | GET | List all devices with state |
| `/api/devices/:node_id` | GET | Single device detail |
| `/api/commission` | POST | Pair new device `{"code": "0000-000-0000"}` |
| `/api/devices/command` | POST | Control: on/off/set_level/set_color/set_color_temp/set_thermostat/lock/unlock |
| `/api/chat` | POST | LLM agent `{"message": "turn off the plug"}` |
| `/api/home` | GET | A2UI Home Surface |
| `/api/events` | GET | SSE stream |
| `/healthz` | GET | Health check |

> *Full spec: [docs/API.md](docs/API.md)*

---

## Demo (2026-02-23)

3 devices managed simultaneously:

| Device | Protocol | Features |
|--------|----------|----------|
| Tuya Door Sensor ×2 | Matter over Thread | Real-time open/close events |
| Tapo Smart Plug ×1 | Matter over WiFi | On/Off toggle control |

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
├── scripts/
│   ├── build-otbr.sh      # OTBR NDK arm64 build (reproducible)
│   ├── bundle-backend.sh  # Full arm64 bundle
│   └── rk3576-thread.sh   # Thread start/stop on Android
├── patches/               # Third-party source patches
│   └── ot-br-posix/       # NDK build fixes (auto-applied)
├── yocto/                 # Yocto build config
│   └── meta-homeagent/    # Recipes: homeagent, matterjs, OTBR
├── docs/
│   ├── PLATFORM-MATRIX.md # RPi5 vs RK3576 stack comparison
│   ├── THREAD.md          # Thread Border Router guide
│   ├── API.md             # REST API spec
│   ├── FLUTTER.md         # Flutter shell architecture
│   ├── A2UI.md            # Agent-driven UI strategy
│   └── A2A.md             # Agent protocol, Constitutional AI
└── aliases.json           # Device name/room mapping
```

---

## Build Commands

| Target | Command | Output |
|--------|---------|--------|
| Go arm64 | `./run.sh go-build` | `go/bin/homeagent` (8.5MB) |
| Flutter APK | `./run.sh apk-build` | `app-release.apk` (44MB) |
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
| [docs/PLATFORM-MATRIX.md](docs/PLATFORM-MATRIX.md) | RPi5 vs RK3576 stack comparison |
| [docs/THREAD.md](docs/THREAD.md) | Thread Border Router (Yocto + Android NDK) |
| [docs/API.md](docs/API.md) | REST API spec (8 commands, OHF compatible) |
| [docs/FLUTTER.md](docs/FLUTTER.md) | Flutter shell architecture + NixOS build |
| [docs/A2UI.md](docs/A2UI.md) | Agent-to-User Interface strategy |
| [docs/A2A.md](docs/A2A.md) | Agent protocol, Constitutional AI |
| [HOWTO.md](HOWTO.md) | Full setup guide (clean state → working hub) |
| [VERSION.md](VERSION.md) | Version matrix (Yocto/Flutter/Node/NDK) |

---

## Hardware

| Platform | Board | Thread RCP | Optional |
|----------|-------|-----------|----------|
| RPi5 | Raspberry Pi 5 (8GB) | ZBDongle-E (USB) | Hailo AI HAT+ |
| RK3576 | RK3576-EVB | ESP32-H2 (UART) | — |

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
