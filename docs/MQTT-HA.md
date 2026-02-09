# MQTT + Home Assistant 호환 전략

HomeAgent의 디바이스 통합 전략: **검증된 HA 프로토콜 재사용 + 오프라인 Thread/Matter 스택**

---

## 전체 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    HomeAgent Go Service Layer                    │
│        (Constitutional AI + A2A + MQTT + Matter WebSocket)      │
└────────┬──────────────────────────────────┬─────────────────────┘
         │ MQTT (HA Autodiscovery)          │ WebSocket :5580
         │ homeassistant/sensor/...         │ (Matter 이벤트/제어)
         │ zigbee2mqtt/...                  │
┌────────┴──────────────────────┐   ┌──────┴──────────────────┐
│       MQTT Broker             │   │    matterjs-server      │
│      (mosquitto)              │   │   (Matter 프로토콜 엔진) │
└────┬──────────────┬───────────┘   │    Node.js / matter.js  │
     │              │               └──────┬──────────────────┘
zigbee2mqtt    matterbridge               │ Thread/IPv6
     │         (Zigbee→Matter 노출)        │
ZBDongle-E #1  (Apple/Google Home용)  ┌────┴─────┐
Zigbee NCP                            │otbr-agent│
3000+ devices                         └────┬─────┘
                                      ZBDongle-E #2
                                      Thread RCP
                                      Matter devices
```

**핵심 설계 원칙:**
- **HomeAgent Go = 컨트롤러**: MQTT 구독 + Matter WebSocket 연동, AI 판단, 디바이스 제어
- **matterjs-server = 프로토콜 엔진**: Matter 프로토콜 처리 (commissioning, fabric, subscribe)
- **Go가 제어 로직 소유**: matterjs-server는 "어떻게" 통신할지, Go는 "무엇을" 할지 결정

---

## 프로토콜 스택 (레이어 분리)

```
┌──────────────────────────────────────────────────────────┐
│  Application    HomeAgent Go (AI 판단 + 제어 명령)        │  ← 컨트롤러
├──────────────────────────────────────────────────────────┤
│  Matter Engine  matterjs-server (matter.js, WebSocket)   │  ← 프로토콜 엔진
├──────────────────────────────────────────────────────────┤
│  Matter         Commissioning, Clusters, Fabric, ACL     │  ← 디바이스 프로토콜
├──────────────────────────────────────────────────────────┤
│  IPv6 / UDP     Mesh Local (fd::/64), Link Local         │  ← 네트워크
├──────────────────────────────────────────────────────────┤
│  Thread         ot-ctl / OTBR (Border Router)            │  ← 무선 메시
├──────────────────────────────────────────────────────────┤
│  802.15.4       ZBDongle-E (EFR32MG21, Thread RCP)       │  ← 라디오
└──────────────────────────────────────────────────────────┘

핵심: ot-ctl은 Thread만 관리. Matter는 모름.
      matterjs-server가 Thread 위에서 Matter를 구동.
      HomeAgent Go가 WebSocket으로 matterjs-server에 명령을 보냄.
