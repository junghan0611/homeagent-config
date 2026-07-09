# 인증 Zigbee/Matter 허브 프로파일 — 오픈소스 허브 랜드스케이프 (SSOT)

이 문서는 **인증받은(CSA Matter certified) Zigbee/Matter 허브 중, 자체 펌웨어/데몬을 올려볼 수
있는 개방적인 하드웨어**를 오픈소스 허브 개발자 관점에서 조사·정리하는 단일 SSOT다.

- **왜 인증 제품인가**: Matter 생태계에 정식으로 물리려면 **CSA Matter 인증**(certified Matter
  device)이 실무 요건이 되는 경우가 많다. 미인증 허브는 학습·연구엔 좋지만 배포 경로에서 막힌다.
- **왜 IKEA DIRIGERA를 전면에 두는가**: 인증 + Zigbee/Thread(Matter) 동시 + **임베디드 Linux** +
  **GPL 소스/UART 콘솔/teardown/보안연구가 공개**되어 있어, 자체 데몬을 올려 실험하기에 가장 열려 있다.
  구조가 이 리포에서 다루는 SG2000 계열 허브(`docs/SMHUB.md`)와 **거의 동형**이라 학습이 전이된다.
- **범위 원칙**: board/라디오/OS/설치면 같은 **오픈소스 사실**만 다룬다. 벤더 비공개 SDK 내부나
  특정 제품 상용 코드는 다루지 않는다. secret/사설 좌표는 이 문서에 두지 않는다(`PRIVATE.md`).
- **재현 등급**: ✅ 완전(공개 소스+정확 버전) / ⚠️ 부분(upstream 공개, 벤더 config/patch 비공개) /
  ❌ 불가(바이너리/폐쇄, 역설계 필요).

---

## 0. 결론 (TL;DR)

**IKEA DIRIGERA = 주력 타깃.** 인증됐고, Linux 기반이라 손댈 여지가 크며, 아키텍처가 SG2000 허브와
동형(Linux 앱코어 + 실시간 코프로세서 + 외장 Silabs EFR32 라디오)이라 학습이 그대로 전이된다.
Zigbee 코디네이터와 Thread Border Router를 **하드웨어 라디오 2개**로 분리해 갖는다.

- **IKEA DIRIGERA** — 인증 + 개방 + 동형. **실기 도착 후 실측 grounding(§4.2)**.
- **Zemismart M1** — 인증됐지만 Tuya 종속 폐쇄 브리지. **"인증된 Matter 브리지가 어떻게 동작하나"의
  레퍼런스 블랙박스**로만 곁에 둔다(뜯을 계획 없음).
- **SMHub(SG2000)** — 미인증. 이 리포의 학습 앵커. 아키텍처 비교 기준으로만 참조(`docs/SMHUB.md`).
- Tuya Matter 허브 — 미인증 + 폐쇄. **조사 대상 아님.**

**위치 정리**: DIRIGERA는 **학습·파일럿·레퍼런스 기판**으로 이상적이다. 다만 소비자 소매가(KR 기준
₩84,900)를 고려하면 자체 하드웨어를 대체하는 최종 기판은 아니다 — 오히려 "인증 허브는 비싸다"는 사실이
**자체 개방 허브를 짓는 동기**(이 리포의 목적)와 정합한다.

**접근 원칙**:
1. IKEA 제품은 **IKEA 스마트홈 앱과 그대로** 쓴다. 기능을 어설프게 분할해 재포장하지 않는다 — 목적은
   제품 흉내가 아니라 **노하우 추출**이다.
2. 추출한 기능을 **SG2000(SMHub)에서 1:1로 검증·재현**한다. 이게 서면 **가성비**(저가 개방 기판)와
   **오픈소스 기여**(재현 가능한 board 지식)를 동시에 달성한다.
3. 그래서 이 문서의 SoC/라디오 비교(§2)는 "SG2000이 인증 허브 SoC를 기능적으로 따라갈 수 있는가"를
   축으로 한다.

---

## 1. 후보 비교 (SMHub 앵커)

