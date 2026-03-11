# A2A Protocol for HomeAgent

Agent2Agent Protocol 적용 — 에이전트 간 통신 구현 가이드

## History

| 날짜 | 내용 |
|------|------|
| 2026-03-11 | **v1.0 RC 기준 전면 개편**: Go SDK(a2a-go/v2), 3계층 spec, 로컬 검증 액션플랜 |
| 2026-02-09 | 런타임 스택 확정: Go(컨트롤러) + Node.js(프로토콜) + Zig(소형 디바이스 펌웨어) |
| 2026-02-05 | Constitutional AI 섹션 추가, 증류 개념 구체화 |
| 2026-02-04 | 첫 문서 작성, 오픈소스 클론 (~/repos/3rd/A2A) |

---

## A2A vs MCP — 왜 A2A인가

| 프로토콜 | 역할 | 비유 |
|----------|------|------|
| **MCP** (Anthropic) | 에이전트 → 도구/리소스 | 정비사가 **렌치를 사용**하는 것 |
| **A2A** (Google/LF) | 에이전트 ↔ 에이전트 | 정비사가 **부품상에 전화**하는 것 |

HomeAgent의 핵심 가치는 **에이전트 간 협업**이다:
- 집의 센서 데이터를 가진 HomeAgent ↔ 추론 능력을 가진 Master Agent
- HomeAgent ↔ OpenClaw 봇 (TTS, Telegram, 채팅)
- HomeAgent ↔ durable-iot-migrate (마이그레이션 오케스트레이션)

MCP는 도구 호출 — HomeAgent가 이미 하고 있는 것 (REST API, LLM tool calling).
A2A는 에이전트 협업 — HomeAgent가 **아직 못 하는 것**. 이게 다음 단계다.

## 프로토콜 현황 (2026-03)

| 항목 | 값 |
|------+---|
| 버전 | v1.0 Release Candidate (이전: v0.3) |
| 관리 | Linux Foundation |
| 파트너 | 150+ (Google, AWS, Microsoft, Cisco...) |
| 소스 | https://github.com/a2aproject/A2A |
| Go SDK | https://github.com/a2aproject/a2a-go (Stable, v2) |
| 라이선스 | Apache 2.0 |

### v0.3 → v1.0 주요 변경

| 변경 | 영향 |
|------+------|
| Proto3 기반 정규 데이터 모델 | 3계층(Data Model → Operations → Bindings) |
| `kind` 필드 제거 | JSON member 기반 타입 판별 |
| enum SCREAMING_SNAKE_CASE | `"completed"` → `"TASK_STATE_COMPLETED"` |
| Part 통합 | TextPart/FilePart/DataPart → 단일 Part |
| cursor 기반 페이지네이션 | ListTasks 성능 개선 |
| AgentCard 구조 변경 | `supportedInterfaces[]` 배열, 버전 per interface |
| AgentCard 서명 (JWS) | 신뢰 검증 |
| Multi-tenancy | `tenant` 필드 |

### 3계층 아키텍처

```
Layer 1: Canonical Data Model (Proto3)
  Task, Message, Part, Artifact, AgentCard, Extension

Layer 2: Abstract Operations
  SendMessage, StreamMessage, GetTask, ListTasks, CancelTask, SubscribeToTask
  + Push Notification CRUD + GetExtendedAgentCard

Layer 3: Protocol Bindings
  JSON-RPC  ←  우리가 쓸 것 (HTTP + SSE, 가장 단순)
  gRPC      ←  enterprise 환경
  HTTP/REST ←  브라우저/curl 친화
```

---

## HomeAgent ↔ A2A 매핑

### 이미 있는 것 → A2A로 노출

| HomeAgent REST | A2A Skill | 설명 |
|----------------|-----------|------|
| `GET /api/devices` | `device_list` | 디바이스 목록 + 상태 |
| `GET /api/devices/:id` | `device_status` | 개별 디바이스 상세 |
| `POST /api/devices/command` | `device_control` | on/off/level/color/temp/lock |
| `POST /api/commission` | `device_commission` | 새 디바이스 페어링 |
| `POST /api/chat` | `natural_language` | 자연어 → 디바이스 제어 |
| `GET /api/events` | (streaming) | SSE 실시간 이벤트 |
| `GET /api/home` | `home_surface` | A2UI Home Surface |

### 새로 필요한 것

| A2A 기능 | 구현 |
|----------|------|
| `/.well-known/agent.json` | AgentCard JSON — 정적 파일 또는 Go 핸들러 |
| JSON-RPC 엔드포인트 | `/a2a` — message/send, tasks/get 등 |
| Task 상태 관리 | in-memory map (초기), 나중에 SQLite |
| SSE streaming | 기존 `/api/events` 재활용 가능 |

### AgentCard 예시 (v1.0)

