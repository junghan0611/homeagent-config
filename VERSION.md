# HomeAgent Config - Version Matrix

Yocto/OpenEmbedded 및 Raspberry Pi 5 버전 호환성 정리

---

## Yocto 릴리스 선택: Scarthgap (5.0 LTS)

| 항목 | Scarthgap (5.0) | Styhead (5.1) | Whinlatter (5.3) |
|------|-----------------|---------------|------------------|
| **릴리스** | 2024년 4월 | 2024년 10월 | 2025년 12월 |
| **지원** | LTS (2028년 4월까지) | EOL | 6개월 (2026년 5월) |
| **Linux Kernel** | 6.6 LTS | 6.10 | (TBD) |
| **GCC** | 13.2 | 14.2 | - |
| **glibc** | 2.39 | 2.40 | - |
| **BitBake** | 2.8 | 2.10 | 2.16 |

**선택 이유**: Scarthgap은 LTS이며 Raspberry Pi OS와 동일한 6.6 LTS 커널 사용

---

## Raspberry Pi OS 비교

| 항목 | Raspberry Pi OS | Yocto Scarthgap |
|------|-----------------|-----------------|
| **Kernel** | 6.6 LTS (2024.03) → 6.12 LTS (2025.04) | 6.6 LTS |
| **Base** | Debian 12 Bookworm | Poky (OE-Core) |
| **GPU Driver** | Mesa (vc4/v3d) | Mesa (vc4/v3d) |
| **Display** | Wayland (labwc) / X11 | Wayland (Weston) |

**호환성**: 
- 커널 6.6 LTS 기준으로 드라이버/펌웨어 호환
- BCM2712 (RPi5 SoC) 지원 동일
- Mesa GPU 드라이버 동일

---

## meta-raspberrypi

| 항목 | 값 |
|------|-----|
| **브랜치** | scarthgap |
| **Machine** | raspberrypi5 |
| **SoC** | BCM2712 (Cortex-A76) |
| **Tune** | cortexa76 (armv8-2a) |
| **DTB** | bcm2712-rpi-5-b.dtb |
| **WiFi/BT FW** | bcm43455, bcm4345c0 |
| **GPU** | vc4-kms-v3d |

```
# conf/machine/raspberrypi5.conf
require conf/machine/include/arm/armv8-2a/tune-cortexa76.inc
MACHINE_FEATURES += "pci"
VC4DTBO ?= "vc4-kms-v3d"
```

---

## meta-openembedded (OTBR)

| 항목 | 값 |
|------|-----|
| **레시피** | ot-br-posix_git.bb |
| **버전** | 0.3.0+git |
| **SRCREV** | a35cc682305bb2201c314472adf06a4960536750 |
| **브랜치** | main (openthread/ot-br-posix) |

**의존성:**
- Build: autoconf-archive, dbus, avahi, jsoncpp, boost, protobuf
- Runtime: iproute2, ipset, avahi-daemon
- Systemd: otbr-agent.service

**알려진 이슈:**
- OTBR_WEB=ON 빌드 시 npm 타임아웃 (Web UI 비활성화 권장)
- RCP 펌웨어 버전 호환성 확인 필요

---

## meta-flutter-sony

| 항목 | 값 |
|------|-----|
| **브랜치** | kirkstone (scarthgap 미지원) |
| **Flutter Engine** | cb4b5fff73 (3.27.1 stable) |
| **백엔드** | Wayland, DRM-GBM, DRM-EGLStream |
| **의존성** | meta-clang |

**주의**: Sony 버전은 kirkstone 기준. Scarthgap 호환성 패치 필요할 수 있음.

**대안**: meta-flutter (커뮤니티 버전)
- 브랜치: scarthgap 지원
- RPi3/4/5 테스트됨
- ivi-homescreen 기반

---

## 커널 버전 타임라인

```
2024.03  Raspberry Pi OS → Kernel 6.6 LTS
2024.04  Yocto Scarthgap → Kernel 6.6 LTS
2024.10  Yocto Styhead   → Kernel 6.10
2025.04  Raspberry Pi OS → Kernel 6.12 LTS
2025.12  Yocto Whinlatter → (TBD)
```

**결론**: 
- Scarthgap (6.6 LTS)은 2024년 Raspberry Pi OS와 완벽 호환
- 2025년 이후 RPi OS가 6.12로 업그레이드되어도 6.6 LTS는 안정적

---

## 권장 구성

```
Yocto Branch: scarthgap (5.0 LTS)
├── poky                    : scarthgap
├── meta-openembedded       : scarthgap
├── meta-raspberrypi        : scarthgap
├── meta-clang              : scarthgap
└── meta-flutter            : scarthgap (커뮤니티) 또는 kirkstone (Sony + 패치)

Kernel: 6.6 LTS
Machine: raspberrypi5
Distro Features: systemd, wayland, opengl, ipv6
```

---

## 참고 링크

- [Yocto Releases](https://wiki.yoctoproject.org/wiki/Releases)
- [meta-raspberrypi](https://github.com/agherzan/meta-raspberrypi)
- [meta-openembedded](https://github.com/openembedded/meta-openembedded)
- [ot-br-posix recipe (scarthgap)](https://git.openembedded.org/meta-openembedded/tree/meta-networking/recipes-connectivity/openthread/ot-br-posix_git.bb?h=scarthgap)
- [Raspberry Pi OS Release Notes](https://www.raspberrypi.com/software/operating-systems/)