```

---

## 생태계 변화 (2026-02 기준)

### python-matter-server → matterjs-server 전환

| 항목 | python-matter-server | matterjs-server |
|------|---------------------|-----------------|
| **상태** | 유지보수 모드 (버그 수정만) | HA 2026.2 공식 채택 |
| **SDK** | C++ chip-wheels (ctypes) | matter.js (순수 JS) |
| **glibc 의존** | >= 2.31 (네이티브 휠) | 없음 |
| **런타임** | Python 3.12 + C++ | Node.js 22 |
| **WebSocket API** | :5580 | :5580 (호환) |
| **추가 기능** | - | 대시보드 UI, Thread 토폴로지 |

**전환 이유:**
- C++ SDK(chip-wheels) 빌드/호환 문제 해소 — glib 버전 제약 없음
- Node.js 단일 런타임 — zigbee2mqtt와 동일 → Python 스택 제거 가능
- HA 공식 방향 — 2026.2에서 python-matter-server 대체
- WebSocket API 호환 — 기존 클라이언트 코드 그대로 사용

### matterbridge 역할 명확화

**matterbridge는 Controller가 아니다.** Bridge만 가능:
- Zigbee 디바이스를 Matter로 노출 (Apple Home/Google Home에서 접근)
- Matter 디바이스를 commissioning하거나 제어하는 기능은 **없음**
- Matter 디바이스 제어는 matterjs-server + HomeAgent Go가 담당

---

## 왜 HA MQTT인가?

### 1. 검증된 인터페이스

- **3000+ Zigbee 디바이스** 지원 (zigbee2mqtt)
- **수백만 HA 사용자**가 검증한 프로토콜
- 디바이스 추가/페어링/관리 로직을 직접 구현하지 않음

### 2. 토큰 세이빙 (증류)

```
Raw Zigbee Frame (복잡)
     ↓ zigbee2mqtt
증류된 엔티티 (sensor.temperature: 24.5°C)
     ↓ MQTT
HomeAgent (정제된 데이터만 처리)
```

- 에이전트는 raw 프로토콜이 아닌 **의미 있는 엔티티**를 받음
- Constitutional AI 판단에 필요한 것: "온도 24.5°C", "문 열림", "사람 감지"

### 3. 에너지 효율

| 직접 구현 | HA MQTT 재사용 |
|----------|---------------|
| Zigbee 스택 구현 | zigbee2mqtt 사용 |
| 3000개 디바이스 프로파일 | 커뮤니티가 유지보수 |
| 페어링 UI 개발 | 웹 UI 제공 |
| → 핵심 역량 분산 | → **A2A/Constitutional AI 집중** |

---

## MQTT Autodiscovery 프로토콜

### 토픽 구조

```
homeassistant/<component>/<node_id>/<object_id>/config
homeassistant/<component>/<node_id>/<object_id>/state
```

### 예시: 온도 센서

**Config (디바이스 등록):**
```json
{
  "name": "Living Room Temperature",
  "device_class": "temperature",
  "state_topic": "zigbee2mqtt/living_room_sensor",
  "unit_of_measurement": "°C",
  "value_template": "{{ value_json.temperature }}"
}
```

**State (상태 업데이트):**
```json
{
  "temperature": 24.5,
  "humidity": 45,
  "battery": 87
}
```

### HomeAgent Go가 구독하는 토픽

```bash
# Zigbee 디바이스 상태
zigbee2mqtt/+

# autodiscovery 설정
homeassistant/#
```

Matter 디바이스는 MQTT가 아닌 **matterjs-server WebSocket**으로 직접 수신:
```
ws://localhost:5580/ws → start_listening → 모든 노드 이벤트 수신
```

---

## Matter 통합 전략 (3단계)

### 동글 전략: 듀얼 동글 (MultiPAN deprecated)

```
ZBDongle-E #1 ──→ Zigbee NCP (EmberZNet)  ──→ zigbee2mqtt ──→ MQTT
ZBDongle-E #2 ──→ Thread RCP (ot-rcp)     ──→ OTBR ──→ matterjs-server
```

- MultiPAN(rcp-uart): HA 공식 deprecated, SiliconLabs도 포기
- 단일 라디오 시분할(time-slicing)로 충돌 잦음
- HA Connect ZBT-2도 칩 2개 탑재 → 업계 합의

### Phase 1: chip-tool 검증 ✅ 완료 (2026-02-09)

```
[Eve 도어센서] ←── Thread ──→ [OTBR/RPi5]
                                    │
                               chip-tool CLI
                                    │
                     commissioning + BooleanState 읽기 성공
