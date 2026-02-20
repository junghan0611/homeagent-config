# A2UI: Agent-to-User Interface

HomeAgent의 동적 UI 전략. 에이전트가 선언적 JSON으로 UI를 기술하면 뷰어가 렌더링한다.

## History

| 날짜 | 내용 |
|------|------|
| 2026-02-20 | HomeAgent 프로젝트 문서 신설 |
| 2026-02-18 | OpenClaw Canvas A2UI v0.8 구현체 분석 |
| 2026-02-17 | A2UI + CopilotKit 패러다임 검토 |

---

## 핵심 철학

```
기존 앱:    [컴파일된 UI] ← 사용자 입력 대기 → [반응]
HomeAgent:  [에이전트] → 선언적 JSON → [뷰어가 렌더링]
```

- 프론트엔드를 코드로 고정하지 않음
- 에이전트가 **무엇을 어떻게 보여줄지** 결정
- UI는 뷰어일 뿐 — 데이터를 받아 표현하는 렌더러
- 빛, 형태, 움직임으로 공간과 소통하는 디지털 아트

---

## A2UI 프로토콜 (Google)

- **공식**: https://a2ui.org | https://github.com/google/A2UI
- **라이선스**: Apache 2.0
- **현재**: v0.8 Public Preview (2026-02)

### 설계 원칙

| 원칙 | HomeAgent 대응 |
|------|----------------|
| 선언적 JSON — 실행 코드가 아닌 데이터 | 에이전트가 코드 주입 불가, 보안 내재 |
| JSONL 스트리밍 (SSE/WebSocket) | 점진적 렌더링, 토큰 세이빙 |
| 컴포넌트 카탈로그 | 클라이언트가 지원 범위 선언, 에이전트는 그 안에서 구성 |
| LLM 최적화 | 평탄한 JSON 구조, 스트리밍 생성에 적합 |

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

### 메시지 예시

```json
{
  "surfaceUpdate": {
    "surfaceId": "main",
    "components": [
      {
        "id": "temp",
        "component": {
          "Text": {
            "text": { "path": "/sensors/living_room/temperature" },
            "usageHint": "h2"
          }
        }
      }
    ]
  }
}
```

---

## HomeAgent 아키텍처

```
HomeAgent (에이전트, RPi5)
    │ A2UI JSONL (선언적 JSON)
    │ WebSocket / SSE
    ▼
뷰어 (다중 클라이언트)
    ├→ RPi5 로컬 디스플레이 (Weston/Wayland, Lit 렌더러)
    ├→ 웹 브라우저 (CopilotKit + AG-UI)
    └→ 모바일 (네이티브 브릿지)
```

**핵심**: 동일 A2UI 프로토콜로 모든 클라이언트에 동일 경험 제공.
에이전트 로직은 하나, 렌더러만 플랫폼별로 다름.

### 양방향 액션

```
사용자 버튼 클릭
  → 뷰어 이벤트 (userAction)
  → WebSocket → HomeAgent
  → 에이전트가 새 A2UI 메시지 생성
  → 뷰어 업데이트
```

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

## 참조 구현: OpenClaw Canvas

[OpenClaw](https://github.com/openclaw/openclaw)가 A2UI v0.8을 Canvas에 완전 내장:

```
Agent (LLM)
  ↓ A2UI JSONL
Gateway (WebSocket, port 18789)
  ↓
Canvas Host (HTTP: /__openclaw__/a2ui/)
  ↓
Lit Renderer (<openclaw-a2ui-host>)
  ↓ 네이티브 브릿지
macOS / iOS / Android / Web
```

- Lit 기반 커스텀 엘리먼트: `<openclaw-a2ui-host>`
- 네이티브 브릿지: iOS(WebKit), Android(JS Interface), Web(globalThis)
- 보안: 로컬 canvas URL만 허용, 디렉토리 탈출 차단

**시사점**:
1. CopilotKit 없이도 A2UI 뷰어 구현 가능 — Lit 렌더러만으로 충분
2. HomeAgent(RPi5)와 동일 프로토콜 공유 가능
3. 동일 JSONL 메시지 형식으로 웹/네이티브 동시 지원

---

## 관련 프레임워크

| 프로젝트 | 역할 | 관계 |
|----------|------|------|
| [A2UI](https://a2ui.org) | UI 프로토콜 스펙 | HomeAgent가 채택하는 프로토콜 |
| [OpenClaw](https://github.com/openclaw/openclaw) | A2UI 구현체 | Canvas에 v0.8 내장, 참조 아키텍처 |
| [CopilotKit](https://github.com/CopilotKit/CopilotKit) | 에이전트 UI 프레임워크 | AG-UI 프로토콜, A2UI + React 렌더링 |
| [pi-mono](https://github.com/badlogic/pi-mono) | 에이전트 인프라 | TUI/Web UI 라이브러리, 에이전트 툴킷 |

---

## HomeAgent 시나리오

### 센서 대시보드 (능동적 표현)

에이전트가 환경에 따라 UI를 동적으로 구성:

```
평상시:   온도/습도 텍스트 + 아이콘
손님 감지: 환영 메시지 + 조명 상태 카드
위험 감지: 경고 배경 + 알림 버튼 + 상세 정보
```

에이전트가 `surfaceUpdate`로 컴포넌트를 추가/교체/제거.
앱을 재배포하거나 코드를 수정할 필요 없음.

### 디지털 아트 모드

입력 대기가 아닌 능동적 표현:
- 에이전트가 `beginRendering`으로 캔버스 생성
- 시간/날씨/센서 데이터에 따라 색상/형태 변화
- 사용자 액션 없이도 에이전트가 먼저 표현

---

## 참고

- [A2UI Specification v0.8](https://github.com/google/A2UI/tree/main/specification/0.8)
- [OpenClaw Canvas Docs](https://docs.openclaw.ai/platforms/mac/canvas)
- [CopilotKit AG-UI](https://docs.copilotkit.ai)
- [Vercel AI SDK streamUI](https://ai-sdk.dev/docs/ai-sdk-rsc) — React 컴포넌트 스트리밍 참고

> 로드맵은 [README.md](../README.md#로드맵) 참조.
