# HomeAgent

**Open-source Matter smart home hub with on-device AI agent.**

RPi5 · RK3576 · Yocto · Android · Go · Matter · LLM Agent · Flutter · Thread

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Vision — 힣봇미니: Physical AI Agent

**"Data Privacy + On-device AI + Matter Hub + Agent Collaboration"**

HomeAgent is a **self-hosted smart home hub** — no cloud required. It combines Matter device control, Hailo-8 NPU vision, on-device sLLM, and an A2A-protocol agent, all on a single RPi5 board.

This is not just a smart home controller. It's **힣봇미니 (GLGbot Mini)** — a Physical AI agent that gives cloud-bound agents eyes, hands, and a local brain:

- **Eyes**: USB camera + Hailo-8 NPU (YOLOv8s, ~21 FPS real-time detection)
- **Hands**: Matter protocol for lights, plugs, sensors, locks
- **Brain**: On-device sLLM (Qwen2.5-0.5B Q4_K_M, offline-capable)
- **Voice**: A2A protocol — cloud agents can query, subscribe to events, and even repair 힣봇미니's config remotely

> *네트워크 없이도 나를 보좌하는 안전한 분신.*
> *클라우드 분신들에게 물리세계를 열어주는 현장 친구.*

```
Flutter App (ivi-homescreen / Android APK)
  └── WebView ──▶ Go HomeAgent v0.8 (:8080)
                   ├── REST API (18 endpoints + SSE)
                   ├── A2A Protocol (JSON-RPC, 7 skills)
                   ├── LLM Agent (cloud fallback ↔ on-device sLLM)
                   ├── Event Subscribe (webhook outbound push)
                   ├── Config API (remote repair interface)
                   ├── Space Summary (interpreted state, not raw)
                   ├── A2UI (server-driven UI, time-based theme)
                   ├── TUI (bubbletea terminal dashboard)
                   ├── Matter WS Client (single ReadLoop)
                   ├── Hailo-8 NPU (YOLOv8s object detection)
                   └── Matter Backend (:5580)
                        ├── matterjs-server (matter.js) ← mainline
                        ├── OTBR (Yocto/Linux)
                        └── Android/Flutter compatibility ← verified, not mainline
```

---

## Current Focus

HomeAgent is no longer primarily a board-validation project. The current work contract is:

1. **RPi5 + Hailo-8** remains the mainline hub.
2. `edgeagent-config` produces the **micro-family node** side.
3. HomeAgent evolves into the **representative / bridge / confederation** side.

This means the next important integration surfaces are:

- companion registry
- NodeCard ingest
- edge health/capability mirroring
- bridge between inner transports (e.g. ESP-NOW) and home transports (MQTT/A2A)

If a change does not help that direction, it is probably secondary for now.

## Platform Support

HomeAgent's mainline target is RPi5 Yocto/Linux. Android/RK3576 was verified as a compatibility path, but it is not the main supported deployment. The current focus is no longer broad board validation; it is **RPi5 + Hailo-8 mainline** and the integration of micro-family nodes being designed in `edgeagent-config`. See [docs/PLATFORM-MATRIX.md](docs/PLATFORM-MATRIX.md) for the full comparison.

```
                     Common Layer
  ┌──────────────────────────────────────────────────┐
  │  Flutter APK (WebView Shell)      — same code    │
  │  Go homeagent (:8080)             — same binary  │
  │  Lit UI (ui/dist/)                — same bundle  │
  │  Matter Backend (:5580)           — matter.js    │
  │  OTBR (Thread Border Router)      — Linux/Yocto  │
  │  matter/ (pure Dart)              — same BLE     │
  ├──────────────────────────────────────────────────┤
  │               Platform Divergence                │
  └──────────────────────────────────────────────────┘

  RPi5 (Yocto Linux)              RK3576 (Android 15, verified path)
  ─────────────────              ─────────────────────────────────
  ivi-homescreen (Wayland)       Flutter APK compatibility
  matterjs + OTBR on Linux       Android-specific scripts archived/secondary
  /dev/ttyUSB0 (ZBDongle-E)     /dev/ttyS5 (ESP32-H2)
  eth0 backbone                  wlan0 backbone
  Hailo-8 NPU                    —
```