| 축 | **SMHub (SG2000)** | **IKEA DIRIGERA** ★ | **Zemismart M1** |
|---|---|---|---|
| Matter 인증 | ❌ 미인증 | ✅ 인증 (Matter 브리지) | ✅ 인증 (CSA23593MAT41106-00, Matter 1.0) |
| Zigbee | ✅ MG24 코디네이터 | ✅ MG21 전용 코디네이터 | ✅ Tuya std Zigbee |
| Thread / TBR | ⚠️ 보류(미활성, TBR 없음) | ✅ MG21 전용 **Thread Border Router** | ⚠️ 지원 표기, 전용 TBR 아님 |
| Matter 역할 | SW 브리지(z2m→matterbridge over IP, 비인증) | **Bridge + Controller + TBR** (펌웨어 네이티브) | **Bridge 전용** (Tuya Zigbee → Matter) |
| Tuya 의존 | 없음 | **없음** (자체 클라우드/로컬) | ❌ 높음 (Tuya/Smart Life 앱·클라우드) |
| OS / 개방성 | Buildroot Linux(riscv64), 이 리포가 SSOT 구축 중 | **임베디드 Linux, GPL 공개 + teardown/보안연구** | 폐쇄, 칩셋 비공개 |
| 해킹 가능성 | 높음(우리 실기) | **매우 높음** | 낮음 |
| 역할 | 학습 앵커(비인증) | **주력 = 인증+개방+동형** | 인증 블랙박스 레퍼런스 |

---

## 2. Main SoC 비교 + 아키텍처 동형

| | **SMHub** | **IKEA DIRIGERA** | **Zemismart M1** |
|---|---|---|---|
| Main SoC | Sophgo **SG2000** (CV181x) | ST **STM32MP157CAB3** | 비공개 |
| 앱 코어 (Linux) | C906B RISC-V @1GHz (ARM A53 스위치 가능) | 2× Cortex-A7 @≈800MHz | ? |
| 실시간 코프로세서 | C906L RISC-V @700MHz (FreeRTOS) + 8051 @300MHz | Cortex-M4 @≈209MHz | ? |
| RAM / 저장 | 512MB SiP DRAM | 512MB DDR3 / 4GB eMMC | ? |
| NPU | 0.5 TOPS TPU (hub 미사용) | 없음 | 없음 |
| 라디오 | 외장 EFR32**MG24** (Cortex-M33, Zigbee, EZSP v13) | 2× 외장 EFR32**MG21** (Zigbee + Thread) + Wi-Fi | 비공개 |
| OS | Buildroot Linux 6.18 (riscv64) | 임베디드 Linux (GPL 공개) | 폐쇄 |

### 핵심 통찰 — 같은 아키텍처 패턴

```
[Linux 앱 코어]  +  [실시간 코프로세서]  +  [외장 Silabs EFR32 라디오]
──────────────────────────────────────────────────────────────────
SMHub:    C906B(Linux)  +  C906L(RTOS)  +  MG24        (Zigbee, EZSP v13)
DIRIGERA:   A7(Linux)   +  M4(RTOS)     +  2× MG21      (Zigbee + Thread)
```

즉 이 리포에서 설계하는 **Linux 데몬(상태머신) + 실시간 코프로세서 + EZSP/Spinel로 라디오 제어**
패턴이 DIRIGERA로 거의 1:1 이식된다. SMHub에서 배운 것을 **인증 제품 위에서** 재현할 수 있다는 뜻.
DIRIGERA 우위 하나: 라디오가 2개라 **Zigbee 코디네이터와 Thread Border Router를 하드웨어로 분리**
소유한다(SMHub는 MG24 1개로 Zigbee만, Thread 보류).

### 2.1 SG2000(Milk-V Duo S) vs STM32MP157 — 자체 기판이 뒤지나?

자체 재현 기판(SG2000 = Duo S 급)이 인증 허브 SoC(STM32MP157)에 스펙상 밀리지 않는지 축별로 본다.

