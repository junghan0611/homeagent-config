# HomeAgent REST API

HomeAgent Go 백엔드의 HTTP API 명세.

외부 홈 관리 플랫폼(월패드 앱, 스마트홈 대시보드, 자동화 서비스 등)에서
Matter 디바이스를 제어하기 위한 표준 인터페이스.

---

## 설계 원칙

1. **REST-first** — 제어/조회는 REST, 실시간 이벤트만 SSE
2. **OHF 시맨틱 호환** — python-matter-server / matterjs-server와 동일한 개념 모델
3. **플랫폼 무관** — 웹, Android, CLI, 자동화 스크립트 어디서든 호출
4. **단일 소스** — Go Hub이 모든 상태의 진실의 원천 (Single Source of Truth)

---

## Base URL

```
http://<host>:8080
```

RPi5 로컬: `http://localhost:8080`
같은 네트워크: `http://192.168.x.x:8080`

---

## 엔드포인트 요약

| Method | Path | 설명 | 상태 |
|--------|------|------|------|
| GET | `/healthz` | 헬스체크 | ✅ 구현됨 |
| GET | `/api/devices` | 디바이스 목록 + 상태 | ✅ 구현됨 |
| GET | `/api/devices/:node_id` | 개별 디바이스 상세 | ✅ 구현됨 |
| DELETE | `/api/devices/:node_id` | 디바이스 삭제 (unpair) | ✅ 구현됨 |
| POST | `/api/devices/command` | 디바이스 제어 | ✅ 구현됨 (8 commands) |
| POST | `/api/commission` | 새 디바이스 페어링 | ✅ 구현됨 |
| GET | `/api/events` | SSE 실시간 이벤트 | ✅ 구현됨 |
| POST | `/api/chat` | LLM 에이전트 (자연어→제어) | ✅ 구현됨 |
| GET | `/api/home` | A2UI Home Surface | ✅ 구현됨 |

---

## 상세 명세

### GET /healthz

서버 상태 확인.

**응답:**
```json
{"status": "ok", "version": "0.8.0"}
```

---

### GET /api/devices

커미셔닝된 모든 Matter 디바이스 목록과 현재 상태.

**응답:**
```json
[
  {
    "node_id": 1,
    "name": "현관문 센서",
    "room": "현관",
    "type": "contact_sensor",
    "available": true,
    "state": {
      "contact": false
    }
  },
  {
    "node_id": 8,
    "name": "거실 플러그",
    "room": "거실",
    "type": "on_off_plug",
    "available": true,
    "state": {
      "on_off": true
    }
  }
]
```

**DeviceState 필드:**

| 필드 | 타입 | 설명 |
|------|------|------|
| `node_id` | int | Matter 노드 ID (커미셔닝 시 할당) |
| `name` | string | 디바이스 별칭 (aliases.json) |
| `room` | string | 방 이름 (aliases.json) |
| `type` | string | 디바이스 타입 (아래 참조) |
| `available` | bool | 현재 연결 상태 |
| `state` | object | 타입별 상태 값 |

**디바이스 타입:**

| type | Matter 클러스터 | state 필드 |
|------|----------------|------------|
| `contact_sensor` | BooleanState (0x0045) | `contact`: bool (true=열림) |
| `on_off_plug` | OnOff (0x0006) | `on_off`: bool |
| `on_off_light` | OnOff (0x0006) | `on_off`: bool |
| `dimmable_light` | LevelControl (0x0008) | `on_off`: bool, `level`: int (0-254) |
| `color_light` | ColorControl (0x0300) | `on_off`, `level`, `hue`, `saturation` |
| `thermostat` | Thermostat (0x0201) | `mode`, `setpoint`, `temperature` |
| `door_lock` | DoorLock (0x0101) | `locked`: bool |

> 현재 `contact_sensor`, `on_off_plug`만 검증됨. 나머지는 클러스터 지원 시 확장.

---

### GET /api/devices/:node_id

✅ **구현됨** — 개별 디바이스 상세 조회.

```
GET /api/devices/8
```

**응답:** DeviceState 단일 객체 + Matter 속성 전체

