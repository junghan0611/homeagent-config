# HomeAgent

**Minimal open-source smart-home hub BSP.**

Buildroot · SG2000 (arm64 dev lane / RISC-V C906 product ISA) · Zig state machine · C906L FreeRTOS coprocessor · EFR32 radio · Zigbee · Matter · matter.js · Go · Yocto origin lane

**왜 이 작업을 하고 왜 공개하는가 → [#7](https://github.com/junghan0611/homeagent-config/issues/7)** (한글)

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Thesis

HomeAgent is being re-centered from a high-spec RPi5/Yocto/Hailo demo into a **minimal hub BSP** project — a reproducible **verification and prototyping ground** across several boards and dev environments. **No business logic lives here**; product logic stays in its own repos.

The work is not to invent a new Matter or Zigbee stack. Buildroot, Linux, Silicon Labs EFR32, Zigbee2MQTT, matter.js, Go, and Flutter already exist. The work here is the wiring:

> boot a small hub-class board with an open image, own the onboard radio, and document a reproducible path from BSP to Matter/Zigbee services.

On SG2000-class hardware the big core boots **either ISA by a physical slide switch** — a switch, not a fuse, so it is reversible. **RISC-V C906 (`riscv64-linux-musl`) remains the product ISA**, but since **2026-07-23 the development lane is arm64/glibc**, where Node 22 + Zigbee2MQTT build with no downstream patches; the RISC-V Node lane is **parked** pending upstream. As of **v2026.7.24** the arm64 image is *flash-and-go*: flash → switch → dongle brings Z2M up with no config edits, proven on a second board.

The runtime design — a **Zig 100ms hub state machine** on Linux plus a **C906L FreeRTOS coprocessor base** owning real-time pins over the SoC mailbox — is the public reconstruction of a hub state machine previously shipped as proprietary work: the architecture is open even though the production code is not. See [`runtime/README.md`](runtime/README.md), and [`NEXT.md`](NEXT.md) for the lane in flight.

RPi5 + Yocto + Hailo remains the **high-spec origin lane**: it proved matter.js, OTBR, Go controller, Flutter/Lit UI, Hailo/sLLM experiments, and recovery patterns. The current product-size hypothesis is smaller: **SG2000-class, 512MB, onboard EFR32**.

---

## Current Target

| Axis | Direction |
|------|-----------|
| Main lane | minimal hub BSP + runtime stratification |
| Host | SOPHGO SG2000 / Milk-V Duo S class |
| Big-core boot | **arm64/glibc = development lane** (2026-07-23~, flash-and-go since v2026.7.24); **RISC-V C906 = product ISA, parked** (upstream Node) |
| Runtime | **Zig 100ms state machine on Linux + C906L FreeRTOS mailbox coprocessor base** |
| Core board | **Milk-V Duo S** (SG2000, dual-ISA by slide switch, full-stack ownership) |
| Commercial reference | **SMHUB Nano MG24** (vendor OS, system-application approach) |
| BSP | Buildroot SDK lineage, **both ISA lanes** built in-repo (`bsp/`) |
| RAM target | 512MB-class for Z2M + MQTT + matter.js/Go evidence |
| Radio | Duo S = **USB ZBDongle-E** (EmberZNet 7.4.2); SMHub = onboard EFR32MG24 → **MG26 / Series 3** trajectory ([`docs/MULTIPROTOCOL.md`](docs/MULTIPROTOCOL.md)) |
| Protocol | Zigbee NCP **or** Thread RCP by firmware switching (single-chip concurrent = chip-timing question) |
| Parked evidence | Tuya THP23-ZB-X / SSD202D / 128MB lower-bound (not active) |

On the Duo S lane a USB coordinator (ZBDongle-E, version-aligned to the board) is the
working radio; onboard EFR32 stays the product shape (SMHub). Firmware:
[`firmware/zbdonglee/`](firmware/zbdonglee/). The runtime architecture lives in
[`runtime/README.md`](runtime/README.md).

---

## Product Direction — Certified Hubs & Radio Timing

**Thesis in one line:** hub certification and radio concurrency are tracked as **landscape research**,
not a product commitment. Single-chip **concurrent** Zigbee+Thread is not viable today (industry, Open
Home Foundation, and the vendor all use 2-radio or firmware mode-switch) — it is a **chip-timing
question** on the **MG21 → MG24 → MG26 → Series 3** line. So the current work is **separate-stack
control** (one radio, one protocol), not concurrency. *(The IKEA DIRIGERA "reproduce 1:1" lane is
**parked** as of 2026-07-14 — `docs/HUBS.md` stays landscape research, not our direction; the active
lanes are Duo S (arm64 dev / RISC-V product ISA) + SMHub reference.)*

**Where to look (recurring product-direction questions):**

| If you're asking… | Read |
|---|---|
| Which certified Zigbee/Matter hub? IKEA vs Zemismart vs SMHub | [`docs/HUBS.md`](docs/HUBS.md) |
| SoC comparison (SG2000 vs STM32MP157), MG21/24/26, PoE | [`docs/HUBS.md`](docs/HUBS.md) §2 |
| Thread TBR vs z2m, Matter over IP vs over Thread | [`docs/HUBS.md`](docs/HUBS.md) §3–4 |
| What devices/product line can the hub support? | [`docs/HUBS.md`](docs/HUBS.md) §7 |
| Single radio doing Zigbee + Thread at once — how / **when**? | [`docs/MULTIPROTOCOL.md`](docs/MULTIPROTOCOL.md) |
| Chip trajectory & when to flip to single-chip concurrent | [`docs/MULTIPROTOCOL.md`](docs/MULTIPROTOCOL.md) §3.7 |
| **Should a stack run on the hub, or should the hub only talk to it?** | [`docs/ECOSYSTEM-PORTFOLIO.md`](docs/ECOSYSTEM-PORTFOLIO.md) |
| Which home-automation host actually fits 512MB? (Buildroot survey) | [`docs/ECOSYSTEM-PORTFOLIO.md`](docs/ECOSYSTEM-PORTFOLIO.md) §3 |
| What does the Zigbee host cost — Z2M vs zigpy vs our own vs none? | [`docs/ECOSYSTEM-PORTFOLIO.md`](docs/ECOSYSTEM-PORTFOLIO.md) §4 · §6.2 |
| What does it cost to speak to Home Assistant / openHAB / Node-RED / …? | [`docs/INTEGRATION-SURFACE.md`](docs/INTEGRATION-SURFACE.md) |

---

## Living Document Set

| File | Role |
|------|------|
| [`AGENTS.md`](AGENTS.md) | week-stable agent rules |
| [`NEXT.md`](NEXT.md) | current handoff |
| [`CHANGELOG.md`](CHANGELOG.md) | closed work / CalVer notes |
| [`ROADMAP.md`](ROADMAP.md) | phase direction |
| [`VERSION.md`](VERSION.md) | stack, version, and physical device matrix |
| [`runtime/README.md`](runtime/README.md) | SG2000 runtime architecture + Zig/C906L code home |
| [`docs/TARGET_DEVICE.md`](docs/TARGET_DEVICE.md) | board/radio strategy details |
| [`docs/HUBS.md`](docs/HUBS.md) | certified Zigbee/Matter hub landscape research (DIRIGERA lane parked — not our direction), SoC/radio comparison, product line |
| [`docs/MULTIPROTOCOL.md`](docs/MULTIPROTOCOL.md) | single-radio Zigbee+Thread concurrency — strategy & timing (MG21/24/26 → Series 3) |
| [`docs/ECOSYSTEM-PORTFOLIO.md`](docs/ECOSYSTEM-PORTFOLIO.md) | home-automation stack landscape — what a 512MB hub can host, and what it should only talk to. The software half of `docs/HUBS.md` |
| [`docs/INTEGRATION-SURFACE.md`](docs/INTEGRATION-SURFACE.md) | the survey under it — all 36 SLZB integrations, transport axis and on-box cost (draft) |
| [`docs/README.md`](docs/README.md) | docs map |

Start with `NEXT.md` when continuing work.

**Topic notes live as issues, not files** (`documentation` label) — the repo keeps few documents on purpose:

| Issue | Topic |
|---|---|
| [#7](https://github.com/junghan0611/homeagent-config/issues/7) | 왜 이 작업을 하고 왜 공개하는가 — 메모리 세 겹, SBC 스펙 근거, 상태머신 축 |
| [#8](https://github.com/junghan0611/homeagent-config/issues/8) | 제품화 구성 — 이미지가 소유해야 하는 것, 남은 축 5개 |
| [#9](https://github.com/junghan0611/homeagent-config/issues/9) | RPi5 + Yocto **origin lane** 세팅 가이드 (재현 절차, 2026-04 기준) |

---

## Architecture Shape

```text
Minimal hub board (SG2000 / 512MB)
  ├─ Open Linux image (Buildroot lineage)
  ├─ MQTT / local service bus
  ├─ Zigbee2MQTT or matter.js service
  ├─ Go HomeAgent surface / bridge
  └─ onboard EFR32 radio
       ├─ Zigbee NCP firmware path
       └─ Thread RCP firmware path
```

High-spec origin lane:

```text
RPi5 / Yocto / Hailo
  ├─ matterjs-server + OTBR
  ├─ Go REST/SSE/A2A/A2UI surface
  ├─ Flutter / Lit UI experiments
  └─ Hailo/sLLM integration evidence
```

---

## Bring-up Checklist

For each minimal hub target:

- [ ] UART console and boot log
- [ ] U-Boot interruption or recovery path
- [ ] Open image build/flash path
- [ ] Rootfs and network access
- [ ] Onboard EFR32 device path
- [ ] Zigbee NCP proof with one paired device
- [ ] Thread RCP / matter.js proof when firmware/resources allow
- [ ] RSS/process evidence for MQTT, Z2M, matter.js, Go
- [ ] Power-cycle recovery notes

Until SMHUB Nano / Milk-V hardware arrives, SDK and document preparation are not blocked.

---

## Existing Commands

These still target the existing codebase and high-spec/origin tooling:

```bash
./run.sh go-build
./run.sh flutter-server
./run.sh flutter-run
./run.sh bundle
./run.sh diff
```

Treat RPi5 deploy and Yocto commands as origin-lane tools unless the task says otherwise.

---

## Project Layout

```text
homeagent-config/
├── runtime/                  # SG2000 runtime stratification (Linux + Zig state machine + C906L)
├── bsp/                      # Duo S board configs (arm64 dev + RISC-V lanes) + build/flash scripts
├── firmware/                 # radio coordinator firmware (ZBDongle-E, version-aligned)
├── go/                       # Go controller / hub surface (origin lane)
├── flutter/                  # Flutter client experiments (origin lane)
├── ui/                       # Lit frontend (origin lane)
├── scripts/                  # build/deploy helpers
├── yocto/                    # high-spec origin lane
├── deprecated/android-docker/ # archived compatibility path
├── docs/                     # strategy and implementation notes
├── AGENTS.md
├── README.md
├── NEXT.md
├── ROADMAP.md
├── CHANGELOG.md
└── VERSION.md
```

---

## Philosophy

- Privacy by default.
- Reproducible over impressive.
- Commodity parts named honestly.
- Own the boot path, rootfs, radio, and service lifecycle.
- Keep platform divergence explicit.
- **No display in the hub.** If a screen is needed, send a message to the web and let it draw (A2UI). Connectivity is the spec — not 4K, not a GPU.
- **Heavy inference is an API call.** The device declares "I am a hub" and turns a state machine, turn by turn.
- **A banner is not evidence.** Verify by filesystem UUID, not by "100% complete".
- **Nothing gets pushed in over ssh to make a product.** If it is not in the image, it is not in the product.

Full statement (한글): [#7](https://github.com/junghan0611/homeagent-config/issues/7) — *경계가 투명하지 않으면 재현성이 사라지고, 재현성이 사라지면 인간의 하루가 훌러덩 사라진다.*

---

## License

MIT
