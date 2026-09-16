# RAIL — 현재 좌표

- [x] **1. Duo S arm64 레인 — flash-and-go 재현 · 크로스호스트 대조 · 프로파일 가드** (~2026-08-30)
- [x] **2. 스택 랜드스케이프 — 512MB에 무엇을 얹고 무엇에 말만 거나** (2026-09-01)
- [x] **3. SMHub Nano 브링업 — 크로스빌드 → ipk → Zigbee 실물 → 이기종 2허브 한 화면** (~2026-09-10)
- [x] **4. 코프로세서 발견 + ASH 관측 — `esphome-bin` = C906L 펌웨어, 43시간 창 수확** (2026-09-16, `v2026.9.16`)
- [ ] **5. 벤더 앱 카탈로그를 의존성으로 검증** ← CURRENT: ipk dossier부터 (보드 무접촉)
- [ ] **6. 런타임 축 — `runtime/README.md` mailbox 계약 판단** ← PAUSED: 설계 판단이라 새 세션이 낫다
- [ ] **7. 부하 등급 판정 (RAIL 11)** ← PAUSED: 곡선이 2대에서 멈춰 있다, 기기를 더 붙여야 움직인다
- [ ] **8. 펌웨어 버전업 (RAIL 13)** ← PAUSED: 벤더 공개 이미지가 전부 hw_flow, 인덱스가 404를 배포 중

현재 좌표: 1~4 완료(`v2026.9.16`에서 닫힘) → **5가 지금 자리** → 6·7·8 보류

---

# NOW — 이어받는 자리 (2026-09-16)

> **한 줄**: 태그를 끊었고 보드는 관측 상태로 서 있다. 다음 한 수는 **보드에 안 붙고**
> ipk를 더 읽어 시나리오 조합표의 `?`를 줄이는 것이다.

- **Current**: `v2026.9.16` 컷 완료. 보드 무접촉 43시간 증거 살아 있음
  (`log_level: info` · `log_output: [console]` · `adapter_concurrent: 1`, uptime 6일).
- **Next**: (1) `matterbridge` · `matterbridge-z2m` · `picoclaw-core` · `tailscale` · `openthread`의
  ipk를 `smhub` 스킬 §2.2 절차로 받아 `control`/`openrc`/`postinst`를 읽는다 →
  (2) 각각의 OpenRC 서비스·실행 방식·기본 설정·포트를 표로 만든다 →
  (3) `.agent-reports/2026-09-16-smhub-dependency-scenarios-terra.md`의 `?` 중 무엇이 닫혔는지 판정.
- **Verify**: 「이 시나리오는 어떤 데몬이 뜨고, 무엇과 배타이고, 되돌리는 법이 무엇인가」에
  **추정 없이** 답할 수 있으면 통과. RSS만은 여전히 실행 전 미지수다 — 그건 `?`로 남겨라.
- **Blocker**: 없음. 보드도 네트워크도 필요 없다(피드 인증만).
- **Read**: `.claude/skills/smhub/SKILL.md` §2 → `docs/SMHUB.md` §5.8 → 위 terra 보고서.
- **Do not touch**:
  - ⛔ **z2m 재기동·보드 재부팅** — 43시간 무크래시 구간이 지금 가장 비싼 증거이고,
    콘솔 로그가 `/tmp`(tmpfs)라 재부팅하면 사라진다. 재기동 자체가 크래시 용의선상이다
    (`smhub/RUNBOOK.md` §6.5.0).
  - ⛔ **RTOS 코어 정지/재기록** (`esphome-bin` 설치·제거 포함) — 원복 경로 미문서화.
  - ⛔ **OTA** · ⛔ **MG24 재플래시** (Zigbee 망 전체를 잃고 재페어링 = 이력 소실).
  - ⛔ 보드 `.164`(gecko) · 보드 91 · `bsp/sdk/out/quarantine/`(오염 이미지).

## GLG 판단 대기

| 무엇 | 지금 상태 |
|---|---|
| **1순위 시나리오** — Node-RED 갱신(싸다) vs Matter 브릿지(축이 크다) | GLG가 «Matter로 바로 안 간다, raw부터»라 했으므로 5번 dossier가 선행 |
| **ASH 2단계** `adapter_concurrent 1 → 16` | 재페어링 때 같이. 그 전에 `tune.sh --ash-off` |
| **`smhub-services` 정지** (+80MB 회수) | 지금은 그냥 둔다(GLG 2026-09-14). ⚠️ 끄면 Apps 화면에서 **설치가 막힌다** — 필요한 설치를 끝낸 뒤에만 |
| **이슈 본문 둘** | [#10](https://github.com/junghan0611/homeagent-config/issues/10) 본문이 닫힌 「보드에 domoticz」를 열린 과제로 지시 · [#11](https://github.com/junghan0611/homeagent-config/issues/11)이 현재 근거보다 강하고 `rxAckFrames` 논거가 빠졌다 |

## 옆 레인에 넘어가 있는 것

**개명 `gq-node-02-r1` → `gq-smhub-01`** — GLG 지시(2026-09-16), 실행은 `works-nixos-zigbee`.
`gq-node-*` 네임스페이스를 그쪽이 가져가기 때문이고, `-r1`은 안 붙인다(온보드 라디오 하나).
**우리 보드는 건드릴 게 없다** — 이름은 마스터 DB `Hardware.Name`과 `master/nodes.json`에만 산다.

순서(마스터 정지 선행): `gq-master rename gq-node-02-r1 gq-smhub-01` → `nodes.json` 수정 →
`seed`(«추가»가 아니라 «갱신»이 찍혀야 맞다) → `status` → **그 뒤에야** `seed-prune`.
`HardwareID=3` 보존이라 기기 22개와 이력이 따라온다.

---

# RECENT

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
| 닫힌 일 전체 (7월~9월) | `CHANGELOG.md` `v2026.9.16` |
| 기기 사실·버전·피드 선언·43시간 관측 | `docs/SMHUB.md` — 특히 **§5.8**(2026-09-16 현재면), §5.6, §5.7 |
| 절차 (새 유닛 → Zigbee 데이터) | `smhub/RUNBOOK.md` — **§6.5.0 「다시 세우지 마라」를 먼저 읽어라** |
| 보드 없이 벤더 선언 읽는 법 · 다섯 평면 · 금지 목록 | `.claude/skills/smhub/SKILL.md` |
| Duo S eMMC 굽기 | `.claude/skills/duo-s-flash/SKILL.md` (별개다) |
| ISA vs 프로파일 두 축, 공유 output 트리 함정 | `bsp/README.md` §profile |
| Duo S 열린 빚 (ION 148M 회수 · defconfig 주석 · corepack · Z2M 키 백업) | `bsp/README.md` §Open debts |
| 온박스에 무엇을 얹나 · 피드에 계측 스택 없음 | `docs/ECOSYSTEM-PORTFOLIO.md` §3.1, §1 |
| 시나리오 조합표·의존성 그래프 (초안) | `.agent-reports/2026-09-16-*.md` (gitignored) |
| 이 세션들의 작업기 | llmlog `20260701T123010` §6 |
| 방향·페이즈 | `ROADMAP.md` |

**보류된 축**: Matter/matter.js 착수(준비 완료, GLG가 raw 우선으로 미룸) ·
S99wpa_supplicant 정리(DEPRIORITIZED 2026-09-07) · gecko 플래시 결과(우리 손 없음) ·
`[NCP COUNTERS]` 42칸 디코드(`EmberCounterType` 대조만 하면 된다, 미착수).
