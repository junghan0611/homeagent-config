# HomeAgent Docs Map

This directory keeps supporting evidence and implementation notes. The living root set is:

- `README.md` — public thesis
- `AGENTS.md` — week-stable agent rules
- `NEXT.md` — active handoff
- `CHANGELOG.md` — closed work / CalVer notes
- `ROADMAP.md` — phase direction

`VERSION.md` is the compact SSOT for stack, version, and physical device state.

## Core References

| Doc | Role | Read when |
|-----|------|-----------|
| [`../VERSION.md`](../VERSION.md) | stack / version / physical device matrix | checking current board/runtime state |
| [`TARGET_DEVICE.md`](TARGET_DEVICE.md) | board and radio strategy details | SG2000 / SSD202D / EFR32 decisions |
| [`THP23-LIBERATION.md`](THP23-LIBERATION.md) | THP23-ZB-X open-source liberation research | bringing up the in-hand THP23 board |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | ADRs and structure decisions | changing process/backend boundaries |
| [`API.md`](API.md) | REST/SSE API notes | changing clients or routes |
| [`BUILD.md`](BUILD.md) | build workflow notes | changing build/release tooling |
| [`MATTER.md`](MATTER.md) | Matter backend strategy | changing matter.js / commissioning paths |
| [`THREAD.md`](THREAD.md) | OTBR/RCP notes | changing Thread/RCP paths |
| [`EDGE-ZIGBEE.md`](EDGE-ZIGBEE.md) | hub ↔ edge/Zigbee boundary | touching ESP32/Zigbee/MQTT interfaces |
| [`YOCTO-OFFLINE-FIRST.md`](YOCTO-OFFLINE-FIRST.md) | Yocto offline recipe policy | origin-lane Yocto recipe work |
| [`FLUTTER.md`](FLUTTER.md) | Flutter shell notes | client/origin-lane UI work |
| [`A2A.md`](A2A.md) | agent protocol notes | A2A work |
| [`A2UI.md`](A2UI.md) | server-driven UI notes | A2UI surface work |
| [`PLATFORM-MATRIX.md`](PLATFORM-MATRIX.md) | legacy platform comparison | origin-lane platform questions |

## Parked / Absorbed Notes

These are not first-read docs for new work:

| Doc | State |
|-----|-------|
| `GO-MATTERJS-OVERLAP.md` | absorbed into architecture decisions |
| `MATTER-VERIFY.md` | verification log, absorbed into Matter notes |
| `INSTALL.md` | absorbed into HOWTO/origin deployment notes |
| `MQTT-HA.md` | absorbed into edge/Zigbee boundary notes |
| `ZIGBEE2MQTT_UPSTREAM_GUIDE.md` | absorbed into edge/Zigbee notes |

## Current Direction

HomeAgent is a **minimal open hub BSP** project first. The current target lane is SG2000 / SMHUB Nano / Milk-V Duo S class with onboard EFR32 and Buildroot lineage. RPi5/Yocto/Hailo, OPi5, and Android/RK work remain preserved origin or compatibility evidence.
