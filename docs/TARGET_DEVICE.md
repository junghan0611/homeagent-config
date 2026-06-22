# Target Device Strategy — Minimal Open Hub BSP

이 문서는 HomeAgent의 **현재 보드/라디오 전략**이다. 예전 Hailo/RK 보드 탐색 메모가 아니라, 지금 작업의 기준점이다.

HomeAgent의 중심은 RPi5 풀스택에서 **미니멀 허브 BSP**로 이동했다. RPi5/Yocto/Hailo는 origin/high-spec lane으로 보존하고, 제품 크기의 현재 가설은 SG2000 + 온보드 EFR32 라디오다.

---

## Decision

| Axis | Decision |
|------|----------|
| Main target | **SMHUB Nano MG24 / SOPHGO SG2000 class** |
| Public BSP reference | **Milk-V Duo Buildroot SDK v2** (`milkv-duo/duo-buildroot-sdk-v2`) |
| Minimum RAM class | **512MB** for Zigbee2MQTT + MQTT + matter.js/Go experiments |
| Radio | **Onboard Silicon Labs EFR32/Gecko**, preferably MG24-class |
| Protocol posture | Zigbee NCP **or** Thread RCP by firmware switching; no concurrent assumption |
| USB coordinator | Proof/origin tool only, not final product shape |
| In-hand liberation target | Tuya THP23-ZB-X / SSD202D / 128MB, current bring-up + 128MB ceiling evidence |

---

## Tier Model

| Tier | Name | What it means | Status |
|------|------|---------------|--------|
| **Tier 2** | **Minimal hub lane** | 512MB-class Buildroot/OpenWrt Linux, onboard EFR32, low BOM/power | **current mainline** |
| **Tier 1** | **High-spec origin lane** | RPi5/RK/Yocto/Hailo/Flutter full stack used to prove protocol/UI/AI pieces | preserved reference |

Tier numbering is only a lane label. The current work optimizes Tier 2 first.

---

## Board Candidates

| Board | SoC | CPU | RAM / storage | Radio | Role | Status |
|------|-----|-----|---------------|-------|------|--------|
| **SMHUB Nano MG24** | **SOPHGO SG2000** | C906 RISC-V + Cortex-A53 selectable | **512MB / 8GB eMMC** | **EFR32MG24** | primary minimal hub | delivery pending |
| **Milk-V Duo S / SDK v2 family** | **SOPHGO SG2000** | C906 RISC-V + Cortex-A53 selectable | 512MB-class | board-dependent | public BSP reference / dev board | delivery pending |
| **Tuya THP23-ZB-X** | **Sigmastar SSD202D** | dual Cortex-A7, 32-bit | **128MB / SPI NAND** | EFR32/Gecko-class | current liberation target / 128MB ceiling evidence | in hand |
| RPi5 + Hailo-8 | BCM2712 | 4×A76 | 8GB | USB EFR32 proof | high-spec origin | verified |
| OPi5 | RK3588S | 4×A76 + 4×A55 | 4GB | USB EFR32 proof | lab target | SSH/GPU verified |

---

## Why SG2000-class?

SG2000 is a practical middle point for a small hub:

1. **512MB RAM** — enough room to test Zigbee2MQTT, MQTT, matter.js, and a small Go bridge without pretending a 128MB ceiling is enough.
2. **64-bit capable** — RISC-V or ARM A53 boot modes make newer Linux/userland paths less awkward than ARMv7-only parts.
3. **Public SDK path** — Milk-V Duo Buildroot SDK v2 gives a starting point even if a commercial hub ships a different private image.
4. **Hub-shaped I/O** — Ethernet/PoE/WiFi/eMMC-class integration is closer to a product hub than a loose dev-board stack.

---

## 128MB Ceiling — THP23-ZB-X

Tuya THP23-ZB-X is the current in-hand liberation target: it is the board we own and bring up *before* the SMHUB-class hubs arrive. SMHUB-class (SG2000 / 512MB) remains the product-size center, but THP23-ZB-X is where the actual open-source bring-up work happens now.

| Item | Implication |
|------|-------------|
| 128MB RAM | Good for bootloader, kernel, BusyBox/OpenWrt-style base, small daemons. Tight for Node/matter.js + Z2M. |
| SSD202D / ARMv7 | Mature 32-bit Linux path, but old userland constraints. |
| Onboard EFR32 | Excellent for radio discovery and firmware/control experiments. |
| Closed default firmware | Useful as a liberation target, not as an endpoint. |

