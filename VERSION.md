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

### Option A: Hailo-8/8L (scarthgap LTS)

```
Yocto Branch: scarthgap (5.0 LTS)
├── poky                    : scarthgap
├── meta-openembedded       : scarthgap
├── meta-raspberrypi        : scarthgap
├── meta-clang              : scarthgap
├── meta-hailo              : hailo8-scarthgap
│   └── HailoRT 4.23.0, TAPPAS 5.1.0
└── meta-flutter            : scarthgap (커뮤니티)

Kernel: 6.6 LTS | Machine: raspberrypi5
```

### Option B: Hailo-10H GenAI (kirkstone)

```
Yocto Branch: kirkstone (4.0)
├── poky                    : kirkstone
├── meta-openembedded       : kirkstone
├── meta-raspberrypi        : kirkstone (RPi5 지원 ✅)
├── meta-clang              : kirkstone
├── meta-hailo              : kirkstone-v5.2.0
│   └── HailoRT 5.2.0, TAPPAS 5.2.0, GenAI ✅
└── meta-flutter            : kirkstone (Sony)

Kernel: 6.1 | Machine: raspberrypi5
```

**선택 기준:**
- Vision AI만 필요 → **Option A** (LTS, 안정적)
- GenAI (LLM/VLM/Voice) 필요 → **Option B** (Hailo-10H 필수)

---

## Hailo AI 가속기

### 지원 모델

| 모델 | 성능 | 인터페이스 | 용도 |
|------|------|-----------|------|
| **Hailo-8** | 26 TOPS (INT8) | M.2 / PCIe | AI HAT+ |
| **Hailo-8L** | 13 TOPS (INT8) | M.2 | AI Kit (컴팩트) |
| **Hailo-10H** | 40 TOPS (INT4) | M.2 / PCIe | AI HAT+ 2 (**GenAI 지원**) |

### Raspberry Pi AI HAT+ 시리즈

| 제품 | 칩셋 | RAM | GenAI | 가격대 |
|------|------|-----|-------|--------|
| **AI HAT+** | Hailo-8 (26 TOPS) | - | ❌ | $70 |
| **AI HAT+ 2** | Hailo-10H (40 TOPS) | 8GB | ✅ LLM/VLM | $110 |
| **AI Kit** | Hailo-8L (13 TOPS) | - | ❌ | $70 |

### meta-hailo (Yocto 레이어)

| 칩셋 | 브랜치 | HailoRT | Yocto | RPi5 |
|------|--------|---------|-------|------|
| **Hailo-8/8L** | `hailo8-scarthgap` | 4.23.0 | scarthgap ✅ | ✅ |
| **Hailo-10H** | `kirkstone-v5.2.0` | 5.2.0 | kirkstone ⚠️ | ✅ |

**⚠️ Hailo-10H 사용 시 주의:**
- Hailo-10H (AI HAT+ 2)는 **kirkstone 브랜치만 지원**
- meta-raspberrypi kirkstone에서 RPi5 지원 ✅
- GenAI (LLM/VLM) 사용하려면 kirkstone으로 빌드 필요

**레이어 구성:**
```
meta-hailo/
├── meta-hailo-accelerator   # PCIe 드라이버, 펌웨어
├── meta-hailo-libhailort    # HailoRT, pyHailoRT, GStreamer
└── meta-hailo-tappas        # TAPPAS 프레임워크
```

**GitHub**: https://github.com/hailo-ai/meta-hailo

### hailo-apps (AI 앱)

| 카테고리 | 앱 | Hailo-8/8L | Hailo-10H |
|----------|-----|-----------|-----------|
| **Vision** | Detection, Pose, Segmentation, Face, Depth, OCR | ✅ | ✅ |
| **GenAI** | LLM Chat, VLM Chat, Whisper, Voice Assistant | ❌ | ✅ |
| **통합** | Ollama (Open WebUI), Agent Tools | ❌ | ✅ |

**GitHub**: https://github.com/hailo-ai/hailo-apps

---

## 참고 링크

- [Yocto Releases](https://wiki.yoctoproject.org/wiki/Releases)
- [meta-raspberrypi](https://github.com/agherzan/meta-raspberrypi)
- [meta-openembedded](https://github.com/openembedded/meta-openembedded)
- [ot-br-posix recipe (scarthgap)](https://git.openembedded.org/meta-openembedded/tree/meta-networking/recipes-connectivity/openthread/ot-br-posix_git.bb?h=scarthgap)
- [Raspberry Pi OS Release Notes](https://www.raspberrypi.com/software/operating-systems/)
- [meta-hailo](https://github.com/hailo-ai/meta-hailo)
- [hailo-apps](https://github.com/hailo-ai/hailo-apps)
- [hailo-rpi5-examples](https://github.com/hailo-ai/hailo-rpi5-examples)
- [Raspberry Pi AI HAT+](https://www.raspberrypi.com/products/ai-hat-plus/)
