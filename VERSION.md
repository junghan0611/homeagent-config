# HomeAgent — Stack / Device Matrix

`VERSION.md` is the single reference for stack versions, target boards, and physical device state. Keep it factual and compact.

---

## Target Strategy (2026-07-15)

| Axis | Current value |
|------|---------------|
| Main lane | **minimal open hub BSP + runtime stratification** (verification/prototyping ground, no business logic) |
| Host class | SOPHGO **SG2000** / Milk-V Duo S class |
| Big-core boot | **RISC-V C906** — booted on Duo S silicon (2026-07-14) |
| Runtime | **Zig 100ms `homeagentd` on Linux + C906L FreeRTOS mailbox coprocessor base** (target `riscv64-linux-musl`) |
| Core board | **Milk-V Duo S** (RISC-V, full-stack: own Buildroot → boot → rootfs → runtime) |
| Commercial reference | **SMHUB Nano MG24** (vendor SMHUB OS, system-application approach) |
| Public BSP base | Milk-V Duo **Buildroot SDK v2** → own RISC-V build in `bsp/` |
| RAM target | **512MB-class** for Z2M + MQTT + matter.js/Go measurement |
| Radio | Duo S = **USB ZBDongle-E** (EmberZNet 7.4.2); SMHub = onboard **EFR32MG24** |
| Protocol | Zigbee NCP **or** Thread RCP by firmware switching |
| Parked evidence | Tuya THP23-ZB-X / SSD202D / 128MB lower-bound (not active) |
| Preserved lane | RPi5/Yocto/Hailo/RK evidence as high-spec origin |
| Architecture SSOT | `runtime/README.md` |

## Device Matrix

| Device | SoC | RAM | BSP / OS path | Radio | Role | State |
|--------|-----|-----|---------------|-------|------|-------|
| **Milk-V Duo S / SDK v2 family** | SOPHGO SG2000 (RISC-V C906 boot + C906L RTOS) | 512MB (323MB usable pre-ION-reclaim) | own `bsp/` RISC-V Buildroot (SDK v2 lineage) | USB ZBDongle-E | **core lane** — full-stack build board | **in hand, RISC-V boot verified 2026-07-14** |
| **SMHUB Nano MG24** | SOPHGO SG2000 (RISC-V C906 boot + C906L RTOS) | 512MB / 8GB eMMC | vendor SMHUB OS (mainline 6.18 + RAUC A/B); system-app approach | onboard EFR32MG24 (ember, EmberZNet 7.4.2 / EZSP 13) | commercial reference | **in hand, OTA beta5 verified** |
| **Tuya THP23-ZB-X** | Sigmastar SSD202D | 128MB | linux-chenxing/OpenWrt/Buildroot research (parked) | EFR32/Gecko-class | parked 128MB lower-bound evidence (not active) | in hand |
| RPi5 + Hailo-8 | BCM2712 | 8GB | Yocto Scarthgap | USB EFR32 proof | high-spec origin | verified |
| OPi5 | RK3588S | 4GB | Yocto Scarthgap, mainline 6.14 | USB EFR32 proof | lab target | SSH/GPU/HDMI verified, NPU parked |
| RK3576 Android board | RK3576 | board-specific | Android 15 | ESP32-H2 proof | compatibility evidence | archived/secondary |

---

## Buildroot Baseline — SG2000

| Item | Value |
|------|-------|
| Public SDK | <https://github.com/junghan0611/duo-buildroot-sdk-v2> `feat/riscv64-nodejs-pure-cross` @ `087547cf8` (upstream `ad920f839`; linux 5.10 / u-boot 2021.10 / opensbi / fsbl / freertos) |
| Docs | <https://milkv.io/docs/duo/getting-started/buildroot-sdk> |
| SMHUB product reference | mainline kernel 6.18 / OpenSBI 1.8 / U-Boot 2026.04 / Buildroot 2025.11 — diff target (see `runtime/README.md`) |
| First proof | **done (2026-07-14)** — own RISC-V C906 image (`riscv64-musl`), booted on silicon, eth0 DHCP + Wi-Fi (aic8800) |
| Second proof | **current** — native-musl Node 22.22.0 → MQTT / Zigbee2MQTT |
| Device facts | Duo S live boot: `Linux milkv-duo 5.10.4 riscv64`, `isa: rv64imafdvcsu`, eMMC 7.3G (p4 rootfs 768M) — see `captures/` |

Policy:

- Start from the public SDK before diffing any commercial image.
- Treat vendor images as observation inputs, not final artifacts.
- Capture RSS/process evidence before making memory claims.

---

## Radio Strategy

| Item | Value |
|------|-------|
| Chip family | Silicon Labs EFR32/Gecko |
| Preferred class | EFR32MG24 for flash/RAM headroom |
| Existing proof | SONOFF ZBDongle-E / EFR32MG21 |
| Duo S radio | **USB ZBDongle-E**, flashed to match board (EmberZNet 7.4.2 / EZSP 13) — `firmware/zbdonglee/` |
| Final product shape | onboard radio module (SMHub EFR32MG24) |
| Zigbee | NCP / EmberZNet-style path |
| Matter/Thread | RCP / OpenThread path |
| Concurrency | no Zigbee + Thread simultaneous assumption |

