# 단일 라디오 동시 멀티프로토콜 (Zigbee + Thread) — 핵심 난제 / 증명 계획

이 리포의 **1:1 재현 레인에서 가장 중요한 난제**의 SSOT다. 질문 하나:

> **SMHub의 단일 EFR32MG24 하나로, Zigbee 코디네이터와 Thread Border Router를 동시에** 돌릴 수 있는가?
> (DIRIGERA는 이걸 MG21 **2개**로 푼다 — `docs/HUBS.md §2.2`.) 이게 되면 라디오 1개짜리 저가 기판으로
> 인증 허브의 "Zigbee+Thread 동시"를 따라잡고, 가성비 + 오픈소스 기여가 동시에 선다.

결론 먼저: **문서화된 솔루션이 실재한다(Silabs AN1333).** 단일 UART `/dev/ttyS1` 하나로 잡히고, host가
멀티플렉싱한다. **단 "타임슬라이싱"은 두 모드로 갈리고, 생태계·Open Home Foundation·벤더 SMHub까지
모두 안정성 때문에 지금은 2-라디오/순차로 간다.**

**스탠스(중요)**: **지금 이걸 개발해 증명할 계획이 아니다.** 현시점(2026) 단일칩 동시는 아직 프로덕션
기본값이 아니고, 2-라디오(DIRIGERA·SMHub Essential) 또는 순차 모드전환(SMHub Nano)이 정답이다 — 이걸
억지로 MG24에서 돌리려는 삽질은 안 한다. 이 문서의 목적은 **전략과 시점** = "단일칩 방향이 **언제** 옳아
지는가(칩·스택 궤적)"를 추적하는 것이다(§3.7). SMHub는 인증 제품이 아니라 **개발·검증 vehicle**이므로,
지금은 실용적으로 가고 **CMP 대응 칩(MG26/Series 3)으로 플립할 준비만** 해둔다. §4 게이트는 그때를 위한
**선택적 readiness probe**이지 현재 의무가 아니다.

---

## 1. 문서화된 아키텍처 — Multi-PAN RCP + CPC (Silabs AN1333)

```
EFR32MG24  [재플래시 필요: Multi-PAN RCP 펌웨어 = OpenThread 802.15.4 RCP + multi-PAN + CPC, ~150K flash]
   │  단일 UART  /dev/ttyS1   (Spinel 메시지를 CPC 프로토콜로 캡슐화, HW flow control 권장)
   ▼
cpcd  (Co-Processor Communication Daemon)  ── 물리 링크 소유 + 프로토콜 스트림 멀티플렉싱
   ├─ zigbeed   (호스트 Zigbee 스택, Spinel-over-CPC 소켓, IID=1, 자기 PAN)
   │               └→ pty(EZSP NCP처럼 보임) → z2m / ZHA
   └─ otbr-agent (ot-rcp, Spinel-over-CPC 소켓, IID=2, 별도 PAN)
                   └→ OTBR → Matter-over-Thread
```

- **`/dev/ttyS1` 하나로 잡힌다는 직관이 맞다.** 물리 UART는 **cpcd**가 독점 소유하고, 그 위에서 여러
  프로토콜 스트림을 CPC로 멀티플렉싱한다. host 앱(zigbeed·otbr)은 각각 소켓으로 cpcd에 붙는다.
- **Spinel + IID(Interface ID)**: 각 host 스택에 고유 IID를 부여해 한 RCP를 공유한다. RCP를 나눠 쓰는
  사실은 host 앱엔 투명하다. Zigbee는 **별도 PAN**, Thread는 **또 다른 PAN**으로 분리된다.
- **zigbeed**: EmberZNet Zigbee 스택을 host에서 돌리고, z2m/ZHA에는 pty로 **EZSP NCP처럼** 노출한다
  (z2m 입장에선 여전히 "시리얼 NCP"). 내부적으로 EZSP ↔ Spinel-over-CPC 변환.
- **Multi-PAN RCP 펌웨어**: OpenThread 802.15.4 RCP에 multi-PAN + CPC를 더한 것. flash ~150K → MG24
  (1024~1536K)엔 여유. 현재 SMHub MG24는 **EmberZNet NCP(EZSP)** 펌웨어라 **반드시 재플래시**해야 한다.

