# 하드웨어 정보

재현(reflash) 시 참고용. 네트워크/USB 구성 변경 시 이 문서도 업데이트할 것.

## 보드

| 항목 | 값 |
|------|-----|
| Model | Raspberry Pi 5 Model B Rev 1.0 |
| Revision | d04170 |
| Serial | 38cb67e2958754c8 |
| RAM | 8GB (8256224 kB) |
| Kernel | 6.6.63-v8-16k aarch64 (PREEMPT) |
| OS | Yocto scarthgap 5.0 LTS (OpenEmbedded) |
| SD Card | SN128, 128GB (2020-12) |
| 패키지 수 | 2204 (opkg) |

## 네트워크 인터페이스

| 인터페이스 | MAC | 용도 | 비고 |
|-----------|-----|------|------|
| eth0 | 2C:CF:67:31:C2:51 | RPi5 내장 이더넷 | 기본 네트워크 |
| eth1 | 20:14:06:20:AA:EF | USB-이더넷 (ASIX AX88772A) | OTBR backbone 후보 |
| wlan0 | - | Wi-Fi (미사용) | DOWN |
| wpan0 | - | Thread (802.15.4) | OTBR 관리 |

### 네트워크 접속 주의사항

- eth0/eth1 중 **실제 UP인 인터페이스** 확인 필수 (`ip -br addr`)
- OTBR backbone interface는 실제 인터넷 연결된 인터페이스로 설정
- 이전 IP 이력: 192.168.0.163 (eth1), 192.168.69.6 (eth0)
- SSH: `./run.sh ssh` 또는 `ssh -i .sshkey/id_ed25519 root@<IP>`

## USB 장치

```
Bus 003 Device 005: ID 10c4:ea60  Silicon Labs CP210x  → Thread RCP (/dev/ttyUSB0)
Bus 003 Device 004: ID 0b95:772a  ASIX AX88772A        → USB-이더넷 (eth1)
Bus 003 Device 003: ID 3434:0710  Keychron Receiver     → 키보드 (디버깅용)
Bus 003 Device 002: ID 1a40:0101  Terminus Hub          → USB 허브
```

### USB 동글 (ZBDongle-E)

| 역할 | 펌웨어 | 디바이스 | USB ID | 상태 |
|------|--------|---------|--------|------|
| Thread RCP | ot-rcp-v2.4.5.0-zbdonglee-460800.gbl | /dev/ttyUSB0 | 10c4:ea60 (CP210x) | 연결됨 |
| Zigbee NCP | EmberZNet (Sonoff Zigbee 3.0 USB Dongle Plus V2) | /dev/ttyACM0 | - | **미연결** |

- 두 동글 모두 SONOFF ZBDongle-E (EFR32MG21)
- Thread RCP: baudrate **460800**, 블루 USB3 포트 권장
- Zigbee NCP: zigbee2mqtt용, 현재 물리적 미연결 상태
- **전원 주의**: USB 동글 안정성을 위해 충분한 전원 공급기 필수 (부족 시 CP210x 타임아웃)

## 서비스 상태

| 서비스 | 상태 | 비고 |
|--------|------|------|
| otbr-agent | running | Thread Border Router |
| avahi-daemon | running | mDNS/DNS-SD (Matter CASE discovery) |
| dbus | running | 시스템 메시지 버스 |
| zigbee2mqtt | - | Zigbee NCP 미연결로 미가동 |

## Thread 네트워크

| 항목 | 값 |
|------|-----|
| 상태 | leader |
| Spinel URL | `spinel+hdlc+uart:///dev/ttyUSB0?uart-baudrate=460800` |
| Dataset (hex) | `0e080000...` (`ot-ctl dataset active -x`로 확인) |

## 온도

- 현재: 55.1°C (`/sys/class/thermal/thermal_zone0/temp`)

---

# Orange Pi 5 (RK3588S) 하드웨어 정보

2026-03-31 추가. 2026-04-30 정리: OPi5는 **mainline 6.14 lab target**으로 보존한다. vendor BSP 6.1/RKNN NPU 경로는 보류.

## 보드

| 항목 | 값 |
|------|-----|
| Model | Orange Pi 5 v1.3.2 |
| SoC | Rockchip RK3588S (4×A76 2.4GHz + 4×A55) |
| GPU | ARM Mali-G610 MP4 (Valhall) — panthor/panfrost 검증 |
| NPU | 6 TOPS (RKNN) — vendor 6.1 필요, 현재 parked |
| RAM | 4GB LPDDR4X |
| Kernel | **6.14** linux-yocto-dev (mainline) |
| OS | Yocto scarthgap 5.0 LTS (OpenEmbedded) |
| SD Card | 128GB |
| 모드 | **Lab target** (SSH/GPU/HDMI 검증용) |