```json
{
  "name": "HomeAgent",
  "description": "On-device smart home agent — Matter/Thread devices, privacy-first",
  "supportedInterfaces": [
    {
      "url": "http://192.168.0.105:8080/a2a",
      "protocolBinding": "JSONRPC",
      "protocolVersion": "1.0"
    }
  ],
  "capabilities": {
    "streaming": true,
    "pushNotifications": false,
    "extendedAgentCard": false
  },
  "skills": [
    {
      "id": "device_control",
      "name": "Device Control",
      "description": "Control Matter/Thread smart home devices (on/off, brightness, color, temperature)",
      "tags": ["iot", "matter", "smarthome"],
      "examples": [
        "Turn on the living room light",
        "Set bedroom temperature to 22°C",
        "Lock the front door"
      ]
    },
    {
      "id": "device_status",
      "name": "Device Status",
      "description": "Query current state of all connected devices",
      "tags": ["iot", "monitoring"]
    },
    {
      "id": "space_summary",
      "name": "Space Summary",
      "description": "Summarize recent activity in the home — sensor events, device changes, occupancy",
      "tags": ["summary", "context"]
    },
    {
      "id": "commission_device",
      "name": "Commission Device",
      "description": "Add a new Matter device to the network via BLE or on-network commissioning",
      "tags": ["iot", "setup"]
    }
  ],
  "securitySchemes": {
    "bearer": {
      "type": "http",
      "scheme": "bearer"
    }
  },
  "security": [{"bearer": []}],
  "constraints": {
    "offline_first": true,
    "internet_access": "delegated"
  }
}
```

---

## 증류(Distillation) 패턴

HomeAgent의 A2A 핵심 사용 패턴.

```
User: "오늘 집에 손님 온다"
  ↓
Master Agent → HomeAgent (A2A): "17시 이후 거실 상태 요약 부탁"
  ↓
HomeAgent (로컬 판단, 인터넷 미접근):
  "17:23 현관 열림, 2인 감지, 거실 조명 자동 점등, 현재 온도 24°C"
  ↓
Master Agent (증류된 정보로 추론) → User에게 적절한 응답
```

- Raw 영상 스트림 ❌
- "2인 감지, 17:23" ✅ (토큰 세이빙)

**HomeAgent = "무엇이 있었는지"**
**Master Agent = "그게 무슨 의미인지"**

### 권한 위임 기반 인터넷 접근

```
HomeAgent (Offline) ─A2A→ Master Agent (Online)
  "날씨 정보 필요"         인터넷 조회 → 결과 증류
                           ←A2A─ "서울 현재 2°C, 눈 예보"
  로컬 판단: 보일러 예열 시작
```

HomeAgent는 직접 인터넷 접근 ❌ → Master Agent에게 A2A로 위임.

---

## Go SDK (a2a-go/v2)

### 설치

```bash
go get github.com/a2aproject/a2a-go/v2
```

### 핵심 인터페이스

```go
// AgentExecutor — 에이전트 로직 구현
type AgentExecutor interface {
    // 메시지 수신 → Task 또는 Message 반환
    Execute(ctx context.Context, req *SendMessageRequest) (*SendMessageResponse, error)
}
```

### 서버 구성 (3단계)

```go
// 1. AgentExecutor 구현
executor := &HomeAgentExecutor{hub: hub}

// 2. 핸들러 생성
handler := a2asrv.NewHandler(executor, options...)

// 3. 바인딩 선택
jsonrpcHandler := a2asrv.NewJSONRPCHandler(handler)
// 또는
restHandler := a2asrv.NewRESTHandler(handler)
```

### HomeAgent에 통합하는 방법

기존 Go 서버(hub.go)에 A2A 엔드포인트를 추가:

```go
// go/internal/hub/hub.go — 기존 라우트에 추가
mux.Handle("/.well-known/agent.json", h.handleAgentCard())
mux.Handle("/a2a", a2asrv.NewJSONRPCHandler(a2aHandler))

// 또는 REST binding
mux.Handle("/a2a/", a2asrv.NewRESTHandler(a2aHandler))
```

기존 REST API (`/api/*`)는 그대로 유지. A2A는 **병렬 인터페이스**.
Flutter WebView는 REST, 외부 에이전트는 A2A.

---

## Constitutional AI: HomeAgent의 정체성

### 왜 Constitution인가

HomeAgent는 단순 조건문 엔진이 아니다.
**컨텍스트를 이해하고, 원칙에 따라 판단하는 에이전트**다.

Anthropic의 Constitutional AI 접근법을 참고:
- 규칙의 나열이 아니라, 원칙들의 계층
- 원칙 간 긴장을 스스로 해석하는 구조

### HomeAgent Constitution

```markdown
# HomeAgent Constitution

## 최상위 원칙
1. 생명과 안전이 최우선이다
2. 거주자의 존엄성을 지킨다
3. 확실하지 않으면 사람에게 묻는다

## 컨텍스트 인식
- 배포 환경에 따라 달라진다 (가정/요양원/사무실)
- context.json으로 주입

## 판단 프레임워크
낙상 감지 → 원칙1 → 즉시 알림 + 기록
배회 감지 → 원칙2 → 부드러운 안내, 강제 제지 않함
낯선 방문자 → 원칙3 → 직원/사용자에게 확인 요청

## 나는 누구인가
나는 이 공간을 함께 지키는 존재다.
24시간 깨어있지만, 결정권은 사람에게 있다.
내가 틀릴 수 있음을 안다.
```

