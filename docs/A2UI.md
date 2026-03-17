# A2UI: Agent-to-User Interface

HomeAgent의 동적 UI 전략. **에이전트가 선언적 JSON으로 UI를 기술하면 뷰어가 렌더링한다.**

## 핵심 개념: "에이전트"는 AI만이 아니다

A2UI에서 **Agent(에이전트)**는 "UI를 결정하는 주체" — AI일 수도 있고, 룰 엔진일 수도 있다.

```
A2UI = Agent → JSON Surface → Viewer(렌더러)

Agent가 될 수 있는 것:
  1. Go surface.go (룰 기반) — 시간/상태 보고 JSON 생성 ("나른한 오후예요")
  2. LLM (DeepSeek/sLLM) — 대화 중 동적 surface 생성 ("디바이스 목록")
  3. 자동화 규칙 — 이벤트 트리거 시 UI 변경
```

**"A2UI = AI가 UI를 만든다"가 아니다.** AI는 하나의 Agent일 뿐. 핵심은 **UI가 코드가 아닌 데이터(JSON)로 선언**된다는 것. 코드를 보내면 보안 위험. 데이터를 보내면 안전.

### HomeAgent의 두 A2UI 경로

| 경로 | Agent | 트리거 | 예시 |
|------|-------|--------|------|
| **Home Surface** | Go `surface.go` | 시간/상태 변화 | "17:00", "나른한 오후예요 🌇", "기기 2개 온라인" |
| **Chat Surface** | LLM (DeepSeek/sLLM) | 사용자 질문 | "디바이스 목록" → 카드형 디바이스 리스트 |

둘 다 같은 JSON 포맷 → 같은 genui 렌더러로 표시.

### 실제 흐름

```
[1] Home Surface (Go 룰 기반, AI 호출 없음)
    서버 시작 → surface.go가 현재 시각 + 디바이스 상태 조회
    → JSON 생성 → GET /api/home → Flutter genui 렌더링

[2] Chat Surface (AI 호출)
    사용자: "디바이스 목록 알려줘"
    → Go agent.go → DeepSeek API 호출
    → LLM 응답에 surface 블록 포함
    → SSE surface_update 이벤트 → Flutter genui 렌더링
```

## History

| 날짜 | 내용 |
|------|------|
| 2026-03-17 | **genui 통합 성공**: Go→JSON→genui 어댑터(트리 평탄화)→Flutter Widget 렌더링. Text/Card/Icon/Row 변환 해결 |
| 2026-03-16 | **genui SDK 분석**: A2UI 프로토콜 4종 (surfaceUpdate, beginRendering, dataModelUpdate, deleteSurface). 트리→ID 평탄화 필요 확인 |
| 2026-02-23 | **Phase 3 완료**: Lit 프론트엔드 + SSE + On/Off 제어. 멀티디바이스(Thread×2, WiFi×1). 방향 전환: OpenClaw 대신 OpenRouter 직접 연동 |
| 2026-02-20 | HomeAgent 프로젝트 문서 신설 |
| 2026-02-18 | OpenClaw Canvas A2UI v0.8 구현체 분석 |
| 2026-02-17 | A2UI + CopilotKit 패러다임 검토 |

---

## 현재 동작하는 스택 (2026-02-23)

```
브라우저 (http://192.168.69.6:8080)
  ├── Lit UI (ha-app, ha-device-card, ha-commission-dialog)
  ├── SSE /api/events → 실시간 상태 업데이트
  └── POST /api/devices/command → On/Off 제어
       │
Go homeagent v0.5.1 (:8080)
  ├── REST: /api/devices, /api/commission, /api/devices/command, /api/events
  ├── 정적 파일 서빙 (/opt/homeagent/ui/)
  ├── 자동 Thread dataset + WiFi credentials 주입
  └── Matter WS 클라이언트 (단일 ReadLoop)
       │
matterjs-server (:5580)
  ├── Node 1: Tuya Door Sensor #1 (Thread, contact_sensor)
  ├── Node 7: Tuya Door Sensor #2 (Thread, contact_sensor)
  └── Node 8: Tapo Mini Smart Wi-Fi Plug (WiFi, on_off_plug)
       │
Thread (OTBR) / WiFi (SKS&GQ_TEST_2.4)
```