| Platform | Board | OS | Thread RCP | Status |
|----------|-------|----|-----------|--------|
| RPi5 | Raspberry Pi 5 8GB | Yocto scarthgap (6.6 LTS) | ZBDongle-E (USB) | ✅ Production |
| **OPi5** | **Orange Pi 5 v1.3.2** | **Yocto scarthgap (mainline 6.14)** | **ZBDongle-E (USB)** | **🟡 Lab only — SSH/GPU verified, NPU parked** |
| RK3576 | RK3576-EVB | Android 15 | ESP32-H2 (UART) | 🟡 Verified compatibility, not mainline |

> OPi5 is kept as a lab target on mainline 6.14 to avoid vendor BSP drift. RKNN/vendor 6.1 notes are parked in llmlog `20260331T114944`; focus stays on RPi5 for HomeAgent, `edgeagent-config` for ESP32/Zig work, and `legoagent-config` for toy-agent experiments.

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
- 👁️ **Vision AI** — Hailo-8 NPU + USB camera, YOLOv8s ~21 FPS real-time detection
- 🧠 **On-device sLLM** — Qwen2.5-0.5B Q4_K_M, offline natural language processing
- 🔗 **A2A Protocol** — 7 skills, webhook subscriptions, remote config repair
- 📡 **Real-time Events** — SSE streaming + outbound webhook push
- 🧵 **Thread Border Router** — OTBR on both Yocto and Android (NDK cross-build)
- 🏗️ **Reproducible Build** — Yocto image (RPi5) or NDK bundle (RK3576)
- 🔒 **Privacy First** — No cloud dependency, all processing on-device
- 📱 **Cross-platform** — Flutter native UI (Android) + WebView shell (Yocto), same codebase
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

The platform. Linux/Yocto Matter hub, Go as extension layer, Flutter as the universal client.

**Principle**: Linux (RPi5) first. Android is a verified compatibility path, not the main supported deployment.

### Current Integration Focus

HomeAgent is being re-centered around **RPi5 + Hailo-8** as the mainline hub and `edgeagent-config` as the source of small edge-family nodes.

- `homeagent-config` = representative / bridge / confederation node
- `edgeagent-config` = micro family node side (ESP32-WROOM, ESP32-CAM, future MCU family)
- `legoagent-config` = toy/education/experiment track

Near-term design pressure on HomeAgent:

- companion registry for edge nodes
- NodeCard ingest and validation
- mirroring/export of edge card + health + capability
- bridge between inner transports (e.g. ESP-NOW) and home transports (MQTT/A2A)

That means future HomeAgent work should prefer **hub↔edge integration** over new board validation.

- [x] **matter.js backend** — matterjs-server as the main Matter controller on Linux/Yocto
- [x] **Go extension layer** — REST/SSE, aliases, A2A, A2UI, sLLM fallback, system/thread state
- [x] **Android compatibility verified** — Flutter APK + Go + matterjs experiments completed
- [x] **Deprecated Android Docker package archived** — `deprecated/android-docker/`, not mainline
- [x] **Thread door sensor commissioning verified** — BLE→PASE→Thread→CASE→CommissionComplete
- [x] **OTBR + Thread path verified** — RPi5 mainline, Android/RK3576 as compatibility evidence
- [x] **Swagger UI** — OpenAPI 3.0 spec + /docs endpoint
- [x] **REST API 12 endpoints** — devices, commission, command, chat, home, events, system, thread
- [ ] **Flutter Linux app** — RPi5 ivi-homescreen native UI (not WebView), matterjs WS direct
- [ ] **HA protocol compat** — Flutter app speaks OHF WebSocket API to matterjs-server
- [ ] **HA Kotlin→Dart port** — Core logic (WS subscription, state management) from ha-android
- [ ] **Go extension API** — Custom REST for clients (aliases, sLLM, A2UI, OTBR integration)
- [ ] **Yocto homeagent recipe** — SD flash → boot → works (ha-2ua)

