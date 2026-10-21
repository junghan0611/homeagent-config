# RAIL — 현재 좌표

- [x] **1. Duo S arm64 레인 — flash-and-go 재현 · 크로스호스트 대조 · 프로파일 가드** (~2026-08-30)
- [x] **2. 스택 랜드스케이프 — 512MB에 무엇을 얹고 무엇에 말만 거나** (2026-09-01)
- [x] **3. SMHub Nano 브링업 — 크로스빌드 → ipk → Zigbee 실물 → 이기종 2허브 한 화면** (~2026-09-10)
- [x] **4. 코프로세서 발견 + ASH 관측 — `esphome-bin` = C906L 펌웨어, 43시간 창 수확** (2026-09-16, `v2026.9.16`)
- [ ] **5. 출고 제품 패키징 — 벤더 규약으로 우리 서비스를 묶어, 부팅하면 제품으로 동작** ← CURRENT: 최소 자체 서비스 패키지 명세/검증표 (구현·설치 아님)
- [ ] **6. 런타임 축 — `runtime/README.md` mailbox 계약 판단** ← PAUSED: 설계 판단이라 새 세션이 낫다
- [ ] **7. 부하 등급 판정 (RAIL 11)** ← PAUSED: 곡선이 2대에서 멈춰 있다, 기기를 더 붙여야 움직인다
- [ ] **8. 펌웨어 버전업 (RAIL 13)** ← PAUSED: 벤더 공개 이미지가 전부 hw_flow, 인덱스가 404를 배포 중

현재 좌표: 1~4 완료(`v2026.9.16`에서 닫힘) → **5가 지금 자리** → 6·7·8 보류

---

# NOW — 출고 제품 패키징 (2026-10-21)

> **Stem** (GLG 2026-10-21 «응 smhub의 이 측면을 좌표로 잡자»): 벤더 기반 위 우리 앱·서비스를
> 벤더 패키지 규약으로 묶어, **전원 인가 → 망·시각 준비 → 장비별 프로비저닝 → 우리 허브 서비스
> 실행**까지 부팅만으로 출고 제품처럼 동작하게 한다. 클라우드 IoT 연동은 그 수준을 설명한
> 예시이지 채택 결정이 아니다. ipk 해부(옛 RAIL 5 dossier)는 독립 목적이 아니라 이 stem의
> **기반 계약 조사**다.

- **Current**: 2026-10-21 보드 읽기 전용 실측 — OS 1.0.2, opkg 11개 버전 9/16과 같음.
  연결 기기 0대는 **의도된 상태**다(연결 테스트 자리가 아니다, GLG). `smhub-services` off는
  **2026-09-10 정책 그대로**다(평상시 stop·자동시작 해제, `docs/SMHUB.md` §5.6). 벤더 출고 이음매
  지도는 `docs/SMHUB.md` §9 「출고 구성」에 요약했다. Core/Home의 역할과 미실행 공동 검증안은
  `README.md` 「Hub, Edge and Core」에 정리했다. 이번에는 코드 없이 문서 정렬로 닫는다.
- **Next**: (1) 기존 ipk 증명(`smhub/pack-ipk.sh`, `smhub/RUNBOOK.md` §5·§6)과 벤더 규약
  (control의 `openrc`·`schema.json`·`postinst`+`/usr/lib/smhub/service-helpers.sh`·`<pkg>.autostart`)의
  차이표 → (2) **「최소 자체 서비스 패키지」 명세/검증표**를 쓴다 — 구현·빌드·설치가 아니다 →
  (3) 검증항목마다 「무엇을 보면 통과인가」를 적는다:
  공통 패키지·설정 vs 장비별 자격증명·상태 · 망/시각 게이트 · 재부팅 멱등성 · 자동시작 ·
  업그레이드·OTA·공장초기화·복원 생존.
- **Verify**: 표의 행마다 `[read]`/`[측정]` 근거가 붙어 있고, 검증항목마다 통과 판정이 관측
  가능한 사실(파일·프로세스·로그)로 적혀 있으면 통과.
