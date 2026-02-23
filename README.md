# HomeAgent

**Open-source Matter smart home platform with on-device AI agent.**

RPi5 · Yocto · Go · Matter · LLM Agent · Lit Frontend

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## What is HomeAgent?

HomeAgent is a **self-hosted smart home hub** that runs entirely on a Raspberry Pi 5. No cloud required. It combines Matter device control, real-time event streaming, and an LLM-powered agent — all in a single Go binary.

```
Browser ──SSE──▶ Go HomeAgent v0.6 (:8080)
                 ├── REST API (devices, commission, command, chat)
                 ├── LLM Agent (OpenRouter / on-device sLLM)
                 ├── Matter WS Client (single ReadLoop)
                 └── Lit Frontend (dashboard, pairing, chat)
                          │
                 matterjs-server (:5580)
                 ├── Thread devices (OTBR)
                 └── WiFi devices
```

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

## Key Features

- 🔌 **Matter Hub** — Commission and control Thread + WiFi devices via BLE
- 📡 **Real-time Events** — SSE streaming for instant state updates
- 🤖 **LLM Agent** — Natural language → device control (Gemini Flash, ~$0.02/day)
- 🏗️ **Yocto Image** — Reproducible: flash SD card → boot → works
- 🔒 **Privacy First** — No cloud dependency, on-device processing
- 📱 **Web UI** — Lit WebComponents, works on any browser

## Architecture

```
┌─────────────────────────────────────────────┐
│  Lit Frontend (Vite build, ~40KB)           │
│  Dashboard · Device Cards · Chat Panel      │
│  Commission Dialog · SSE Event Log          │
└─────────────────┬───────────────────────────┘
                  │ REST + SSE
┌─────────────────┴───────────────────────────┐
│  Go HomeAgent (single binary, ~7MB)         │
│  ├── Hub: state management, SSE broadcast   │
│  ├── Agent: OpenRouter → action extraction  │
│  ├── Matter: WS client, single ReadLoop     │
│  └── Config: Thread dataset + WiFi auto-inject │
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

### Option B: Development (cross-compile)

```bash
# Build Go binary
cd go
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o bin/homeagent ./cmd/homeagent/

# Build UI
cd ui && npm install && npx vite build

# Deploy
scp go/bin/homeagent root@<rpi5>:/opt/homeagent/
scp -r ui/dist/* root@<rpi5>:/opt/homeagent/ui/
```

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/devices` | GET | List all devices with current state |
| `/api/commission` | POST | Pair new device `{"code": "0000-000-0000"}` |
| `/api/devices/command` | POST | Control device `{"node_id": 8, "command": "on"}` |
| `/api/chat` | POST | LLM agent `{"message": "turn off the plug"}` |
| `/api/events` | GET | SSE stream (real-time state changes) |
| `/healthz` | GET | Health check |

## Roadmap

### Phase 1: Yocto + Protocol Verification ✅
- Yocto build (scarthgap 5.0 LTS) + RPi5 boot
- OTBR auto-init (Thread leader + SRP server)
- chip-tool Matter commissioning verified
- Matter full flow: BLE → PASE → Thread → CommissioningComplete

### Phase 2: Matter + Go Controller ◐ (50%)
- [x] matterjs-server WebSocket API (100% match with chip-tool oracle)
- [x] Go controller v0.6 (Hub, SSE, REST, auto Thread/WiFi inject)
- [x] Lit frontend (dashboard, pairing, On/Off toggle, event log)
- [x] Multi-device: Thread ×2 + WiFi ×1 simultaneously
- [x] LLM agent chat (Gemini Flash, natural language → device control)
- [ ] Event-triggered agent (door open → LLM judgment → proactive alert)
- [ ] A2UI dynamic rendering (LLM generates surfaceUpdate JSON)
- [ ] TTS announcements ("The front door is open")

### Phase 3: AI + Agent + A2UI
- [ ] A2A protocol (agent-to-agent cooperation)
- [ ] Constitutional AI framework
- [ ] On-device sLLM (Hailo-10H GenAI)
- [ ] Full Yocto image with everything integrated

### Phase 4: Production + Scale
- [ ] RK3588 Yocto port (production target)
- [ ] Zigbee support (zigbee2mqtt)
- [ ] Zig firmware for custom Thread sensors

## Project Structure

```
homeagent-config/
├── go/                    # Go controller (homeagent binary)
│   ├── cmd/homeagent/     # Entry point
│   ├── internal/hub/      # Hub coordinator (state, SSE, REST)
│   ├── internal/matter/   # matterjs-server WS client
│   └── internal/agent/    # LLM agent (OpenRouter)
├── ui/                    # Lit frontend (Vite)
│   └── src/               # app, device-card, chat-panel, commission-dialog
├── yocto/                 # Yocto build (meta-homeagent layer)
├── docs/                  # Architecture docs
│   ├── MATTER-VERIFY.md   # chip-tool vs matterjs-server comparison
│   ├── A2UI.md            # Agent-to-User Interface strategy
│   └── A2A.md             # Agent protocol, Constitutional AI
└── matter/                # chip-tool binaries
```

## Documentation

| Doc | Content |
|-----|---------|
| [MATTER-VERIFY.md](docs/MATTER-VERIFY.md) | Matter verification (chip-tool oracle vs matterjs-server) |
| [A2UI.md](docs/A2UI.md) | Dynamic UI strategy, LLM → surfaceUpdate |
| [A2A.md](docs/A2A.md) | Agent protocol, Constitutional AI |
| [HOWTO.md](HOWTO.md) | Full setup guide (clean state → working RPi5) |
| [README-KO.md](README-KO.md) | 한국어 문서 (Korean documentation) |

## Philosophy

- **Being to Being** — AI as a collaborator, not a tool
- **Privacy by default** — No cloud, no data leaving your home
- **Reproducible** — Yocto image → SD card → boot → works
- **Agent-first UI** — The agent decides what to show ([A2UI](https://a2ui.org))

## License

MIT