### Phase 5: Agent Intelligence

The mind. AI that understands context.

#### Edge federation TODOs (coming into focus)

- [ ] **Companion registry** — edge node registration, lifecycle, trust boundary
- [ ] **NodeCard ingest** — receive/store/validate edge cards
- [ ] **Representative mirroring** — export edge state/health/capability through HomeAgent
- [ ] **Inner transport bridge** — ESP-NOW/broadcast style inner transport ↔ MQTT/A2A/home transport

The longer-term shape is: edge nodes stay small and local; HomeAgent represents them outward.

- [x] **A2A Phase 0+1** — AgentCard + JSON-RPC + Task lifecycle + SSE streaming
- [x] **sLLM benchmark** — Qwen3-0.6B: baseline 42% → LoRA 88% (action 100%)
- [x] **GGUF pipeline** — LoRA merge → f16 → Q4_K_M (379MB, ARM 4s/req)
- [ ] sLLM Go integration — llama-server HTTP → agent.go fallback chain (ha-17d)
- [ ] A2UI native renderer — JSON Surface → Flutter Widget (bd-i6o)
- [ ] OpenClaw integration — TTS/Telegram/chat delegated (ha-3nc)
- [ ] EdgeAI Runtime: Hailo-8 + ONNX/TFLite (ha-3lu)

### Phase 6: Production + Scale

The product. Ship it.

- [ ] **RK3588/OPi5 follow-up** — lab target only; mainline 6.14 SSH/GPU verified, vendor 6.1 NPU path parked
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
│  Matter Backend (matter.js)                 │
│  └── matterjs-server (:5580) mainline       │
│  BLE/on-network commissioning · Events      │
└─────────────────┬───────────────────────────┘
                  │ Spinel HDLC (UART)
┌─────────────────┴───────────────────────────┐
│  Thread Border Router (Linux/Yocto)          │
│  wpan0 · SRP Server · Border Routing        │
│  Android/RK3576 path is compatibility-only   │
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
RPi5 (Yocto/Linux) — HomeAgent Hub mainline
├── Node.js  matterjs-server (Matter protocol engine, matter.js)
├── Native   OTBR (Thread Border Router)
├── Go       HomeAgent (controller, AI, state machine, A2A, Swagger UI)
├── Dart     Flutter Native UI / WebView Shell compatibility
├── C/C++    llama.cpp (sLLM on-device inference)
└── (none)   Python — not used on the hub (training only on GPU cluster)

Android/RK3576: verified compatibility path only. Docker/python-matter-server experiments are archived under deprecated/android-docker.

Dev environment (NixOS host)
├── Go 1.25  go build / GOOS=linux GOARCH=arm64
├── Flutter  3.38.9 (APK build, Linux desktop)
├── NDK r27  ot-br-posix cross-compile (Android compatibility experiments)
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

### Option D: Android Docker Package (deprecated reference)

Android Docker packaging was kept for a client/compatibility path, but it is not the HomeAgent core path. Use the Flutter APK/native deployment path unless you explicitly need the old Docker package.

```bash
cd deprecated/android-docker && bash setup-docker.sh
```

> See [deprecated/android-docker/README.md](deprecated/android-docker/README.md) for archived architecture details and AOSP patches.

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
| `/api/subscribe` | POST | Event webhook subscription |
| `/api/subscriptions` | GET | List active subscriptions |
| `/api/subscribe/{id}` | DELETE | Unsubscribe |
| `/api/config` | GET | Runtime config query |
| `/api/config` | PATCH | **Repair** — update sLLM prompt, model, context |
| `/api/space/summary` | GET | Space status summary (interpreted) |
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
├── deprecated/android-docker/ # Archived Android Docker package
│   ├── docker-android.sh      # Native Docker Engine management
│   ├── docker-compose.yml     # Android-specific compose (no dbus)
│   └── setup-docker.sh        # PC → board one-command setup
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
│   ├── README.md          # 문서 지도 — 무엇을 읽고 어디로 흡수할지
│   ├── ARCHITECTURE.md    # ADR — 구조 결정 근거
│   ├── API.md             # REST/SSE API spec
│   ├── THREAD.md          # Thread Border Router guide
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

