# Go ↔ matterjs-server 중복 분석

Phase 4 판단: Go 서버가 matterjs-server WS를 래핑하는 엔드포인트 정리.

---

## 결론: 삭제하지 않음 — "프록시+확장" 유지

Go REST API는 다음 이유로 유지:

1. **외부 클라이언트 호환** — 월패드, curl, Swagger, HA WebSocket 어댑터 등
2. **부가 로직** — aliases, peer 정리, SSE 변환, 응답 정규화
3. **Flutter 이중 경로** — 직접 WS + Go REST 동시 지원

---

## 중복 매핑 (Go REST ← matterjs WS)

| Go REST | Method | matterjs WS 명령 | Go 부가 로직 | 판단 |
|---------|--------|------------------|-------------|------|
| `/api/devices` | GET | `get_nodes` | aliases 적용 (name/room), DeviceState 정규화 | **유지** — aliases 없으면 raw node |
| `/api/devices/:id` | GET | 로컬 캐시 | 위와 동일 | **유지** |
| `/api/devices/:id` | DELETE | `remove_node` | peer 스토리지 정리 (`cleanPeerStorage`) | **유지** — 정리 없으면 디스크 누적 |
| `/api/devices/:id` | PATCH | — | aliases 수정 + 영속 (Go 전용) | **유지** — matterjs에 없음 |
| `/api/devices/command` | POST | `device_command` | attrMap 기반 SSE 변환 | **유지** — SSE 이벤트 발행 |
| `/api/commission` | POST | `commission_with_code` | WiFi creds 자동 주입 | **유지** — 편의 로직 |
| `/api/commission-on-network` | POST | `commission_on_network` | 위와 동일 | **유지** |
| `/api/wifi-credentials` | POST | `set_wifi_credentials` | 순수 래핑 | ⚠️ 제거 가능 (Flutter WS 직접) |
| `/api/events` | GET (SSE) | WS `node_updated` 구독 | Matter path → attrMap 키 변환 | **유지** — SSE는 REST 클라이언트 전용 |

---

## Go 전용 엔드포인트 (중복 아님)

| Go REST | 역할 | 의존 |
|---------|------|------|
| `/healthz` | 헬스체크 | 없음 |
| `PATCH /api/devices/:id` | aliases 수정 + 영속 | aliases.json |
| `GET /api/system` | 서버 상태 통합 | OTBR + LLM config |
| `GET /api/thread/status` | Thread 상태 | OTBR REST :8081 |
| `POST /api/chat` | LLM Agent | DeepSeek/OpenRouter |
| `GET /api/home` | A2UI Surface | 디바이스 상태 |
| `GET /api/wifi-info` | Android WiFi 감지 | Android prop |
| `/dashboard` | matterjs 대시보드 리다이렉트 | matterjs :5580 |
| `POST /api/devices/:id/attributes` | 속성 쓰기 (write_attribute) | matterjs WS |
| `GET /api/discover` | 커미셔닝 가능 디바이스 발견 | matterjs WS |
| `GET /api/devices/fabrics/:id` | 패브릭 목록 조회 | matterjs WS |
| `DELETE /api/devices/fabrics/:id` | 패브릭 제거 | matterjs WS |

---

## Phase 4 아키텍처 결정

```
Flutter ──WS 직접──→ matterjs (:5580)
  │                     │
  │                     │ (디바이스 CRUD, 이벤트, 커미셔닝)
  │
  └──REST──→ Go (:8080)
              │
              ├── aliases (PATCH, 이름/방)
              ├── sLLM (POST /api/chat)
              ├── A2UI (GET /api/home)
              ├── Thread (GET /api/thread/status)
              ├── System (GET /api/system)
              └── SSE (GET /api/events) ← 월패드/외부용
```

### Flutter 클라이언트 연결 패턴

| 기능 | 경로 | 이유 |
|------|------|------|
| 디바이스 목록/이벤트 | matterjs WS 직접 | 지연 최소, Go 우회 |
| 디바이스 제어 | matterjs WS 직접 | 지연 최소 |
| 커미셔닝 (Linux) | matterjs WS 직접 | on-network only |
| 커미셔닝 (Android) | matterjs WS + BLE relay | BLE는 Android 전용 |
| 이름/방 변경 | Go REST PATCH | aliases는 Go 전용 |
| AI 채팅 | Go REST POST /api/chat | LLM은 Go 전용 |
| 시스템 상태 | Go REST GET /api/system | 통합 정보 |

### 제거 후보 (Phase 5+)

| 엔드포인트 | 제거 조건 |
|-----------|----------|
| `POST /api/wifi-credentials` | Flutter가 matterjs WS로 직접 전송 시 |
| `POST /api/commission` | Flutter가 matterjs WS로 직접 커미셔닝 시 |
| `POST /api/commission-on-network` | 위와 동일 |

**Phase 4에서는 삭제하지 않음** — 하위 호환 유지 + 외부 클라이언트 지원.

---

## 참고: matterjs-server WS 프로토콜

```json
// 메시지 형식
{"messageId": "1", "command": "get_nodes", "args": {}}

// 응답
{"messageId": "1", "result": {...}}

// 이벤트 (start_listening 후)
{"event": "node_updated", "data": {"nodeId": 8, ...}}
```

주요 명령:
- `start_listening` — 이벤트 구독 시작
- `get_nodes` — 디바이스 목록
- `device_command` — 제어
- `commission_with_code` — 페어링 코드 커미셔닝
- `commission_on_network` — IP 커미셔닝
- `remove_node` — 디바이스 제거
- `set_wifi_credentials` — WiFi 설정
- `set_thread_dataset` — Thread dataset 주입