## Yocto BSP 구성 (2026-04-30)

| 항목 | 값 |
|------|-----|
| meta-rockchip | radxa/meta-rockchip 기반 |
| MACHINE | `orangepi-5` |
| 커널 | `linux-yocto-dev` 6.14 |
| DTS | upstream OPi5 DTS 사용 |
| GPU | panthor 1.3.0 + Mesa 24.1.7 |
| HDMI | 3840x2160@30Hz 검증 |
| NPU | 보류 — rknn-toolkit2 호환 경로는 vendor 6.1 필요 |

### 정책: vendor BSP 6.1/RKNN 경로 보류

| mainline 6.14 | vendor BSP 6.1 |
|---|---|
| ✅ SSH/GPU/HDMI 검증 완료 | ✅ rknpu 드라이버 경로 가능 |
| ✅ 유지보수 부담 낮음 | ❌ 별도 recipe/patch 유지 필요 |
| ❌ rknn-toolkit2 호환 NPU 경로 없음 | ✅ RKNN 가능성 있음 |

**결론**: HomeAgent 본류는 RPi5로 충분하다. OPi5 vendor 6.1/RKNN 실험은 필요할 때 재개하고, 재개 자료는 llmlog `20260331T114944`를 기준으로 한다.

### meta-rockchip 히스토리

| 시점 | 레이어 | 커널 | 비고 |
|------|--------|------|------|
| 2026-03-31 ~ 04-03 | radxa meta-rockchip | mainline 6.14 (linux-yocto-dev) | GPU/HDMI 검증 완료 |
| 2026-04-08 | JeffyCN meta-rockchip | vendor 6.1 (linux-rockchip) | NPU 실험, 현재 리포에서는 보류 |
| **2026-04-30 ~** | **radxa/meta-rockchip** | **mainline 6.14** | **lab target 보존** |

## 네트워크 인터페이스

| 인터페이스 | MAC | 용도 | 비고 |
|-----------|-----|------|------|
| end0 | 5E:2A:56:85:D2:7D | 내장 Gigabit Ethernet | 기본 네트워크 |

### 네트워크 접속

- IP: 192.168.0.177 (DHCP)
- SSH: `./run.sh ssh opi5`
- IP 파일: `.current-device-ip.opi5`

## NPU (RKNN, parked)

| 항목 | 값 |
|------|-----|
| 하드웨어 | RK3588S 내장 NPU 3코어, **6 TOPS** (INT8) |
| mainline 6.14 | rknn-toolkit2 호환 BSP 경로 없음 |
| vendor 6.1 | `rknpu` + NPU/IOMMU DTS 경로 가능 |
| 유저스페이스 | `rknn-toolkit2` + `rknn_server` 별도 레시피 필요 |
| 모델 포맷 | RKNN (.rknn) |
| 상태 | **보류** — HomeAgent 본류에서 추적하지 않음 |

재개 시 llmlog `20260331T114944`와 `VERSION.md`의 OPi5 섹션을 먼저 확인한다.

### RPi5 Hailo-8 vs OPi5 RKNN 비교

| | RPi5 + Hailo-8 | OPi5 RKNN |
|---|---|---|
| **TOPS** | 26 (외장 M.2) | 6 (내장) |
| **커널 드라이버** | meta-hailo (out-of-tree) | rknpu (vendor BSP 필요) |
| **Yocto 레시피** | meta-hailo | parked |
| **모델 포맷** | HEF | RKNN |

## GPU 스택 (mainline 6.14 검증 기록)

> OPi5에서 현재 보존할 핵심은 이 mainline 6.14 GPU/HDMI 검증 상태다.

| 항목 | 값 (mainline 6.14 기준) |
|------|-----|
| GPU 드라이버 | panthor 1.3.0 (kernel module) |
| Mesa | 24.1.7 (panfrost + panthor kmod) |
| GL | OpenGL ES 3.1 |
| Weston | 13.0.1 DRM backend |
| HDMI | dw-hdmi-qp, 3840x2160@30Hz (LG HDR 4K) |

## 추가 보드 (미활성)

| 보드 | SoC | 상태 |
|------|-----|------|
| Orange Pi 5 Ultra | RK3588 | 미설정 — DTB 확인 필요 |