| 축 | **SG2000 (Duo S)** | **STM32MP157CAB3 (DIRIGERA)** | 판정 |
|---|---|---|---|
| Linux 앱 코어 | 1× C906B RISC-V @1GHz (또는 A53 @1GHz, 스위치) | **2× Cortex-A7 @650–800MHz** | ⚠️ STM32 = 듀얼코어 병렬 우위 |
| 실시간 코프로세서 | C906L RISC-V @700MHz(FreeRTOS) + 8051 @300MHz | Cortex-M4 @209MHz | ✅ SG2000 코어 더 많음 |
| NPU/TPU | **0.5 TOPS TPU**(INT8, ONNX/TFLite) | 없음 | ✅ SG2000 (on-device AI) |
| RAM | 512MB SiP DRAM | 512MB DDR3 | = |
| 저장 | eMMC 옵션 **최대 8GB** + microSD | 4GB eMMC | ✅ SG2000 |
| Ethernet | 10/100M | 10/100M(칩은 Gbit 가능) | = (허브엔 100M 충분) |
| **PoE** | **지원(PoE HAT) → 단일 케이블 전원+데이터** | 없음(USB-C 전원 별도) | ✅ SG2000 (현장 설치 유리) |
| 무선 | 온보드 **Wi-Fi 6 / BT 5** 옵션 | 별도 Wi-Fi 모듈 | ✅ SG2000 |
| GPU | VPU(H.264/265) + ISP, 3D GPU 없음 | 3D GPU(Vivante, 디스플레이용) | = (헤드리스 허브엔 무의미) |
| ISA/개방성 | **RISC-V 개방 ISA + Milk-V 공개 BSP** | ARM(성숙, 메인라인 잘 지원) | ✅ SG2000 (OSS 기여 정합) |
| 성숙도/수급 | 신생, 생태계 작음 | **산업용, 장기 공급, 대형 생태계** | ⚠️ STM32 |
| 원가 | 저가(가성비) | 상대적 고가 | ✅ SG2000 |

**판정**: 허브 용도로 **SG2000/Duo S에 치명적으로 빠진 것은 없다.** 오히려 TPU·PoE·온보드 Wi-Fi6/BT5·
8GB eMMC·개방 RISC-V·저가로 앞선다. **단 한 축 = 메인 Linux 코어가 1개(@1GHz)** — STM32는 듀얼 A7이라,
z2m(Node) + matterbridge + OTBR를 **동시 상시 구동**할 때의 CPU 여유가 관건. (RAM 여유는 확인됨:
`docs/SMHUB.md` 기준 z2m RSS ≈105MB, available ≈216M.) → **동시 부하 CPU 헤드룸을 실측으로 확인**하면
"1:1 재현 가능" 판정이 선다. 성숙도/수급은 제품화 단계에서 별도 판단.

### 2.2 라디오 — EFR32 MG21 vs MG24

| | **EFR32MG21** (DIRIGERA ×2) | **EFR32MG24** (SMHub ×1) |
|---|---|---|
| 코어 | Cortex-M33 @80MHz | Cortex-M33 @78MHz |
| Flash | 512 / 768 / 1024KB | **1024 / 1536KB** |
| RAM | 64 / 96KB | **128 / 256KB** |
| AI/ML NPU | 없음 | **있음**(매트릭스 가속) |
| 보안 | Secure Vault(등급별) | **Secure Vault High** |
| 프로토콜 | Zigbee 중심, Thread/Matter 여유 적음 | **Zigbee 3.0 + Thread + Matter + BLE** 여유 |
| 세대 | 구형(라인전원 최적) | 현행(Matter 권장) |

**설계 함의(1:1 재현 핵심)**: DIRIGERA가 **MG21을 2개** 쓰는 이유 = MG21은 메모리가 작아 한 칩이
**한 프로토콜만**(하나=Zigbee 코디네이터, 하나=Thread RCP) 담당하는 게 안전하기 때문이다. SMHub의
**MG24 1개**는 flash/RAM/NPU가 커서 더 여유롭지만, 현재 Zigbee 코디네이터로만 쓴다(Thread 보류).
→ **DIRIGERA의 "Zigbee+Thread 동시"를 SMHub 단일 MG24로 재현하려면**, ① MG24 Multi-PAN RCP + cpcd
(동일채널 무-타임슬라이스 / 독립채널 Concurrent Listening) 또는 ② 두 번째 라디오 추가 중 택해야 한다.
이 리포 **1:1 재현 레인의 최중요 난제**이며, 문서화된 솔루션·모드·증명 게이트는 **[`MULTIPROTOCOL.md`](MULTIPROTOCOL.md)** 참조.