```json
{
  "node_id": 8,
  "name": "거실 플러그",
  "room": "거실",
  "type": "on_off_plug",
  "available": true,
  "state": {"on_off": true},
  "attributes": {
    "0/40/2": "Tapo",
    "0/40/4": "P110M",
    "1/6/0": true
  }
}
```

---

### DELETE /api/devices/:node_id

✅ **구현됨** — 디바이스를 fabric에서 제거 (unpair).

```
DELETE /api/devices/4
```

**응답 (성공):**
```json
{"status": "ok"}
```

**응답 (없는 노드):** `404`
```json
{"error": "device not found"}
```

**응답 (matterjs 에러):** `500`
```json
{"error": "remove_node error 3: node not found in fabric"}
```

**SSE 이벤트:** 삭제 시 `device_removed` 이벤트 발생.

---

### POST /api/devices/command

디바이스 제어 명령 전송.

**요청 예시:**
```json
{"node_id": 8, "command": "on"}
{"node_id": 8, "command": "set_level", "level": 128, "transition_time": 10}
{"node_id": 8, "command": "set_color", "hue": 120, "saturation": 200}
{"node_id": 8, "command": "set_color_temp", "color_temp": 300}
{"node_id": 8, "command": "set_thermostat", "mode": "heat", "temperature": 2200}
{"node_id": 8, "command": "lock"}
```

**지원 명령:**

| command | 대상 타입 | 추가 필드 | 상태 |
|---------|----------|-----------|------|
| `on` | on_off_plug, *_light | — | ✅ |
| `off` | on_off_plug, *_light | — | ✅ |
| `set_level` | dimmable_light, color_light | `level` (0-254), `transition_time` | ✅ |
| `set_color` | color_light | `hue`, `saturation` (0-254), `transition_time` | ✅ |
| `set_color_temp` | color_light | `color_temp` (mireds 153-500), `transition_time` | ✅ |
| `set_thermostat` | thermostat | `mode` ("heat"/"cool"), `temperature` (0.01°C) | ✅ |
| `lock` | door_lock | — | ✅ |
| `unlock` | door_lock | — | ✅ |

> `transition_time`: 100ms 단위. 기본 0 (즉시).

**응답:**
```json
{"status": "ok"}
```

**에러:**
```json
{"error": "unknown command"}        // 400
{"error": "device not available"}   // 500
```

---

### POST /api/commission

Matter 디바이스 페어링 (BLE → PASE → Thread/WiFi).

**요청:**
```json
{"code": "34970112332"}
```

> code: Matter 설정 코드 (QR 또는 매뉴얼)

**응답:** 202 Accepted (비동기, 60-180초 소요)

커미셔닝 결과는 SSE `/api/events`로 전달:
```
event: commission_success
data: {"node_id": 9, "type": "on_off_light"}

event: commission_error
data: {"error": "PASE failed: timeout"}
```

---

### GET /api/events

Server-Sent Events (SSE) — 실시간 상태 변경 스트림.

**연결:**
```
GET /api/events
Accept: text/event-stream
```

**이벤트 타입:**

| event | data | 설명 |
|-------|------|------|
| `attribute_updated` | `{"node_id": 1, "path": "1/69/0", "value": true}` | 속성 변경 |
| `device_state_changed` | DeviceState 전체 | 디바이스 상태 갱신 |
| `commission_success` | `{"node_id": 9}` | 페어링 성공 |
| `commission_error` | `{"error": "..."}` | 페어링 실패 |
| `surface_update` | A2UI JSON | 동적 UI 업데이트 |

**예시 (curl):**
```bash
curl -N http://localhost:8080/api/events
```

```
event: device_state_changed
data: {"node_id":1,"name":"현관문 센서","type":"contact_sensor","available":true,"state":{"contact":true}}

event: attribute_updated
data: {"node_id":8,"path":"1/6/0","value":false}
```

---

### POST /api/chat

LLM 에이전트에게 자연어로 명령.

**요청:**
```json
{"message": "플러그 꺼줘"}
```

**응답:**
```json
{
  "reply": "거실 플러그를 끄겠습니다.",
  "actions": [
    {"type": "device_command", "node_id": 8, "command": "off"}
  ]
}
```

> LLM 에이전트가 디바이스 컨텍스트를 보고 의도를 파악하여 실행.
> OPENROUTER_API_KEY 미설정 시 503 반환.

---

### GET /api/home