Start with [docs/README.md](docs/README.md). It is the document map: which files are SSOT, which are evidence logs, and which documents should eventually be absorbed elsewhere.

| Doc | Content |
|-----|---------|
| [docs/README.md](docs/README.md) | 문서 지도 — 역할, 읽는 시점, 흡수/이동 방향 |
| [README.md](README.md) | Public landing — vision, roadmap, quick start |
| [AGENTS.md](AGENTS.md) | Agent instructions — current direction, invariants, no-hype rules |
| [VERSION.md](VERSION.md) | Version/stack SSOT — Yocto, kernels, runtime versions |
| [HARDWARE.md](HARDWARE.md) | Physical device state — boards, IPs, dongles, RCP |
| [HOWTO.md](HOWTO.md) | RPi5 clean rebuild/reflash guide |
| [INVARIANTS.md](INVARIANTS.md) | Runtime invariants and review checklist |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture Decision Records |
| [docs/API.md](docs/API.md) | REST/SSE API spec; keep aligned with OpenAPI and Go routes |
| [docs/MATTER.md](docs/MATTER.md) | Matter SDK/backend strategy |
| [docs/BUILD.md](docs/BUILD.md) | Build environment, artifacts, build farm workflow |
| [docs/THREAD.md](docs/THREAD.md) | Thread Border Router and RCP guide |
| [docs/FLUTTER.md](docs/FLUTTER.md) | Flutter shell architecture + NixOS build |
| [docs/A2UI.md](docs/A2UI.md) | Agent-to-User Interface strategy |
| [docs/A2A.md](docs/A2A.md) | Agent protocol and Constitutional AI |
| [docs/PLATFORM-MATRIX.md](docs/PLATFORM-MATRIX.md) | Platform divergence details |
| [docs/YOCTO-OFFLINE-FIRST.md](docs/YOCTO-OFFLINE-FIRST.md) | Yocto offline recipe policy |
| [docs/EDGE-ZIGBEE.md](docs/EDGE-ZIGBEE.md) | HomeAgent ↔ Edge/Zigbee/MQTT boundary |
| [deprecated/android-docker/README.md](deprecated/android-docker/README.md) | Deprecated Android Docker packaging kept for reference |

---

## Hardware

| Platform | Board | Thread RCP | NPU |
|----------|-------|-----------|-----|
| RPi5 | Raspberry Pi 5 (8GB) | ZBDongle-E (USB) | Hailo-8 M.2 (준비 중) |
| **OPi5** | **Orange Pi 5 (4GB)** | **ZBDongle-E (USB)** | **RKNN 6 TOPS (내장, parked)** |
| RK3576 | RK3576-EVB | ESP32-H2 (UART) | — |

### Hailo-8 NPU (RPi5) ✅ Verified

Hailo-8 M.2 AI 가속기를 RPi5에 장착. Object detection, presence sensing 동작 확인 완료.

| Item | Status |
|------|--------|
| PCIe detection | ✅ `0000:01:00.0 Hailo-8` |
| Firmware | ✅ 4.23.0 |
| GStreamer hailonet | ✅ v4l2src → hailonet → YOLOv8s |
| USB Webcam | ✅ ABKO APC930 QHD (UVC) |
| Real-time inference | ✅ ~21 FPS (camera input) |
| Benchmark (synthetic) | ✅ 398 FPS (YOLOv8s, no camera overhead) |

**RPi5 `/opt/models/`:**

| Model | Size | Purpose |
|-------|------|---------|
| `yolov8s.hef` | 10 MB | Object detection (Hailo-8 NPU) |
| `qwen2.5-0.5b-instruct-q4_k_m.gguf` | 469 MB | sLLM on-device inference |

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