---

## 3. Thread Border Router(TBR) vs Zigbee/z2m — 두 경로

Zigbee와 Thread는 **다른 프로토콜**이다. 둘 다 IEEE 802.15.4 무선 PHY를 공유하지만 그 위
네트워크/앱 계층이 다르다. 그래서 허브 내부에서 처리 경로가 갈린다.

```
[Zigbee 경로]  Zigbee 기기 ──802.15.4──▶ Zigbee 코디네이터(EFR32)
                 ──▶ z2m / 벤더 Zigbee 스택 ──▶ Matter 브리지(번역) ──▶ Matter fabric
                 ※ Zigbee 기기는 Matter를 모름 → "번역"이 필수 (z2m이 이 자리)

[Thread 경로]  Thread 기기 ──802.15.4──▶ Thread Border Router (OpenThread + RCP 펌웨어)
                 ──IPv6 라우팅──▶ Matter fabric 에 직접
                 ※ Thread 기기는 Matter-over-Thread 네이티브 → 번역 불필요, z2m 무관
```

- **Thread Border Router(TBR)**: 저전력 IPv6 메시(Thread)와 일반 IP망(Wi-Fi/이더넷)을 잇는 IPv6
  라우터. Thread 기기가 Matter 컨트롤러(폰/HA)에 닿게 하는 관문. 표준 구현 = **OpenThread Border
  Router(OTBR, `otbr-agent`)** on Linux + 라디오는 **RCP(Radio Co-Processor)** 펌웨어(Spinel 프로토콜).
- **z2m은 Zigbee 전용**이다. Thread/Matter-over-Thread는 z2m을 **전혀 거치지 않는다.** Thread 기기는
  Matter 앱 계층이 기기↔컨트롤러 end-to-end로 돌고, TBR은 IPv6 패킷만 넘긴다.
- DIRIGERA가 라디오 2개인 이유가 여기서 나온다: **MG21 #1 = Zigbee 코디네이터**, **MG21 #2 = Thread
  RCP(OTBR)**. 각자 다른 스택. 두 경로가 한 박스 안에 공존한다.
- **SMHub 대비**: SMHub는 z2m(Zigbee) + matterbridge(SW Matter 브리지)만 있고 Thread/OTBR은 보류
  → TBR 없음. DIRIGERA는 하드웨어 TBR을 실제로 제공한다.

---

## 4. IKEA DIRIGERA — 주력 프로파일

### 4.0 무엇을 동시에 지원하나 (핵심 확정)

DIRIGERA는 **Zigbee망과 Matter를 한 박스에서 동시 운용**한다(라디오 2개). Matter는 **over IP와 over
Thread 둘 다** 지원한다.

| 역할 | 지원 | 근거 / 버전 |
|---|---|---|
| Zigbee 코디네이터 | ✅ 본업(2023 출시~) | IKEA/타사 Zigbee 기기 직접 수용 |
| Matter 브리지 | ✅ | 자기 Zigbee 기기를 다른 Matter 생태계로 노출(fw 1.12.x, 2023, 지연 큼) |
| Matter 컨트롤러 | ✅ | 타사 Matter 기기를 IKEA 앱에 추가/관리(fw 2.805.6, 2025~) |
| Matter over Wi-Fi/IP | ✅ | 컨트롤러가 LAN Matter 기기 온보딩(원래 지원) |
| Matter over Thread | ✅ | Thread Border Router 활성(fw 2.0.x TBR HW 켬 → 2.805.6 full). Thread 1.3/1.4 라인(보도별 상이, 실기 확인) |

**⚠️ 듀얼 프로토콜 기기의 배타성 (반드시 인지)**: IKEA 신형 기기(KAJPLATS 등)는 Zigbee + Thread 라디오를
둘 다 갖지만 **기기 하나는 한 번에 한 프로토콜만** 쓴다. Thread로 전환하면 그 기기의 **Zigbee 연결이
끊기고** IKEA Zigbee 리모컨 직접 바인딩도 끊긴다. 즉 *허브*는 두 망을 동시 운용하지만 *듀얼 기기 하나*는
양자택일이다.

