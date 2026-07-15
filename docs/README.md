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
| [`../runtime/README.md`](../runtime/README.md) | RISC-V Linux + Zig state machine + C906L coprocessor architecture | the SG2000 runtime center (RISC-V C906 boot, L0–L4, C906 base) |
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
| [`MULTIPROTOCOL.md`](MULTIPROTOCOL.md) | **핵심 난제 SSOT — 단일 EFR32MG24로 Zigbee+Thread 동시** (Multi-PAN RCP + cpcd + zigbeed + otbr). 동일채널 vs Concurrent Listening 모드, HA 애드온 폐기·2-라디오 후퇴의 정직한 판정, SMHub 증명 게이트 G0~G4 | 단일 라디오 멀티프로토콜 설계/증명, MG24 재플래시(RCP), Zigbee+Thread 동시 재현 | 
| [`HUBS.md`](HUBS.md) | **인증 Zigbee/Matter 허브 랜드스케이프 SSOT** — 인증(CSA Matter)받고 자체 펌웨어/데몬을 올릴 수 있는 개방 허브 조사. IKEA DIRIGERA 전면(주력), Zemismart M1(인증 블랙박스 레퍼런스), SMHub(SG2000 학습 앵커) 비교. Main SoC 동형 분석, Thread TBR vs z2m 경로, 오픈소스 클론 후보 | 인증 허브 선택/조사, DIRIGERA 실기 작업, Thread/TBR 개념 확인 |
| [`SMHUB.md`](SMHUB.md) | **SMHub Nano Mg24 single SSOT** — HW platform, radios, state model (backend.db/OpenRC/p7), live 0.9.8 verify log, control-boundary/reproduction matrix, info walls, vendor-manual review, open design questions, next verification steps | any SMHub product-verification / bring-up / config-set work (merges former PRODUCT-CONFIG-MODEL + SMHUB-CONTROL-MAP + SMHUB-MANUAL-REVIEW) |

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

HomeAgent is a **minimal open hub BSP** project first — a reproducible verification/prototyping ground with **no business logic**. The core lane is **Milk-V Duo S (SG2000, RISC-V C906)**, booted on real silicon from our own Buildroot image (full-stack ownership), with a **Zig 100ms state machine on Linux + a C906L FreeRTOS mailbox coprocessor base** (see `../runtime/README.md`) and radio via **USB ZBDongle-E**. **SMHUB Nano MG24** is the commercial reference (vendor OS, system-application approach, onboard EFR32MG24). Both are SG2000/riscv64; their images are not interchangeable. Tuya THP23-ZB-X is parked as 128MB lower-bound evidence. RPi5/Yocto/Hailo, OPi5, and Android/RK work remain preserved origin or compatibility evidence.