Known proof radios:

| Device | Chip | Role | Firmware | State |
|--------|------|------|----------|-------|
| SONOFF ZBDongle-E | EFR32MG21 | Zigbee NCP (Duo S lane) | `zbdonglee_zigbee_ncp_7.4.2.0_hw_flow_115200.gbl` (EmberZNet 7.4.2 / EZSP 13, 115200, `rtscts:false`) | in-repo `firmware/zbdonglee/`, board-aligned |
| SONOFF ZBDongle-E | EFR32MG21 | Zigbee NCP (newer) | `zbdonglee_zigbee_ncp_8.0.3.0_sw_flow_115200.gbl` | in-repo `firmware/zbdonglee/` |
| SONOFF ZBDongle-E | EFR32MG21 | Thread RCP | `zbdonglee_openthread_rcp_2.5.3.0_no_flow_460800.gbl` (460800) | in-repo `firmware/zbdonglee/` |
| SMHUB Nano MG24 | EFR32MG24 | onboard coordinator | ember, EmberZNet **7.4.2 [GA]** / EZSP 13 (live verified) | in hand |
| THP23-ZB-X | EFR32/Gecko-class | parked onboard radio | TBD | in hand (parked) |

Firmware files are part of the firmware-switching record; keep exact filenames and baudrates here, not just generic stack names.

---

## Physical State — Origin Lane

### RPi5

| Item | Value |
|------|-------|
| Model | Raspberry Pi 5 Model B Rev 1.0 |
| RAM | 8GB |
| Kernel | 6.6.63-v8-16k aarch64 (Yocto origin image) |
| OS | Yocto Scarthgap / OpenEmbedded |
| SSH | `./run.sh ssh` or `.current-device-ip` |
| Thread proof | SONOFF ZBDongle-E on `/dev/ttyUSB0`, CP210x `10c4:ea60` |
| Spinel | `spinel+hdlc+uart:///dev/ttyUSB0?uart-baudrate=460800` |
| OTBR backbone | `eth1` = USB-ethernet (ASIX AX88772A); set backbone iface to the actually-UP internet link (`ip -br addr`) |
| Power note | insufficient USB power → CP210x timeout; use an adequate PSU and a USB3 port for the dongle |
| Services proven | otbr-agent, avahi, dbus, matterjs-server, Go surface |
| Role | high-spec origin lane |

### OPi5

| Item | Value |
|------|-------|
| Model | Orange Pi 5 v1.3.2 |
| SoC | RK3588S |
| RAM | 4GB LPDDR4X |
| Kernel | linux-yocto-dev **6.14** mainline |
| OS | Yocto Scarthgap / OpenEmbedded |
| SSH | `./run.sh ssh opi5` or `.current-device-ip.opi5` |
| GPU | panthor/panfrost verified |
| Display | HDMI 3840x2160@30Hz verified |
| NPU | vendor 6.1 RKNN path parked |
| Role | lab target only |

OPi5 policy: keep the mainline 6.14 SSH/GPU/HDMI evidence. Do not revive vendor 6.1/RKNN unless explicitly requested.

---

## Matter / Runtime Stack

| Component | State |
|-----------|-------|
| matterjs-server | 0.3.5 in origin lane |
| @matter/main | 0.16.9-alpha in origin lane |
| Target Node.js | **22.22.0**, riscv64-musl, Buildroot image-baked; pure-cross package support pinned in SDK fork |
| DevShell Node.js | Node 22, local development only |
| Go | hub surface / bridge |
| Flutter / Lit | client/origin lane, not BSP center |
| OTBR | proven in Yocto origin lane; minimal hub path TBD |

Policy:

- Linux + matter.js remains the preferred Matter backend direction.
- python-matter-server / Android Docker is deprecated reference under `deprecated/android-docker/`.
- devShell versions do not define target runtime versions.

---

## Deprecated / Parked

| Path | State |
|------|-------|
| Android Docker / python-matter-server | deprecated reference |
| RK3576 server deployment | compatibility evidence |
| OPi5 vendor 6.1 RKNN | parked |
| New high-spec board shopping | deferred |
| USB-only coordinator productization | not a target |

---

## References

- Milk-V Duo Buildroot SDK v2: <https://github.com/milkv-duo/duo-buildroot-sdk-v2>
- Milk-V Buildroot docs: <https://milkv.io/docs/duo/getting-started/buildroot-sdk>
- matter.js: <https://github.com/project-chip/matter.js>
- Zigbee2MQTT: <https://github.com/Koenkk/zigbee2mqtt>
- Yocto releases: <https://wiki.yoctoproject.org/wiki/Releases>
- meta-raspberrypi: <https://github.com/agherzan/meta-raspberrypi>
- meta-hailo: <https://github.com/hailo-ai/meta-hailo>