```

- chip-tool v1.4.0.0: Docker 크로스 컴파일 (linux-arm64-chip-tool-clang)
- 전체 흐름 검증: BLE→PASE→NOC→Thread→SRP→mDNS→CASE→CommissioningComplete
- Eve 도어센서 Node ID 1, BooleanState: FALSE (문 닫힘) 확인
- **한계**: CLI 도구, 데몬 모드 없음, 지속적 구독 어려움

#### chip-tool 크로스 컴파일 (재현 정보)

```bash
# 빌드 스크립트
./scripts/build-chip-tool.sh all   # clone + build

# 핵심 파라미터
CHIP_VERSION="v1.4.0.0"           # v1.5.0.1은 glib 2.80 필요 → Yocto 비호환
DOCKER_IMAGE="ghcr.io/project-chip/chip-build-crosscompile:81"
BUILD_TARGET="linux-arm64-chip-tool-clang"
```

| SDK 버전 | Docker 태그 | sysroot | glib | Yocto 호환 |
|----------|------------|---------|------|:----------:|
| v1.5.0.1 | 177 | ubuntu-24.04-aarch64 | 2.80 | X (`g_once_init_enter_pointer` 누락) |
| **v1.4.0.0** | **81** | **ubuntu-22.04.1-aarch64** | **2.72** | **O** (Yocto scarthgap glib 2.78) |

```bash
# 배포
./scripts/deploy-chip-tool.sh [RPi5_IP]   # scp → /opt/chip-tool/

# commissioning (검증 완료)
/opt/chip-tool/run-chip-tool.sh pairing code-thread 1 \
  hex:<dataset> 0073-043-4300 --bypass-attestation-verifier true