---

## 2. "타임슬라이싱"의 진실 — 두 모드로 갈린다

사용자 직관("타임슬라이싱을 하든 뭘 하든")이 핵심을 짚었는데, 실제로는 **채널 배치**에 따라 두 갈래다.

| 모드 | 채널 | 동작 | 성능 | 지원 |
|---|---|---|---|---|
| **Multi-PAN (동일 채널)** | Zigbee·Thread **같은 채널** | PHY/MAC 공유, **타임슬라이싱 없음**. PAN ID로만 구분해 동시 수신 | 최선(열화 없음) | 표준 Multi-PAN RCP |
| **Concurrent Listening (독립 채널)** | Zigbee·Thread **다른 채널** | **초고속 프리앰블 스캔 스위칭**(수십 µs) — 프리앰블 감지되면 그 채널에 머물러 수신 후 재개. dynamic MP의 거친 타임슬라이싱과 다름 | PHY 감도 **약 -98dBm로 소폭 하락**(수신 거리↓) | **xG21·xG24 전용** |

- 즉 **같은 채널이면 시간 손실 0**(그냥 한 라디오가 두 PAN을 동시 수신). 문제는 Zigbee와 Thread를
  같은 채널에 묶어야 한다는 제약.
- **다른 채널을 쓰고 싶으면** Concurrent Listening — 이건 타임슬라이싱이 아니라 **프리앰블만 잡는
  µs급 채널 스위칭**이다. 대가 = 감도 -98dBm(거리·벽 투과 약간 손해). **MG24가 이 기능을 지원한다**(중요).
- 참고: BLE까지 얹는 **dynamic multiprotocol**은 진짜 시간분할(coarse time-slicing)이라 별개.

---

## 3. 정직한 생태계 판정 — 업계는 2-라디오로 후퇴했다

이게 이 난제의 무게중심이다. **기술적으로는 되지만, 신뢰성/지원 논쟁이 크다.**

- **Home Assistant**가 "Silicon Labs Multiprotocol" 애드온을 **2025-07 폐기·제거**. 권고 = "멀티프로토콜
  쓰지 말고 **어댑터 2개**(하나 Zigbee, 하나 Thread) 사라." Open Home Foundation·ZHA 개발자·z2m
  개발자 모두 **단일 라디오 멀티프로토콜을 강하게 비권장**. 주요 이유 = 안정성(주기적 크래시, HA Core
  업글마다 깨짐).
- **반대 증거**: SONOFF이 Silabs 공식 지원(2024 하반기)으로 ZBDongle-E(xG21e)에서 최신 MultiPAN
  펌웨어로 Zigbee+Thread 동시를 **안정적으로 돌려** "Multiprotocol is Not Dead"를 발표. → 되긴 된다.
- 종합: **AN1333로 문서화된 정식 기능이지만, 실전 안정성은 펌웨어/스택 버전·부하에 민감**해서 대중
  생태계는 2-라디오를 안전 기본값으로 삼았다. DIRIGERA의 MG21 2개도 이 선택과 정합.

→ **함의**: SMHub가 단일 MG24로 **안정 동작을 증명하면** = 업계가 물러난 지점을 저가·오픈으로 다시
여는 것 = 강한 오픈소스 기여. **증명 못 하면** = "2-라디오가 정답"이라는 것도 그 자체로 값진 공개 결론.

---

## 3.5 벤더 SMHub는 이 문제를 어떻게 푸나 — 매뉴얼 실측 (결정적)

벤더 공식 매뉴얼(`docs/smhub-manual/pages/`)을 뒤져보면, **벤더는 Matter-bridge·Thread·OTBR을 전부
인지·지원하지만, 단일 MG24 동시 멀티프로토콜은 풀지 않았다.** 모델에 따라 갈린다.

| 모델 | Zigbee | Thread | 동시성 방식 |
|---|---|---|---|
| **Essential / Premium** | TI **CC26xx** (별도 칩, `/dev/ttyS1`) | Silabs **EFR32MG** (별도 칩, `/dev/ttyS2`) | **라디오 칩 2개** → §6.7 "simultaneously out of the box" (= DIRIGERA 2-라디오 패턴) |
| **Nano Mg24** (우리 기기) | **단일 EFR32MG24** (`/dev/ttyS1`) | 같은 MG24를 **Radio mode 전환** | **재플래시 모드 스위칭** (Zigbee NCP ↔ Thread RCP) → **동시 아님, 순차** |

