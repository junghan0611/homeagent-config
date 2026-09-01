# Target Device Strategy — Minimal Open Hub BSP

이 문서는 HomeAgent의 **현재 보드/라디오 전략**이다. 예전 Hailo/RK 보드 탐색 메모가 아니라, 지금 작업의 기준점이다.

HomeAgent의 중심은 RPi5 풀스택에서 **미니멀 허브 BSP**로 이동했다. RPi5/Yocto/Hailo는 origin/high-spec lane으로 보존하고, 현재 코어 레인은 **Milk-V Duo S (SG2000, RISC-V C906) 풀스택 소유**다. SMHub Nano(온보드 EFR32MG24)는 상용 레퍼런스로 비교하고, Duo S는 온보드 라디오가 없어 **USB ZBDongle-E**로 Zigbee/Matter를 붙인다.

---

## Decision

| Axis | Decision |
|------|----------|
| Core lane | **Milk-V Duo S (SOPHGO SG2000, RISC-V C906)** — own Buildroot build, full-stack |
| Commercial reference | **SMHUB Nano MG24** — vendor SMHUB OS, system-application approach |
| **Big-core boot mode** | **RISC-V C906** — booted on Duo S silicon (2026-07-14); see [`../runtime/README.md`](../runtime/README.md) |
| Public BSP reference | **Milk-V Duo Buildroot SDK v2** (`milkv-duo/duo-buildroot-sdk-v2`) → own RISC-V build in `../bsp/` |
| Minimum RAM class | **512MB** for Zigbee2MQTT + MQTT + matter.js/Go experiments — **이 값은 Node를 전제로 한다**. Node를 빼면 256MB(Duo 256M/SG2002)가 후보로 열린다(아래 절) |
| Radio | Duo S = **USB ZBDongle-E** (EmberZNet 7.4.2); SMHub = onboard EFR32MG24 |
| Protocol posture | Zigbee NCP **or** Thread RCP by firmware switching; no concurrent assumption |
| USB coordinator | Duo S working radio (no onboard MG24); dev/proto, not the final product radio |
| Parked evidence board | Tuya THP23-ZB-X / SSD202D / 128MB — 128MB lower-bound evidence only, **not active** |

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
| **Milk-V Duo S / SDK v2 family** | **SOPHGO SG2000** | C906 (RISC-V boot) + C906L RTOS coprocessor | 512MB-class | USB ZBDongle-E | **core lane** — full-stack build board | in hand, RISC-V boot verified 2026-07-14 |
| **SMHUB Nano MG24** | **SOPHGO SG2000** | C906 (RISC-V boot) + C906L RTOS coprocessor | **512MB / 8GB eMMC** | **onboard EFR32MG24** | commercial reference (vendor OS) | in hand, OTA beta5 verified |
| **Milk-V Duo 256M** | **SOPHGO SG2002** | CA53 (ARM) + C906 lanes, 둘 다 SDK에 있음 | **256MB / microSD only** | USB dongle (**온보드 WiFi 없음**) | **Node를 빼면 열리는 후보** (GLG 2026-09-01) | 미보유 · SDK 보드정의 실재 |
| **Tuya THP23-ZB-X** | **Sigmastar SSD202D** | dual Cortex-A7, 32-bit | **128MB / SPI NAND** | EFR32/Gecko-class | parked 128MB lower-bound evidence (not active) | in hand |
| RPi5 + Hailo-8 | BCM2712 | 4×A76 | 8GB | USB EFR32 proof | high-spec origin | verified |
| OPi5 | RK3588S | 4×A76 + 4×A55 | 4GB | USB EFR32 proof | lab target | SSH/GPU verified |

---

## Why SG2000-class?

SG2000 is a practical middle point for a small hub:

1. **512MB RAM** — enough room to test Zigbee2MQTT, MQTT, matter.js, and a small Go bridge without pretending a 128MB ceiling is enough.
2. **64-bit RISC-V** — the big core is booted in **RISC-V C906 mode** (`riscv64-linux-musl`), matching the product / SMHub ISA; the riscv64 toolchain and package maturity measured on the way *is* the portfolio content. The other C906L RISC-V small core stays the real-time / always-on coprocessor layer. (ARM A53 boot is available and kept only as a historical comparison build.) See [`../runtime/README.md`](../runtime/README.md).
3. **Public SDK path** — Milk-V Duo Buildroot SDK v2 gives a starting point even if a commercial hub ships a different private image.
4. **Hub-shaped I/O** — Ethernet/PoE/WiFi/eMMC-class integration is closer to a product hub than a loose dev-board stack.

---

## 256MB 후보 — Milk-V Duo 256M (SG2002), Node를 뺀 다음의 자리

> **GLG 2026-09-01**: *"nodejs가 필요 없어지면 Milk-V Duo 버전으로 갈 수도 있어. 256MB짜리
> 제품이고 SG2002 코어 들어간 거야."* — 조건부 후보다. 지금 옮기는 것이 아니라, **Node를
> 빼는 작업(`docs/ECOSYSTEM-PORTFOLIO.md` §4)이 성공하면 열리는 문**이다.

### SDK가 이미 아는 보드다 [측정, `duo-buildroot-sdk-v2`]

```
device/milkv-duo256m-glibc-arm64-sd/     ← ARM A53 레인
device/milkv-duo256m-musl-riscv64-sd/    ← RISC-V 레인
build/boards/cv181x/sg2002_milkv_duo256m_glibc_arm64_sd/
    config.json → "board_information": "CA53 + DDR 256MB"
```

Duo S와 **같은 SDK, 같은 cv181x 계열**이라 보드 브링업이 새 레인이 아니다. ISA 두 축도
그대로 있다.

