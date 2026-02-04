# A2A Protocol for HomeAgent

Agent2Agent Protocol 적용 검토 문서

## History

| 날짜 | 내용 |
|------|------|
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

## 참고

- [A2A 공식 문서](https://github.com/a2aproject/A2A/tree/main/docs)
- [Google 발표 블로그](https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/)
- [Linux Foundation 프로젝트](https://www.linuxfoundation.org/press/linux-foundation-launches-the-agent2agent-protocol-project-to-enable-secure-intelligent-communication-between-ai-agents)