근거(매뉴얼 직접 인용):
- **§6.7 Multi-Radio**: "Zigbee + Thread + Wi-Fi + BT operate **simultaneously out of the box**" —
  단 이건 **CC26xx(Zigbee) + EFR32MG(Thread)가 별도 칩**인 Essential/Premium 전제(§6.1/§6.2 포트 분리).
- **Page 17/§ TBR**: Nano에서 Thread를 켜려면 **"Settings → Radio → Radio mode: **Thread** → Thread
  firmware → Update"** = **단일 라디오를 Thread RCP로 재플래시.** 곧 Zigbee 코디네이터를 그만둔다.
- **Page 19 IEEE**: **"Nano Mg24 = `/dev/ttyS1`"** vs **"Essential/Premium = `/dev/ttyS2`"**로 명시 구분
  → Nano의 MG24는 Zigbee 포트(ttyS1)에 단독. (제네릭 매뉴얼 §6.1의 CC26xx는 타 모델 전제, Nano는
  MG24=ember EZSP — `docs/SMHUB.md §2` 라이브와 정합.)
- **Matterbridge**: 소프트웨어 브리지로 Zigbee/Thread를 **Matter over IP**에 노출(§6.8, 로컬). Thread는
  **1.1/1.2**(DIRIGERA 1.3/1.4보다 구형).

**함의(이 난제의 핵심)**: 벤더조차 단일 MG24에서 **Zigbee+Thread를 동시**로는 안 한다 — 2-칩(Essential/
Premium)이거나 **모드 전환 순차**(Nano)다. 즉 §3의 업계 후퇴 + DIRIGERA 2-라디오 + 벤더 Nano 순차가
**모두 같은 결론**을 가리킨다. → **단일 MG24 동시 Multi-PAN(§4 G4)은 벤더도 안 푼 진짜 미개척 지점**이며,
이걸 SMHub Nano에서 증명하면 **2-칩/순차보다 싼 단일칩 동시**를 여는 것 = 이 리포의 독창적 기여.

---

## 3.7 전략과 시점 — 단일칩은 "언제" 옳아지나 (핵심 관점)

2-라디오는 **지금 시점의 명분**이 맞다(§3의 넷이 합의). 하지만 이건 **영구 진실이 아니라 실리콘·스택
성숙도의 함수**다. Silabs 칩 궤적을 보면 단일칩 동시가 언제 프로덕션이 되는지 시점이 보인다.

| 세대 | 칩 | Flash / RAM | 동시 멀티프로토콜(CMP) | 위치 |
|---|---|---|---|---|
| Series 2 (구) | **MG21** | 0.5~1MB / 64~96KB | 개념상 가능(concurrent listening)하나 메모리 빠듯 → 비권장 | DIRIGERA ×2 |
| Series 2 (현) | **MG24** | ~1.5MB / 256KB | 가능하나 스택 안정성 논쟁 | SMHub Nano(순차) |
| Series 2 (신, 2025-02) | **MG26** | **최대 3.2MB / 512KB**(MG24의 5×) | **CMP 지원, "게이트웨이/허브" 명시 타깃** — Zigbee + Matter-over-Thread 한 칩 | 인플렉션 시작 |
| **Series 3 (최신)** | **SiMG301 / SixG301** | 최대 4MB / 512KB | **멀티코어 — 앱 M33@150MHz + 라디오·보안 전용 코어. 네이티브 CMP로 Zigbee + Matter-over-Thread 동시.** PSA Level 4 | **아키텍처적 해답** |

**시점을 가르는 두 신호**:
1. **메모리 벽 해소** — MG26(5× 메모리)부터 Zigbee+Thread+Matter+BLE 스택을 한 칩에 동시 적재할 여유.
   근거 앱노트 = **AN1418**(Concurrent MP on SoC), MG26/Series 3 대상.
2. **아키텍처 벽 해소** — Series 3의 **라디오 전용 코어**가 Series 2 단일-앱코어 타임슬라이싱의 신뢰성
   문제(생태계가 물러난 그 이유)를 구조적으로 없앤다.
