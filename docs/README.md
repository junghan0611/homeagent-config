# HomeAgent Docs Map

This directory keeps supporting evidence and implementation notes. The living root set is:

- `README.md` — public thesis
- `AGENTS.md` — week-stable agent rules
- `NEXT.md` — active handoff
- `CHANGELOG.md` — closed work / CalVer notes
- `ROADMAP.md` — phase direction

`VERSION.md` is the compact SSOT for stack, version, and physical device state.

**Topic notes are issues, not files** (`documentation` label) — this repo keeps few documents on purpose:
[#7](https://github.com/junghan0611/homeagent-config/issues/7) 왜 이 작업을 하고 왜 공개하는가 ·
[#8](https://github.com/junghan0611/homeagent-config/issues/8) 제품화 구성 (이미지가 소유해야 하는 것) ·
[#9](https://github.com/junghan0611/homeagent-config/issues/9) RPi5+Yocto origin lane 세팅 가이드

## Core References

| Doc | Role | Read when |
|-----|------|-----------|
| [`../VERSION.md`](../VERSION.md) | stack / version / physical device matrix | checking current board/runtime state |
| [`../runtime/README.md`](../runtime/README.md) | RISC-V Linux + Zig state machine + C906L coprocessor architecture | the SG2000 runtime center (RISC-V C906 boot, L0–L4, C906 base) |
| [`BUILDROOT.md`](BUILDROOT.md) | SG2000/Duo S Buildroot experience + strategy (core lane) | building/flashing the Duo S image, either ISA lane (operational how-to in `../bsp/README.md`) |
| [`TARGET_DEVICE.md`](TARGET_DEVICE.md) | board and radio strategy details | SG2000 / SSD202D / EFR32 decisions |
| [`THP23-LIBERATION.md`](THP23-LIBERATION.md) | THP23-ZB-X liberation research (parked 128MB evidence) | reference for the parked 128MB lower-bound lane |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | ADRs and structure decisions | changing process/backend boundaries |
| [`API.md`](API.md) | REST/SSE API notes | changing clients or routes |
| [`BUILD.md`](BUILD.md) | **origin-lane** build workflow notes (RPi5/Android/Yocto) | origin-lane build/release tooling — not the SG2000 runtime build |
| [`MATTER.md`](MATTER.md) | Matter backend strategy | changing matter.js / commissioning paths |
| [`THREAD.md`](THREAD.md) | OTBR/RCP notes | changing Thread/RCP paths |
| [`EDGE-ZIGBEE.md`](EDGE-ZIGBEE.md) | hub ↔ edge/Zigbee boundary | touching ESP32/Zigbee/MQTT interfaces |
| [`YOCTO.md`](YOCTO.md) | Yocto offline-first recipe policy (origin lane, RPi5) | origin-lane Yocto recipe work |
| [`FLUTTER.md`](FLUTTER.md) | Flutter shell notes | client/origin-lane UI work |
| [`A2A.md`](A2A.md) | agent protocol notes | A2A work |
| [`A2UI.md`](A2UI.md) | server-driven UI notes | A2UI surface work |
| [`PLATFORM-MATRIX.md`](PLATFORM-MATRIX.md) | legacy platform comparison | origin-lane platform questions |
| [`MULTIPROTOCOL.md`](MULTIPROTOCOL.md) | **핵심 난제 SSOT — 단일 EFR32MG24로 Zigbee+Thread 동시** (Multi-PAN RCP + cpcd + zigbeed + otbr). 동일채널 vs Concurrent Listening 모드, HA 애드온 폐기·2-라디오 후퇴의 정직한 판정, SMHub 증명 게이트 G0~G4 | 단일 라디오 멀티프로토콜 설계/증명, MG24 재플래시(RCP), Zigbee+Thread 동시 재현 | 
| [`HUBS.md`](HUBS.md) | **인증 Zigbee/Matter 허브 랜드스케이프 SSOT** (조사 자료 — 우리 방향 아님; DIRIGERA 레인 폐기 2026-07-14) — 인증(CSA Matter)받고 자체 펌웨어/데몬을 올릴 수 있는 개방 허브 조사. IKEA DIRIGERA·Zemismart M1(인증 블랙박스 레퍼런스)·SMHub(SG2000 학습 앵커) 비교. Main SoC 동형 분석, Thread TBR vs z2m 경로, 오픈소스 클론 후보 | 허브 랜드스케이프 조사, Thread/TBR 개념 확인 |
| [`ECOSYSTEM-PORTFOLIO.md`](ECOSYSTEM-PORTFOLIO.md) | **홈오토메이션 스택 랜드스케이프** (조사 자료 — 채택 결정 아님). `HUBS.md`(하드웨어)의 짝. 층위 A⁰/A/A′/B/C, Buildroot 2025.02 패키지 실사(domoticz만 패키징됨), Zigbee 호스트 선택지 4개(Z2M·Z4D·자체·ser2net), domoticz·Zigbee for Domoticz 실사, 벤더 두 곳의 어댑터/앱-레지스트리 모델 | "512MB에 무엇을 얹고 무엇을 얹지 않나", Node를 빼는 경로 검토, 외부 플랫폼 연동 판단 |
| [`SMHUB.md`](SMHUB.md) | **SMHub Nano Mg24 single SSOT** — HW platform, radios, state model (backend.db/OpenRC/p7), live 0.9.8 verify log, control-boundary/reproduction matrix, info walls, vendor-manual review, open design questions, next verification steps | any SMHub product-verification / bring-up / config-set work (merges former PRODUCT-CONFIG-MODEL + SMHUB-CONTROL-MAP + SMHUB-MANUAL-REVIEW) |

## Current Direction

HomeAgent is a **minimal open hub BSP** project first — a reproducible verification/prototyping ground with **no business logic**. The core lane is **Milk-V Duo S (SG2000)**, booted on real silicon from our own Buildroot image (full-stack ownership). SG2000 carries both an A53 and a C906 on one die and a **physical slide switch** picks which boots: **RISC-V C906 remains the product ISA, but since 2026-07-23 the development lane is arm64/glibc** (Node 22 + Z2M build with no downstream patches; the RISC-V Node lane is parked pending upstream). Since **v2026.7.24** the arm64 image is flash-and-go. The runtime design — **Zig 100ms state machine on Linux + a C906L FreeRTOS mailbox coprocessor base** (see `../runtime/README.md`) — is unchanged; radio is a **USB ZBDongle-E**. **SMHUB Nano MG24** is the commercial reference (vendor OS, system-application approach, onboard EFR32MG24; single MG24 means Zigbee *or* Thread, exclusive). Tuya THP23-ZB-X is parked as 128MB lower-bound evidence. RPi5/Yocto/Hailo, OPi5, and Android/RK work remain preserved origin or compatibility evidence.
