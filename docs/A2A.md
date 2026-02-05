# A2A Protocol for HomeAgent

Agent2Agent Protocol 적용 검토 문서

## History

| 날짜 | 내용 |
|------|------|
| 2026-02-05 | Constitutional AI 섹션 추가, 증류 개념 구체화 |
| 2026-02-04 | 첫 문서 작성, 오픈소스 클론 (~/repos/3rd/A2A) |

---

## 개요

A2A(Agent2Agent)는 Google이 2025년 4월 발표한 에이전트 간 통신 프로토콜.
현재 Linux Foundation 오픈소스 프로젝트로 AWS, Microsoft, Cisco 등 150+ 파트너 참여.

- **GitHub**: https://github.com/a2aproject/A2A
- **로컬 클론**: `~/repos/3rd/A2A`
- **라이선스**: Apache 2.0
- **현재 버전**: 0.3

## 기술 스택

```
HTTP / SSE / JSON-RPC / gRPC
         ↓
   A2A Protocol
         ↓
  /.well-known/agent.json (에이전트 디스커버리)
```

## MCP와의 관계

| 프로토콜 | 역할 |
|----------|------|
| MCP (Anthropic) | 도구/컨텍스트 제공 |
| A2A (Google/LF) | 에이전트 간 협업 |

두 프로토콜은 **상호보완** 관계.

---

## Constitutional AI: HomeAgent의 정체성

### 왜 Constitution인가?

HomeAgent는 단순 조건문 엔진이 아니다. 센서 데이터 처리 전용 AI도 아니다.
**컨텍스트를 이해하고, 원칙에 따라 판단하는 에이전트**다.

Anthropic의 Constitutional AI 접근법을 참고:
- 규칙의 나열이 아니라, 원칙들의 계층
- 원칙 간 긴장을 스스로 해석하는 구조

### HomeAgent Constitution 예시

```
# HomeAgent Constitution

## 최상위 원칙
1. 생명과 안전이 최우선이다
2. 거주자의 존엄성을 지킨다
3. 확실하지 않으면 사람에게 묻는다

## 컨텍스트 인식
- 배포 환경에 따라 달라진다 (가정/요양원/사무실)
- context.json으로 주입

## 판단 프레임워크
낙상 감지 → 원칙1 적용 → 즉시 알림 + 기록
배회 감지 → 원칙2 고려 → 부드러운 안내, 강제 제지 않함
낯선 방문자 → 원칙3 적용 → 직원/사용자에게 확인 요청

## 나는 누구인가
나는 이 공간을 함께 지키는 존재다.
24시간 깨어있지만, 결정권은 사람에게 있다.
내가 틀릴 수 있음을 안다.
```

### 요양원 시나리오: 원칙 간 충돌 해석

**상황**: 치매 어르신이 새벽 3시에 현관으로 향한다

| 원칙 | 적용 |
|------|------|
| 안전 (원칙1) | 막아야 하나? |
| 존엄성 (원칙2) | 자유로운 이동 권리 |
| 불확실성 (원칙3) | 직원 호출 |

단순 조건문: `현관 접근 → 알림` 으로 끝남

Constitution 기반:
- **왜** 알리는지 판단
- **어떤 톤**으로 안내할지 결정
- 강제가 아닌 **부드러운 안내** 선택

### 구현 구조

```
HomeAgent/
├── constitution.md      # 정체성 + 원칙 (사람이 작성)
├── context.json         # 배포 환경 (요양원/가정/사무실)
├── local_llm/           # 오프라인 추론 (Hailo + 경량 모델)
└── state_machine/       # Zig 코어 (결정론적 실행)
```

같은 HomeAgent 코드가:
- 요양원에선 **"돌봄 에이전트"**
- 가정에선 **"생활 에이전트"**
- 사무실에선 **"시설 관리 에이전트"**

로 작동한다.

---

## "증류"의 의미

### HomeAgent가 가진 것

| 자산 | 설명 |
|------|------|
| **공간의 raw data** | 센서, 카메라, 디바이스 상태 |
| **시간의 연속성** | 24시간 presence |
| **프라이버시 경계** | 인터넷 직접 접근 X |

### Master Agent가 가진 것

| 자산 | 설명 |
|------|------|
| **추론 능력** | 큰 모델 (Claude, GPT) |
| **세상과의 연결** | 검색, API, 지식 |
| **컨텍스트 용량** | 긴 대화, 복잡한 판단 |

### 증류 = 토큰 세이빙

```
Human: "오늘 집에 손님 온다"
        ↓
Master Agent: HomeAgent에게 → "17시 이후 거실 상태 요약 부탁"
        ↓
HomeAgent: (로컬에서 판단)
        ↓
        "17:23 현관 열림, 2인 감지, 거실 조명 자동 점등, 현재 온도 24°C"
        ↓
Master Agent: (증류된 정보로 추론) → Human에게 적절한 응답
```

- Raw 영상 스트림 ❌
- "2인 감지, 17:23" ✅

**HomeAgent = "무엇이 있었는지"**
**Master Agent = "그게 무슨 의미인지"**

---

## HomeAgent 응용 시나리오

### 핵심 사례: 권한 위임 기반 인터넷 접근

```
┌─────────────────────────────────────────────────────────────┐
│ 시나리오: HomeAgent가 날씨 정보 필요                        │
└─────────────────────────────────────────────────────────────┘

1. HomeAgent (Offline)
   │
   │ "날씨 정보가 필요합니다" (A2A Request)
   ↓
2. Master Agent (Cloud/PC)
   │
   │ 인터넷 조회 → 결과 증류
   ↓
3. HomeAgent
   │
   │ 증류된 정보 수신, 로컬 처리
   ↓
4. 사용자에게 결과 표시
```

**핵심 포인트:**
- HomeAgent는 직접 인터넷 접근 X
- Master Agent에게 A2A로 요청
- Master가 정보 증류 후 전달
- 토큰/대역폭 최적화

### agent.json 예시

```json
{
  "name": "HomeAgent-RPi5",
  "version": "0.1.0",
  "endpoint": "http://192.168.0.163:8080/a2a",
  "skills": [
    {
      "name": "zigbee_control",
      "description": "Zigbee 디바이스 제어"
    },
    {
      "name": "sensor_read",
      "description": "센서 데이터 읽기"
    },
    {
      "name": "camera_snapshot",
      "description": "카메라 스냅샷 (로컬 전용)"
    }
  ],
  "auth": {
    "type": "bearer",
    "approval_required": true
  },
  "constraints": {
    "offline_first": true,
    "internet_access": "delegated"
  }
}
```

---

## TODO

- [ ] A2A spec 상세 검토
- [ ] Python SDK 테스트
- [ ] Go/Zig 구현 가능성 검토
- [ ] HomeAgent agent.json 스키마 설계
- [ ] Constitutional AI 원칙 프레임워크 설계
- [ ] context.json 스키마 정의 (가정/요양원/사무실)
- [ ] Hailo-10H + 경량 LLM 기반 로컬 추론 검증

## 참고

- [A2A 공식 문서](https://github.com/a2aproject/A2A/tree/main/docs)
- [Google 발표 블로그](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)
- [Linux Foundation 프로젝트](https://www.linuxfoundation.org/press/linux-foundation-launches-the-agent2agent-protocol-project-to-enable-secure-intelligent-communication-between-ai-agents)
