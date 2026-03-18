# Architecture Decision Records

> Why this stack? Why this structure? Answers to the questions every engineer asks.

---

## Overview

HomeAgent uses a **microservice architecture on a single board** — four independent processes communicating via WebSocket and REST.

```
┌───────────────────────────────────────────────────┐
│                 Android / Linux Board              │
│                                                    │
│   ┌───────────┐    ┌────────────────────────────┐ │
│   │ Flutter   │    │    Server (background)      │ │
│   │ App (UI)  │    │                             │ │
│   │           │    │  ┌────────┐  ┌───────────┐ │ │
│   │ Dashboard │◄───┤  │ Go     │◄─┤ matterjs  │ │ │
│   │ BLE relay │REST│  │ :8080  │WS│ :5580     │ │ │
│   │           │API │  │        │  │           │ │ │
│   └───────────┘    │  └────────┘  └───────────┘ │ │
│                    │  ┌────────┐                │ │
│                    │  │ OTBR   │                │ │
│                    │  │ :8081  │                │ │
│                    │  └────────┘                │ │
│                    └────────────────────────────┘ │
└───────────────────────────────────────────────────┘
```

| Component | Role | Size | Language |
|-----------|------|------|----------|
| **Flutter App** | Native UI + BLE antenna | 51MB APK | Dart (3,128 lines) |
| **Go Server** | REST API, state, LLM agent, external integration | 9.5MB binary | Go (3,800 lines) |
| **matterjs** | Matter protocol engine | 68MB (with runtime) | TypeScript |
| **OTBR** | Thread Border Router | 9.8MB | C (NDK cross-build) |

---

## ADR 1: Why Go on Android?

### Context

The hub needs a **background server** running 24/7 on an Android board. Options:

| Option | Pros | Cons |
|--------|------|------|
| Kotlin (Ktor) | Native Android | JVM overhead (~100MB RAM), 2-5s startup, Gradle build |
| Python (FastAPI) | Rapid prototyping | Runtime dependency, memory, speed |
| Node.js (Express) | Already have Node for matterjs | Two Node processes, memory |
| **Go** | Single binary, no deps, 0.1s startup | Not "standard" Android |

### Decision

**Go, cross-compiled to `android/arm64`.**

```bash
# One line. No Android Studio, no NDK, no app store.
GOOS=android GOARCH=arm64 go build -o homeagent
```

The resulting 9.5MB binary runs directly on Android's Linux kernel — the same way `adb`, `toybox`, and other system tools work.

### Consequences

- ✅ **~20MB RAM** vs ~100MB for JVM
- ✅ **0.1s startup** vs 2-5s for JVM warmup
- ✅ **Same binary** runs on Android, RPi5 Linux, any arm64 — true cross-platform
- ✅ **No dependency management** — statically linked, copy and run
- ✅ Build in **12 seconds** (vs minutes for Gradle)
- ⚠️ Not a "standard" Android pattern — but Docker, Kubernetes, Terraform are all Go for the same reasons

---

## ADR 2: Why matterjs as a Separate Process?

### Context

matter.js is the Matter protocol engine. It handles BLE commissioning, Thread/WiFi provisioning, device subscriptions, and CASE sessions. It runs on **Node.js**.

Options for integrating matter.js:

| Option | Feasibility |
|--------|-------------|
| Embed Node.js in Kotlin via JNI | 🔴 Extremely complex. Memory/thread conflicts |
| Run JS in WebView | 🟡 Possible but no BLE/Thread access (browser sandbox) |
| **Separate process + WebSocket** | ✅ Clean separation. Industry standard |

### Decision

**Run matterjs-server as an independent Node.js process. Communicate via WebSocket on port 5580.**

### Consequences

- ✅ matter.js updates are independent of app/server releases
- ✅ If matterjs crashes, Go server detects and reconnects (5s retry)
- ✅ If app crashes, Matter connections stay alive
- ✅ Can test Matter protocol without any UI — just WebSocket messages
- ⚠️ Requires Node.js runtime (~68MB including node_modules)
- ⚠️ On Android, Node.js runs via bundled glibc (ld-linux shim)

---

## ADR 3: Why Flutter?

### Context

The app needs to:
1. Display a dashboard UI
2. Provide **BLE antenna** for Matter commissioning (only an app process can access Android BLE)
3. Run on Android boards (wall panels, EVBs)

Options:

| Option | BLE Access | Cross-platform | Ecosystem |
|--------|-----------|----------------|-----------|
| Kotlin (Jetpack Compose) | ✅ | Android only | Large |
| React Native | Via plugin | Android + iOS | Large |
| **Flutter** | ✅ (flutter_blue_plus) | Android + iOS + Linux + Web | Large, Google-backed |