- **지연 비교**: Zigbee→Matter 브리지 = 500ms~2s / 네이티브 Thread = 50~200ms.
- **펌웨어 타임라인**: 1.12.x(2023, 기본 Zigbee→Matter 브리징) → 2.0.x(2024, TBR HW 활성) →
  2.805.6(2025, full Matter 컨트롤러 + Thread 1.3 credential sharing + 신형 21종 지원) →
  2.934.0(2026-03, 온보딩/페어링 개선) → 2.934.1(2026-04, 웹서버 rootfs 노출 보안 수정).

### 4.1 하드웨어 / 개방성

- **인증**: CSA Matter 인증. Matter **브리지**로 시작해 펌웨어 업데이트로 **Matter Controller +
  Thread Border Router**까지 확장(§4.0).
- **하드웨어**: 메인 SoC **STM32MP157CAB3**(2× Cortex-A7 + Cortex-M4, 임베디드 Linux, 512MB DDR3 /
  4GB eMMC). 라디오 = **2× Silicon Labs EFR32MG21**(하나는 Zigbee 코디네이터, 하나는 Thread RCP) +
  Wi-Fi 모듈. UART 시리얼 콘솔 존재(teardown 문서화).
- **개방성 근거**:
  - **GPL 소스 공개** — `gpl-code.ikea.com`(커널/부트로더/OSS 컴포넌트).
  - **UART 콘솔 + teardown** — FOSDEM 2023 "Exploring a swedish smarthome hub" 발표, 커뮤니티 리버스
    엔지니어링(`wjtje/DIRIGERA`).
  - **보안 연구** — Pentagrid가 웹서버 root 파일시스템 노출(GCVE-2342-2026-1) 발견, IKEA가 fw 2.934.1
    에서 수정. → 파일시스템/서비스 배치를 이해하는 데 유용.
  - **Tuya 무관** — 클라우드 종속 없이 로컬/HA 연동 가능.
- **주의(정직하게)**: IKEA가 MG21 라디오 모듈을 debug-lock 시작. U-Boot/secure boot이 Linux root
  접근을 어렵게 할 수 있음(칩 보안 기능). 다만 Linux 사용자공간·API 쪽은 문서화가 잘 되어 있다.
- **OSS 재현 메모**: DIRIGERA의 Zigbee 스택은 벤더 자체(Linux 앱 ↔ MG21 코디네이터). 우리가 z2m을
  올리려면 코디네이터 펌웨어를 표준 NCP로 재플래시해야 할 수 있음(SMHub MG24 EZSP 상황과 동형).
  Thread는 `ot-br-posix` + `ot-efr32`(MG21 RCP)로 표준 OTBR 재현 경로가 열려 있다.

### 4.2 도착 후 실측 grounding (TODO — 실기 확보 시 채움)

`docs/SMHUB.md`의 라이브 실측 규율을 따른다. 도착 시 확인 항목:

- [ ] 모델명·하드웨어 리비전·펌웨어 버전(뒷면/설정)
- [ ] UART 콘솔 핀아웃 + 부트로그(SoC/커널/부트로더 버전 확정)
- [ ] 파티션·rootfs 레이아웃, OS 배포판/init 시스템
- [ ] Zigbee 코디네이터 펌웨어 종류(EmberZNet/EZSP? Z-Stack?) + z2m 접속 가능성
- [ ] Thread: `otbr-agent`/OpenThread 버전, MG21 RCP 펌웨어
- [ ] LAN API(Leggin/dirigera 토큰 발급) 동작 확인
- [ ] Matter: fabric 참여/commissioning 경로, TBR 노출

---

## 5. Zemismart M1 — 인증 레퍼런스 블랙박스

- **인증**: CSA Matter 인증(Cert ID `CSA23593MAT41106-00`, Matter 1.0, 2023-05-26).
- **역할**: **Matter 브리지 전용** — Tuya Zigbee(+일부 Thread) 기기를 Matter 플랫폼(HomeKit/Google
  Home)에 노출. Matter Controller/독립 TBR 아님.
