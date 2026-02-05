# MQTT + Home Assistant 호환 전략

HomeAgent의 디바이스 통합 전략: **검증된 HA 프로토콜 재사용**

---

## 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    HomeAgent Go Service Layer                   │
│                    (HA API 호환 레이어)                          │
└─────────────────────────┬───────────────────────────────────────┘
                          │ MQTT (HA Autodiscovery)
                          │ homeassistant/sensor/...
                          │ zigbee2mqtt/...
┌─────────────────────────┴───────────────────────────────────────┐
│                         MQTT Broker                             │
│                        (mosquitto)                              │
└───────┬─────────────────┬─────────────────┬─────────────────────┘
        │                 │                 │
   zigbee2mqtt      (future)           (future)
        │           matter2mqtt        other bridges
   ZBDongle-E
   3000+ devices
```

---

## 왜 HA MQTT인가?

### 1. 검증된 인터페이스

- **3000+ Zigbee 디바이스** 지원 (zigbee2mqtt)
- **수백만 HA 사용자**가 검증한 프로토콜
- 디바이스 추가/페어링/관리 로직을 직접 구현하지 않음

### 2. 토큰 세이빙 구조

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
# 모든 디바이스 상태
zigbee2mqtt/+

# autodiscovery 설정
homeassistant/#
```

---

## Matter와의 관계

### Matter → MQTT (HA 경유)

```
[Matter 디바이스]
     ↓ Thread/WiFi
[Matter Controller (HA/chip-tool)]
     ↓ HA Entity
[MQTT Bridge]
     ↓
[HomeAgent]
```

- HA의 Matter integration이 Matter 디바이스를 엔티티로 노출
- 해당 엔티티를 MQTT로 브릿지 가능

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

### HomeAgent의 위치

```
                    ┌─────────────┐
                    │ Matter 생태계│
                    │ Apple/Google │
                    └──────┬──────┘
                           │ (선택적)
┌──────────────────────────┼──────────────────────────┐
│                     HomeAgent                       │
│  ┌─────────────────────────────────────────────┐   │
│  │         Constitutional AI Layer              │   │
│  │    (판단, A2A 협력, 토큰 최적화)              │   │
│  └─────────────────────────────────────────────┘   │
│                          │                          │
│  ┌─────────────────────────────────────────────┐   │
│  │         HA API 호환 레이어 (Go)              │   │
│  └─────────────────────────────────────────────┘   │
│                          │                          │
│                    MQTT Broker                      │
│                          │                          │
│         ┌────────────────┼────────────────┐        │
│    zigbee2mqtt      matter2mqtt       other        │
│         │               │                          │
│    [Zigbee]         [Matter]                       │
└─────────────────────────────────────────────────────┘
```

**핵심**: MQTT는 디바이스 프로토콜과 무관한 **통합 메시징 레이어**

---

## 환경 변수

zigbee2mqtt 설정은 환경 변수로 주입 ([공식 문서](https://www.zigbee2mqtt.io/guide/configuration/)):

```bash
# /etc/default/zigbee2mqtt
# 형식: ZIGBEE2MQTT_CONFIG_<PATH_IN_UPPERCASE>

# MQTT
ZIGBEE2MQTT_CONFIG_MQTT_SERVER=mqtt://localhost:1883
ZIGBEE2MQTT_CONFIG_MQTT_BASE_TOPIC=zigbee2mqtt

# Serial (ZBDongle-E)
ZIGBEE2MQTT_CONFIG_SERIAL_PORT=/dev/ttyUSB0
ZIGBEE2MQTT_CONFIG_SERIAL_ADAPTER=ember

# Frontend
ZIGBEE2MQTT_CONFIG_FRONTEND_PORT=8080

# HA Autodiscovery
ZIGBEE2MQTT_CONFIG_HOMEASSISTANT=true

# Security
ZIGBEE2MQTT_CONFIG_PERMIT_JOIN=false
```

Yocto 이미지에 기본값 포함, 필요시 `/etc/default/zigbee2mqtt` 수정으로 오버라이드.

---

## 참고 자료

- [Home Assistant MQTT Integration](https://www.home-assistant.io/integrations/mqtt)
- [MQTT Discovery Protocol](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery)
- [zigbee2mqtt Supported Devices](https://www.zigbee2mqtt.io/supported-devices/)
- [Home Assistant Matter Integration](https://www.home-assistant.io/integrations/matter/)
- [matterbridge-zigbee2mqtt](https://github.com/Luligu/matterbridge-zigbee2mqtt)

---

## 다음 단계

1. [ ] zigbee2mqtt 환경 변수 기반 설정 (Yocto 레시피)
2. [ ] Go HA API 호환 레이어 - MQTT 구독/파싱
3. [ ] Constitutional AI Layer - 엔티티 기반 판단
4. [ ] A2A Protocol - Master Agent 연동