### Decision

**Flutter with native UI (not WebView).**

### Why not Kotlin?

If Android is the only target, Kotlin is a valid choice. Flutter was chosen for specific reasons:

**1. BLE relay stability**

The most critical app function is acting as a **BLE antenna** for Matter commissioning. The app relays raw BLE bytes between matterjs-server (WebSocket :5581) and the physical BLE radio.

```
Flutter (flutter_blue_plus)     matterjs-server
        │                            │
        │◄── WS :5581 ──────────────►│
        │    ble_scan / ble_connect   │
        │    ble_write (C1 bytes)     │
        │    ble_data  (C2 bytes)     │
        │                            │
        │  Flutter = BLE byte shuttle │
        │  matterjs = full protocol   │
```

`flutter_blue_plus` operates at a different abstraction level than Android's native BLE API, avoiding known issues encountered with the connectedhomeip C++ SDK's BLE layer.

**2. Code efficiency**

Same features (dashboard, device cards, commissioning, settings) in fewer lines:

```
Typical monolithic app:  ~8,000 lines (UI + Matter SDK glue + services)
Flutter + REST API:      ~3,100 lines (UI + HTTP calls + BLE relay)
```

Matter protocol code in the app: **0 lines**. The server handles it.

**3. Future portability (bonus)**

Same codebase builds for Android, Linux desktop, and potentially web — no rewrite needed if the target OS changes.

### Consequences

- ✅ BLE commissioning works reliably on Android
- ✅ ~60% less app code vs monolithic approach
- ✅ App developers don't need to understand Matter protocol
- ⚠️ Flutter SDK required for builds (~500MB dev environment)
- ⚠️ APK size is 51MB (Flutter runtime included)

---

## ADR 4: Monolithic App vs Process Separation

### Fault Isolation

| Scenario | Monolithic (all-in-app) | Separated (this project) |
|----------|----------------------|--------------------------|
| UI bug → app crash | 🔴 Matter stops entirely | ✅ Server keeps running, restart app |
| BLE stack error | 🔴 Full app restart | ✅ App restart only, server unaffected |
| OOM (out of memory) | 🔴 Everything dies | ✅ Only the affected process restarts |
| During update | 🔴 All functions stop | ✅ Server stays, update app independently |

### Testability

| Aspect | Monolithic | Separated |
|--------|-----------|-----------|
| API testing | Must run the app | `curl localhost:8080/api/devices` |
| Automation | Android test framework | Standard HTTP requests |
| Debugging | logcat + app debugger | Independent process logs |
| QA | Full app build required | Test API and UI independently |

### Deployment Independence

| Change | Monolithic | Separated |
|--------|-----------|-----------|
| UI-only fix | Rebuild entire APK | Replace HTML/assets only |
| Server logic fix | Rebuild entire APK | Replace Go binary (9.5MB) |
| Matter version upgrade | Rebuild entire APK | Update matterjs only |
| Emergency hotfix | Full APK (51MB) | Affected component only |

### Extensibility

| Capability | Monolithic | Separated |
|-----------|-----------|-----------|
| External system integration | Add code to app | REST API call (standard HTTP) |
| Voice assistant | Custom development | A2A protocol support built-in |
| Cloud integration | Direct from app | Server handles MQTT/HTTP |
| Multiple UIs | Not possible | Web browser, app, TUI — simultaneously |
| Other platforms | Android only | Same stack on Linux (RPi5, Yocto) |

---

## ADR 5: Boot Resilience Design

### Problem

On Android boards, power can be cut at any time. The system must recover automatically:

1. All services must start without human intervention
2. Thread network must reconnect to existing devices
3. Matter pairings must survive power cycles

### Decision

**Android init service + Thread dataset 3-layer protection.**

```
Power on
  └── sys.boot_completed=1
       └── homeagent.rc (init service)
            └── start.sh
                 ├── [1] Kill Android Thread HAL
                 │        stop ot-daemon (init service disable)
                 │        + 8-second kill loop (crash limit trigger)
                 ├── [2] OTBR start (UART flush + 3 retries)
                 │        └── Thread dataset 3-layer protection:
                 │             1st: otbr-data/ auto-restore
                 │             2nd: dataset-backup.hex file fallback
                 │             3rd: new network (+ matter-data reset)
                 ├── [3] matterjs-server (:5580, :5581)
                 ├── [4] Go homeagent (:8080)
                 └── [5] APK auto-launch
```

### Key detail: Android Thread HAL conflict