### 이미 동작하는 것 ✅

| 기능 | 상태 | 비고 |
|------|:----:|------|
| 디바이스 페어링 (BLE → Thread/WiFi) | ✅ | 브라우저에서 Setup Code 입력 |
| 실시간 이벤트 (도어 열림/닫힘) | ✅ | SSE 스트리밍 |
| On/Off 제어 (스마트플러그) | ✅ | 토글 버튼 |
| 멀티 디바이스 관리 | ✅ | 3대 동시 |
| 에이전트 메시지바 | ✅ | 상태/에러 표시 (하드코딩) |

### 아직 안 되는 것 ❓

| 기능 | 상태 | 핵심 질문 |
|------|:----:|----------|
| LLM이 디바이스 상태를 이해 | ❓ | 프롬프트에 넣으면 추론 가능한가? |
| A2UI 동적 렌더링 | ❓ | LLM이 surfaceUpdate JSON을 생성할 수 있는가? |
| 자연어 → 디바이스 제어 | ❓ | "거실 불 꺼줘" → On/Off 매핑? |
| 이벤트 기반 에이전트 판단 | ❓ | 도어 열림 → 상황 판단 → 알림/액션? |
| 음성 인터페이스 (TTS/STT) | ❓ | 온디바이스 가능? 지연시간? |

---

## 핵심 철학

```
기존 앱:    [컴파일된 UI] ← 사용자 입력 대기 → [반응]
HomeAgent:  [에이전트] → 선언적 JSON → [뷰어가 렌더링]
현재:       [하드코딩 Lit] → 디바이스 카드 고정
다음:       [LLM 에이전트] → A2UI JSON → Lit 렌더러 → 상황 맞춤 UI
```

---

## 다음 단계: LLM 직접 연동 (ha-1mr.2)

### 왜 OpenClaw가 아닌 OpenRouter 직접 호출?

| 비교 | OpenClaw 경유 | OpenRouter 직접 |
|------|:------------:|:--------------:|
| 의존성 | npm -g openclaw, Gateway 프로세스 | Go HTTP 클라이언트 하나 |
| 바이너리 | Go + Node.js | Go 단일 바이너리 |
| 커스터마이징 | Gateway 플러그인 API 학습 | 프롬프트 직접 제어 |
| 디바이스 컨텍스트 | Gateway에 주입하는 방법? | 시스템 프롬프트에 직접 |
| 온디바이스 전환 | Gateway를 sLLM으로? | HTTP 엔드포인트만 바꾸면 됨 |
| 디버깅 | 블랙박스 | 프롬프트/응답 전부 가시 |

**결론**: 지금은 직접 연동이 맞다. OpenClaw는 나중에 멀티채널(Telegram, Discord) 필요 시 도입.

### 구현 계획

```
Phase A: 에이전트 채팅 (가장 빠른 검증)
──────────────────────────────────────
1. Go에서 OpenRouter API 호출 (POST /api/chat)
2. 시스템 프롬프트: 디바이스 목록 + 상태 + 제어 가능 명령
3. 사용자: "플러그 꺼줘" → LLM: {action: "off", node_id: 8} → 실행
4. UI: 채팅 패널 (메시지 입출력)
→ 검증: LLM이 디바이스 컨텍스트를 이해하고 명령을 매핑하는가?

Phase B: 이벤트 트리거 에이전트
──────────────────────────────────────
1. Matter 이벤트 발생 (도어 열림)
2. Go가 이벤트 + 디바이스 상태를 LLM에 전달
3. LLM이 판단: "밤 11시에 현관문 열림 → 경고" vs "오후 3시 → 무시"
4. 결과를 에이전트 메시지바 + TTS로 전달
→ 검증: 이벤트 기반 능동적 판단이 유용한가?

Phase C: A2UI 동적 UI
──────────────────────────────────────
1. LLM 응답에 A2UI surfaceUpdate JSON 포함
2. Lit 렌더러가 동적으로 컴포넌트 생성
3. 상황별 UI: 위험 시 경고 카드, 평상시 미니멀
→ 검증: LLM이 생성한 UI가 하드코딩보다 나은가?
```

