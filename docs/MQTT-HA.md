# MQTT + Home Assistant 호환 전략

HomeAgent의 디바이스 통합 전략: **검증된 HA 프로토콜 재사용 + 오프라인 Thread/Matter 스택**

---

## 전체 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    HomeAgent Go Service Layer                    │
│              (Constitutional AI + A2A + MQTT 통합)               │
└─────────────────────────┬───────────────────────────────────────┘
                          │ MQTT (HA Autodiscovery)
                          │ homeassistant/sensor/...
                          │ zigbee2mqtt/... , matter/...
┌─────────────────────────┴───────────────────────────────────────┐
│                         MQTT Broker                              │
│                        (mosquitto)                               │
└───────┬─────────────────┬────────────────────┬──────────────────┘
        │                 │                    │
   zigbee2mqtt     matter-agent          (future)
        │          (Go, Phase 3)        other bridges
   ZBDongle-E #1   ZBDongle-E #2
   Zigbee NCP      Thread RCP
   3000+ devices   Matter devices
```

---

## 프로토콜 스택 (레이어 분리)

```
┌──────────────────────────────────────────────────────────┐
│  Application    chip-tool / python-matter-server / Go    │  ← Matter 컨트롤러
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
      chip-tool이 Thread 위에서 Matter를 구동.
```

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

### HomeAgent가 구독하는 토픽

```bash
# Zigbee 디바이스 상태
zigbee2mqtt/+

# Matter 디바이스 상태 (Phase 3)
matter/+/+

# autodiscovery 설정
homeassistant/#
```

---

## Matter 통합 전략 (3단계)

### 동글 전략: 듀얼 동글 (MultiPAN deprecated)

```
ZBDongle-E #1 ──→ Zigbee NCP (EmberZNet)  ──→ zigbee2mqtt ──→ MQTT
ZBDongle-E #2 ──→ Thread RCP (ot-rcp)     ──→ OTBR ──→ Matter ──→ MQTT
```

- MultiPAN(rcp-uart): HA 공식 deprecated, SiliconLabs도 포기
- 단일 라디오 시분할(time-slicing)로 충돌 잦음
- HA Connect ZBT-2도 칩 2개 탑재 → 업계 합의

### Phase 1: chip-tool 검증 (현재)

```
[Matter 디바이스] ←── Thread ──→ [OTBR/RPi5]
                                      │
                                 chip-tool CLI
                                      │
                              commissioning + 수동 제어
