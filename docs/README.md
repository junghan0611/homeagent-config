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
| [`../runtime/README.md`](../runtime/README.md) | ARM Linux + Zig state machine + C906L coprocessor architecture | the SG2000 runtime center (ARM boot, L0–L4, C906 base) |
| [`TARGET_DEVICE.md`](TARGET_DEVICE.md) | board and radio strategy details | SG2000 / SSD202D / EFR32 decisions |
| [`THP23-LIBERATION.md`](THP23-LIBERATION.md) | THP23-ZB-X liberation research (parked 128MB evidence) | reference for the parked 128MB lower-bound lane |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | ADRs and structure decisions | changing process/backend boundaries |
| [`API.md`](API.md) | REST/SSE API notes | changing clients or routes |
| [`BUILD.md`](BUILD.md) | **origin-lane** build workflow notes (RPi5/Android/Yocto) | origin-lane build/release tooling — not the SG2000 runtime build |
| [`MATTER.md`](MATTER.md) | Matter backend strategy | changing matter.js / commissioning paths |
| [`THREAD.md`](THREAD.md) | OTBR/RCP notes | changing Thread/RCP paths |
| [`EDGE-ZIGBEE.md`](EDGE-ZIGBEE.md) | hub ↔ edge/Zigbee boundary | touching ESP32/Zigbee/MQTT interfaces |
| [`YOCTO-OFFLINE-FIRST.md`](YOCTO-OFFLINE-FIRST.md) | Yocto offline recipe policy | origin-lane Yocto recipe work |
| [`FLUTTER.md`](FLUTTER.md) | Flutter shell notes | client/origin-lane UI work |
| [`A2A.md`](A2A.md) | agent protocol notes | A2A work |
| [`A2UI.md`](A2UI.md) | server-driven UI notes | A2UI surface work |
| [`PLATFORM-MATRIX.md`](PLATFORM-MATRIX.md) | legacy platform comparison | origin-lane platform questions |
| [`PRODUCT-CONFIG-MODEL.md`](PRODUCT-CONFIG-MODEL.md) | SMHub product state map — backend.db/OpenRC/p7 USER (what a product set must weave together) | understanding where product state lives before designing a set |
| [`SMHUB-MANUAL-REVIEW.md`](SMHUB-MANUAL-REVIEW.md) | vendor manual review index (22 pages, checkboxes) | working through official SMHUB docs page-by-page next session |

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

HomeAgent is a **minimal open hub BSP** project first. The active runtime lane is SG2000 / Milk-V Duo S / SMHUB Nano class on the **ARM Cortex-A53 boot mode**, with a **Zig 100ms state machine on Linux + a C906L FreeRTOS mailbox coprocessor base** (see `../runtime/README.md`), onboard EFR32, and Buildroot lineage. Tuya THP23-ZB-X is parked as 128MB lower-bound evidence. RPi5/Yocto/Hailo, OPi5, and Android/RK work remain preserved origin or compatibility evidence.
