# RPi5 하드웨어 정보

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
