# SMHUB 벤더 매뉴얼 — 검토 인덱스 (다음 세션 작업 목록)

출처: <https://smlight.tech/support/manuals/books/smhub> (BookStack, 2026-07-01 스냅샷, 22 페이지).
목적: 벤더가 공식 문서로 제공하는 절차/기능을 **하나씩 검토**하며 (1) 제품화 세트에 엮을 것,
(2) 검수(verify) 항목, (3) 이미 라이브로 확인한 것을 대조한다. `[ ]` = 미검토, `[x]` = 검토 완료.

> 검토 시 각 행에 "벤더 절차 ↔ 우리 라이브 실측" 대조 결과를 `docs/PRODUCT-CONFIG-MODEL.md`
> 또는 `captures/`에 남긴다. 버전 종속 값은 스냅샷일 뿐(§버전 드리프트) — 절차/구조를 본다.

## A. Restore & Updating (OTA / 복구 / 접근)
우리 OTA·백업·SSH 게이트와 직접 연관. 이미 0.9.8 블록 백업·SSH 접근은 라이브로 확보함.

- [ ] [SMHUB OS - Update & Restore Methods](https://smlight.tech/support/manuals/books/smhub/page/smhub-os-update-restore-methods) — A/B·RAUC·복구 경로 총론. **OTA beta5 게이트 전 필독.**
- [ ] [Update/Restore using Type-C](https://smlight.tech/support/manuals/books/smhub/page/updaterestore-using-type-c) — full flash 경로. rollback 검증 뒤에만 (NEXT §Do not touch).
- [ ] [Update/Restore using SD-Card](https://smlight.tech/support/manuals/books/smhub/page/updaterestore-using-sd-card) — SD 복구 경로.
- [ ] [SMHUB Early Adopter – Quick Start Guide](https://smlight.tech/support/manuals/books/smhub/page/smhub-early-adopter-quick-start-guide) — 초기 부팅/셋업 전제.
- [ ] [Access SMHUB via External SSH client](https://smlight.tech/support/manuals/books/smhub/page/access-smhub-via-external-ssh-client) — 벤더 공식 SSH 활성 절차. **우리 우회(/tmp/hk sshd)와 대조.**
- [ ] [SMHUB-OS release notes](https://smlight.tech/support/manuals/books/smhub/page/smhub-os-release-notes) — 버전별 변경. 로컬 `smhub-os-release-notes.org`(PRIVATE) 있음 → 최신분 대조.

## B. Product Description (핵심 레퍼런스, 1~8·10)
제품 세트를 "무엇으로 엮나"의 벤더 기준. **§6 Radios & Protocols 가 우리 뼈대와 직결.**

- [ ] [1. Introduction](https://smlight.tech/support/manuals/books/smhub/page/1-introduction)
- [ ] [2. Hardware Overview](https://smlight.tech/support/manuals/books/smhub/page/2-hardware-overview) — MG24/SG2000/주변장치 공식 스펙. Z-Wave 부재 등 대조.
- [ ] [3. Getting Started](https://smlight.tech/support/manuals/books/smhub/page/3-getting-started)
- [ ] [4. Software & System](https://smlight.tech/support/manuals/books/smhub/page/4-software-system) — 앱/서비스 모델. backend.db·OpenRC 라이브 대조.
- [ ] [5. Network & Connectivity](https://smlight.tech/support/manuals/books/smhub/page/5-network-connectivity)
- [ ] [6. Radios & Protocols](https://smlight.tech/support/manuals/books/smhub/page/6-radios-protocols) — **★ Zigbee/Thread 배타·MG24 모드. ember coordinator 라이브 확정과 대조.**
- [ ] [7. User Interface](https://smlight.tech/support/manuals/books/smhub/page/7-user-interface) — Web UI 앱 토글 = backend.db.apps 대조.
- [ ] [8. Modules & Extensions](https://smlight.tech/support/manuals/books/smhub/page/8-modules-extensions) — matterbridge/z2m/otbr/zwave 등 모듈 카탈로그.
- [ ] [10. Glossary](https://smlight.tech/support/manuals/books/smhub/page/10-glossary)

## C. Task Guides (기능별 절차 — 검수/세트 후보)
"제품 기능을 끝까지 검증"의 실제 절차. 검수 매트릭스 rows 의 원천.

- [ ] [Connecting Zigbee2MQTT on SMHUB to Home Assistant](https://smlight.tech/support/manuals/books/smhub/page/connecting-zigbee2mqtt-on-smhub-to-home-assistant) — **Zigbee 먼저 검증 경로.**
- [ ] [Using SMHUB as Thread Border Router for Matter devices](https://smlight.tech/support/manuals/books/smhub/page/using-smhub-as-thread-border-router-for-matter-devices) — Thread/OTBR(현재 보류, Matter-only 재고 시).
- [ ] [Run Thread networks](https://smlight.tech/support/manuals/books/smhub/page/run-thread-networks) — Thread 운용(보류 레인).
- [ ] [Change IEEE address on SMHUB radio](https://smlight.tech/support/manuals/books/smhub/page/change-ieee-address-on-smhub-radio) — coordinator IEEE. per-unit 프로비저닝과 연관.
- [ ] [SMHUB Peripheral (IR, Buzzer, Ambilight) Control Guide](https://smlight.tech/support/manuals/books/smhub/page/smhub-peripheral-ir-buzzer-ambilight-control-guide) — `/etc/peripherals/*.conf` 실제 스키마. (GPT가 지어냈던 부분 → 여기서 정본 확보.)
- [ ] [Tailscale set-up](https://smlight.tech/support/manuals/books/smhub/page/tailscale-set-up) — 원격 접근(선택).
- [ ] [Troubleshooting](https://smlight.tech/support/manuals/books/smhub/page/troubleshooting) — 장애 대응 레퍼런스.

## 검토 우선순위 (다음 세션 제안)
1. **B-6 Radios & Protocols** + **C Zigbee2MQTT→HA** — 우리 기본 프로필(z2m+matterbridge) 검증의 핵심.
2. **A Update & Restore Methods** + **A External SSH** — OTA/백업 게이트 절차 정본화.
3. **B-2/4/7/8** — 하드웨어/소프트웨어/UI/모듈 = backend.db·OpenRC 라이브 대조.
4. **C Peripheral Control Guide** — 주변장치 conf 정본(지어낸 값 대체).
5. 나머지(Thread/Tailscale/Glossary) — 보류/선택.