Android 15 includes its own Thread stack (`ot-daemon` + `vendor.threadnetwork_hal`) that competes for the UART RCP device (`/dev/ttyS5`). Simply killing the HAL with `pkill` is insufficient — Android init restarts it automatically.

**Solution:**
- `stop ot-daemon` — disables the init service (prevents restart)
- `stop vendor.threadnetwork_hal` — stops the HAL
- 8-second kill loop — triggers Android's crash limit, preventing further restarts
- UART buffer flush before OTBR start — clears residual spinel frames from HAL

### Consequences

- ✅ Physical power cycle → full stack in ~80 seconds
- ✅ Thread devices reconnect automatically (same dataset)
- ✅ Matter pairings survive indefinitely (matter-data/ untouched)
- ✅ No human intervention required after initial install

---

## Matter Device Support Matrix

### Supported Commands (8)

| Command | Cluster | Example |
|---------|---------|---------|
| `on` | On/Off | Turn on a light or plug |
| `off` | On/Off | Turn off a light or plug |
| `set_level` | Level Control | Dimming (0-254) |
| `set_color` | Color Control | RGB color (hue + saturation) |
| `set_color_temp` | Color Control | Color temperature (mireds) |
| `set_thermostat` | Thermostat | Set target temperature |
| `lock` | Door Lock | Lock a smart lock |
| `unlock` | Door Lock | Unlock a smart lock |

### Supported Device Types

| Device Type | Protocol | Control | Events | Verified Hardware |
|------------|----------|---------|--------|-------------------|
| Light (on/off) | Thread/WiFi | ✅ | ✅ | Nanoleaf Essentials |
| Light (dimmable) | Thread/WiFi | ✅ | ✅ | Nanoleaf Essentials |
| Light (color temp) | Thread/WiFi | ✅ | ✅ | Nanoleaf Essentials |
| Light (full color) | Thread/WiFi | ✅ | ✅ | — |
| Smart Plug | WiFi | ✅ | ✅ | TP-Link Tapo P100 |
| Contact Sensor | Thread | — | ✅ | Tuya Door Sensor |
| Temperature Sensor | Thread/WiFi | — | ✅ | (no hardware) |
| Humidity Sensor | Thread/WiFi | — | ✅ | (no hardware) |
| Door Lock | Thread/WiFi | ✅ | ✅ | (no hardware) |
| Thermostat | Thread/WiFi | ✅ | ✅ | (no hardware) |

### Adding a New Device Type

Adding a new Matter device type follows a pattern (~60 lines total):

```
1. Go server: add case in hub.go command handler (~30 lines)
2. Flutter UI: add device card variant (~30 lines)
3. Test: curl -X POST localhost:8080/api/devices/command
```

---

## FAQ

### Q: Does pairing survive power cycles?

**Yes.** Pairing data is persisted in `matter-data/` (fabric, certificates, node list) and `otbr-data/` (Thread dataset). On power restore, matterjs loads existing pairings and devices reconnect automatically. Verified with physical power-off/on cycles.

### Q: Does it work without internet?

**Yes.** Matter is a local protocol. Device discovery (mDNS), control, and event streaming all happen within the LAN. The only feature requiring internet is LLM chat (cloud API). All device control works fully offline.

### Q: What happens when the WiFi router changes?

- **Thread devices** (sensors, lights): ✅ **Unaffected.** Thread uses 802.15.4 radio, completely independent of WiFi.
- **WiFi devices** (plugs): ❌ **Need re-pairing.** The WiFi SSID/password was stored during commissioning.
- **The board itself**: Needs manual WiFi reconfiguration in Android settings.

### Q: Does redeployment (code update) preserve pairings?

**Yes.** Deployment scripts only update binaries and UI assets. `matter-data/` and `otbr-data/` are never touched during redeployment. Software updates and device data are completely separated.

### Q: Is this production-ready or a prototype?

The architecture is production-grade (microservice separation, fault isolation, automated recovery). Every major smart home hub — Home Assistant, Samsung SmartThings, Apple HomePod, Google Nest — uses the same "server + app separation" pattern rather than putting everything in one app.

---

## References

- [Matter Specification](https://csa-iot.org/all-solutions/matter/) — CSA
- [matter.js](https://github.com/project-chip/matter.js) — TypeScript Matter SDK
- [ot-br-posix](https://github.com/openthread/ot-br-posix) — Thread Border Router
- [A2UI](https://a2ui.org) — Agent-to-User Interface protocol
- [docs/API.md](API.md) — REST API specification
- [docs/PLATFORM-MATRIX.md](PLATFORM-MATRIX.md) — RPi5 vs RK3576 comparison
