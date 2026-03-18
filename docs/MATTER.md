# Matter SDK Strategy

> Why matter.js? What are the alternatives? Runtime analysis and roadmap.

---

## SDK Landscape: Only Two Official Options

The [CSA Matter Handbook](https://handbook.buildwithmatter.com/development/) recognizes two SDK implementations:

| | **connectedhomeip** (C++ SDK) | **matter.js** (TypeScript SDK) |
|---|---|---|
| Language | C++ | TypeScript/JavaScript |
| Matter version | 1.5 (latest) | 1.4.2 |
| Embedded (MCU) | ✅ | ❌ |
| Chipset SDK integration | ✅ (Wi-Fi/Thread chip direct) | ❌ |
| OS-based (Linux/macOS) | ✅ | ✅ |
| Windows | ❌ | ✅ |
| Rapid prototyping | ❌ | ✅ |
| Certification | ✅ | ✅ (passed) |

**No other SDK is officially recognized by CSA for Matter certification.**

---

## Why matter.js for Hub/Controller Devices

connectedhomeip is optimized for **MCU/embedded** targets. For OS-based devices (hubs, wall panels, gateways running Linux or Android), matter.js is the better fit:

| Aspect | connectedhomeip | matter.js (HomeAgent) |
|--------|----------------|----------------------|
| Build complexity | 8.5GB SDK, GN build, Docker 5GB | `npm install` |
| Android integration | C++ JNI wrappers required | Node.js binary, no JNI |
| BLE commissioning | [Known bug #29410](https://github.com/project-chip/connectedhomeip/issues/29410) (2+ years unresolved) | Working via Flutter BLE relay |
| Developer skillset | C++ + JNI + Android (rare) | TypeScript + Go (common) |
| Controller/Bridge docs | Minimal | Well-documented |
| Google dependency | Play Services required for commissioning | Fully independent |
| Lines of code (app) | ~8,000 (SDK glue: 2,959) | ~3,100 (SDK glue: 0) |
| Time to first device | Weeks | Hours |

### Industry validation

- **Home Assistant** — world's largest open-source smart home — [migrated to matter.js](https://github.com/home-assistant/core) for their Matter integration
- **Samsung SmartThings Hub** — runs a server process separate from the app (same architecture pattern)
- **Apple HomePod**, **Google Nest Hub** — all use server+app separation, not monolithic apps

---

## Runtime Analysis: Node.js on Android

### Measured Memory (RK3576, 8GB RAM, 3 paired devices)

```
Process          RSS (measured)  Notes
──────────────   ──────────────  ──────────────────
OTBR (C)              9 MB      Thread Border Router, leader
Go homeagent         11 MB      8 threads, REST+SSE+WS
matterjs (Node.js)   65 MB      matter-server 0.3.5 + 3 devices
Flutter APK         225 MB      Android runtime (55 threads)
──────────────────────────────
Total               310 MB / 8GB = 3.8%
Free                6.7 GB
```

**Node.js is not the memory problem.** The Flutter/Android runtime (225MB) is 3.5× larger than matterjs (65MB). Total stack uses under 4% of available RAM.

### Disk footprint

| Component | Disk size |
|-----------|----------|
| Go homeagent | 9.5 MB |
| OTBR (otbr-agent + ot-ctl) | 9.8 MB |
| Node.js runtime | 45 MB |
| matterjs node_modules | 23 MB |
| **Total nodejs-bundle** | **~68 MB** |
| Flutter APK | 51 MB |

### Node.js native APIs used by matter.js

```
node:crypto    — Matter encryption (CASE/PASE/AES-CCM)
node:dgram     — UDP (Matter protocol core transport)
node:fs        — Device data persistence
node:http      — WebSocket server
node:os        — Network interface discovery
node:sqlite    — Device state DB (Node 22+ built-in)
```

---

## Alternative Runtimes: Bun and Deno

### Compatibility matrix

| | **Node.js** (current) | **Bun** | **Deno** |
|---|---|---|---|
| Engine | V8 (Chrome) | JavaScriptCore (WebKit) | V8 (Chrome) |
| node:dgram (UDP) | ✅ native | ✅ compat | ⚠️ partial |
| node:crypto | ✅ | ✅ | ⚠️ partial |
| node:sqlite | ✅ (22+) | ✅ `bun:sqlite` (**matter.js explicitly supports**) | ❌ none |
| arm64 Linux | ✅ | ✅ official | ✅ |
| arm64 Android | ✅ glibc bundle | ⚠️ unofficial (no Bionic) | ❌ unsupported |
| Startup time | ~1s | ~0.1s | ~0.5s |
| Memory (idle) | ~60-80MB | ~30-50MB | ~50-70MB |

### Key finding: matter.js already supports Bun

```typescript
// @matter/nodejs SqliteStorage.d.ts:
// "Supports node:sqlite, bun:sqlite. (maybe also better-sqlite3 support)"

// matter.js 0.15 release notes (2025-06):
// "we are proud to announce that matter.js now runs on Bun
//  as a supported JavaScript runtime"
```

**Code-level: ready. Blocker: Bun Android arm64 support.**

### Verdict

| Alternative | Feasibility | Blocker |
|-------------|------------|---------|
| **Bun** | 🟡 Most promising | No official Android arm64 build. Linux arm64 exists. glibc bundle possible but unverified |
| **Deno** | 🔴 Difficult | `node:dgram` incomplete, `node:sqlite` missing, no Android |
| **Node.js** | ✅ Proven | Current choice. Working in production |

---

## matter.js Release Timeline

| Version | Date | Matter Spec | Key Changes |
|---------|------|------------|-------------|
| 0.10 | 2024-08 | 1.3 | Matter 1.1→1.3 upgrade |
| 0.12 | 2025-01 | 1.3 | Stabilization, legacy API deprecation |
| 0.13 | 2025-03 | **1.4** | Matter 1.4, legacy Device API removed |
| 0.14 | 2025-04 | 1.4.1 | Enhanced Setup Flow, NFC |
| **0.15** | **2025-06** | 1.4.2 | **🔥 Bun official runtime support**, Matter Groups |
| **0.16** | **2026-01** | **1.4.2** | OTA updates, Scenes, **Electron + React Native** runtimes |
| **0.17** | **2026 Q2~Q3** (est.) | **1.5.0** | Matter 1.5, new Controller API, ICD |

> 0.16 release notes: *"Looking ahead, we'll focus on adding support for **Matter 1.5.0**, expanding support for **remaining Matter protocol features**, and **finalizing the new Controller API**."*

### Release cadence

- 0.10→0.12: 5 months
- 0.12→0.15: 5 months
- 0.15→0.16: 7 months
- **0.16→0.17: estimated 5-7 months → June-August 2026**

---

## Matter Specification Timeline

| Spec | Date | Key additions |
|------|------|--------------|
| Matter 1.4 | 2024-11 | Energy management, HRAP, ICD |
| Matter 1.4.1 | 2024-11 | Enhanced Setup, Multi-Device QR |
| Matter 1.4.2 | 2025-06 | BLE commissioning improvements, PSA crypto |
| **Matter 1.5** | **2025-11** | **Cameras, Closures, Energy management, TCP** |
| Matter 1.5.1/1.5.2 | 2026 H1 (est.) | Quality updates |
| Matter 1.6 | 2026 Q4 (est.) | Annual major + quality updates pattern |

> CSA has settled into "1 major release/year + multiple quality updates" cadence.

---

## Unimplemented Protocol Features (matter.js)

From [COMPATIBILITY.md](https://github.com/matter-js/matter.js/blob/main/docs/MATTER_COMPATIBILITY.md):

```
- Groups persistence for controller (not implemented)
- Bindings (partial)
- DCL validation with revocation checks (not implemented)
- ICD client/server (not implemented)
- UDC — User Directed Commissioning (not implemented)
- NFC/WPAF commissioning (not implemented)
- Enhanced commissioning flow / TC feature (not implemented)
- AccessControl ARL feature (not implemented)
```

---

## Roadmap

| Timeframe | Action |
|-----------|--------|
| **Now** | Node.js — proven, 65MB RSS, no issues |
| **2026 Q2~Q3** | matter.js 0.17 release → upgrade (Matter 1.5, new Controller API) |
| **2026 Q3** | Bun linux-arm64 PoC on dev board (glibc bundle) |
| **When Bun supports Android** | Drop-in replacement: `node` → `bun` (zero code changes) |

### Bun transition trigger

Monitor these:
- [Bun Android issue (oven-sh/bun#75)](https://github.com/oven-sh/bun/issues/75)
- matter.js 0.17 release + stability period
- Bun linux-arm64 glibc bundle test on RK3576

---

## References

- [CSA Matter Handbook — Development](https://handbook.buildwithmatter.com/development/)
- [matter.js COMPATIBILITY.md](https://github.com/matter-js/matter.js/blob/main/docs/MATTER_COMPATIBILITY.md)
- [matter.js 0.16 release](https://github.com/matter-js/matter.js/discussions/2976)
- [matter.js 0.15 release (Bun support)](https://github.com/matter-js/matter.js/discussions/2203)
- [Matter 1.5 CSA announcement](https://csa-iot.org/newsroom/matter-1-5-introduces-cameras-closures-and-enhanced-energy-management-capabilities/)
- [Matter timeline (matteralpha.com)](https://www.matteralpha.com/matter-timeline)
- [connectedhomeip BLE issue #29410](https://github.com/project-chip/connectedhomeip/issues/29410)
- [Bun roadmap](https://github.com/oven-sh/bun/issues/159)