### 진짜 숫자 — 256MB는 256MB가 아니다 [측정, `memmap.py`]

| | Duo S (SG2000) | **Duo 256M (SG2002)** |
|---|---|---|
| `DRAM_SIZE` | 512M | **256M** |
| `FREERTOS_SIZE` | 2M | 2M |
| **`ION_SIZE`** | **170M** | **75M** |
| Linux에 남는 것 | 512 − 2 − 170 = **340M** | 256 − 2 − 75 = **179M** |
| 실측 `MemTotal` | **311M** (커널 오버헤드 후) | 미측정 — 위 비율로는 **~165M** 추정 |

**그리고 여기 레버가 하나 있다.** `ION`은 카메라/비디오 파이프라인 몫이다 — 같은 파일에서
`H26X_BITSTREAM_SIZE = 2M`, `ISP_MEM_BASE_SIZE = 20M`이 그 안에 예약된다. **헤드리스 허브는
ISP도 H.264 인코더도 쓰지 않는다.** 즉 Duo S의 170M도, Duo 256M의 75M도 대부분 우리에겐
버리는 값이다. `ION_SIZE`를 줄이는 것은 **우리가 소유한 보드 설정 파일 한 줄**이고, 그것만으로
Duo 256M의 가용 RAM이 크게 달라진다. **아직 시도 안 했다.**

### 옮기기 전에 알아야 할 두 가지 차이 [측정]

1. **eMMC 변형이 없다.** SDK 보드 정의가 `-sd` 둘뿐이다(Duo S는 `-emmc`/`-sd` 넷).
   → `bsp/flash-emmc.sh` 경로와 eMMC CID 기반 `stable-mac`의 씨앗이 **그대로 적용되지 않는다.**
2. **온보드 WiFi가 없다.** [측정] `dts_arm64/*.dts`에서 `aic8800|wifi|sdio` 매치가
   **Duo 256M = 0건**, Duo S = 3건. → `S99wpa_supplicant`·`hostapd`·`wlan0` stable-MAC 등
   현재 RAIL의 WiFi 소유권 논의는 이 보드에서 **주제 자체가 사라진다**(대신 USB WiFi 또는
   유선 전용 결정이 필요해진다).

### 판정

**지금 옮기지 않는다.** 선행조건이 Node 제거이고 그건 아직 조사 단계다
(`docs/ECOSYSTEM-PORTFOLIO.md`). 다만 **이 문서의 "Minimum RAM class = 512MB"는 Node를
전제로 한 값**이라는 것을 여기 적어 둔다 — 전제가 바뀌면 그 줄도 바뀐다.

## 128MB Ceiling — THP23-ZB-X (parked)

Tuya THP23-ZB-X is in hand, but it is **no longer the active bring-up lane**. It is kept only as **128MB lower-bound evidence**: proof of how far an open Linux hub *can* be liberated at the bottom of the spec range. Active Tuya liberation work is parked; the runtime lane is SG2000-class (Milk-V Duo S / SMHUB Nano MG24) on the RISC-V C906 boot lane.

| Item | Implication |
|------|-------------|
| 128MB RAM | Good for bootloader, kernel, BusyBox/OpenWrt-style base, small daemons. Tight for Node/matter.js + Z2M. |
| SSD202D / ARMv7 | Mature 32-bit Linux path, but old userland constraints. |
| Onboard EFR32 | Excellent for radio discovery and firmware/control experiments. |
| Closed default firmware | Useful as a liberation target, not as an endpoint. |

Expected outcome:

- If it ever boots open Linux and exposes the radio, that stands as the **128MB lower-bound evidence**. See [`THP23-LIBERATION.md`](THP23-LIBERATION.md) for the parked bring-up plan.
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

USB dongles are the working radio on the Duo S dev lane (no onboard MG24), version-aligned to the SMHub board (EmberZNet 7.4.2 / EZSP 13). The **product** target is **onboard EFR32** (SMHub); a shipped hub should not require a dangling USB coordinator.

### Product-shaped candidates

| Product | Host | Radio | Notes |
|---------|------|-------|-------|
| **SMHUB Nano MG24** | SG2000 | EFR32MG24 | primary target, 512MB-class |
| THP23-ZB-X | SSD202D | EFR32/Gecko-class | parked 128MB lower-bound evidence (not active) |
| SONOFF Dongle Plus MG24 | none | EFR32MG24 | good proof coordinator, USB only |
| Home Assistant Connect ZBT-2 | bridge MCU | EFR32MG24 | proof/reference coordinator |
| SLZB-MR3 | coordinator box | multi-radio | useful reference, not the integrated hub target |

---

## Buildroot / BSP Path

BSP base: **`milkv-duo/duo-buildroot-sdk-v2`, `develop` branch** (full boot chain in one
tree — fsbl/opensbi/u-boot-2021.10/linux_5.10/ramdisk/freertos). The dev-SDK-vs-SMHUB
version diff and methodology live in [`../runtime/README.md`](../runtime/README.md).

Public reference:

- <https://github.com/milkv-duo/duo-buildroot-sdk-v2> (`develop`)
- <https://milkv.io/docs/duo/getting-started/buildroot-sdk>

Initial BSP goals:

1. Build our RISC-V C906 image for Duo S from the dev SDK lineage, bootloader up. **(done 2026-07-14)**
2. Confirm boot log, kernel version, rootfs layout, package manager story, and serial recovery.
3. Diff against the SMHUB Nano product (mainline kernel 6.18 / OpenSBI 1.8 / U-Boot 2026.04 / Buildroot 2025.11) to learn product tuning — only after the dev SDK baseline is understood.
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