```

- chip-tool: Docker 크로스 컴파일 (linux-arm64-chip-tool-clang)
- commissioning, cluster read/write, subscribe 가능
- 한계: CLI 도구, 지속적 구독 어려움

### Phase 2: python-matter-server 검증 (다음)

```
[Matter 디바이스] ←── Thread ──→ [OTBR/RPi5]
                                      │
                              python-matter-server
                              (fabric, 이벤트 구독, HA의 공식 Matter 컨트롤러)
                                      │
                                  WebSocket API (ws://localhost:5580/ws)
                                      │
                              HomeAgent Go (구독 + MQTT publish)
```

- HA의 공식 Matter 컨트롤러 ([python-matter-server](https://github.com/home-assistant-libs/python-matter-server))
- 내부: Python → ctypes → chip-wheels(C++ SDK) — **무거운 작업은 C++**
- Fabric 관리, commissioning, attribute subscribe, 이벤트 스트리밍
- RPi5 8GB에서 성능 이슈 없음 (HA가 RPi4 4GB에서도 운영)
- **Yocto 레시피로 패키징** → SD 재플래시해도 유지

```bash
# Yocto 설치 (레시피화 필요)
# python-matter-server + chip-wheels (aarch64 pre-built)
# systemd 서비스로 자동 시작

# WebSocket 이벤트 구독
# ws://localhost:5580/ws → start_listening → 모든 노드 이벤트 수신
```

### Phase 3: matterbridge 연동 (양방향 브릿지)

```
┌─────────────────────────────────────────────────────────────┐
│                        RPi5 서비스 스택                       │
│                                                              │
│  python-matter-server          matterbridge                  │
│  (Matter → 읽기/제어)          (Zigbee → Matter 노출)         │
│       │                              │                       │
│       │ WebSocket                    │ matter.js              │
│       │                              │                       │
│  ┌────┴──────────────────────────────┴────┐                 │
│  │              MQTT Broker               │                  │
│  │             (mosquitto)                │                  │
│  └────┬──────────────────────────────┬────┘                 │
│       │                              │                       │
│  zigbee2mqtt                    HomeAgent Go                 │
│  (Zigbee → MQTT)               (AI + 제어)                   │
└───────┴──────────────────────────────┴───────────────────────┘
```

- [matterbridge](https://github.com/Luligu/matterbridge): matter.js 기반, Node.js (이미 설치됨)
- Zigbee 디바이스를 Apple Home / Google Home에 Matter로 노출
- `npm install -g matterbridge` → 512MB 메모리로 동작
- **Yocto 레시피로 패키징** (zigbee2mqtt와 동일한 npm 패턴)

### 서비스 역할 정리

| 서비스 | 방향 | 역할 | 런타임 |
|--------|------|------|--------|
| zigbee2mqtt | Zigbee → MQTT | Zigbee 디바이스 데이터 수집 | Node.js |
| python-matter-server | Matter → WebSocket | Matter 디바이스 제어/구독 | Python + C++ |
| matterbridge | MQTT → Matter | Zigbee를 Matter 생태계에 노출 | Node.js |
| mosquitto | 중앙 | 메시지 브로커 | C |
| HomeAgent Go | MQTT → AI | Constitutional AI 판단/제어 | Go |

### 왜 Go 재구현 안 하나?

- python-matter-server 내부 = C++ SDK wrapper → Python은 껍데기
- RPi5 8GB에서 Python 오버헤드 무시 가능 (~100MB)
- 재구현 비용 (수 개월) vs 그대로 사용 (즉시) → **ROI 불리**
- 필요시 HomeAgent Go가 WebSocket으로 연동하면 충분
- Node.js도 이미 zigbee2mqtt 때문에 존재 → matterbridge 추가 비용 0

---

## 오프라인 Thread/Matter 스택

### RPi5 단독 동작 구조 (Yocto 이미지 내 서비스)

```
┌──────────────────────────────────────────────────────────┐
│                        RPi5 (Yocto)                       │
│                                                           │
│  systemd services (모두 Yocto 레시피로 패키징):              │
│                                                           │
│  ┌────────────┐ ┌───────────────────┐ ┌──────────────┐   │
│  │  otbr-agent│ │python-matter-server│ │ matterbridge │   │
│  │  (Thread)  │ │(Matter Controller) │ │(Zigbee→Matter)│  │
│  └─────┬──────┘ └────────┬──────────┘ └──────┬───────┘   │
│        │                 │ WebSocket          │           │
│  ┌─────┴──────┐          │              ┌────┴─────┐     │
│  │Thread RCP  │    ┌─────┴──────┐       │zigbee2mqtt│    │
│  │ZBDongle-E  │    │ mosquitto  │       │(Zigbee)   │    │
│  │/dev/ttyUSB1│    │ (MQTT)     │←──────┤/dev/ttyUSB0│   │
│  └────────────┘    └─────┬──────┘       └───────────┘    │
│                          │                                │
│                    ┌─────┴──────┐                         │
│                    │ HomeAgent  │                         │
│                    │ (Go + AI)  │                         │
│                    └────────────┘                         │
└──────────────────────────────────────────────────────────┘
         ↕ (선택적)
    외부 네트워크 / A2A Master Agent
```

### Yocto 레시피 구조

```
meta-homeagent/recipes-connectivity/
├── zigbee2mqtt/          # done (npm, systemd)
├── python-matter-server/ # todo (pip, chip-wheels, systemd)
├── matterbridge/         # todo (npm, systemd)
└── otbr-config/          # todo (bbappend, /etc/default/otbr-agent)
```

### 오프라인 요구사항

| 컴포넌트 | 오프라인 동작 | 비고 |
|----------|:----------:|------|
| OTBR + Thread | O | 로컬 메시 네트워크 |
| Matter commissioning | O | 로컬 fabric, BLE/IP |
| Matter 디바이스 제어 | O | Thread 직접 통신 |
| MQTT Broker | O | localhost |
| zigbee2mqtt | O | 로컬 Zigbee 네트워크 |
| Constitutional AI | O | 로컬 LLM (Hailo NPU) |
| A2A Master 연동 | X | 네트워크 필요 |

### 핵심 원칙: 오프라인 퍼스트

1. **인터넷 없이 동작**: 모든 디바이스 제어는 로컬
2. **클라우드 의존 제로**: Matter fabric은 RPi5가 관리
3. **네트워크는 보너스**: A2A Master 연동, OTA 업데이트만

---

## Zigbee ↔ Matter 브릿지 (양방향)

### Zigbee → Matter (matterbridge)

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

### Matter → MQTT (우리가 구현)

```
[Matter 디바이스]
     ↓ Thread
[OTBR + Matter Controller]
     ↓ 이벤트 구독
[matter-agent]
     ↓ JSON publish
[MQTT Broker]
     ↓
[HomeAgent AI]
```

- MQTT topic: `matter/<node_id>/<endpoint>/<cluster>`
- HA Autodiscovery 호환 config 자동 생성

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
# /etc/default/otbr-agent
OTBR_AGENT_OPTS="-I wpan0 -B eth0 spinel+hdlc+uart:///dev/ttyUSB0?uart-baudrate=460800 trel://eth0"
OTBR_NO_AUTO_ATTACH=1
```

---

## 검증 현황

| 항목 | 상태 | Yocto 레시피 | 비고 |
|------|:----:|:----------:|------|
| MQTT Broker (mosquitto) | done | 있음 | systemd 서비스 |
| zigbee2mqtt v1.42.0 | done | 있음 | ember adapter, Tuya TS0201 |
| HA Autodiscovery | done | - | homeassistant/sensor/*/config |
| OTBR v0.3.0 | done | 있음 (meta-oe) | Thread leader, ch14 |
| OTBR 설정 오버라이드 | pending | **필요** | /etc/default/otbr-agent |
| Thread RCP 동글 | done | - | ZBDongle-E v2.5.3 |
| chip-tool | in progress | 불필요 (테스트용) | Docker 크로스 컴파일 |
| python-matter-server | pending | **필요** | pip + chip-wheels |
| matterbridge | pending | **필요** | npm (zigbee2mqtt 패턴) |
| HomeAgent Go | pending | **필요** | 단일 바이너리 |

---

## 참고 자료

- [Home Assistant MQTT Integration](https://www.home-assistant.io/integrations/mqtt)
- [MQTT Discovery Protocol](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery)
- [zigbee2mqtt Supported Devices](https://www.zigbee2mqtt.io/supported-devices/)
- [Home Assistant Matter Integration](https://www.home-assistant.io/integrations/matter/)
- [python-matter-server](https://github.com/home-assistant-libs/python-matter-server)
- [matterbridge-zigbee2mqtt](https://github.com/Luligu/matterbridge-zigbee2mqtt)
- [canonical/matter-mqtt-bridge](https://github.com/canonical/matter-mqtt-bridge) (반대 방향: MQTT→Matter)
- [connectedhomeip](https://github.com/project-chip/connectedhomeip) (Matter SDK v1.5.0.1)

---

## 로드맵

### 완료
1. [x] zigbee2mqtt + MQTT Autodiscovery 검증 (v1.42.0, Tuya TS0201)
2. [x] OTBR + Thread 네트워크 형성 (leader, ch14)
3. [x] Thread RCP 플래시 (ZBDongle-E v2.5.3)

### 진행중
4. [ ] chip-tool 크로스 컴파일 + Matter commissioning 검증
5. [ ] OTBR 설정 Yocto 레시피화 (otbr-config bbappend)

### 다음
6. [ ] python-matter-server Yocto 레시피 (pip + chip-wheels)
7. [ ] python-matter-server 동작 확인 (WebSocket 이벤트 구조)
8. [ ] matterbridge Yocto 레시피 (npm, zigbee2mqtt 패턴)
9. [ ] HomeAgent Go → python-matter-server WebSocket 연동
10. [ ] Yocto rootfs 확장 (서비스 추가에 따른 디스크 확보)

### 최종
11. [ ] Constitutional AI Layer - MQTT 엔티티 기반 판단
12. [ ] A2A Protocol - Master Agent 연동