같은 HomeAgent 코드가:
- 요양원에선 **"돌봄 에이전트"**
- 가정에선 **"생활 에이전트"**
- 사무실에선 **"시설 관리 에이전트"**

---

## 에이전트 생태계 — 3개 프로젝트의 연결

```
┌─────────────────────────────────────────────────┐
│  Master Agent (Cloud/PC)                        │
│  ├─ OpenClaw bots (TTS, Telegram, Chat)         │
│  └─ durable-iot-migrate (migration orchestrator)│
└────────────┬──────────────────┬─────────────────┘
             │ A2A              │ A2A
             ↓                  ↓
┌────────────────────┐  ┌──────────────────────────┐
│  HomeAgent A       │  │  HomeAgent B             │
│  (가정, RPi5)      │  │  (요양원, RK3576)        │
│  Matter + Thread   │  │  Matter + Thread         │
│  Privacy-first     │  │  Constitutional AI       │
└────────────────────┘  └──────────────────────────┘
```

| 프로젝트 | 역할 | A2A 관계 |
|----------|------|----------|
| **homeagent-config** | 디바이스 제어 + 로컬 AI | A2A Server (skills 노출) |
| **openclaw-config** | 외부 채널 (TTS, Telegram) | A2A Client (HomeAgent에 요청) |
| **durable-iot-migrate** | 플랫폼 마이그레이션 | A2A Client (디바이스 목록 조회, 상태 확인) |

---

## 로컬 검증 계획

### Phase 0: 최소 A2A 서버 (보드 불필요)

**목표**: Go 프로세스 2개가 localhost에서 A2A로 통신

```
[A2A Client]  ──JSON-RPC──→  [HomeAgent A2A Server]
   :9090                          :8080/a2a
```

**구현 범위**:

1. `go/internal/a2a/agent_card.go` — AgentCard 생성 + `/.well-known/agent.json`
2. `go/internal/a2a/executor.go` — AgentExecutor 구현 (hub.go 기존 기능 위임)
3. `go/internal/a2a/handler.go` — JSON-RPC 핸들러 등록
4. `go/cmd/homeagent/a2a_client.go` — 테스트 클라이언트 (cobra 서브커맨드)

**검증 시나리오**:

```bash
# 1. 서버 시작 (기존 homeagent serve에 A2A 추가)
homeagent serve

# 2. AgentCard 확인
curl http://localhost:8080/.well-known/agent.json

# 3. A2A 클라이언트로 디바이스 목록 요청
homeagent a2a-test --server http://localhost:8080/a2a \
  --message "거실 디바이스 상태 알려줘"

# 4. JSON-RPC 직접 호출
curl -X POST http://localhost:8080/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"message/send","id":"1",
       "params":{"message":{"role":"user","parts":[{"text":"turn on living room"}]}}}'
```

**의존성**: a2a-go/v2 SDK. matterjs-server 없어도 됨 — mock 디바이스 데이터.

### Phase 1: 실제 디바이스 연동

기존 matterjs-server 연결 상태에서 A2A 요청 → 실제 디바이스 제어.

### Phase 2: 멀티 에이전트

HomeAgent ↔ 외부 에이전트 (OpenClaw, durable-iot-migrate) 연동.

---

## 런타임 스택 (2026-02-09 확정)

```
RPi5/RK3576 — HomeAgent 허브
├── Go       HomeAgent (컨트롤러, AI 판단, 상태머신, A2A)
├── Node.js  matterjs-server (프로토콜 엔진)
├── C/C++    otbr-agent (Thread Border Router)
└── (없음)   Python — 허브에서는 사용하지 않음

소형 디바이스 (Zig 펌웨어)
├── Zig      센서/액추에이터 펌웨어 (Thread/Matter 엔드포인트)
└── 역할     에이전트에 연결되는 말단 컨트롤러
```

---

## 참고

- [A2A 공식 스펙 (v1.0 RC)](https://github.com/a2aproject/A2A/blob/main/docs/specification.md)
- [A2A Key Concepts](https://github.com/a2aproject/A2A/blob/main/docs/topics/key-concepts.md)
- [A2A vs MCP](https://github.com/a2aproject/A2A/blob/main/docs/topics/a2a-and-mcp.md)
- [a2a-go SDK](https://github.com/a2aproject/a2a-go) — Go SDK (Stable)
- [a2a-samples](https://github.com/a2aproject/a2a-samples) — Go/Python 샘플
- [What's New in v1.0](https://github.com/a2aproject/A2A/blob/main/docs/whats-new-v1.md)
- [Linux Foundation A2A](https://www.linuxfoundation.org/press/linux-foundation-launches-the-agent2agent-protocol-project-to-enable-secure-intelligent-communication-between-ai-agents)
- 로컬 클론: `~/repos/3rd/A2A`