Expected outcome:

- If it boots open Linux and exposes the radio, it is a success as the **current in-hand liberation target**. See [`THP23-LIBERATION.md`](THP23-LIBERATION.md) for the bring-up plan.
- If matter.js/Zigbee2MQTT do not fit comfortably, that confirms the 512MB lower-bound target rather than invalidating the project.

---

## Radio Coordinator — Zigbee/Matter

### Decision: EFR32/Gecko family

- Use **one radio, one protocol at a time**.
- Switch protocol by flashing firmware:
  - Zigbee NCP / EmberZNet path
  - Thread RCP / OpenThread path
- Do not assume stable multi-protocol concurrent Zigbee + Thread on one chip.
- Prefer MG24-class flash/RAM headroom for new hardware.

### Proof hardware already used

| Device | Chip | Role | Status |
|--------|------|------|--------|
| SONOFF ZBDongle-E | EFR32MG21 | Thread RCP proof | verified as USB origin tool |
| SONOFF ZBDongle-E | EFR32MG21 | Zigbee NCP proof | available proof path |

USB dongles are still useful for firmware and protocol proof. The current target is **onboard EFR32**, not a product that requires a dangling USB coordinator.

### Product-shaped candidates

| Product | Host | Radio | Notes |
|---------|------|-------|-------|
| **SMHUB Nano MG24** | SG2000 | EFR32MG24 | primary target, 512MB-class |
| THP23-ZB-X | SSD202D | EFR32/Gecko-class | current liberation target, 128MB ceiling |
| SONOFF Dongle Plus MG24 | none | EFR32MG24 | good proof coordinator, USB only |
| Home Assistant Connect ZBT-2 | bridge MCU | EFR32MG24 | proof/reference coordinator |
| SLZB-MR3 | coordinator box | multi-radio | useful reference, not the integrated hub target |

---

## Buildroot / BSP Path

Public reference:

- <https://github.com/milkv-duo/duo-buildroot-sdk-v2>
- <https://milkv.io/docs/duo/getting-started/buildroot-sdk>

Initial BSP goals:

1. Build a stock SDK image for the closest SG2000 board.
2. Confirm boot log, kernel version, rootfs layout, package manager story, and serial recovery.
3. Diff SMHUB image behavior only after the public SDK baseline is understood.
4. Add only the minimum packages needed for radio and service proof.
5. Keep board-specific facts in `VERSION.md` once physical devices arrive.

---

## Bring-up Checklist

### Common

- [ ] Photograph / record board revision and connector orientation
- [ ] UART pins confirmed
- [ ] Serial console captured from power-on
- [ ] U-Boot interruption or recovery mode confirmed
- [ ] Open image build or flash path documented
- [ ] Root login / shell / filesystem access confirmed
- [ ] Kernel config and device tree captured
- [ ] Network interface up

### Radio

- [ ] Onboard EFR32 appears as UART/SPI/USB/other Linux device
- [ ] Reset/bootloader pin control understood
- [ ] Current firmware identified when possible
- [ ] Zigbee NCP firmware path tested
- [ ] Thread RCP firmware path tested when available
- [ ] One Zigbee device pairs through Zigbee2MQTT
- [ ] One Matter/Thread commissioning flow tested through matter.js/OTBR if resources allow

### Resource lower-bound

- [ ] Idle RSS/process list captured
- [ ] MQTT broker RSS captured
- [ ] Zigbee2MQTT RSS captured
- [ ] matter.js RSS captured
- [ ] Go HomeAgent RSS captured
- [ ] Reboot recovery tested

---

## High-spec Origin Lane

Keep these as proven references, not current product center:

| Item | Status |
|------|--------|
| RPi5 + Yocto Scarthgap | verified origin build lane |
| Hailo-8 | driver/runtime/model integration evidence |
| OPi5 mainline 6.14 | lab target, SSH/GPU verified, NPU parked |
| RK3576/Android path | compatibility evidence, archived/secondary |
| USB EFR32 coordinators | proof tools for firmware/protocol flows |

When a new minimal-hub feature is ambiguous, prove it first in the smallest lane that can carry it. Escalate to Tier 1 only when the feature genuinely needs the larger system.
