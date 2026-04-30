# HomeAgent 문서 지도

이 문서는 `docs/` 아래 문서의 역할을 고정하는 문서다. 문서를 지우기보다, **어디가 SSOT인지 / 어디로 흡수될 예정인지**를 명시해서 에이전트가 엉뚱한 오래된 문서를 기준으로 작업하지 않게 한다.

## 원칙

1. **README는 공개 랜딩** — 큰 그림과 현재 방향만 둔다.
2. **AGENTS.md는 작업 지침** — 에이전트가 반드시 지켜야 할 현재 결정과 금지 규칙.
3. **VERSION.md는 버전/스택 SSOT** — 커널, 런타임, 주요 패키지 버전은 여기서 먼저 확인.
4. **HARDWARE.md는 실제 장비 상태** — IP, 동글, 보드, 물리 연결처럼 재현/복구에 필요한 정보.
5. **docs/는 근거 문서** — 설계 판단, 빌드, API, 플랫폼 차이를 보관한다.
6. 오래된 문서는 삭제하지 않는다. 대신 아래 표의 **흡수 방향**을 따라 병합/보관한다.

## 현재 핵심 문서

| 문서 | 역할 | 언제 읽나 | 흡수/정리 방향 |
|------|------|-----------|----------------|
| [`../README.md`](../README.md) | 공개 소개, 로드맵, 빠른 시작 | 처음 보는 사람/에이전트 | 세부 상태값은 줄이고 하위 문서 링크로 위임 |
| [`../AGENTS.md`](../AGENTS.md) | 에이전트 작업 지침, 인바리언트, 현재 방향 | 모든 에이전트 작업 시작 시 | 길어지면 세부 절차는 docs/HOWTO류로 분리 |
| [`../VERSION.md`](../VERSION.md) | Yocto/런타임/보드 버전 매트릭스 | 버전·스택 확인 | 중복된 히스토리는 llmlog로 내리고 현재값 중심 유지 |
| [`../HARDWARE.md`](../HARDWARE.md) | 실제 RPi5/OPi5 장비 상태 | 재플래시/SSH/동글 문제 | 실제 물리 상태만 남긴다 |
| [`../HOWTO.md`](../HOWTO.md) | RPi5 클린 재현 + Android 배포 요약 | 처음부터 빌드/플래시/배포 | `docs/INSTALL.md` 핵심 흡수 완료 |
| [`../INVARIANTS.md`](../INVARIANTS.md) | 런타임 체크리스트 | 코드 수정/리뷰 | AGENTS의 금지 규칙과 상호 링크 유지 |

## docs/ 설계·구현 문서

| 문서 | 역할 | 언제 읽나 | 흡수/정리 방향 |
|------|------|-----------|----------------|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | ADR: Go, Flutter, matter backend, 프로세스 분리, 부팅 복원 | 구조 변경 전 | `GO-MATTERJS-OVERLAP.md` 결론 흡수 완료 |
| [`API.md`](API.md) | HomeAgent REST/SSE API 명세 | API/클라이언트 작업 | OpenAPI 생성물과 동기화 필요. 엔드포인트 수 수동 기입 주의 |
| [`BUILD.md`](BUILD.md) | 개발/빌드팜/산출물 워크플로 | 빌드·배포·dist 정리 | 절차는 HOWTO, 자원/빌드팜은 BUILD |
| [`FLUTTER.md`](FLUTTER.md) | Flutter shell, NixOS 빌드, WebView/Native 구조 | UI/앱 작업 | flutter/README.md는 이 문서로 위임 |
| [`THREAD.md`](THREAD.md) | OTBR, RCP, Thread 네트워크 | Thread/Matter 연결 문제 | HARDWARE의 실제 동글 상태와 구분 |
| [`MATTER.md`](MATTER.md) | Matter SDK/matter.js 본류와 Android BLE 경계 | Matter backend 변경 | python-matter-server는 deprecated 참고만 |
| [`A2A.md`](A2A.md) | Agent protocol, AgentCard, Constitutional AI | A2A/에이전트 연동 | 철학+구현이 길어지면 구현 절차 분리 |
| [`A2UI.md`](A2UI.md) | 서버 주도 UI, surface, 동적 UI 전략 | UI surface/LLM UI 작업 | README에는 한 문단만 남김 |
| [`PLATFORM-MATRIX.md`](PLATFORM-MATRIX.md) | RPi5/RK3576/OPi5 플랫폼 차이 | 플랫폼별 분기 작업 | README 플랫폼 표의 상세판 |
| [`YOCTO-OFFLINE-FIRST.md`](YOCTO-OFFLINE-FIRST.md) | Yocto 오프라인 레시피 정책 | recipe/npm/pip 추가 | 반드시 유지. 삽질 방지 문서 |
| [`EDGE-ZIGBEE.md`](EDGE-ZIGBEE.md) | HomeAgent ↔ Edge/Zigbee/MQTT 경계 | Zigbee/MQTT 이야기가 나올 때 | edgeagent-config와의 책임 분리 문서 |

## 보류·흡수 후보 문서

이 문서들은 삭제하지 않는다. 다만 새 작업의 1차 기준으로 삼지 말고, 아래 방향으로 흡수한다.

| 문서 | 현재 성격 | 흡수/이동 방향 |
|------|-----------|----------------|
| [`GO-MATTERJS-OVERLAP.md`](GO-MATTERJS-OVERLAP.md) | Go REST ↔ matterjs WS 중복 분석 | **흡수 완료** — `ARCHITECTURE.md` ADR 2.1 참조 |
| [`MATTER-VERIFY.md`](MATTER-VERIFY.md) | 2026-03 RK3576 Matter 검증 로그 | **흡수 완료** — `MATTER.md` BLE boundary 섹션 참조 |
| [`INSTALL.md`](INSTALL.md) | Android/배포 설치 가이드 | **흡수 완료** — `HOWTO.md` Android/RK3576 섹션 참조 |
| [`MQTT-HA.md`](MQTT-HA.md) | MQTT/HA/Zigbee 전략 | **흡수 완료** — `EDGE-ZIGBEE.md` 참조 |
| [`ZIGBEE2MQTT_UPSTREAM_GUIDE.md`](ZIGBEE2MQTT_UPSTREAM_GUIDE.md) | Zigbee2MQTT upstream 기여 가이드 | **흡수 완료** — `EDGE-ZIGBEE.md` 참조 |
| [`TARGET_DEVICE.md`](TARGET_DEVICE.md) | Hailo/RK3588/제품 보드 전략 | **흡수 완료** — `VERSION.md` Target device strategy 참조 |

## 현재 방향 메모

- HomeAgent 본류는 **RPi5 + Yocto + matter.js + Matter/Thread + Hailo/sLLM/A2A** 중심.
- OPi5는 **mainline 6.14 lab target**으로 보존한다. vendor 6.1/RKNN NPU 경로는 보류하고 llmlog `20260331T114944`를 참고한다.
- ESP32/Zig 계열 edge 작업은 `~/repos/gh/edgeagent-config`로 분리한다.
- 장난감/교육용 에이전트는 `~/repos/gh/legoagent-config`로 분리한다.