- **미결 — 사실·정책으로 적지 마라**: seed 적재 경로(`.factory-seed` 작성 주체 미확인) ·
  (A) 벤더 이미지 repack / 벤더 커스텀 이미지 · 장비별 자격증명을 둘 자리 · 특정 클라우드 채택.
- **Blocker**: 없음. 이번 한 수는 문서·명세라 보드가 필요 없다.
- **Read**: `docs/SMHUB.md` §9 → `smhub/RUNBOOK.md` §5·§6 → `.claude/skills/smhub/SKILL.md` §2.
- **Do not touch**:
  - ⛔ **구현·빌드·보드 설치** — 명세가 먼저다. `smhub-services` 기동도 GLG go가 있을 때만.
  - ⛔ **z2m 재기동·보드 재부팅** — 기록된 크래시 둘은 모두 재기동 직후다(n=2,
    `smhub/RUNBOOK.md` §6.5.0). 43시간 로그는 9/16에 수확했고, 그 tmpfs는 이후 전원 차단으로 이미 없다.
  - ⛔ **RTOS 코어 정지/재기록** (`esphome-bin` 설치·제거 포함) — 원복 경로 미문서화.
  - ⛔ **OTA** · ⛔ **MG24 재플래시** (Zigbee 망 전체를 잃고 재페어링 = 이력 소실).
  - ⛔ 보드 `.164`(gecko) · 보드 91 · `bsp/sdk/out/quarantine/`(오염 이미지).

## GLG 판단 대기