3. **성숙 신호(날짜)** — **2026-06 Silabs가 200-노드 Matter-over-Thread 검증망**을 발표(대규모 신뢰성/
   확장성 실증). "지금 성숙 중"의 강한 지표.

### 벤더 로드맵이 시점을 확증 (SMLIGHT 2026 라인)

칩 궤적이 추상론이 아니라 **벤더 제품 로드맵으로 이미 굴러간다**:
- **SLZB-06Mg26** — 단일 **EFR32MG26** 코디네이터(Zigbee 3.0 **또는** Thread/Matter-over-Thread, OTBR).
  MG26의 메모리 헤드룸 스텝.
- **SLZB-MR4** — SMLIGHT "advanced coordinator"로 **CC2674P10 + EFR32MG26 두 칩**을 합쳐 **Zigbee +
  Thread 동시**를 보장. → **중요**: MG26 세대에서도 *보장된 동시*의 답은 **여전히 2-칩**이다. 즉 MG26은
  "메모리 벽 해소"이지 "단일칩 동시 종착점"이 아니다. **단일칩 동시 종착점 = Series 3**(전용 라디오 코어).
- **SMHUB → MG26** — 벤더가 SMHUB 계열도 MG26으로 이동(제품 페이지). → 우리 타깃 기판의 칩도 자연히
  MG24 → MG26 궤적을 탄다 = **"기다리면 되는 일"이 벤더 로드맵으로 확증**.

**우리 트리거 조건** (아래가 **동시에** 서면 단일칩으로 플립):
- (a) 보드에 **CMP 대응 칩**(MG26 이상, 이상적으로 Series 3)이 올라간다, **그리고**
- (b) host/스택이 **프로덕션 안정**에 도달한다(cpcd+zigbeed+otbr 안정화 또는 Series 3 SoC-side CMP;
  HA/z2m가 "2-라디오 권고"를 뒤집는 순간이 리트머스).

**그때까지 우리 행동 = "각 스택 독립 제어 기반" 닦기** (동시성 아님):
- 지금의 일은 동시가 아니라 **Zigbee 경로와 Thread 경로를 각각 독립적으로 제어할 수 있는 기반**을
  만드는 것이다. 리포 불변식 "one radio, one protocol"(`AGENTS.md`)과 정합 — 지금은 그게 맞다.
- SMHub(MG24)는 **순차 모드전환**(벤더 방식)으로 두 경로를 각각 검증만 한다.
- 제품 레인엔 **라디오 추상화**(Zigbee 경로 / Thread 경로를 코디네이터 칩 종류와 독립)를 깔아, 나중에
  MG26/Series 3(또는 SLZB-MR4식 2-칩)로 **코드 변경 최소**로 플립되게 설계한다.
- → **지금 삽질 0. 각 스택을 깨끗이 제어하는 기반만 단단히. 시점(Series 3/CMP 성숙) 오면 즉시 전환.**

---

## 4. (선택) SMHub 증명 계획 — readiness probe, 현재 의무 아님

> **주의**: 이 게이트들은 §3.7의 트리거가 설 때(=CMP 칩 채택 시) 돌릴 **선택적 준비 점검**이다. 지금
> MG24에서 억지로 완주할 이유는 없다. running ≠ working.

`docs/SMHUB.md`의 실측 규율을 따른다. 각 게이트는 통과/실패가 명확한 관측으로만 판정.

| 게이트 | 내용 | 통과 기준 |
|---|---|---|
| **G0 재플래시** | MG24 EmberZNet-NCP(EZSP) → **Multi-PAN RCP** (`.gbl`, universal-silabs-flasher / smhub-flasher, ttyS1). **HW flow control(rtscts) 재조정 필수** — cpcd는 신뢰 UART 요구, 현재 z2m는 `rtscts:false`(§HUBS/§SMHUB Q5) | RCP 부팅 + 버전 응답 |
| **G1 cpcd 링크** | 단일 `/dev/ttyS1` 위 cpcd 기동, CPC 링크 헬시 | cpcd secondary 연결·핸드셰이크 OK |
| **G2 Zigbee 경로** | zigbeed(IID=1) → pty → z2m 페어링 | 1기기 report→command ack, 재시작 생존 |
| **G3 Thread 경로** | otbr-agent(IID=2) → Matter-over-Thread 커미셔닝 | Thread 기기 fabric 참여 |
| **G4 동시 부하** | G2+G3 **동시**로 수 시간, 실기 부하. 지연/유실/크래시 로깅. **동일채널 Multi-PAN** vs **Concurrent Listening(독립채널)** 각각 | 허용 지연·무크래시 지속 |