- **Tuya 종속**: Tuya/Smart Life 앱·클라우드 필수(QR 공유로 3rd party 연동). 칩셋 비공개.
- **판단**: 뜯어봐도 폐쇄+칩셋 비공개라 확장성 낮음. **"인증된 Matter 브리지의 동작 관찰용"**
  레퍼런스로만 곁에 둔다. 능동 작업 대상 아님. (변형 M1 Pro = IR 내장 + Thread 추가.)

---

## 6. 오픈소스 클론 후보 (레이어별)

작업 클론 위치 = **`~/repos/3rd/ikea/`**. **먼저 볼 것 = ★**. 실기 도착 전 정보 수집용.
아래 ✅ 표시는 이미 클론 완료(shallow, `--depth 1`).

### 6.1 허브 제어 (LAN API / HA 통합)
- ★ ✅ `Leggin/dirigera` → `ikea/dirigera` — 비공식 Python 클라이언트(DIRIGERA LAN API). action 버튼
  으로 토큰 발급. → **API 표면 학습의 출발점.**
- ✅ `nrbrt/dirigera_platform` → `ikea/dirigera_platform` — HA 통합(활발히 유지, WebSocket keepalive/
  재동기화). fork 계보: `sanjoyg/dirigera_platform` → `crowbarz`/`nrbrt`.
- ✅ `crowbarz/ha-dirigera_platform` → `ikea/ha-dirigera_platform` — HA 통합(활발히 유지).
- `home-assistant-libs/pytradfri` — 구형 TRÅDFRI 게이트웨이 API. 역사적 맥락 참고용(단종, 미클론).

### 6.2 리버스 엔지니어링 / 하드웨어
- ★ ✅ `wjtje/DIRIGERA` → `ikea/DIRIGERA` — 하드웨어/teardown 일반 정보 정리.
- IKEA GPL 소스 — `gpl-code.ikea.com`(커널/부트로더/OSS). ※ 리포 클론 아님, 다운로드.
- Pentagrid 블로그 — root 파일시스템 노출 연구(웹서버/FS 배치 이해).
- FOSDEM 2023 슬라이드 — "Exploring a swedish smarthome hub"(Linux 해커 teardown).

### 6.3 Thread / TBR (OSS 재현)
- ★ ✅ `openthread/ot-br-posix` → `ikea/ot-br-posix` — POSIX/Linux용 OTBR(`otbr-agent`). DIRIGERA
  Linux 쪽에 대응. (이전 클론 재사용)
- ★ ✅ `openthread/ot-efr32` → `ikea/ot-efr32` — EFR32(MG21 포함) RCP 펌웨어 빌드. `OTBR_RCP_BUS`로
  UART/SPI 선택. ※ 빌드하려면 submodule 초기화 필요(현재 shallow).
- `openthread/openthread` — 코어 Thread 스택(ot-br-posix/ot-efr32 submodule로 포함, 별도 미클론).
- `home-assistant/addons` (`openthread_border_router`) — HA OTBR 애드온 레퍼런스(미클론).

### 6.4 Zigbee / Matter (SMHub 궤도와 공유)
- `Koenkk/zigbee2mqtt` + `Koenkk/zigbee-herdsman` — Zigbee 코디네이터 제어(ember=EZSP). SMHub와 공용.
- `project-chip/connectedhomeip` — Matter SDK(chip-tool 등). fabric 쪽 이해.
- matterbridge — SW Matter 브리지(SMHub 경로에서 이미 사용).

---

## 7. 지원 제품군 (Product Line) — 무엇을 붙일 수 있나

**핵심 프레이밍**: 지원 제품군의 넓이는 **어떤 펌웨어가 도느냐**에 달렸다.

