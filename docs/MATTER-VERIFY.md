# Matter 커미셔닝 검증 기록

## 2026-03-08: RK3576-EVB matterjs-server 실행 + BLE 블로킹 발견

### 성과

1. **matterjs-server RK3576 실행 성공** — glibc 번들 Node.js v20.18.2 + matter-server 0.3.5
2. **Go homeagent ↔ matterjs WS 연결 성공** — `ws://localhost:5580`
3. **optional deps 해결** — `@matter/nodejs`, `@matter/nodejs-ble` 포함 재빌드
4. **WiFi credentials 설정 성공** — `set_wifi_credentials` API 동작 확인
5. **mDNS 스캔 동작 확인** — wlan0에서 `_matterc._udp.local` 쿼리 정상

### BLE 블로킹: Linux vs Android BT 스택

| | RPi5 (Linux/Yocto) | RK3576 (Android 15) |
|---|---|---|
| BT 스택 | BlueZ (커널 HCI) | Android HAL 1.0 (userspace) |
| `/sys/class/bluetooth/hci0` | ✅ 커널에 등록 | ❌ HAL이 직접 관리 |
| `AF_BLUETOOTH` 소켓 | ✅ | ❌ |
| noble (`@stoprocent`) | ✅ 동작 | ❌ 소켓 없음 |
| BLE 커미셔닝 | ✅ matterjs 직접 | ❌ 불가 |

**원인**: Android BT HAL 1.0은 `/dev/ttyS4` (Broadcom UART)를 직접 관리하며, Linux 커널 HCI 디바이스를 등록하지 않음. noble이 의존하는 `AF_BLUETOOTH` 소켓이 존재하지 않음.

### WiFi Matter 디바이스 커미셔닝 시나리오

| 시나리오 | BLE 필요 | 방법 |
|---|---|---|
| A. 공장 초기화 (WiFi 미연결) | ✅ | BLE로 WiFi credentials 전달 → IP 커미셔닝 |
| B. 이미 WiFi에 연결됨 | ❌ | on-network 커미셔닝 (mDNS → PASE over IP) |
| C. Multi-admin (다른 허브에 등록) | ❌ | open-commissioning-window → on-network |

### HA Android 앱 아키텍처 (참고)

```
HA Android 앱
  → Google Play Services (GMS) Matter API
    → GMS가 BLE 커미셔닝 전부 처리
  → python-matter-server는 commissionOnNetworkDevice(passcode, ip)만 호출
```

HA 서버(python-matter-server)는 BLE를 직접 다루지 않음. Android 앱(GMS)이 BLE를 처리하고, 서버는 IP 기반 on-network 커미셔닝만 담당.

### 우리 아키텍처 (결정)

```
Flutter 앱 (Android BLE API)
  → BLE로 디바이스 발견 + WiFi credentials 전달
  → 디바이스가 WiFi 연결
  → matterjs-server에 commission_with_code (on-network) 호출
```

- **앱 레이어**: BLE 커미셔닝 (Android BLE API, GMS 불필요)
- **서버 레이어**: on-network IP 커미셔닝 (matterjs-server)
- **RPi5 의존 없는 완전 독립 스택**

### 시도한 것들 (실패 기록)

1. `--bluetooth-adapter 0` → noble이 HCI 어댑터 못 찾음
2. Go로 `hciattach` 대체 (TIOCSETD N_HCI) → line discipline 설정만으로 부족, Broadcom firmware 로딩 필요
3. Android BT HAL 중지 + 직접 HCI attach → hci0 안 올라옴

### 환경 메모

- Thread HAL 중지: `adb shell stop vendor.threadnetwork_hal`
- BT HAL 중지: `adb shell stop vendor.bluetooth-1-0`
- BT disable: `adb shell svc bluetooth disable`
- matterjs-server BLE 옵션: `--bluetooth-adapter 0` (Linux에서만 동작)
- BT UART: `/dev/ttyS4` (Broadcom AP6275P), baudrate 미확인
- Thread UART: `/dev/ttyS5` (ESP32-H2 RCP), baudrate 460800
