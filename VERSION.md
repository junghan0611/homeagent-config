# HomeAgent — Stack / Device Matrix

`VERSION.md` is the single reference for stack versions, target boards, and physical device state. Keep it factual and compact.

---

## Target Strategy (2026-06-23)

| Axis | Current value |
|------|---------------|
| Main lane | **minimal open hub BSP + runtime stratification** |
| Host class | SOPHGO **SG2000** / Milk-V Duo S class |
| Big-core boot | **ARM Cortex-A53, fixed** (not RISC-V) |
| Runtime | **Zig 100ms `homeagentd` on Linux + C906 FreeRTOS mailbox coprocessor base** |
| Main candidate | **SMHUB Nano MG24** |
| Public BSP base | Milk-V Duo **Buildroot SDK v2** |
| RAM target | **512MB-class** for Z2M + MQTT + matter.js/Go measurement |
| Radio | **onboard EFR32/Gecko**, preferably MG24-class |
| Protocol | Zigbee NCP **or** Thread RCP by firmware switching |
| Parked evidence | Tuya THP23-ZB-X / SSD202D / 128MB lower-bound (not active) |
| Preserved lane | RPi5/Yocto/Hailo/RK evidence as high-spec origin |
| Architecture SSOT | `runtime/README.md` |

## Device Matrix

| Device | SoC | RAM | BSP / OS path | Radio | Role | State |
|--------|-----|-----|---------------|-------|------|-------|
| **Milk-V Duo S / SDK v2 family** | SOPHGO SG2000 (ARM A53 boot + C906 RTOS) | 512MB-class | `duo-buildroot-sdk-v2` | board-dependent | active BSP + runtime build board | ordered / pending |
| **SMHUB Nano MG24** | SOPHGO SG2000 (ARM A53 boot + C906 RTOS) | 512MB | vendor image unknown; use public SG2000 baseline first | EFR32MG24 | primary product-shaped minimal hub | ordered / pending |
| **Tuya THP23-ZB-X** | Sigmastar SSD202D | 128MB | linux-chenxing/OpenWrt/Buildroot research (parked) | EFR32/Gecko-class | parked 128MB lower-bound evidence (not active) | in hand |
| RPi5 + Hailo-8 | BCM2712 | 8GB | Yocto Scarthgap | USB EFR32 proof | high-spec origin | verified |
| OPi5 | RK3588S | 4GB | Yocto Scarthgap, mainline 6.14 | USB EFR32 proof | lab target | SSH/GPU/HDMI verified, NPU parked |
| RK3576 Android board | RK3576 | board-specific | Android 15 | ESP32-H2 proof | compatibility evidence | archived/secondary |

---

## Buildroot Baseline — SG2000

| Item | Value |
|------|-------|
| Public SDK | <https://github.com/milkv-duo/duo-buildroot-sdk-v2> (`develop`: linux 5.10 / u-boot 2021.10 / opensbi / fsbl / freertos) |
| Docs | <https://milkv.io/docs/duo/getting-started/buildroot-sdk> |
| SMHUB product reference | mainline kernel 6.18 / OpenSBI 1.8 / U-Boot 2026.04 / Buildroot 2025.11 — diff target (see `runtime/README.md`) |
| First proof | dev SDK (develop) ARM A53 image build, boot log, serial recovery |
| Second proof | minimal packages for MQTT / radio / Zigbee2MQTT / matter.js |
| Device facts | record here after hardware arrives |

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
| Final shape | onboard radio module |
| USB dongles | proof/origin tools only |
| Zigbee | NCP / EmberZNet-style path |
| Matter/Thread | RCP / OpenThread path |
| Concurrency | no Zigbee + Thread simultaneous assumption |

Known proof radios:

| Device | Chip | Role | Firmware | State |
|--------|------|------|----------|-------|
| SONOFF ZBDongle-E | EFR32MG21 | Thread RCP proof | `ot-rcp-v2.4.5.0-zbdonglee-460800.gbl` (baudrate 460800) | verified USB origin tool |
| SONOFF ZBDongle-E | EFR32MG21 | Zigbee NCP proof | EmberZNet (Sonoff Zigbee 3.0 USB Dongle Plus V2) | available proof path |
| SMHUB Nano MG24 | EFR32MG24 | target onboard radio | TBD after arrival | pending arrival |
| THP23-ZB-X | EFR32/Gecko-class | in-hand onboard radio to identify | TBD | in hand |

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
| Target Node.js | Node 20+ family; exact Buildroot package TBD |
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