A2UI Home Surface — 에이전트가 생성하는 동적 UI 데이터.

**응답:** A2UI JSON (시간 기반 테마 + 디바이스 상태 요약)

```json
{
  "greeting": "좋은 아침이에요",
  "theme": "morning",
  "palette": {
    "--bg-primary": "#1a1a2e",
    "--text-primary": "#e0e0e0"
  },
  "cards": [
    {"type": "device_summary", "count": 3, "active": 2},
    {"type": "sensor_status", "node_id": 1, "label": "현관문", "value": "닫힘"}
  ]
}
```

> 자세한 내용: [A2UI.md](A2UI.md)

---

## 외부 플랫폼 연동 가이드

### 시나리오: 홈 관리 앱에서 HomeAgent 디바이스 제어

```
┌──────────────────────┐
│  홈 관리 앱 (월패드)  │
│  Android / Web / IoT  │
└──────────┬───────────┘
           │ HTTP REST
           ▼
┌──────────────────────┐
│  HomeAgent REST API   │
│  :8080               │
└──────────┬───────────┘
           │ WebSocket
           ▼
┌──────────────────────┐
│  matterjs-server      │
│  Matter 프로토콜 엔진 │
└──────────┬───────────┘
           │
     Thread / WiFi
           │
    Matter 디바이스
```

### 통합 예시 (Android)

```kotlin
// 1. 디바이스 목록 조회
val response = httpClient.get("http://192.168.x.x:8080/api/devices")
val devices: List<Device> = json.decode(response.body)

// 2. 플러그 끄기
httpClient.post("http://192.168.x.x:8080/api/devices/command") {
    body = """{"node_id": 8, "command": "off"}"""
}

// 3. 실시간 이벤트 구독
val sse = EventSource("http://192.168.x.x:8080/api/events")
sse.onEvent("device_state_changed") { data ->
    updateUI(json.decode(data))
}
```

### 통합 예시 (Python / 자동화)

```python
import requests

# 디바이스 목록
devices = requests.get("http://localhost:8080/api/devices").json()

# 제어
requests.post("http://localhost:8080/api/devices/command",
    json={"node_id": 8, "command": "on"})

# 자연어 제어
result = requests.post("http://localhost:8080/api/chat",
    json={"message": "현관문 열려있어?"}).json()
print(result["reply"])
```

---

## OHF 호환성

HomeAgent API는 [Open Home Foundation](https://www.openhomefoundation.org/)의 python-matter-server와 동일한 개념 모델을 사용합니다:

| OHF 개념 | HomeAgent 매핑 | 비고 |
|----------|---------------|------|
| Node | `node_id` | Matter 노드 ID |
| Endpoint | `state` 필드 내 | 1번 엔드포인트 기본 |
| Cluster | `type`으로 추상화 | OnOff, BooleanState 등 |
| Attribute | `attributes` (상세 조회) | Matter 속성 경로 |
| Fabric | 내부 관리 | matterjs-server가 관리 |

**python-matter-server → HomeAgent 전환 시:**
- WebSocket → REST (더 단순)
- 동일한 node_id / command 시맨틱
- SSE로 이벤트 구독 (WebSocket 대안)

---

## 인증 (계획)

🔲 현재: 인증 없음 (로컬 네트워크 신뢰 모델)

**계획:**
- `X-API-Key` 헤더 기반 인증
- 키 생성: `homeagent --generate-api-key`
- 로컬 네트워크에서만 접근 가능 (방화벽)
- 원격 접근 시 Tailscale/WireGuard VPN 권장

```bash
curl -H "X-API-Key: ha_xxxxxxxxxxxx" http://localhost:8080/api/devices
```

---

## 로드맵

- [x] 기본 CRUD (devices, command, commission)
- [x] SSE 실시간 이벤트
- [x] LLM 에이전트 채팅
- [x] A2UI Home Surface
- [ ] 개별 디바이스 조회 (`/api/devices/:node_id`)
- [ ] 클러스터별 세분화 제어 (Level, Color, Thermostat)
- [ ] toggle 명령
- [ ] 이벤트 필터링 (노드/타입별 구독)
- [ ] API key 인증
- [ ] OpenAPI 3.0 스펙 생성
- [ ] Android IPC 어댑터 (AIDL thin layer)