### 시스템 프롬프트 설계 (Phase A)

```
당신은 HomeAgent, Matter 스마트홈 어시스턴트입니다.

## 현재 디바이스 상태
- Node 1: Door Window Sensor_Thread (contact_sensor) → contact: false (닫힘)
- Node 7: Door Window Sensor_Thread (contact_sensor) → contact: true (열림)  
- Node 8: Mini Smart Wi-Fi Plug (on_off_plug) → on: false (꺼짐)

## 가능한 명령
- {"action": "on", "node_id": 8}  — 플러그 켜기
- {"action": "off", "node_id": 8} — 플러그 끄기

## 규칙
- 디바이스 제어 요청 시 JSON action을 응답에 포함
- 상태 질문은 현재 데이터 기반으로 답변
- 한국어로 응답
```

### API 설계

```
POST /api/chat
  Request:  {"message": "플러그 꺼줘"}
  Response: {"reply": "플러그를 끄겠습니다.", "actions": [{"action": "off", "node_id": 8}]}

GET /api/events (SSE, 기존)
  data: {"type": "agent_message", "value": "현관문이 열렸습니다. 확인하시겠습니까?"}
```

---

## A2UI 프로토콜 참조 (Google)

- **공식**: https://a2ui.org | https://github.com/google/A2UI
- **라이선스**: Apache 2.0
- **현재**: v0.8 Public Preview (2026-02)

### 메시지 4종

| 메시지 | 역할 |
|--------|------|
| `beginRendering` | 서피스 렌더링 시작 |
| `surfaceUpdate` | UI 컴포넌트 추가/수정 |
| `dataModelUpdate` | 데이터 바인딩 업데이트 (동적 콘텐츠) |
| `deleteSurface` | 서피스 제거 |

### 표준 컴포넌트 카탈로그 (37개+)

- **Layout**: Column, Row, Card, List, Tabs, Modal, Divider
- **Text**: Text (h1~h5, body, caption)
- **Media**: Image, Icon, Video, AudioPlayer
- **Input**: TextField, Button, CheckBox, Slider, DateTimeInput, MultipleChoice

### 양방향 액션

```json
{
  "userAction": {
    "id": "uuid",
    "name": "toggle_light",
    "surfaceId": "main",
    "sourceComponentId": "living_room_light_btn",
    "context": { "target": "living_room", "action": "toggle" }
  }
}
```

---

## 참조 구현

| 프로젝트 | 역할 | HomeAgent 관계 |
|----------|------|----------------|
| [A2UI](https://a2ui.org) | UI 프로토콜 스펙 | Phase C에서 채택 |
| [OpenClaw](https://github.com/openclaw/openclaw) | A2UI v0.8 구현체 | 참조만, 의존 X |
| [CopilotKit](https://github.com/CopilotKit/CopilotKit) | AG-UI | React 기반, 참고 |
| [OpenRouter](https://openrouter.ai) | LLM 라우터 | Phase A 백엔드 |

---

## 참고

- [Flutter Shell](FLUTTER.md) — Flutter 크로스플랫폼 배포 계층 (A2UI의 delivery shell)
- [A2UI Specification v0.8](https://github.com/google/A2UI/tree/main/specification/0.8)
- [OpenRouter API Docs](https://openrouter.ai/docs)
- [OpenClaw Canvas Docs](https://docs.openclaw.ai/platforms/mac/canvas)

> 로드맵은 [README.md](../README.md#로드맵) 참조.