**최종 결정**:
- G4 안정 → **단일 MG24 1:1 재현 성립** (모든 방향의 문 열림).
- G4 불안정 → **2-라디오(DIRIGERA 패턴)가 정직한 답** → HW 설계에 2번째 802.15.4 라디오 반영.

**폴백 사다리**: ① 동일채널 Multi-PAN(가장 안정) → ② Concurrent Listening(독립채널, 감도 -98dBm) →
③ 순차 스위치(Zigbee **또는** Thread, 동시 아님 — PRIVATE 기기노트의 "Zigbee↔Thread 순차"와 정합) →
④ 2번째 라디오.

---

## 5. 열린 질문 (증명 중 확정)

- ttyS1 UART가 cpcd가 요구하는 속도/flow control을 물리적으로 지원하는가(배선·핀뮤스 실측).
- MG24 Multi-PAN RCP `.gbl`을 GSDK 어느 버전에서 빌드하나(§SMHUB §5.5 = GSDK 4.5.0=EmberZNet 7.5.1 보유).
- C906B 단일 Linux 코어에서 cpcd+zigbeed+otbr 동시 CPU 여유(§HUBS §2.1 헤드룸 실측과 연동).
- 동일채널 강제 시 Zigbee/Thread 채널 계획(간섭·Wi-Fi 회피).
- 재플래시 후 z2m 스택 전환: 기존 `ember@ttyS1` 직접 EZSP → cpcd+zigbeed pty 경유로 전면 교체.

---

## Provenance / Sources

- Silabs **AN1333** — "Running Zigbee, OpenThread, and Bluetooth Concurrently with 802.15.4 RCP"
  (`application-notes/an1333-concurrent-protocols-with-802-15-4-rcp.pdf`)
- Silabs docs — Multiprotocol Solution on Linux: System Architecture / Running CPCd·Zigbeed·OTBR
  Concurrently (`docs.silabs.com/openthread/latest/multiprotocol-solution-linux/...`)
- Silabs **UG103.16** Multiprotocol Fundamentals + "Types of Multiprotocol Implementations"
  (Multi-PAN 동일채널 vs Concurrent Listening 독립채널, xG21/xG24 전용, -98dBm)
- HA 애드온 폐기(2025-07) + 2-라디오 권고 — HA Community, `home-assistant/addons` DeepWiki,
  issue #4095(SkyConnect Multiprotocol crash)
- 반대 증거 — SONOFF "Multiprotocol is Not Dead"(ZBDongle-E, MultiPAN, Silabs 공식 지원 2024 H2)
- 칩 궤적 — Silabs `efr32mg26-series-2-socs`(3.2MB/512KB, 게이트웨이/허브 타깃, 2025-02),
  `simg301-series-3-socs`(멀티코어, 네이티브 CMP, PSA L4), LinuxGizmos SixG301
- CMP 앱노트 — Silabs **AN1418** "Running Zigbee, OpenThread, and Bluetooth — Concurrent MP SoC"
- 성숙 신호 — PRNewswire `silicon-labs-...-200-node-matter-over-thread-validation-network`(2026-06)
- 벤더 로드맵 — SMLIGHT `slzb-06mg26`(단일 MG26), `slzbmr4`(CC2674P10+MG26 2-칩 동시), Howmation
  "SMLight 2026 Range" 가이드, SMLIGHT `smhub`(MG26 이동)

> **정직성 주의**: G0~G4는 아직 **미실행 계획**이다. Multi-PAN/Concurrent Listening은 Silabs 문서 기능,
> ttyS1 배선·flow control·GSDK 빌드·CPU 헤드룸은 SMHub 실기에서 확정해야 한다. 업계 비권고는
> 안정성 근거이지 "불가능"이 아니다.
