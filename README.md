# HomeAgent

**Minimal open-source smart-home hub BSP.**

Buildroot · SG2000 (RISC-V C906) · Zig state machine · C906L FreeRTOS coprocessor · EFR32 radio · Zigbee · Matter · matter.js · Go · Yocto origin lane

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Thesis

HomeAgent is being re-centered from a high-spec RPi5/Yocto/Hailo demo into a **minimal hub BSP** project — a reproducible **verification and prototyping ground** across several boards and dev environments. **No business logic lives here**; product logic stays in its own repos.

The work is not to invent a new Matter or Zigbee stack. Buildroot, Linux, Silicon Labs EFR32, Zigbee2MQTT, matter.js, Go, and Flutter already exist. The work here is the wiring:

> boot a small hub-class board with an open image, own the onboard radio, and document a reproducible path from BSP to Matter/Zigbee services.

On SG2000-class hardware the big core is booted in **RISC-V C906 mode** (`riscv64-linux-musl`), with a **Zig 100ms hub state machine** on Linux and a **C906L FreeRTOS coprocessor base** owning the real-time pins over the SoC mailbox. This is the public reconstruction of a hub state machine that was previously shipped as proprietary work — the architecture is open even though the production code is not. See [`runtime/README.md`](runtime/README.md).

RPi5 + Yocto + Hailo remains the **high-spec origin lane**: it proved matter.js, OTBR, Go controller, Flutter/Lit UI, Hailo/sLLM experiments, and recovery patterns. The current product-size hypothesis is smaller: **SG2000-class, 512MB, onboard EFR32**.

---

## Current Target

| Axis | Direction |
|------|-----------|
| Main lane | minimal hub BSP + runtime stratification |
| Host | SOPHGO SG2000 / Milk-V Duo S class |
| Big-core boot | **RISC-V C906** — booted on Duo S silicon (2026-07-14) |
| Runtime | **Zig 100ms state machine on Linux + C906L FreeRTOS mailbox coprocessor base** |
| Core board | **Milk-V Duo S** (SG2000, RISC-V, full-stack ownership) |
| Commercial reference | **SMHUB Nano MG24** (vendor OS, system-application approach) |
| BSP | Buildroot SDK lineage, own RISC-V build in-repo (`bsp/`) |
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
lanes are Duo S RISC-V + SMHub reference.)*

**Where to look (recurring product-direction questions):**

| If you're asking… | Read |
|---|---|
| Which certified Zigbee/Matter hub? IKEA vs Zemismart vs SMHub | [`docs/HUBS.md`](docs/HUBS.md) |
| SoC comparison (SG2000 vs STM32MP157), MG21/24/26, PoE | [`docs/HUBS.md`](docs/HUBS.md) §2 |
| Thread TBR vs z2m, Matter over IP vs over Thread | [`docs/HUBS.md`](docs/HUBS.md) §3–4 |
| What devices/product line can the hub support? | [`docs/HUBS.md`](docs/HUBS.md) §7 |
| Single radio doing Zigbee + Thread at once — how / **when**? | [`docs/MULTIPROTOCOL.md`](docs/MULTIPROTOCOL.md) |
| Chip trajectory & when to flip to single-chip concurrent | [`docs/MULTIPROTOCOL.md`](docs/MULTIPROTOCOL.md) §3.7 |

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
| [`docs/README.md`](docs/README.md) | docs map |

Start with `NEXT.md` when continuing work.

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
├── runtime/                  # SG2000 runtime stratification (main lane: RISC-V Linux + Zig + C906L)
├── bsp/                      # Duo S RISC-V board configs + build/flash scripts
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

---

## License

MIT