```

### Phase 2: matterjs-server 연동 (다음)

```
[Matter 디바이스] ←── Thread ──→ [OTBR/RPi5]
                                      │
                               matterjs-server
                               (Matter 프로토콜 엔진, matter.js 기반)
                                      │
                                  WebSocket API (ws://localhost:5580/ws)
                                      │
                               HomeAgent Go
                               (컨트롤러: 구독 + 판단 + 제어 + MQTT publish)
```

- [matterjs-server](https://github.com/matter-js/matterjs-server): matter.js 기반, HA 2026.2 공식 채택
- **C++ SDK 불필요** — 순수 JavaScript Matter 구현
- Node.js 22 런타임 (zigbee2mqtt와 공유)
- Fabric 관리, commissioning, attribute subscribe, 이벤트 스트리밍
- 대시보드 UI 내장 (Thread/WiFi 토폴로지 시각화)
- **Yocto 레시피**: npm 패턴 (zigbee2mqtt와 동일)

#### WebSocket API (python-matter-server 호환)

| 명령 | 파라미터 | 설명 |
|------|---------|------|
| `set_thread_dataset` | `dataset` | Thread 데이터셋 설정 |
| `commission_with_code` | `code` | QR/수동 페어링 코드로 커미셔닝 |
| `get_nodes` | - | 모든 커미셔닝된 노드 조회 |
| `start_listening` | - | 실시간 이벤트 스트림 시작 |
| `read_attribute` | `node_id`, `attribute_path` | 어트리뷰트 읽기 |
| `write_attribute` | `node_id`, `attribute_path`, `value` | 어트리뷰트 쓰기 |
| `device_command` | `node_id`, `endpoint_id`, `cluster_id`, `command_name` | 명령 전송 |

#### HomeAgent Go의 역할 (컨트롤러)

```go
// HomeAgent Go가 matterjs-server WebSocket에 연결하여:
// 1. start_listening → 모든 노드 이벤트 실시간 수신
// 2. 이벤트를 MQTT HA Autodiscovery 형식으로 변환하여 publish
// 3. Constitutional AI 판단에 따라 device_command로 제어
// 4. A2A Master Agent에게 증류된 정보 전달
```

### Phase 3: matterbridge 추가 (Zigbee를 외부 생태계에 노출)

```
[Zigbee 디바이스]
     ↓
[zigbee2mqtt]
     ↓ MQTT
[matterbridge-zigbee2mqtt]
     ↓ Matter
[Apple Home / Google Home / SmartThings]
```

- [matterbridge](https://github.com/Luligu/matterbridge) v3.5.3: matter.js 기반, Node.js
- **단방향 Bridge**: Zigbee 디바이스를 Matter로 노출 (Controller 아님)
- Apple Home, Google Home에서 기존 Zigbee 디바이스 접근 가능
- `npm install -g matterbridge` → 512MB 메모리로 동작
- **Yocto 레시피**: npm 패턴 (zigbee2mqtt와 동일)

### 서비스 역할 정리

| 서비스 | 역할 | 데이터 흐름 | 런타임 |
|--------|------|-----------|--------|
| **HomeAgent Go** | 컨트롤러 + AI 판단 | MQTT ← zigbee2mqtt, WS ← matterjs-server | Go |
| matterjs-server | Matter 프로토콜 엔진 | Thread ↔ Matter 디바이스 | Node.js |
| zigbee2mqtt | Zigbee 데이터 수집 | Zigbee → MQTT | Node.js |
| matterbridge | Zigbee를 Matter 노출 | MQTT → Matter (외부 생태계) | Node.js |
| mosquitto | 메시지 브로커 | 중앙 MQTT | C |
| otbr-agent | Thread Border Router | 802.15.4 ↔ IPv6 | C++ |

### 왜 Go에서 Matter를 직접 구현하지 않나?

- matter.js = 순수 JS로 전체 Matter 스택 구현 (C++ SDK 불필요)
- matterjs-server가 프로토콜 복잡성을 캡슐화 → Go는 WebSocket API만 사용
- Matter 프로토콜 재구현 비용 (수 개월) vs WebSocket 연동 (수 일) → **ROI 불리**
- Node.js는 이미 zigbee2mqtt 때문에 존재 → 추가 런타임 비용 0
- HomeAgent Go의 핵심: **AI 판단 + 제어 로직** (프로토콜 구현이 아님)

---

## 오프라인 Thread/Matter 스택

### RPi5 단독 동작 구조 (Yocto 이미지 내 서비스)

```
┌──────────────────────────────────────────────────────────┐
│                        RPi5 (Yocto)                       │
│                                                           │
│  systemd services (모두 Yocto 레시피로 패키징):              │
│                                                           │
│  ┌────────────┐ ┌───────────────┐ ┌──────────────┐       │
│  │  otbr-agent│ │matterjs-server│ │ matterbridge │       │
│  │  (Thread)  │ │(Matter Engine)│ │(Zigbee→Matter)│      │
│  └─────┬──────┘ └───────┬───────┘ └──────┬───────┘       │
│        │                │ WS :5580        │               │
│  ┌─────┴──────┐         │           ┌────┴─────┐         │
│  │Thread RCP  │   ┌─────┴──────┐    │zigbee2mqtt│        │
│  │ZBDongle-E  │   │ mosquitto  │    │(Zigbee)   │        │
│  │/dev/ttyUSB1│   │ (MQTT)     │←───┤/dev/ttyUSB0│       │
│  └────────────┘   └─────┬──────┘    └───────────┘        │
│                          │                                 │
│                    ┌─────┴──────┐                          │
│                    │ HomeAgent  │                          │
│                    │ Go (AI +   │← WS :5580 (Matter)      │
│                    │  컨트롤러) │← MQTT (Zigbee)           │
│                    └────────────┘                          │
└──────────────────────────────────────────────────────────┘
         ↕ (선택적)
    외부 네트워크 / A2A Master Agent
```

### Yocto 레시피 구조

```
meta-homeagent/recipes-connectivity/
├── openthread/              # done (bbappend: eth1/ttyUSB0/460800)
├── zigbee2mqtt/             # done (npm, systemd)
├── matterjs-server/         # todo (npm, systemd)
├── matterbridge/            # todo (npm, systemd)
└── homeagent/               # todo (Go 단일 바이너리, systemd)
```

### 오프라인 요구사항

| 컴포넌트 | 오프라인 동작 | 비고 |
|----------|:----------:|------|
| OTBR + Thread | O | 로컬 메시 네트워크 |
| matterjs-server | O | 로컬 fabric, BLE/IP commissioning |
| Matter 디바이스 제어 | O | Thread → matterjs-server → HomeAgent Go |
| MQTT Broker | O | localhost |
| zigbee2mqtt | O | 로컬 Zigbee 네트워크 |
| Constitutional AI | O | 로컬 LLM (Hailo NPU) |
| A2A Master 연동 | X | 네트워크 필요 |

### 핵심 원칙: 오프라인 퍼스트

1. **인터넷 없이 동작**: 모든 디바이스 제어는 로컬
2. **클라우드 의존 제로**: Matter fabric은 RPi5가 관리
3. **네트워크는 보너스**: A2A Master 연동, OTA 업데이트만

---

## Zigbee ↔ Matter 브릿지

### Zigbee → Matter (matterbridge, 단방향)

```
[Zigbee 디바이스]
     ↓
[zigbee2mqtt]
     ↓ MQTT
[matterbridge-zigbee2mqtt]
     ↓ Matter
[Apple Home / Google Home / SmartThings]
```

- 기존 Zigbee 디바이스를 Matter 생태계에 노출
- 참고: [matterbridge-zigbee2mqtt](https://github.com/Luligu/matterbridge-zigbee2mqtt)

### Matter → HomeAgent Go (WebSocket 직접 연동)

```
[Matter 디바이스]
     ↓ Thread
[OTBR → matterjs-server]
     ↓ WebSocket 이벤트
[HomeAgent Go]
     ├── AI 판단 (Constitutional AI)
     ├── MQTT publish (HA Autodiscovery 호환)
     └── A2A Master 보고 (증류된 정보)
```

- HomeAgent Go가 matterjs-server에 `start_listening`
- 노드 attribute 변경을 실시간 수신
- HA Autodiscovery 호환 MQTT config 자동 생성하여 publish
- Matter 디바이스도 MQTT 토픽으로 통합: `matter/<node_id>/<endpoint>/<cluster>`

---

## 환경 변수

### zigbee2mqtt

```bash
# /etc/default/zigbee2mqtt
ZIGBEE2MQTT_CONFIG_MQTT_SERVER=mqtt://localhost:1883
ZIGBEE2MQTT_CONFIG_MQTT_BASE_TOPIC=zigbee2mqtt
ZIGBEE2MQTT_CONFIG_SERIAL_PORT=/dev/ttyUSB0
ZIGBEE2MQTT_CONFIG_SERIAL_ADAPTER=ember
ZIGBEE2MQTT_CONFIG_FRONTEND_PORT=8080
ZIGBEE2MQTT_CONFIG_HOMEASSISTANT=true
ZIGBEE2MQTT_CONFIG_PERMIT_JOIN=false
```

### OTBR

```bash
# /etc/default/otbr-agent (bbappend로 영구화)
OTBR_AGENT_OPTS="-I wpan0 -B eth1 spinel+hdlc+uart:///dev/ttyUSB0?uart-baudrate=460800 trel://eth1"
OTBR_NO_AUTO_ATTACH=1
```

### Matter Commissioning 진단 흐름 (검증 완료)

```
1. SDK 호환성 ✅ → chip-tool v1.4.0.0 + Docker tag 81 (glib 2.72)
2. BLE commissioning ✅ → Linux BlueZ 정상
3. Thread 조인 ✅ → ot-ctl child table 확인
4. SRP 등록 ✅ → ot-ctl srp server enable
5. mDNS publish ✅ → avahi-browse -apt (_matter._tcp 확인)
6. CASE discovery ✅ → operational 세션 성공
7. 데이터 읽기 ✅ → BooleanState: FALSE (문 닫힘)
```

**근본 원인 해결**: RPi5 전원 부족 → USB CP210x 타임아웃 → 전원 강화 + USB3 포트 사용

---

## 검증 현황

| 항목 | 상태 | Yocto 레시피 | 비고 |
|------|:----:|:----------:|------|
| MQTT Broker (mosquitto) | ✅ | 있음 | systemd 서비스 |
| zigbee2mqtt v1.42.0 | ✅ | 있음 | ember adapter, Tuya TS0201 |
| HA Autodiscovery | ✅ | - | homeassistant/sensor/*/config |
| OTBR v0.3.0 | ✅ | 있음 (meta-oe) | Thread leader |
| OTBR 설정 bbappend | ✅ | 있음 | eth1/ttyUSB0/460800 |
| Thread RCP 동글 | ✅ | - | ZBDongle-E v2.5.3, 460800 baud |
| avahi-utils | ✅ | 있음 | avahi-browse 0.8 |
| chip-tool v1.4.0.0 | ✅ | 불필요 (테스트용) | commissioning + 데이터 읽기 완료 |
| **matterjs-server** | **다음** | **필요** | npm, Node.js 22, systemd |
| **matterbridge** | 이후 | **필요** | npm, Zigbee→Matter 노출 |
| **HomeAgent Go** | 이후 | **필요** | 단일 바이너리, WS + MQTT 연동 |

---

## 참고 자료

### Matter 생태계
- [matterjs-server](https://github.com/matter-js/matterjs-server) — HA 2026.2 공식 Matter 컨트롤러 (matter.js 기반)
- [matter.js](https://github.com/matter-js/matter.js) — 순수 JavaScript Matter 구현
- [python-matter-server](https://github.com/home-assistant-libs/python-matter-server) — 이전 컨트롤러 (유지보수 모드)
- [connectedhomeip](https://github.com/project-chip/connectedhomeip) — Matter SDK (C++, chip-tool 빌드용)

### MQTT / Zigbee
- [Home Assistant MQTT Integration](https://www.home-assistant.io/integrations/mqtt)
- [MQTT Discovery Protocol](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery)
- [zigbee2mqtt Supported Devices](https://www.zigbee2mqtt.io/supported-devices/)

### Bridge
- [matterbridge](https://github.com/Luligu/matterbridge) — Zigbee→Matter 노출 (Bridge, Controller 아님)
- [matterbridge-zigbee2mqtt](https://github.com/Luligu/matterbridge-zigbee2mqtt)

---

## 로드맵

### 완료
1. [x] zigbee2mqtt + MQTT Autodiscovery 검증 (v1.42.0, Tuya TS0201)
2. [x] OTBR + Thread 네트워크 형성 (leader)
3. [x] Thread RCP 플래시 (ZBDongle-E v2.5.3)
4. [x] OTBR 설정 Yocto bbappend (eth1/ttyUSB0/460800)
5. [x] avahi-utils + opkg Yocto 이미지 포함
6. [x] chip-tool 크로스 컴파일 + Matter commissioning 전체 검증

### 다음 (Phase 2)
7. [ ] matterjs-server Yocto 레시피 (npm, Node.js 22, systemd)
8. [ ] matterjs-server → Eve 센서 commissioning 검증
9. [ ] HomeAgent Go → matterjs-server WebSocket 연동 프로토타입
10. [ ] Matter 이벤트 → MQTT HA Autodiscovery publish

### 이후 (Phase 3)
11. [ ] matterbridge Yocto 레시피 (npm, systemd)
12. [ ] matterbridge-zigbee2mqtt → Apple/Google Home 노출

### 최종
13. [ ] Constitutional AI Layer — MQTT + Matter 엔티티 기반 판단
14. [ ] A2A Protocol — Master Agent 연동