| 경로 | 스톡 IKEA 펌웨어 | **우리 자체 펌웨어(리포 목표)** |
|---|---|---|
| **Zigbee** (코디네이터 MG21#1) | IKEA 카탈로그 중심. 타사 Zigbee는 **IKEA 앱에 동종 카테고리가 있을 때만**(외부 온도센서·블라인드 드라이버·모션센서). 문/창 센서·라디에이터 밸브 등 동종 없으면 ❌. 공식=IKEA-only | **z2m/ZHA 재플래시 → 임의 Zigbee 수천 종 전면 개방** |
| **Matter over Thread** (RCP MG21#2 + OTBR) | 임의 Matter-over-Thread 기기(브랜드 무관) | OTBR로 동일 + 완전 제어 |
| **Matter over IP** (Wi-Fi/이더넷, 컨트롤러) | 임의 Matter 인증 기기(브랜드 무관) | 동일 + 자체 컨트롤러/브리지 |

→ **스톡 펌웨어의 개방성은 Zigbee가 아니라 Matter(IP·Thread)에서 나온다.** Zigbee까지 전면 개방하려면
자체 스택(z2m/OTBR)을 올려야 하고, 그게 이 리포가 하드웨어를 공부하는 이유다.

### 7.1 기기 카테고리 (Matter 기기 타입, 버전별 확장)

Matter가 정의하는 기기 타입 = 붙일 수 있는 제품군의 상한. (컨트롤러 펌웨어가 그 타입을 구현해야 앱에
노출됨 → §7.2 주의)

| 카테고리 | 기기 타입 예 | Matter 버전 |
|---|---|---|
| **조명** | On/Off·Dimmable·Color-Temp·Extended-Color Light, 조광 스위치 | 1.0 |
| **플러그/전원** | Smart Plug(1.4 전력·에너지 모니터링), 인월 On/Off·Dimmable 로드 컨트롤 | 1.0 / 1.4 |
| **센서** | 문/창(contact), 모션/재실, 온도, 습도, 조도 | 1.0 |
| | 공기질(PM/CO2/VOC), 연기/CO 알람, 공기청정기 | 1.2 |
| | 누수(leak)·결빙(freeze)·강우(rain) 센서 | 1.3/1.4 |
| **잠금/출입** | Door Lock (Thread/Wi-Fi) | 1.0 |
| **공조/기후** | Thermostat, Fan | 1.0 |
| | Room AC, 히트펌프, 급탕기(water heater) | 1.2/1.4 |
| **창가림** | Window Covering(블라인드/셰이드/커튼) | 1.0 |
| **가전** | 냉장고, 식기세척기, 세탁기/건조기, 오븐, 쿡탑, 후드, 전자레인지 | 1.2/1.3 |
| **로봇청소기** | 시작/모드/진행/상태 | 1.2 |
| **에너지** | EV 충전기(EVSE), 태양광/PV, 배터리, Device Energy Management, 미터 | 1.3/1.4/1.5 |
| **네트워크** | 홈 라우터/AP | 1.4 |
| **카메라** | 라이브 영상/음성(WebRTC), PTZ, 감지/프라이버시 존 | 1.5 |
| **미디어** | 스피커, 미디어 플레이어/캐스팅 | 1.0 |
| **브리지** | Bridged Device(다종 기기 노출) | 1.0 |

Zigbee 경로도 동종 카테고리를 커버한다: 전구·플러그·스위치·버튼/리모컨·각종 센서·잠금·라디에이터
밸브(TRV)·블라인드·사이렌·리피터. (자체 z2m이면 전면, 스톡 IKEA면 IKEA 목록 중심.)

- **IKEA 1차 Matter 밀기 = 조명·센서·컨트롤 중심**(신형 21종). 스톡 펌웨어에서 안정적으로 먼저 붙는
  범주 = 전구/조광/색온도·버튼/씬·플러그·모션/접촉/온습도/누수/공기질 센서·블라인드.
- **Matter 1.5 확장**: 카메라(WebRTC) 외에 closures(개폐 액추에이터)·토양 센서·에너지 요금(tariff) 등.

### 7.2 주의 — "정의됨" ≠ "붙음" (스톡 펌웨어 함정)

- **타사 Matter 온보딩은 되지만, IKEA 앱 노출 범주는 IKEA 구현 프로파일에 제한**(The Verge 인터뷰
  기준). 조명·센서·버튼은 가능성 높고, **도어락·로봇청소기·가전은 아직 제한적**. 즉 Matter로 붙긴 해도
  IKEA 앱이 그 카테고리를 안 다루면 제어 표면이 안 뜬다.
- **컨트롤러 게이팅**: Matter 스펙이 타입을 정의해도, DIRIGERA 컨트롤러 펌웨어가 그 타입을 **구현해야**
  뜬다. 신형 타입(로봇청소기·카메라·에너지)은 펌웨어 지원 여부를 실기에서 확인해야 한다.
- **타사 Zigbee는 제품 약속이 아님**: 스톡 펌웨어에서 IKEA 동종 카테고리가 있을 때만 부분 동작
  (§7.0). 불확실/미지원으로 취급.
- **최대 개방은 자체 스택/HA**: IKEA 앱이 못 다루는 타입도 우리 스택(z2m + OTBR + Matter 컨트롤러) 또는
  Home Assistant로 붙이면 커버 폭이 넓어진다.
- **듀얼 프로토콜 기기 양자택일**(§4.0) 재확인: Zigbee↔Thread 동시 아님.

---

## Provenance / Sources

- SG2000/SG2002 SoC — CNX Software `2024/02/07/sophgo-sg2000-sg2002-ai-soc-...`
- Milk-V Duo S (SG2000) — CNX Software `2024/03/25/duo-s-risc-v-arm-sbc-...`
- Zemismart M1 인증 — CSA-IOT `csa_product/zemismart-m1-hub`
- Zemismart M1 스펙 — Matter Alpha `zemismart/zemismart-m1-hub-p236`
- DIRIGERA Matter 지원 — IKEA Global newsroom `ikea-dirigera-matter-bridge-240911`
- DIRIGERA Matter Controller — matter-smarthome.de `ikea-update-dirigera-hub-becomes-a-matter-controller`
- EFR32MG21 — Silicon Labs `wireless/zigbee/efr32mg21-series-2-socs`
- DIRIGERA root FS 취약점 — Pentagrid `ikea-dirigera-security-misconfiguration-...`
- DIRIGERA teardown — FOSDEM 2023 `Exploring_a_swedish_smarthome_hub`
- 리포 목록 — GitHub: `Leggin/dirigera`, `nrbrt/dirigera_platform`, `crowbarz/ha-dirigera_platform`,
  `wjtje/DIRIGERA`, `openthread/ot-br-posix`, `openthread/ot-efr32`
- Matter 기기 타입 — CSA-IOT `matter-1-2-arrives-...`, AppleInsider `new-matter-14-spec-...`,
  Wikipedia `Matter_(standard)`, matter-smarthome.de `the-matter-standard-in-2026-a-status-review`
- DIRIGERA 컨트롤러/TBR 능력 — Matter Alpha `ikea-adds-matter-controller-and-thread-support-...`,
  matter-smarthome.de `ikea-update-dirigera-hub-becomes-a-matter-controller`, PCWorld `2839091`
- DIRIGERA 타사 Zigbee 제한 — IKEA 고객센터 `articles/...other-brands`, Matter Alpha
  `ikea-dirigera-hidden-features-guide`
- DIRIGERA Matter 앱 카테고리 제한 + Thread 1.4 — The Verge `tech/814928/ikea-matter-thread-dirigera-...`
- IKEA 신형 Matter 21종(조명·센서·컨트롤) — IKEA newsroom `the-new-smart-home-from-ikea-matter-compatible-251106`
- Matter 1.4/1.5 device types — CSA-IOT `matter-1-4-enables-...`, `matter-1-5-introduces-cameras-closures-...`
- DIRIGERA KR 소매가 ₩84,900 — IKEA `p/dirigera-hub-for-smart-products-...`

> **정직성 주의**: SoC 클럭/코어 구성은 SG2000·STM32MP157 공개 데이터시트 기반 근사값. DIRIGERA의
> 라디오 2개 역할 분담·debug-lock·펌웨어 버전 타임라인은 커뮤니티/보도 기반이며 **실기 실측(§4.1)으로
> 확정 예정**. M1 내부 칩셋은 teardown 미확보(비공개).
