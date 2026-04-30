# Go ↔ matterjs-server 중복 분석 — absorbed

이 문서의 결론은 [`ARCHITECTURE.md`](ARCHITECTURE.md)의 **ADR 2.1: Why keep Go REST when matterjs already has WebSocket?** 섹션으로 흡수했다.

## 결론

Go REST API는 삭제하지 않는다. matterjs WebSocket을 단순 포장하는 것처럼 보이는 엔드포인트도 다음 역할 때문에 유지한다.

- 외부 클라이언트 호환: 월패드, curl, Swagger/OpenAPI, HA adapter
- Go 부가 로직: aliases, room/name mapping, peer storage cleanup, SSE 변환
- Go 전용 기능: LLM chat, A2UI surface, Thread/system/config/space/subscription APIs

## 현재 경로

```text
Flutter ──WS 직접──→ matterjs (:5580)   # Matter 저지연 경로
  └──REST──→ Go (:8080)                 # 안정 외부 API + 확장 레이어
```

제거 후보는 `POST /api/wifi-credentials`, `POST /api/commission`, `POST /api/commission-on-network`이지만, 클라이언트 의존이 사라지기 전까지 유지한다.