| 무엇 | 지금 상태 |
|---|---|
| **출고 구성 미결** — seed 적재 경로 · (A) repack / 벤더 커스텀 이미지 · 장비별 자격증명 자리 · 클라우드 채택 | 5번 명세/검증표가 선행. 그 전엔 어느 것도 사실·정책으로 적지 않는다 |
| **1순위 시나리오** — Node-RED 갱신(싸다) vs Matter 브릿지(축이 크다) | GLG가 «Matter로 바로 안 간다, raw부터»라 했으므로 5번 명세가 선행 |
| **ASH 2단계** `adapter_concurrent 1 → 16` | 재페어링 때 같이. 그 전에 `tune.sh --ash-off` |
| **`smhub-services` 기동** | 평상시 stop·자동시작 해제가 정책이다(GLG 2026-09-10). 2026-10-21 실측 off. 켜야 Apps 설치·UDS 정보면이 열린다 — 켤 때마다 GLG go |
| **현재 이슈판** | [#8](https://github.com/junghan0611/homeagent-config/issues/8) 제품 패키징 현재 · [#6](https://github.com/junghan0611/homeagent-config/issues/6) 자체 이미지 보류 · [#12](https://github.com/junghan0611/homeagent-config/issues/12) ROS 독립 검수. #10은 결과 갈무리, #11은 진단 보정 후 연구 보관 종료 |

## 옆 레인에 넘어가 있는 것

**개명 `gq-node-02-r1` → `gq-smhub-01`** — GLG 지시(2026-09-16), 실행은 `works-nixos-zigbee`.
`gq-node-*` 네임스페이스를 그쪽이 가져가기 때문이고, `-r1`은 안 붙인다(온보드 라디오 하나).
**우리 보드는 건드릴 게 없다** — 이름은 마스터 DB `Hardware.Name`과 `master/nodes.json`에만 산다.

순서(마스터 정지 선행): `gq-master rename gq-node-02-r1 gq-smhub-01` → `nodes.json` 수정 →
`seed`(«추가»가 아니라 «갱신»이 찍혀야 맞다) → `status` → **그 뒤에야** `seed-prune`.
`HardwareID=3` 보존이라 기기 22개와 이력이 따라온다.

---

# RECENT

- **[2026-10-21]** 좌표 재설정 — RAIL 5 = 출고 제품 패키징(GLG). 보드 읽기 전용 실측, `smhub-services`
  1.1.0-1 해부, 벤더 출고 이음매 지도. 9/16의 Apps 「미설치」 predicate `?`는 닫혔다 — 벤더 파서가
  opkg status의 `Recommends:`에서 해석을 멈춘다(`smhub-services`·`esphome-bin`만 해당).
- **[2026-10-21]** 정체성 정리는 `CHANGELOG.md` `v2026.10.21`로 갈무리했다.
  다음은 RAIL 5. 미결: 벤더 이미지 repack 여부. 스킬·클론 목록·MG24 정정의 로컬 변경은
  해당 태그에는 포함되지 않았으며, 후속 문서 정리 커밋에서 함께 반영한다.
- **[2026-09-16]** `v2026.9.16` 컷 — 52커밋, SMHub 레인 전체. `.claude/skills/smhub/` 신설
  (피드·ipk를 보드 없이 읽는 절차가 핵심). terra 정합성 검토 반영.
- **[2026-09-16]** ASH 43시간 15분 수확: 덤프 46개 중 오류 비영 1개(그것도 CRC 정상 복구),
  `rxAckTimeouts` 전부 0. **크래시 둘은 재기동 직후**(+8분14초, +18초 `GET_EUI64`) → 고장 축이
  「부하·대수」가 아닐 수 있다. n=2. 상세 `docs/SMHUB.md` §5.8.
- **[2026-09-16]** 「미설치」는 사실이 아니었다 — `opkg`엔 `esphome-bin`·`smhub-services` 둘 다 있다.
  Web UI Apps는 정본 4층(`docs/SMHUB.md:143-152`) 어디와도 안 맞는 **다섯 번째 표기면**이고,
  그 predicate는 아직 `?`.
- **[2026-09-16]** `esphome-bin` = C906L 코프로세서 펌웨어 확정. ⚠️ **install/update와 remove는
  다른 위험**이다(그 archive에 `prerm` 없음).
- **[2026-09-14]** RAIL 18 「조이기 회귀」는 오독 — 누수가 아니라 `smhub-services` 스위치가
  켜진 채였다. 📌 **조이기 수치를 적을 땐 RSS 상위 몇 줄을 같이 남긴다.**

---

# LEDGER — 어디를 읽나

이 문서는 부트섹터다. 닫힌 일의 서사는 여기 두지 않는다.

| 찾는 것 | 어디 |
|---|---|
| 닫힌 일 전체 · 정체성 체크포인트 | `CHANGELOG.md` `v2026.9.16` · `v2026.10.21` |
| 기기 사실·버전·피드 선언·43시간 관측 | `docs/SMHUB.md` — 특히 **§5.8**(2026-09-16 현재면), §5.6, §5.7 |
| 절차 (새 유닛 → Zigbee 데이터) | `smhub/RUNBOOK.md` — **§6.5.0 「다시 세우지 마라」를 먼저 읽어라** |
| 보드 없이 벤더 선언 읽는 법 · 다섯 평면 · 금지 목록 | `.claude/skills/smhub/SKILL.md` |
| Duo S eMMC 굽기 | `.claude/skills/duo-s-flash/SKILL.md` (별개다) |
| ISA vs 프로파일 두 축, 공유 output 트리 함정 | `bsp/README.md` §profile |
| Duo S 열린 빚 (ION 148M 회수 · defconfig 주석 · corepack · Z2M 키 백업) | `bsp/README.md` §Open debts |
| 온박스에 무엇을 얹나 · 피드에 계측 스택 없음 | `docs/ECOSYSTEM-PORTFOLIO.md` §3.1, §1 |
| 시나리오 조합표·의존성 그래프 (초안) | `.agent-reports/2026-09-16-*.md` (gitignored) |
| 출고 경로 지도·`smhub-services` 해부·보드 실측 원본 (로컬 전용) | `.agent-reports/2026-10-21-smhub-*.md` (gitignored) — 공개 요약은 `docs/SMHUB.md` §9 |
| 이 세션들의 작업기 | llmlog `20260701T123010` §6 |
| 방향·페이즈 | `ROADMAP.md` |

**보류된 축**: Matter/matter.js 착수(준비 완료, GLG가 raw 우선으로 미룸) ·
S99wpa_supplicant 정리(DEPRIORITIZED 2026-09-07) · gecko 플래시 결과(우리 손 없음) ·
`[NCP COUNTERS]` 42칸 디코드(`EmberCounterType` 대조만 하면 된다, 미착수).
