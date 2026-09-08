# RAIL — 현재 좌표

- [x] **1~5** — flash-and-go 재현 · 크로스호스트 대조 · 프로파일 가드 · gecko 회신 · 스택 랜드스케이프 (2026-08-30~09-01)
- [ ] **6. S99wpa_supplicant 제거/no-op 판단** ← DEPRIORITIZED (GLG 2026-09-07)
- [ ] **7. gecko 플래시 결과 대기** ← PAUSED: 우리 손 없음
- [ ] **8. #8 나머지 아이덴티티 / Matter** ← PAUSED
- [x] **9. SMHub에 domoticz 올리기 — 돈다 (2026-09-08)**. 크로스빌드 → ipk → 설치 → 기동 → 리부트 생존 → z2m MQTT 연결 → **기기 12대 페어링, domoticz 엔티티 112개**
- [x] **10. Zigbee 호스트 결정 — `domoticz + Z2M`, Z4D 비채택 (GLG 2026-09-08)**
- [ ] **11. 부하 등급 판정** ← 진행 중. RAM은 병목 아님이 밝혀졌고, **병목은 시리얼**로 드러났다
- [ ] **12. 라디오 펌웨어 복구** ← **NOW / BLOCKING**. 8.0.2.0 플래시 후 NCP가 EZSP를 말하지 않는다

현재 좌표: 1~5·9·10 완료 → **12가 11을 막고 있다** → 6·7·8 보류

---

# NOW — 이어받는 자리 (2026-09-08 퇴근 시점)

> **한 줄**: **라디오가 EZSP를 말하지 않는다.** 8.0.2.0을 굽고 나서 z2m이 못 뜬다.
> 벽돌은 아니고 복구 경로도 확보돼 있다. **내일 첫 일은 coordinator NCP를 다시 굽는 것**이고,
> 웹 UI가 아니라 **우리가 아는 방식**으로 한다.

## 지금 기기 상태

| | |
|---|---|
| **z2m** | ❌ 못 뜬다. `Failed to start EZSP layer with status=HOST_FATAL_ERROR` 반복 |
| **라디오** | `ASH starting → ASH Adapter reset → ASH starting` 무한. **`RSTACK` 응답 없음** |
| **domoticz** | ✅ 정상. 8081, 엔티티 **112개** (z2m이 죽어도 안 죽는다) |
| 설정 | `adapter: ember` · `115200` · `rtscts: false` · `log_level: info` |
| `NODE_OPTIONS` | `--v8-pool-size=0 --max-old-space-size=128 --max-semi-space-size=2` (`/etc/conf.d/zigbee2mqtt`) |

**리셋은 먹는다** — 로그의 `ASH Adapter reset`이 GPIO 리셋이 살아 있다는 증거다.
**응답만 없다** → 보율·플로우컨트롤 문제가 아니라 **지금 칩에 NCP가 아닌 펌웨어가 올라가 있다.**

## 내일 첫 일 — 12. 라디오 복구

**웹 UI로 하지 않는다 (GLG 2026-09-08).** 동글에서 이미 여러 번 해 본 방식으로 간다:
`~/repos/work/hejhub-nano/firmware/zbdongle-e/` · 우리 `firmware/zbdonglee/`.

**짐작**: 벤더 UI가 `Factory coordinator firmware (v8.0.2.0)`이라 표시했지만 **실제로는 라우터
이미지를 구웠을 가능성**이 크다. 공개 URL에서 8.0.2.0으로 배포되는 건 **router**이고,
coordinator(NCP)는 **7.4.1.0**이다.

```text
updates.smlight.tech/firmware/slzb-07/
  ncp-uart-hw-v7.4.1.0-slzb-07-115200.gbl      239,520 B   ← coordinator (이걸 구워야 한다)
  slzb07_zigbee_router_8.0.2.0_115200.gbl      284,760 B   ← router (아마 이게 들어갔다)
  ot-rcp-v2.4.5.0-slzb-07-460800.gbl           109,068 B
updates.smlight.tech/firmware/smhub/utils/
  flash-efr.sh · efr_btl_enabler.sh
```

**벤더가 SMHub의 EFR32를 SLZB-07 호환으로 취급한다** — `flash-efr.sh`가 위 slzb-07 이미지를
가리킨다. `firmware/nano/`·`firmware/smhub-nano/`는 404다.

**⚠️ 이 보드 프로파일에 맞는 것을 골라야 한다**: 우리는 `rtscts:false` @115200이므로
**`sw_flow`/`no_flow` + `115200`** 이어야 한다. 3rd-party(Nerivec) slzb-07 빌드는 **전부
`hw_flow`**라 쓰면 안 된다. 참고로 우리 리포에 같은 규칙의 파일이 이미 있다:
`firmware/zbdonglee/zbdonglee_zigbee_ncp_8.0.3.0_sw_flow_115200.gbl`(칩이 달라 그대로는 못 쓴다).

**부트로더 진입은 GPIO다** — `efr_btl_enabler.sh`:

```sh
GPIO_RST_EFR32=423 ; GPIO_FLSH_EFR32=422
# rst=0, flsh=0 → 0.1s → rst=1 → 0.5s → flsh=1
```

앱 펌웨어가 무엇이든 호스트가 부트로더를 부를 수 있다 → **벽돌이 아니다.**
⚠️ 단 `flash-efr.sh`는 `/dev/ttyS2`(상위 모델)를 쓴다. **우리 Nano Mg24는 `/dev/ttyS1`**이고
GPIO 422/423도 이 모델에서 재확인이 필요하다(`docs/SMHUB.md` §3.8 실측 맵과 대조).

## 안전망 (복구용, 리포 밖)

```text
~/smhub-safety/20260908-1805/
  coordinator_backup.json   network_key · pan_id e760 · channel 11 · ext_pan 41492c8588524cda
  database.db               기기 12대
  configuration.yaml · state.json
```

**커밋 금지** — `network_key`가 들어 있다. 라디오가 살아나면 z2m이 이 백업으로 네트워크를
복원한다. 안 되면 12대 재페어링(GLG "괜찮다").

## 12가 풀리면 바로 11

**RAIL 11 = 1코어 488M이 30~40대를 받는가.** 오늘 두 축이 갈렸다:

**RAM은 병목이 아니다.** 곡선이 허수였다 — 같은 5대인데 z2m 재시작만으로 139.8 → 122.4 MB
(−17.5). 0대 93.0 → 5대 122.4 = **+29.4 MB**이고 이건 zhc가 `TS011F` 정의 모듈 12개(소스 2.03 MB)를
지연 로드하는 **일회성 계단**이다. 47대여도 그대로다. 초기의 "4.45 MB/기기 → 47대 359 MB"는 폐기.
원인: [측정] 이 보드에서 V8이 `heap_size_limit`을 **259 MB**(MemTotal의 53%)로 스스로 잡아
압박을 못 느낀다 → GC를 미룬다.

**병목은 시리얼이다.** 크래시 순간 ASH 카운터가 갈랐다 — CRC 0 · comm 0 · out-of-buffers 0,
그런데 `ACK frames RX=0/TX=858` + `Retry dupes 20`. **바이트를 흘린 게 아니라 CPU에 굶었다**
(같은 시각 CPU0 100%, node 78%). `smhub/RUNBOOK.md` §6.5.

**튜닝은 완화지 해결이 아니었다** — `adapter_concurrent:2` + `log_level:warning` +
`NODE_OPTIONS` 셋을 다 넣고도 페어링 버스트에서 계속 끊겼다. 재현 가능한 형태로
**`smhub/tune.sh`**에 넣어 뒀다(`--revert`/`--show`, 리부트 생존 확인).

⚠️ **`log_level: warning`은 진단을 가린다** — ASH 카운터 덤프가 `info` 레벨이다. 이 문제를 더
팔 거면 `info`로 두어라(지금 `info`다).

## 남은 미측정 (11의 실제 질문)

- **부하가 꽂힌 뒤의 msg/s** — [측정] 지금 유휴 8대에서 **0.2 msg/s**다. 플러그가 전부 0 W라
  리포팅 임계(`change`)가 안 걸린다. 상한은 `min=5s` 기준 47대 **37.6 msg/s**이고, 실제 값은
  **부하가 정한다.** 그때 `min` 5초 → 300초 재설정이 업스트림 처방이다(끈적하지 않아 재인터뷰마다
  되돌아간다 → **운영 스크립트가 필요하다**).
- **10대·20대 곡선 점** — 오늘 12대까지 갔으나 크래시로 오염됐다. 재측정 필요.
- 샘플러: `smhub/logs/rail11-curve.csv` (60초 간격, 읽기 전용)

## 그다음 — x86 미니PC (GLG 2026-09-08)

이 보드의 값은 나왔다: **"1코어 488M에 얹히긴 하는데 온보드 MG24의 시리얼 경로가 상한을 만든다."**
다음은 x86이고, 거기선 USB CDC라 이 문제가 성립하지 않는다.
`works-nixos-zigbee`가 같은 방법으로 **paired 0/1/N 세 점**을 재기로 했다
(그쪽 Z4D 기준선: 47대에서 **140.6 MB 단일 프로세스**, CPU 8.8%, 2코어).

---

# RAIL 10 결정 — Zigbee 호스트는 Z2M, Z4D는 쓰지 않는다 (GLG 2026-09-08)

**전제 셋을 GLG가 고정했다**: ① 듀얼 동글은 안 한다(전부 싱글) ② 메모리 풋프린트는 판정 축이
아니다 ③ domoticz는 Z2M으로 된다.

**결정적 사실**: [측정 `docs/ECOSYSTEM-PORTFOLIO.md` §5] domoticz `hardware/` 149개 드라이버 중
**Zigbee만 네이티브가 없고**, 유일한 입구가 `hardware/MQTTAutoDiscover.cpp` = **Z2M+MQTT**다.
즉 Z2M이 우회로가 아니라 **domoticz의 표준 Zigbee 경로**이고, Z4D가 서드파티 우회로다.

**Z4D의 존재 이유는 하나였고, 그게 전제 ②에서 사라진다.** `EP §4`의 판정은 "플랫폼 선택보다
Zigbee를 Node에서 떼는 것이 크다"였다 — Z4D는 경량이라 후보였던 게 아니라 **Node를 빼주는 유일한
domoticz 경로**라서 후보였다. 그런데 [측정 §6.2] Node 49.5M을 빼자 **CPython+zigpy 86M**이 들어왔고,
풋프린트가 판정 축이 아니면 남는 이유가 없다.

**반대편 비용은 그대로 남는다**: riscv64 Rust/PyO3 벽(기기에 `cryptography`·`pip` 없음, 위 9-2) ·
가짜 초록(`0702`/`0b04`를 읽고 버리고 On/Off 등록) · 컨버터 DB 규모 · 아웃바운드(google.com 조회 +
Matomo 텔레메트리 기본 ON + 런타임 pip 업그레이드) · 비표준 경로.

**Node를 빼고 싶어지면 목적지는 Z4D가 아니다** — `EP §4` 표의 우리 답은 **자체 Zig 게이트웨이**
(EZSP 직결)다. Z4D는 양쪽에서 눌린 중간항이다:

```
Node를 유지한다  →  Z2M          (표준 경로 · SMHub에서 이미 돎 · 컨버터 DB)
Node를 뺀다      →  자체 Zig     (EZSP 직결, 이 리포의 원래 축)
                    Z4D = Node 대신 Python+Rust를 받는 중간항
```

**지금 구운 ipk는 그대로 쓴다 — 다시 빌드할 게 없다.** [측정 2026-09-08] 바이너리에
`MQTTAutoDiscover` 심볼이 내장돼 있고(`on_message(mosquitto_message*)`, `zigbee2mqtt` 문자열),
`libmosquitto.so.1`을 링크하며, 브로커는 기기에 이미 떠 있다. **선택한 경로를 이미 싣고 있다.**

- `USE_PYTHON=ON`은 **유지한다.** 이유가 "Z4D 전제"에서 "dlopen이라 비용 0, 열어둘 이유 없음"으로
  바뀌었을 뿐이다. 플러그인을 안 쓰면 CPython 인스턴스가 아예 안 뜬다([측정 §6.2] A′ 조건 = 35 MB).
  끄면 바이너리가 조금 줄지만 **재빌드 4시간을 쓸 값이 아니다.**
- 9-4의 목적이 바뀐다: **"Z4D 준비"가 아니라 "1코어 488M이 이 등급을 받는가"**. 그 값은 플랫폼
  선택과 무관하게 works-nixos-zigbee 레인에 돌려줄 숫자다.
- `EP §9`의 미결 하나가 절반 닫힌다 — *"riscv64/musl 가부: domoticz·zigpy 양쪽 다 미측정"*에서
  **zigpy 쪽은 이제 안 재도 된다.**

---

# NOW — 이어받는 자리 (2026-09-08)

> **한 줄**: **domoticz 2026.3이 SMHub Nano(riscv64/1코어/488M)에서 돌고, 리부트도 건넜다.**
> 남은 미지값은 **부하 하나** — 30~40대에서 1코어가 받는가.

**절차는 문서가 진다 → [`smhub/RUNBOOK.md`](smhub/RUNBOOK.md)** (증거 경계표가 맨 위에 있다).
이 파일은 현재 작업자 handoff다.

## 오늘 닫힌 것 (RUNBOOK ❓ 네 칸 전부)

| 판정 | 값 |
|---|---|
| 설치 | `opkg install` → `domoticz - 2026.3-1` |
| 기동 | pid 살아 있고 **8081 listen**, 밖에서 **HTTP 200** |
| **리부트 생존** | 자동 재기동 ✅ + **SSH host key가 리부트를 건넜다** → `docs/SMHUB.md` §3.6 닫힘 |
| 유휴 실측 | 아래 표 |

**[측정 2026-09-08, 리부트 후 279초, 페어링 0대, 두 스택 동시]**

| | `VmRSS` | Threads | CPU(누적) |
|---|---|---|---|
| **domoticz 2026.3** | **23.6 MB** | 18 | **1.46 s (0.5%)** |
| **zigbee2mqtt 2.13.0** | **93.0 MB** | 11 | **33.4 s (12%)** |
| 시스템 | used 224M / **available 263M** | | load 0.29 |

**읽는 법**: 부담은 domoticz가 아니라 **Zigbee 호스트**다 — RSS 3.9배, CPU 23배. `EP §6.2`가
x86에서 내린 판정이 제품 폼에서 재현됐고, 그 표의 `domoticz + Z2M` 빈칸이 **116.6 MB**로 채워졌다
(x86 `domoticz + Z4D`는 121 MB였다). 여유는 절반 남는다.

## 다음 한 걸음 (RAIL 11)

**부하 등급.** 지금 값은 전부 **페어링 0대의 유휴치**다. 그 상태에서 z2m이 이미 CPU 12%를 쓴다.

```bash
# 기기 좌표는 PRIVATE.md
ssh -i .sshkey/id_ed25519 smlight@<기기> 'D=$(pgrep -x domoticz|head -1); Z=$(pgrep -f "^/opt/bin/node /opt/bin/zigbee2mqtt"|head -1); for p in $D $Z; do grep -E "^VmRSS|^Threads" /proc/$p/status; awk "{print \$14+\$15}" /proc/$p/stat; done; free -m|head -2; cat /proc/loadavg'
```

- **기기를 붙여야 한다** — 페어링할 Zigbee 장치 없이는 못 잰다. 그것 말고 막는 것은 없다.
- **domoticz ↔ z2m 연결은 섰다 ✅ (2026-09-08).** MQTT Auto Discovery로 붙였고 domoticz가
  **브리지 엔티티 4개**를 자동 등록했다(Coordinator version `7.4.2 [GA]` 포함 — §2.1이 시리얼로
  잰 좌표가 파이프 반대편에 도착했다). **paired Zigbee device는 0대**라 그 이상은 올라올 게 없다.
  절차와 함정은 `smhub/RUNBOOK.md` §6.4.
- 그때까지 **"1코어가 세트를 받는다"고 말하지 않는다.** running ≠ working.

## ⚠️ 기기에 손으로 넣은 상태 — 패키지가 소유하지 않는다

공장 초기화나 재설치로 **사라진다.** 다음 사람이 같은 상태를 기대하면 안 된다:

| 무엇 | 어디 | 왜 필요했나 |
|---|---|---|
| `homeassistant.enabled: true` | 벤더 `/opt/zigbee2mqtt/data/configuration.yaml` | 기본이 `false`라 discovery 토픽이 아예 안 나온다 |
| `Preferences.WebLocalNetworks` | `/opt/domoticz/domoticz.db` | 초기 domoticz는 `Users`가 비어 `json.htm`이 전부 401 |
| `Hardware` 행 (MQTT Auto Discovery) | `/opt/domoticz/domoticz.db` | 연결 자체가 이 행이다 |

제품이라면 **idempotent postinst나 이미지 시드**가 소유해야 한다
([#8](https://github.com/junghan0611/homeagent-config/issues/8) 축). `smhub/pack-ipk.sh`엔 아직 postinst가 없다.

## 손 안 댄 것

페어링·라디오·벤더 앱 설정·`backend.db` 무변형. `/dev/ttyS1`은 z2m이 계속 쥔다.

---

## 참조 — 2026-09-07 당시 상태 (역사, 현재값 아님)

> 아래는 **그날의 좌표**다. 현재 상태는 위 RAIL·NOW가 SSOT이고, 기기 사실은
> `docs/SMHUB.md` §4.1, 절차는 `smhub/RUNBOOK.md`가 진다. 날짜를 보고 읽어라.

### 9-1~9-2 배경 — 틀 변경과 버전 좌표 (닫힘)

> **틀 변경 (GLG 2026-09-07)**: Milk-V Duo S 레인은 "되는 것"을 이미 증명했다. 이제 **통합보드
> 제품(SMHub Nano Mg24, riscv64 고정)에 domoticz를 올린다.** 실증 레인(회사, x86/NixOS)이 스택을
> 관통시켰고(47대 계약), 그 스택을 제품 폼에서 다시 세우는 것이 여기 몫이다.
> **6번(S99wpa_supplicant)은 당장 필요 없다.**

- **Stem**: 제품 폼 = **SMHub Nano**(SG2000, riscv64, MG24 온보드). 이미지는 벤더 것이고 우리는
  **p7 설치면 + ipk**로 얹는다(`docs/SMHUB.md` §3.7 패턴 (a)). Duo S는 이제 개발/대조 보드.
- **기기는 켜져 있다** — 접근은 SSH가 아니라 **Web UI → Console(Web Terminal)**. `:22`는 여전히
  refused(host key 0바이트, §3.6). 오늘 측정은 전부 그 경로로 했고 **무변형(읽기만)** 이다.

## 9-1. 버전 좌표 — 실측으로 확정 (닫힘)

| 축 | 값 | 근거 |
|---|---|---|
| **SMHub OS (라이브)** | **1.0.0.beta5**, Buildroot **`2026.02-18-g60430d6802`**, 커널 **6.18.17-patch21** riscv64 | [측정] `/etc/os-release`·`uname -a` |
| **libc / 컴파일러 / Python** | **glibc 2.42** · **GCC 15.2.0** · `libstdc++.so.6.0.34` · **Python 3.14.3** | [측정] `/lib/libc.so.6`·`python3 -V` |
| **하드웨어 여유** | `MemTotal` **488M** + zram 511M · **`nproc` = 1** · p7 5.7G(9%) | [측정] `free -m`·`/proc/cpuinfo`·`df` |
| **domoticz 목표 버전** | **`2026.3`** (2026-08-02 stable = upstream 최신) | [측정] GitHub releases; 태그 `2026.1·2026.2·2026.3` |
| **실증 레인이 도는 버전** | **domoticz 2026.3** (nixpkgs unstable) + Python 3.14 | [읽음] 그쪽 `flake.nix`·`README.md` — **목표와 동일** |
| **Buildroot 레시피 현황** | `DOMOTICZ_VERSION = 2024.4` — **master(2026-08-27)까지 그대로** | [읽음] `package/domoticz/domoticz.mk` |
| **Z4D 최소 요구** | Domoticz **≥2025.1**(readme), 권장 **≥2025.2**(Z4D AGENTS/CLAUDE) | [읽음] Z4D `readme.md:31`·`CLAUDE.md:91` |
| **판정** | Buildroot 핀 2024.4는 **Z4D 게이트 미달** → **2026.3으로 bump가 선택이 아니라 전제** | 위 두 줄의 교차 |

**★ ABI 계약이 base를 정해 준다 (이 항목이 제일 값나간다).** 기기의 glibc 2.42 / Python 3.14.3 /
GCC 15.2.0 은 upstream Buildroot **태그 `2026.02`** 의 핀과 **정확히 일치**한다
([측정] `git show 2026.02:package/{glibc,python3}` → `glibc 2.42-51-gcbf39c2`, `python3 3.14.3`,
`BR2_GCC_VERSION_15_X = 15.2.0`). 벤더 rev의 `-18-g60430d6802`는 **upstream에 없는 벤더 자체 18커밋**
이라 bit-identical은 불가하지만, **`2026.02`가 우리 크로스빌드의 재현 가능한 base**다.
**master(glibc 2.44)로 빌드하면 2.42 기기에서 심볼이 안 맞아 실행되지 않는다** — 이 축은 최신으로
올리는 게 이득이 아니다. (domoticz는 최신, 툴체인은 기기와 동일 — 두 방향이 반대다.)

**조달면 판정 (opkg)**: 벤더 피드 `https://pkg.smlight.tech/v1`(basic auth) 카탈로그는
**45 stanza / 17 패키지명**이고 **domoticz 0건**, 라이브러리 패키지도 없다(앱 ipk만) —
[측정] 기기 `opkg list` + off-device `curl /v1/Packages` 양쪽 일치. 즉 **벤더가 주는 길은 없고,
우리가 riscv64 ipk를 만든다.** ipk 메타 필드는 **`Required-OS-Version: 1.0.0`**, `Architecture: riscv64`.

**빌드해야 하는 것 / 이미 지불된 것**: rootfs에 `libcurl.so.4`·`libsqlite3.so.3.51.2`·`libssl.so.3`·
**`libmosquitto.so.1`**·`libjsoncpp.so.26`·`libz`·`libpython3.14.so.1.0`·`libstdc++.so.6.0.34`가
**이미 있다**(+`/usr/sbin/mosquitto` 실행 중). **없는 것 = boost · lua5.3 · minizip · fmt/cereal.**
→ 우리 ipk가 실을 것 = **domoticz 2026.3 본체 + boost(atomic/date_time/system/thread) + lua 5.3 + minizip**.
Buildroot `2026.02`에 boost 1.83(≥ domoticz 최소 1.69) · lua 5.3.6 · minizip-zlib 1.3.2 · cereal 1.3.2가
전부 있다 → **레시피 조달 대상은 domoticz 하나**(서브모듈 5개: `libwebem`·`jwt-cpp`·`jsoncpp`·`minizip`·
`sqlite-amalgamation` — [측정] 2026.3 `.gitmodules`). domoticz 2026.3은 cmake ≥3.16 · C++17 ·
`find_package(Python3 3.4 COMPONENTS Development)`(플러그인=Z4D의 전제) 요구.

**라디오 자리는 비어 있다**: z2m 2.10.1이 **설치돼 있지만 `rc-status default`에 없다**(started = mosquitto만)
→ 지금 `/dev/ttyS1`(MG24, EmberZNet 7.4.2 / EZSP 13)을 잡은 프로세스가 없다. Z4D(bellows)가 EZSP 13으로
같은 라디오를 물 수 있는 자리다. **단 z2m을 켜면 즉시 경쟁** — 한 라디오 한 host 스택.

## 9-2. 다음 한 걸음 — **(A) 트랙 확정 (GLG 2026-09-07)**, 단 OS 버전을 먼저 고정한다

- **트랙 = (A) domoticz만 먼저.** GLG 지시("당연히 A로 쪼개서 가야한다"). `2026.3`이 riscv64 /
  glibc 2.42에서 서는지 하나만 본다. Z4D·`cryptography`는 그 뒤 별개 관문.
- **선행 사실 둘이 이미 갈렸다**: ① Z4D는 **`cryptography` 없음 + pip 없음**([측정] 기기
  `import cryptography` → ModuleNotFoundError, `python3 -m pip` 무응답) → **riscv64 Rust/PyO3
  크로스빌드가 이 레인의 진짜 벽**이고, 실증 레인의 "x86_64 휠 하나"가 여기선 안 통한다.
  ② **`nproc`=1** — 실증 레인이 x86 4스레드를 잠정 하한으로 적은 형상을 **단일 코어**로 받는다.
  RSS는 128M/488M(26%)로 여유가 있지만 **CPU가 새 미측정 축**이다.
- **⚠️ 빌드 전에 OS 버전을 고정해야 한다 (2026-09-07 발견).** 기기 `Settings → Updates`가
  **Stable 채널에 `1.0.2 (stable)` 사용 가능**을 보고한다(현재 `1.0.0.beta5` = beta 라인).
  우리 ipk는 **glibc 2.42 / Python 3.14.3 / GCC 15.2.0에 못박힌 바이너리**이므로, beta5에 맞춰
  굽고 나서 OTA로 1.0.2에 올리면 **base가 움직여 그 바이너리가 무효가 될 수 있다.**
  → 순서는 **① 1.0.2로 OTA → ② `docs/SMHUB.md` §4.1 재측정(glibc/python/Buildroot rev 3분) →
  ③ 그 값으로 base 핀 확정 → ④ 빌드.** 제품 폼이므로 채널도 **Stable이 맞다**(beta 라인에 제품을
  올리지 않는다).
  - **OTA 안전 근거**: RAUC는 비활성 슬롯만 쓰고 실패 시 B로 남는다. 단 [측정] 지금 **`kernel.0`(A)의
    boot status = `bad`**, 부팅은 `kernel.1`(B) — OTA가 A를 새로 쓰며 그 상태도 갱신한다.
    **p7(`/opt`·`/home`·`/var`)은 OTA가 안 건드린다** → 설치면·z2m 데이터 생존. **SSH host key 0바이트
    결함은 OTA로 안 고쳐진다**(§3.6, beta5 OTA에서 이미 반증됨) → 접근은 계속 Web Terminal.
    **금지 유지**: Type-C full flash를 OTA보다 먼저 하지 말 것(A/B 롤백 전제 붕괴).
  - **백업은 안 한다 — 날것으로 간다 (GLG 2026-09-07).** *"완전 깔끔하게 날것으로 가려고 하는 거야.
    재현 가능해야 하니까. 삽질의 기억은 우리 리포에 있을 거야."* 이 레인의 자산은 **기기의 상태가
    아니라 절차**다. `backend.db`·z2m data(네트워크키)는 벤더 공장 상태의 파생물이고, 다시 만들 수
    있는 것을 보존하면 그게 재현 불가능한 특수 상태가 된다 — 이 리포 불변식 "ssh로 밀어넣어 제품을
    만들지 않는다"의 같은 얼굴이다. **그래서 OTA 전에 아무것도 뽑지 않는다.**
    - 잃을 게 실제로 적다는 근거: [측정 0.9.8] **paired end-device 0**(z2m `database.db` 1행 =
      Coordinator 자기 자신). beta5에서 z2m은 미기동이라 그 뒤 페어링이 생겼을 가능성은 낮지만
      **beta5 재확인은 안 했다**. 그리고 0.9.8 factory baseline은 이미 `captures/`에 있다.
    - 기억은 파일에 있다: [#10](https://github.com/junghan0611/homeagent-config/issues/10) ·
      `docs/SMHUB.md` §3.6(SSH 결함)·§3.7(설치면)·§4.1(플랫폼) · `CHANGELOG.md`.
  - **OTA 결과 (2026-09-07, GLG 실행) — 성공.** **`1.0.2` 부팅**(배너 + `/etc/os-release`
    `VERSION_ID=1.0.2`), 리부트 후 ~100초 네트워크 복귀, **RAUC가 `kernel.0`(A)로 부팅하고
    boot status `good`** = OTA가 `bad`였던 A 슬롯을 새로 쓰며 회복시켰다.
  - **② ABI 재측정 닫힘 — glibc가 안 움직였다.** [측정, GLG Console] Buildroot
    **`2026.02-1281-g9407f694e5`**(beta5는 `+18`) · 커널 6.18.17-patch21(build **2026-07-15**) ·
    **glibc 2.42 그대로** · Python **3.14.6**(3.14.3에서, 같은 3.14 soname) · `nproc` 1 ·
    MemTotal 488M(used 220 / avail 268).
    → **③ base 핀 확정: upstream Buildroot 태그 `2026.02`.** 벤더가 같은 계열에서 1263커밋을
    더 갔는데도 유일한 심볼 버전 축(glibc)이 2.42에 머물렀다. 2.42로 빌드 → 2.42+ 실행(하위호환).
    Python 차이는 soname `libpython3.14.so.1.0` 동일이라 무해. **GCC만 재확인 남음**(beta5 15.2.0).
  - **⚠️ 1.0.2가 Web UI 인증을 강제한다 (신규 사실).** beta5는 무인증으로 열렸는데 1.0.2는
    `Email or Username` + `Password` 화면이 먼저 뜬다([측정] 헤드리스 브라우저, `smlight`/`smlight`
    **거부** — 그 값은 셸 계정이고 Web UI 계정이 아니다). GLG 브라우저에선 열린다(세션 쿠키 추정).
    → **제품화 축으로 올라간다**([#8](https://github.com/junghan0611/homeagent-config/issues/8)):
    "계정/인증을 이미지가 소유하는가". 지금은 벤더 공장 admin 1행에 딸려 있다.
- **Blocker (2026-09-07, 원인 확정 — 남은 건 한 줄 실행)**: SSH가 「가짜 초록」으로 실패한 정체는
  **오버레이가 아니라 벤더 init**이었다. `/etc/init.d/sshd`의 `start_pre()`가 **p7 `/mnt/user/ssh`에
  host key를 캐시하고 매 기동 `cp -p`로 복원**하는데, 거기 **0바이트 키가 이미 저장돼 있다**
  (`cp -p`가 mtime까지 보존 → `Dec 11 2025`가 되살아난 이유). 즉 우리가 `/etc/ssh`에 만든 키는
  **sshd 기동 직전에 덮였다.** 벤더 의도는 OTA 생존(주석 그대로)이었고, 하필 **0바이트를
  영속화**한 것이 결함이다.
  - **해법은 벤더 경로를 그대로 쓰는 한 줄**: `sudo rm -f /mnt/user/ssh/ssh_host_* /etc/ssh/ssh_host_*;
    sudo rc-service sshd restart` → 캐시가 비면 else 분기가 스스로 `ssh-keygen -A` + p7 저장을 하고,
    **그 순간부터 OTA·리부트를 넘어 지속**한다. §3.6의 "리부트 지속성 미검증"이 이 경로로 닫힌다.
  - **클라이언트 쪽은 준비돼 있다**: `.sshkey/id_ed25519`, 공개키는 p7 `authorized_keys`(98B,
    `Jun 30`)에 OTA 두 번을 넘어 등록 상태. → 실행되면 즉시 `ssh -i .sshkey/id_ed25519
    smlight@<기기>`로 붙고 **웹 입력이 이 레인에서 사라진다.**
  - **이건 부수적이 아니다**: 셸 진입점이 인증 뒤 Web Terminal 하나로 좁혀져 있어 **④ 빌드 이후
    설치·기동·측정 전부가 사람 손 하나를 거친다.** 그래서 SSH 복구는 편의가 아니라 레인의 처리량이다.
- **Read**: **[#10](https://github.com/junghan0611/homeagent-config/issues/10)**(이 레인의 판 — 버전 좌표·조달면·판정 렌즈) · `docs/SMHUB.md` **§4.1**(오늘 재측정) + §3.7(설치면 p7 · 패턴 (a) ipk+OpenRC) ·
  §2.1(EZSP 13 계약) · `docs/ECOSYSTEM-PORTFOLIO.md` §4~§6(domoticz+Z4D 비용) · `PRIVATE.md`(피드 인증).

## 9-3. 레시피 계획 — OTA 대기 중 기기 없이 확정한 것 (2026-09-07)

**서브모듈은 회피 불가고, 그래서 오히려 싸다.** [측정] GitHub 태그 타르볼
`domoticz-2026.3.tar.gz`(13.5MB)의 `extern/` 5개는 **전부 빈 디렉터리**(엔트리 6개뿐)이고,
CMake는 그 부재를 `FATAL_ERROR: The submodules were not downloaded!`로 잡는다
(`CMakeLists.txt:151-162`). 더 결정적인 건 **`add_subdirectory(extern/libwebem)`에 옵션이 없다**
(`:471`, `target_link_libraries(domoticz webem)`) — 즉 `USE_BUILTIN_*`을 다 꺼도 **libwebem은
반드시 서브모듈로 와야 한다.** → Buildroot의 `$(call github,…)` 타르볼 방식으로는 안 선다.

**해법은 한 줄이다**: `DOMOTICZ_SITE_METHOD = git` + `DOMOTICZ_GIT_SUBMODULES = YES`
([측정] Buildroot가 지원 — `package/pkg-download.mk:130`이 `-r`을 넘기고, 쓰는 패키지도
`azure-iot-sdk-c`·`libplacebo`·`brickd` 등 실재). 서브모듈 리비전은 태그의 gitlink가 고정하므로
**재현성이 유지되고**, Buildroot가 만든 타르볼이 `dl/`에 캐시된다.
→ **새 Buildroot 패키지 0개. 레시피 1장(기존 `package/domoticz` 수정)이 전부다.**

**빌드 옵션 방향 — 없는 건 정적으로 삼키고, 있는 건 rootfs 것을 쓴다**

| 항목 | 2026.3 기본값 | 우리 선택 | 이유 |
|---|---|---|---|
| `USE_BUILTIN_JSONCPP` / `MINIZIP` / `JWTCPP` | YES | **YES 유지**(정적) | 기기에 minizip 없음, jsoncpp는 있지만 ABI 걸 이유 없음. **ipk가 그만큼 자립** |
| `USE_BUILTIN_SQLITE` | NO | **NO** | rootfs `libsqlite3.so.3.51.2` 사용 |
| `USE_PYTHON` | YES | **YES 필수** | Z4D 플러그인의 전제. rootfs `libpython3.14` 대상 |
| `USE_STATIC_BOOST` | YES | **OFF + 동봉** | [측정] Buildroot boost는 `link=shared runtime-link=shared` 고정(`boost.mk:110`)이라 `.a`가 안 나온다 → boost 정적은 불가. `libboost_{thread,system,date_time,atomic}.so` 동봉 확정 |
| `USE_LUA_STATIC` | YES | 빌드에서 확인 | domoticz는 `liblua5.3.a`/`liblua5.3.so` + `lua5.3/lua.h`를 찾는데 Buildroot는 `liblua.so`/`/usr/include`에 깐다 → `find_package(Lua)` fallback(`:496`) 의존. 2024.4가 이 경로로 서 있으니 통과가 기대값이지만 **첫 빌드에서 볼 것** |
| `USE_PRECOMPILED_HEADER` | YES | **OFF** | 기존 레시피가 이미 끈다 |

→ **ipk 내용 = domoticz 바이너리(jsoncpp·minizip·jwtcpp·libwebem 정적 내장) + boost 4개 + lua**,
그리고 정적 자산 **`www/` 14.6M + `Config/` 5.5M**([측정] 타르볼). `Config/`는 OpenZWave 경로용이
대부분이라 **회수 후보**(9-4에서 판정). 설치 위치는 `/opt/domoticz`(기존 레시피 기본값 =
p7 지속면과 정합).

**Do not**: OTA 진행 중 기기에 접근하지 마라(Web Terminal 포함). 이 절은 전부 로컬 소스/타르볼
측정이고 기기를 안 건드렸다.

## 참조 — 스택 랜드스케이프 (닫힘 2026-09-01, 실증은 딴 레인)

**이 리포의 중심은 "다 만든다"가 아니다 — 512MB급 작은 폼팩터에 이 주제를 밀어넣는 것이고,
그래서 남이 만든 스택을 재는 게 일이다(GLG 2026-09-01). 고집할 스택은 없다.**

- **문서 둘**: `docs/ECOSYSTEM-PORTFOLIO.md`(신설) — `docs/HUBS.md`(하드웨어)의 짝인 소프트웨어
  랜드스케이프. 그 아래 `docs/INTEGRATION-SURFACE.md`(**초안, 미커밋 아님/커밋됨은 아래 참조**) —
  SLZB Integrations 36개 전수 실사. 둘 다 **조사 자료이며 채택 결정이 아니다**는 배너가 맨 위에 있다.
  지도는 `README.md`·`AGENTS.md`·`docs/README.md` 세 곳에서 이 둘을 가리킨다(2026-09-01 연결).
- **한 줄**: 판정은 크기가 아니라 **런타임 개수**다. 그리고 플랫폼 선택보다
  **Zigbee를 Node에서 떼는 것(141M)** 이 압도적으로 크다.
- **실증은 우리가 안 한다.** domoticz+Z4D 경로의 실물 검증은 GLG가 회사 레인의 별도 배포판
  리포에서 직접 돌린다(전담 시민 배치됨). 좌표는 `PRIVATE.md`. **우리 몫은 기억과 재료.**
- **버전 방침 확정 (GLG 2026-09-01): domoticz는 최신 `2026.3`으로 간다.** Buildroot가 pin한
  `2024.4`가 아니다. [측정] 업스트림 태그에 `2026.1·2026.2·2026.3` 실재. 부채 0을 사자고
  2년 묵은 버전을 신지 않는다 — **서브모듈 5개 조달이 알고 지는 값**이고, 그게 이 레인의
  첫 실작업이 된다(`libwebem`·`jwt-cpp`·`jsoncpp`·`minizip`·`sqlite-amalgamation`).
  ~~`jwt-cpp`는 Buildroot에 패키지가 없어 새로 쓴다~~ **← 정정(2026-09-07, 아래 9-3): 새 패키지는
  0개다. `SITE_METHOD=git` + `GIT_SUBMODULES=YES` 한 줄이 다섯 개를 한꺼번에 가져온다.**
- **놓치면 안 되는 맥락 (GLG)**: 타깃은 **Duo S급 저사양에 꽉 눌러담는 것**이다. 큰 기계에서
  되는 걸 확인하는 게 아니다. 모든 표는 "되나"가 아니라 **"512MB에 들어가나"**로 읽는다.
- **그리고 이건 Milk-V 레인 구조를 바꿀 수 있다 (GLG)**: 회사 레인 실증이 잘 되면 이 리포의
  이미지 구조 자체를 그쪽에 맞춰 다시 볼 수 있다. **지금은 기다린다.**
- **Node를 빼면 보드가 한 칸 내려간다 (GLG 2026-09-01)**: 타깃이 **Milk-V Duo 256M
  (SG2002, 256MB)** 으로 갈 수 있다. [측정] SDK에 보드 정의가 이미 있다
  (`device/milkv-duo256m-{glibc-arm64,musl-riscv64}-sd`, `config.json` = `"CA53 + DDR 256MB"`),
  Duo S와 같은 cv181x 계열이라 브링업이 새 레인이 아니다. **그런데 256MB는 256MB가 아니다** —
  `memmap.py` 기준 Linux 몫은 Duo S가 `512−2−170(ION)=340M`(실측 MemTotal 311M),
  Duo 256M은 `256−2−75(ION)=179M`(→ 같은 비율이면 **~165M** 추정, 미측정). **ION은 카메라/ISP
  몫이라 헤드리스 허브엔 거의 버리는 값이고, 그 줄은 우리가 소유한 보드 설정이다 — 아직 안 건드렸다.**
  차이 둘도 미리 잡아둠: **eMMC 변형 없음**(`-sd`만; flash-emmc·eMMC CID stable-mac 경로 무효)
  · **온보드 WiFi 없음**(dts에 `aic8800|wifi|sdio` **0건** vs Duo S 3건 → RAIL 6의 wlan0 주제가
  이 보드에선 사라진다). 상세 = `docs/TARGET_DEVICE.md` "256MB 후보" 절. **지금 옮기지 않는다.**
- **실증 레인 1차 회신 — 벽 2가 절반 닫혔다 (인계, 2026-09-01, 우리 측정 아님).** 그쪽 x86_64에서
  `constraints.txt` 전수 대조 → **Zigbee 스택 전체가 핀을 정확히 통과**(`zigpy 2.1.0`·
  `zigpy_znp 1.1.0`·`zigpy_deconz 1.0.0`·`zigpy-blz 0.1.0`·`bellows 1.0.0`·`pyserial`·`serialx`).
  못 채운 셋은 전부 Zigbee와 무관한 부수 라이브러리이고 **Z4D의 2022년 stale 핀**으로 판정.
  `cryptography==40.0.2`는 휠이 있어 조달은 되지만 **채우지 않고 최신으로 진행**하기로 했다.
  **[측정, 여기] 그 핀은 Z4D 자신의 요구가 아니다** — `import cryptography` 계열이 소스에 **0건**,
  zigpy의 전이 의존을 대신 눌러 놓은 자리다.
  **레인 역할 분담 (GLG 2026-09-01)**: 실증 레인은 **NixOS/x86 리눅스 머신**이고 임베디드
  작업이 아니다. **x86에서 점검하고, 임베디드로 우리가 또 검수한다.** 그래서 그쪽 사실은
  결론이 아니라 **검수 대상**으로 넘어온다 — 그대로 옮기면 "x86에서 됐다"가 "보드에서 된다"로
  조용히 승격된다. 조달 방식부터 다르다: 그쪽은 `x86_64` 휠 하나, 우리는 **소스 타르볼 +
  maturin + Rust 크로스빌드**(`riscv64gc` 경로는 있다). 대신 **그쪽이 우리 미측정 목록을 대신
  줄여 준다** — 스택 층이 거기서 갈리면 우리 몫은 "같은 조합이 크로스빌드로도 서는가" 하나로
  좁혀진다.
- **`CheckRequirements` 플래그 — 우리 쪽 검수 항목 하나 추가 (2026-09-01).** 실증 레인은
  `CheckRequirements=0`으로 두고 근거를 이렇게 갈랐다(인계): *"zigpy가 메이저 갭인 채로 끄는
  것"과 "zigbee 코어가 정확히 맞은 상태에서 부수 셋만 남기고 끄는 것"은 성격이 다르다.*
  그 판단은 그대로 가져온다. **[측정, 여기] 그런데 그 게이트는 우리 쪽에서 다르게 생겼다** —
  `plugin.py:476`은 미충족 시 `onStop()` 하는 **fail-closed 게이트**이고, 앞에
  `self.internet_available and`가 붙어 있다. 즉 **오프라인 허브에서는 게이트가 통과가 아니라
  부재가 된다** — 우리가 아니라 네트워크 상태가 정해 주는 값이고, 이 리포 불변식
  ("On-device first")과 정면으로 만난다. **우리 몫 = 그 값을 명시적으로 정하는 것.**
  **GLG: "우리가 할 때는 다시 고민해보면 된다" — 지금 정하지 않는다.**
- **실증 레인 2차 회신 — 스택이 페어링까지 관통했고 RSS가 갈렸다 (2026-09-01).**
  **[측정, 여기]** 그쪽이 띄운 프로세스를 `/proc/1217454`로 직접 관측: **프로세스 1개**
  (`node` 0 · 별도 python 데몬 0 · Z2M 0, CPython 3.14 in-process, fd→`/dev/ttyUSB0` 직결),
  `VmRSS` **121 M**(`Pss`도 같음 — `Shared_Clean` 496 kB뿐), 바이너리 **17.4 M**, 설치 **43 M**.
  → 우리 Z2M 경로 **141 M** 대비 디스크 **1/3.3**.
  **[인계, 그쪽 측정]** 3조건 분해: domoticz만 **35 M** / +Z4D 로드 **85 M** / +라디오 **121 M**
  → **domoticz C++ 35 M, Python 스택 86 M(71%)**. *"Node를 뺐더니 Python이 들어왔나"의 답은 예.*
  보고자가 B의 하한성을 밝혔으므로 보수적으로 **CPython+Z4D ≥ 50 M · zigpy ≤ 37 M**로 읽는다.
  → **호스트는 싸고 Zigbee 호스트가 비싸다.** 35 M 위에 무엇을 얹느냐가 전부이고, 그래서
  **자체 Zig 게이트웨이 경로가 처음으로 계산 가능해졌다.** Duo 256M(~165 M) 기준 Z4D 경로는
  **73%**, ION 회수가 되면 **52%** — **두 레버가 곱해진다.**
- **⚠️ Z4D는 기동할 때마다 밖으로 나간다 (인계, 우리 지적에서 나온 후속).**
  `is_internet_available()`이 매 기동 `https://www.google.com` 조회(오프라인 시 3초 타임아웃 +
  요구사항 게이트 소실) · **Matomo 텔레메트리 기본 ON**(`MatomoOptIn` 기본 1=opt-out, 실제 발신
  로그 확인, 대상 `z4d.pipiche.net`) · **런타임 pip 업그레이드 시도**. 우리 불변식
  ("On-device first" · "Own the box")과 정면으로 만나고, 임베디드 이미지엔 pip이 없다.
  **거부권이 아니라 검수 항목이다** — 끌 수 있는가, 끄면 뭐가 같이 죽는가. 상세 =
  `docs/ECOSYSTEM-PORTFOLIO.md` §6.3.
- **신규 플러그까지 연결 확인 (GLG 전언 2026-09-01, 우리 측정 아님).** 실증 레인이 커넥터를
  만들어 **인벤토리에 없던 신규 플러그까지 붙는 것**을 확인했다. → 스택 관통이 페어링 1대에서
  멈춘 게 아니라 **기기 정의를 우리가 추가할 수 있는 축**까지 열렸다는 뜻이다(Z4D의 기기 정의는
  별도 pip 패키지 `z4d-certified-devices`이므로, 그 확장 경로가 우리 이미지에서 어떻게 서는지는
  임베디드 쪽 검수 항목으로 남는다 — 런타임 pip이 없다).
- **대조군은 아직 없다.** Z2M+Node RSS는 동글을 Z4D가 쥐고 있어 못 쟀다. 그쪽이 RAIL 1 뒤에
  재고 **먼저 제안하겠다**고 했다. riscv64/musl 재검은 **우리 몫**으로 확인됨.
- **라이선스 확인 — 등급이 안 바뀐다 (GLG 요청, 2026-09-01, 닫힘).** domoticz **GPL-3.0**
  [읽음 `License.txt`+`domoticz.mk`] · Z4D **GPL-3.0** [읽음 `LICENSE.txt`+SPDX 헤더] ·
  zigpy·bellows·zigpy-znp **GPL-3.0** [측정, store `dist-info/METADATA`]. **그리고 우리가 지금
  싣는 Zigbee2MQTT도 GPL-3.0**[측정 `package.json`] → **이미 GPL-3.0을 싣고 있으므로 새 의무가
  아니라 같은 등급 교체다.** 임베디드 관건은 GPL-3.0 §6 Installation Information(반-티보화)인데
  이 리포 불변식("Own the box")이 이미 그 방향이고 **현재 Z2M 경로에도 똑같이 붙어 있다.**
  소스 제공 기계도 있다 — [측정] Buildroot `legal-info` 타깃(`Makefile:144`, `manifest.csv`/
  `licenses/`/`sources/` 산출, `:226-231`). **빚: `bsp/build.sh`가 아직 `legal-info`를 안 부른다.**
  **미확인**: `z4d-certified-devices` 라이선스 · zigpy 계열 근거가 구버전 산출물 메타데이터라
  실사용 버전(2.1.0/1.0.0/1.1.0) 재확인 필요.
- **기준 보드 = Duo S 512M 확정 (GLG 2026-09-01).** 256M(SG2002)은 조건부 후보로 열어만 둔다.
  Duo S 실측 `MemTotal` 311M 기준 `domoticz+Z4D` 121M = **39%, 여유 있다.**
  **Python 86M을 새 비용으로 읽지 않는다** — 우리 defconfig에 `BR2_PACKAGE_PYTHON3=y`가 이미
  있어 **디스크 축에선 지불된 값**이다(단 **RAM 축은 별개** — 이미지에 있는 것과 인터프리터가
  떠서 86M을 쥐는 것은 다르다). 요지는 **Node가 빠지는 것이 순이득**.
- **텔레메트리는 끈다 (GLG 지시, 실증 레인에 전달됨).** 남는 검수 항목은 둘 —
  `is_internet_available()`의 google.com 조회, 런타임 pip 업그레이드.
- **실증 레인 3차 회신 — 47대 계약이 서고 납품물이 정해졌다 (인계 2026-09-07, 우리 측정 아님).**
  전담 시민(`works-nixos-zigbee`, meta-session `20260907T140211-fae201`)이 랩 현황을 넘겼다.
  회신 불필요로 왔고, **인계 이유는 GLG가 이걸 SMHub 임베디드 보드에 얹어 테스트할 계획**이라는 것이다
  (아직 우리 쪽 지시는 아니다 — RAIL 항목을 만들지 않았다).
  - **납품물 = USB 설치 이미지 하나(NixOS 배포판)**, 스택은 `domoticz + Z4D` **동글 직결(z2m 없음)**.
    현장은 SK하이닉스 데모룸 Zigbee 스마트플러그 **400대** 전력량 수집.
  - **[인계] 리포팅 계약 47/47 통과·실패 0**(전부 `4/4` 되읽기), 위젯 237개, 기기 최신 갱신 2초 /
    중앙 82초 / 최고령 273초(< `PowerPollingFreq=300`). 랩의 47대(10A 43 + `_TZ3000_w0qqde0g` 4)는
    **전부 대리물이고 납품 제품은 16A SP** — 산정은 16A로 다시 잰다. 물려받는 건 숫자가 아니라 구조.
  - **[인계] 47대 부하에서 CPU 4.6% · RSS 128M** — 우리 9/1 관측 121M(무부하급)의 연장선이고,
    **대수가 붙어도 등급이 안 바뀐다**는 첫 증거다. Duo S 실측 `MemTotal` 311M 기준 41%.
  - **듀얼 동글은 구조적으로 안 된다.** domoticz가 Hardware 행마다 파이썬 sub-interpreter를 띄우는데
    zigpy가 쓰는 `cryptography`가 Rust(PyO3) 확장이라 그 안에서 import되지 않는다(상류 PyO3#3451,
    ETA 없음). 둘 이상은 **domoticz 프로세스를 나누는 배치**로만 된다 → 배치 결정(GLG 2026-09-04):
    저사양 미니PC + 동글 1개 = 1세트, 10세트를 100m에 10m 간격, 세트당 30~40대.
    **우리 쪽 의미: "라디오 1개 = 프로세스 1개" 상한을 그대로 물려받는다** — 온보드 EFR32 + USB RCP
    동시 구상(LEDGER "USB 2동글")은 Z4D 경로에서 한 프로세스로 못 선다.
  - **임베디드 검수 항목 셋 추가**: ① Z4D는 `(Model, Manufacturer)` 정확 매칭이 없으면 `0702`/`0b04`를
    읽고도 버리고 On/Off 스위치로 등록한다 — 위젯이 서고 `Data: 'On'`까지 정상으로 보이므로
    **화면만 보고 통과 판정하면 안 된다**(새 모델은 `z4d/local-devices/`에 정의 추가). 이건 9/1에
    확인한 "신규 플러그까지 붙는다"의 뒷면이다. ② 동글 식별은 `/dev/serial/by-id/` 시리얼로 —
    `/dev/ttyUSB*` 번호는 꽂는 순서로 바뀐다(우리 mdev by-id helper와 같은 계약, 그쪽도 같은 결론).
    ③ **채널 프로비저닝은 동글 꽂기 전에** 들어가야 한다 — 채널은 코디네이터 형성 시점에 정해지므로
    `/etc/gq-node/channel` → seed 유닛 → z4d 순서이고, **init 순서가 계약의 절반**인 우리 overlay와
    같은 종류의 제약이다.
  - **그쪽이 명명한 반복 실패 모양 = 「가짜 초록」** — 성공 응답이 생존의 증거가 아닌 자리(z2m kWh
    미갱신도 에러가 아니라 조용한 미갱신이었고, 채널 시드 배포 때 `mktemp` 0600이 그대로 옮겨가
    z4d가 못 읽는데 로그는 성공을 찍었다). **우리 불변식 "A banner is not evidence"와 같은 것**이고,
    임베디드 이관 시 첫 렌즈로 쓴다(우리 쪽 등가물 = `usb_dl` 거짓 완료 → UUID 대조).
  - **SSOT는 그쪽 파일이다**(요약 아님): `~/repos/work/works-nixos-zigbee`의 `NEXT.md`(좌표·LEDGER) ·
    `INTERFERENCE.md`(무선/채널 정본) · `SP-10A-16A.md`(기기 raw, Part A만). 그쪽 RAIL은
    1(스택)·2(리포팅 계약)·3(동글당 30대)·5(USB 설치 이미지) 닫힘, **4.6 노드 간 간섭이 현재 좌표**
    (다음 한 걸음 = 두 번째 노드 하나 → 채널 형성·0대 energy scan·10m 이웃 dBm 동시 답), 4(마스터
    취합면)은 4.6 답 대기로 PAUSED.
  - **경계**: `~/repos/3rd/zigbee/*`는 읽기 전용 참조(커밋·vendoring 금지), `hejhub-nano`는 다른 레인,
    미니PC 하드웨어 축은 GLG가 아직 열어 둔 상태. 노드 좌표/계정은 공개 파일에 안 적는다(`PRIVATE.md`).
- **다음에 값이 붙는 순서**: ① ~~최신 `cryptography`로 Z4D가 도는가~~ → **답 왔다 (인계 2026-09-07)**:
  그쪽 RAIL 1(스택) 닫힘 + 47대 `4/4` 통과 = **최신 `cryptography`로 Z4D가 돈다**(단 x86_64 휠 ·
  단일 sub-interpreter 한정 — 우리 몫은 여전히 **소스 타르볼 + maturin + Rust 크로스빌드**로 같은
  조합이 서는가) ② **`2026.3` Buildroot 레시피 — 서브모듈 조달**(조사 아님, 실작업) ③ domoticz
  바이너리 실측 ④ RSS 실측 — **47대 부하값 128M이 인계로 들어왔으니 남은 건 riscv64/musl 실측**
  ⑤ riscv64/musl 가부.
- **Do not**: 이 조사를 근거로 지금 이미지에 스택을 얹지 마라. 버전 방침만 정해졌고 착수는
  회사 레인 결과 뒤다.

## 참조 — gecko 플래시 결과 대기 (PAUSED)

- **Next**: 없음 — 대기. gecko(`20260830T131729-9833bd`)가 `.164`를 굽고 결과를 보낸다.
- **판정 경계 (gecko와 합의)**: `wlan0` MAC ≠ `06:b3:51:d1:75:4e` · `/dev/serial/by-id` 후보 ≠ 1개 · `hostapd` 부재/AP-ENABLED 미확인 → **이미지 축, 우리에게 돌아온다**. 그 밖(`install`/`certs`/REG/AWS) → gecko가 가져간다.
- **돌아오면 쓸 이미지**: 오늘 자 minimal이 **두 호스트에서 동일**하게 나왔다. 랩탑 `…-minimal_2026-0830-1432.zip`(59,561,194B) / gpu1i `…-minimal_2026-0830-1410.zip`(59,560,594B). 재빌드가 필요하면 클린 15분(랩탑) 또는 9분(gpu1i).
- **당분간 `minimal`로 간다 (GLG 2026-08-30).** `full`을 굽는 건 별도 판단이고, 아래 미검증 항목이 붙어 있다.
- **아직 안 닫힌 것 하나 — `full`은 overlay 분리 이후 미빌드다.** 양 호스트 모두 이제 클린이라 V8 포함 40분 안팎. `target/etc/init.d/S70zigbee2mqtt`와 `etc/mosquitto/mosquitto.conf`가 서는지만 보면 닫힌다. **GLG 승인 없이 시작하지 마라.**
- **Read**: `bsp/README.md` "Profiles" + "Rebuilding after an overlay/config change"(프로파일 전환 예외 포함); `bsp/overlay/README.md`; arm64 defconfig `# 6) HOSTAPD`; gecko `docs/GECKO_PORT.md` §8.

## ⚠️ 헷갈리기 쉬운 두 축 — 이름이 비슷하다

| 축 | 값 | 어디서 정하나 |
|---|---|---|
| **ISA** | `arm64`(glibc) / `riscv64`(musl) | 보드 이름 + `bsp/buildroot/<board>_defconfig`. arm64는 `BR2_aarch64=y`, riscv는 `BR2_riscv=y`. SDK 브랜치도 다르다(arm64 `3a50ffe28` / riscv `087547cf8`) |
| **프로파일** | `full`(Node+Z2M+mosquitto) / `minimal` | `HOMEAGENT_BSP_PROFILE`, `bsp/buildroot/profiles/<board>_<profile>.fragment` |

**`full`은 ISA가 아니다.** [측정 2026-08-30] gpu1i의 `buildroot/output/`엔 `milkv-duos-glibc-arm64-emmc` **하나만** 있었고 riscv 트리는 없었다 — riscv 시도 흔적은 랩탑 쪽에 있다(거긴 트리 셋). 프로파일 프래그먼트도 arm64용 하나뿐이라 riscv 보드에 `minimal`을 걸면 컨테이너 시작 전에 fail-closed 된다.

**그리고 두 축은 독립이 아니다 — 한 output 트리를 공유한다.** 프로파일을 바꾸면 `.config`는 갈리지만 `target/`은 갈리지 않는다. **프로파일을 바꿔 굽기 전에 `output/<board>/target/`을 비워야 한다.** 2026-08-30부터 `build.sh`가 이걸 강제한다 — `full` 트리에 `minimal`을 걸면 빌드 전에 거부하고 `rm -rf <sdk>/buildroot/output/<board>`를 알려준다. 되돌리는 방향만 위험하다(`minimal` 트리에 `full`은 Node를 다시 깔 뿐).

- **Do not touch**: 보드 `.164`(gecko가 쥐고 있다) · 보드 91 · RISC-V defconfig · `feat/riscv64-nodejs-pure-cross` · gecko 펌웨어 · `bsp/sdk/out/quarantine/`(오염 이미지, 플래시 금지) · gpu1i untracked `meta-hailo/`·`yocto/sstate-cache-backup/` · hostapd를 부팅 init으로 올리는 것 · eudev 추가 · `S39`/`S99v` 번호 변경 · **minimal 이미지를 허브 보드에 굽는 것**.
  - 이전 NEXT의 "**gpu1i output 트리를 지우지 마라**"는 **해제됐다** (GLG 2026-08-30: "full은 언제든 다시할 수 있잖아. 이미 한 달 넘게 지난 터라 누구도 검증을 못해"). 7월 V8 스탬프는 재현 대조의 자산이 아니라 오염원이었다.
# 참조 — 닫힌 것들

## gecko 인계 (닫힘 2026-08-30) — 플래시는 그쪽이 몬다

- **이미 들어 있는 것 (레시피, 2026-08-28)**: `BR2_PACKAGE_HOSTAPD=y` (개방망, WPA3 옵션 없음, init으로 안 올림). `/dev/serial/by-id`는 eudev 없이 mdev helper. `stable-mac`은 eMMC CID → LAA (`02:` eth0 / `06:` wlan0) — #8 MAC 조각. init 순서 계약: `S39stablemac` < `S40network`/`S41dhcpcd`, `S99user` < `S99v_stablemac` < `S99wpa_supplicant`. `S99v`의 `v`는 자리용 글자, 번호 옮기지 말 것.
- **닫힌 것 (2026-08-30, 랩탑)**: gpu1i가 못 닿아(점프 호스트 `s3i` kex reset) **로컬에서 minimal 프로파일로 구웠다 — 3분 55초.** `milkv-duos-glibc-arm64-emmc-minimal_2026-0830-1137.zip` (57M, sha256 `08eb904b…`). 6개 파일 전부 확인, Node/Z2M/mosquitto 0건. **init 순서 계약도 실물로 확인**: `S39stablemac … S40network S41dhcpcd … S99serial-by-id S99user S99v_stablemac S99wpa_supplicant`.
- **gecko와 합의 완료 (2026-08-30, entwurf `20260830T131729-9833bd` 왕복 3회)**: 그쪽 `docs/GECKO_PORT.md §8.3` 의존 표를 minimal `target/`과 전수 대조 → **hostapd 포함 10/10**, 추가 요구 `awk`/`sed`/`cut`도 전부 있음(busybox `CONFIG_AWK/SED/CUT=y`, 그리고 minimal 프래그먼트는 심볼 5개만 만져서 **프로파일이 busybox를 건드릴 수 없다**). 남은 이미지 쪽 일 **0**.
- **우리 쪽 할 일은 없다. 대기다.** 플래시 승인은 GLG가 gecko에 줬고(2026-08-30), 이미지·계약·검증 순서는 양쪽 다 준비됐다. 결과가 오면 위 "판정 경계"로 받는다.
- **`.164`에 `full`(Z2M) 이미지를 굽지 마라 — 해롭다.** Z2M이 `/dev/ttyUSB0`을 선점하면 gecko resolver의 by-id 후보가 1개가 아니게 되어 fail-closed 된다(그쪽 `zigbee_backend.zig:574-604`). `gq_gateway`가 Gecko EZSP로 NCP를 직접 잡고 AWS IoT MQTT 클라이언트로 TLS 직결하므로 Z2M도 mosquitto도 쓸 자리가 없다. 롤백으로 7월 full을 굽는 경우에도 이 문제가 같이 돌아온다는 걸 알고 굽는다.
- **닫은 갈래 둘 (이미지 쪽 작업 아님으로 확정)**:
  - **예제 `/etc/hostapd.conf`는 남긴다.** post-build script 제안했다가 그쪽 근거로 철회. 상세는 arm64 defconfig `# 6) HOSTAPD`.
  - **`CONFIG_CFG80211_WEXT`는 계속 off.** [측정] 이 이미지의 커널 `.config`에 `# CONFIG_CFG80211_WEXT is not set` — `/proc/net/wireless`가 안 생기고, 그쪽 `wifi.zig:462`가 RSSI를 매번 0으로 덮는다. 커널 defconfig가 우리 소유라 한 줄로 켤 수 있고 4분이면 되지만, **켜지 않기로 합의**했다(WEXT deprecated · 그쪽이 이미 `iw`의 `signal:`을 파싱 중 · `§8.3` 표 판정이 원래 `iw` · spawn 빈도가 문제 되는 규모가 아님). 그쪽이 `wifi.zig`에서 닫았다 — `getRssiLive`(`iw`)로 교체 + 호출처 4곳 정리, aarch64 제품 빌드 통과, 실기만 플래시 뒤로 남음.
    - **빈도 근거는 한 번 정정됐다 (gecko 자진 정정 2026-08-30).** 처음 넘어온 근거는 "`.network` shadow 발행 4곳, **주기 발행 0**"이었는데, RSSI 소비처가 그 shadow만이 아니었다 — `aws.zig:658` `publishKeepaliveImpl`의 `networkRssi`가 `core/timeout.zig:176` `KEEPALIVE_INTERVAL_MS` **15분 주기**로 읽는다(하루 96회). **결론은 안 바뀌지만 "주기 발행 0"은 우리 쪽에도 그대로 적혀 있었으므로 정확히 옮긴다**: `.network` 발행은 이벤트 구동이고, RSSI는 15분 주기로도 읽히며, 어느 쪽이든 `iw` spawn이 부담이 되는 규모가 아니다.
    - 그리고 그 자리에 함정이 있었다: 고치기 전 `aws.zig:656-658`은 **`ctx.mutex`를 쥔 채** RSSI를 읽었고 주석이 "파일 read라 안전"을 근거로 달고 있었다. 거기 그대로 `iw`를 넣었으면 mutex를 쥔 채 fork/exec — AP 경로가 100ms 루프를 굶긴 것과 같은 계열이 됐을 것이다. 그쪽이 읽기를 lock 앞으로 뺐다.
- **플래시는 gecko가 몬다 — GLG가 그쪽에 지시했다 (2026-08-30).** 우리는 대기다. **폴백**: 그쪽에서 안 되면 GLG가 여기로 돌린다. 그때 필요한 건 `out/`의 zip뿐이고 **그건 무사하다** — 빈 output 트리는 플래시를 막지 않는다(`flash-emmc.sh`는 zip만 읽는다). 즉 위의 재빌드는 폴백의 선행조건이 아니다.
- **인계 근거 (왜 우리가 안 굽나).** 근거: [측정] `.164`는 LAN으로 살아 있지만 이 랩탑 USB엔 아무 보드도 없다(`lsusb` CVITEK 없음, `ttyACM*`/`ttyUSB*` 없음). 플래시는 스위치(ARM)·recovery 버튼·Type-C 직결 재연결·`sudo usb-recovery-prepare.sh`가 필요해 **어차피 GLG 손**이고, 그렇다면 플래시 후 사슬(MAC 게이트 → `install` → `certs` → resolver → AP)을 쥔 쪽이 스크립트를 모는 게 맞다 — 실패가 이미지 문제인지 그쪽 단계인지 같은 자리에서 갈린다. gecko는 **자기 세션에서 GLG 승인을 직접 받고** 시작한다(전언으로 갈음 안 함).
- **넘긴 것**: 절대 경로(`HOMEAGENT_BSP_SDK=/home/junghan/repos/3rd/milkv/duo-buildroot-sdk-v2` — SDK 트리는 gitignore라 `git pull`로 안 온다), `./bsp/flash-emmc.sh arm64-minimal`, 함정 둘(cdc_acm은 붙였다 뗀다 / `100%`는 증거가 아니라 UUID로 대조), 롤백(`arm64` → 7월 full 104M, 단 Z2M 선점 문제 동반).
- **판정 경계 (gecko와 합의)**: `wlan0` MAC ≠ `06:b3:51:d1:75:4e` · `/dev/serial/by-id` 후보 ≠ 1개 · `hostapd` 부재/AP-ENABLED 미확인 → **이미지 축, 우리에게 돌아온다**(재빌드 4분). 그 밖(`install`/`certs`/REG/AWS) → gecko가 가져간다.
- **Verify (zip, 보드 아님) — 방법이 바뀌었다**: zip 안 `rootfs_ext4.emmc`는 **raw ext4가 아니라 CIMG**다(LEDGER 참조). 파일 단위 확인은 `<sdk>/buildroot/output/<board>/target/`에서 하고, 산출물 확인은 `LC_ALL=C grep -a -c <이름> rootfs_ext4.emmc`로 한다. 같은 CID면 플래시 뒤 wlan0이 다시 `06:b3:51:d1:75:4e`여야 한다 — 그건 플래시 후 gecko 검증.
- **Read**: `bsp/README.md` "Profiles — one board, two package sets"; `bsp/overlay/README.md` "Two overlays, split by profile"; arm64 defconfig `# 6) HOSTAPD` + `PROFILES`; gecko `board/duo-s/README.md` + `docs/GECKO_PORT.md` §8.
- **Do not touch**: 보드 `.164`. RISC-V defconfig. `feat/riscv64-nodejs-pure-cross`. gecko 펌웨어. hostapd를 부팅 init으로 올리지 말 것. eudev 넣지 말 것. `S39`/`S99v` 번호 변경. gpu1i untracked `meta-hailo/`·`yocto/sstate-cache-backup/`. **minimal 이미지를 허브 보드에 굽지 말 것** (`flash-emmc.sh arm64`는 이미 못 집게 돼 있다).

## 빌드 프로파일 — full / minimal (2026-08-30 신설)

`HOMEAGENT_BSP_PROFILE`로 **한 보드에서 두 패키지 셋**을 굽는다. 툴체인·커널·`bsp/overlay/common`은 동일하고 애플리케이션 층만 움직인다.

| 프로파일 | 패키지 | 오버레이 | 산출물 | 플래시 |
|---|---|---|---|---|
| `full` (기본) | Node 22 + Z2M + mosquitto | `common` + `z2m` | `<board>_<date>.zip` | `flash-emmc.sh arm64` |
| `minimal` | 없음 (ICU도 제외) | `common`만 | `<board>-minimal_<date>.zip` | `flash-emmc.sh arm64-minimal` |

```bash
HOMEAGENT_BSP_SDK=~/repos/3rd/milkv/duo-buildroot-sdk-v2 \
HOMEAGENT_BSP_PROFILE=minimal ./bsp/build.sh milkv-duos-glibc-arm64-emmc
```

- **존재 이유는 V8 하나다.** 랩탑 1h29m 중 1h16m, gpu1i 40m 중 28m37s가 V8이다. 증명해야 할 표면(hostapd·stable-mac·by-id)은 전부 Node **아래**라 Node가 필요 없다. 그래서 랩탑에서 4분에 끝난다.
- **베이스는 하나.** `<board>_defconfig`가 곧 `full`이고, `profiles/<board>_<profile>.fragment`를 뒤에 붙인다. kconfig가 **마지막 값**을 취하므로 override지 충돌이 아니다 → 두 프로파일이 툴체인·BSP에서 갈라질 수 없다.
- **패키지와 rootfs 파일이 같이 움직인다.** 프래그먼트가 `z2m` 오버레이도 같이 뗀다. 없는 바이너리를 가리키는 init 스크립트는 부팅 에러다.
- **이름이 안전장치다.** `flash-emmc.sh arm64`의 glob `<board>_*.zip`은 `<board>-minimal_*.zip`에 안 걸린다. 명시 경로로 줘도 `profile: MINIMAL` 배너가 뜬다.
- **산출물마다 매니페스트**: `out/<artifact>.manifest.txt`에 repo 커밋(`-dirty` 표시)·SDK 핀·sha256·해결된 패키지 셋이 남는다.
- **아직 검증 안 된 한 곳 — `full` 프로파일은 분리 이후 빌드된 적이 없다.** overlay 분리는 git이 순수 rename으로 인식했고(내용 변경 0줄) 합집합은 이전과 동일하지만, `BR2_ROOTFS_OVERLAY`에 `/bsp/overlay/z2m`가 더해진 상태로 실제로 구워보진 않았다. 첫 `full` 빌드에서 `target/etc/init.d/S70zigbee2mqtt`와 `target/etc/mosquitto/mosquitto.conf`가 있는지만 보면 닫힌다. **단 이제 gpu1i도 클린이다** — 2026-08-30에 12G output 트리를 지웠으므로 V8을 다시 굽는다(40분 안팎). 증분 몇 분이 아니다.

## flash-and-go 재현 (닫힘 — 참조용)

- **마지막 이미지**: `milkv-duos-glibc-arm64-emmc_2026-0724-1244.zip` (rootfs UUID f0cd08f2-…), 보드 91(aarch64, eth0 192.168.0.162) + dev보드(192.168.0.192) 둘 다 Z2M :8080 OK.
- **재현 절차 (SSOT)**: 맨바닥/클린은 `bsp/README.md` "Building on a remote host (gpu1i)", 증분은 같은 문서 "Rebuilding after an overlay/config change". flash는 `duo-s-flash` 스킬 + `bsp/flash-emmc.sh` 상단 PROCEDURE.
- **flash 요약**: `sudo ./bsp/usb-recovery-prepare.sh` → `./bsp/flash-emmc.sh arm64` → 꽂고 `dmesg`에 `ttyACM` 확인 → UUID로 증명. 핵심은 **cdc_acm은 막는 게 아니라 붙였다 뗀다**, **100%/complete는 증거가 아니다(UUID로 대조)**.
- **잔여 후보 (급한 것 없음, 아래 '작은 빚')**: 보드 90(dev) `2026-0724-1244`로 reflash + MAC 채우기(`bsp/BOARDS.md`); Z2M 상태 백업 절차.

## 재현 파이프라인 (요지 — 상세는 CHANGELOG v2026.7.24 + bsp/README.md)

`bsp/setup.sh` → `bsp/build.sh` 두 줄이면 빈 기계에서 같은 이미지가 선다.

- SDK fork `junghan0611/duo-buildroot-sdk-v2` **`feat/arm64-hub-baseline`** @ `3a50ffe28` (push 완료).
- **fork에는 주입으로 표현 못 하는 것만** — 커널 config, Buildroot 패키지 수정, 툴 권한. 보드/Buildroot defconfig와 `bsp/overlay`는 `bsp/`가 SSOT이고 `build.sh`가 주입한다. 양쪽에 두면 드리프트.
- `host-tools` 6.8G가 SDK git에 있어 툴체인까지 pin으로 따라온다. `buildroot/dl`은 gitignore(다운로드 캐시).
- overlay/config만 바뀐 재빌드는 **증분 ~2-3분** — output 트리를 지우지 마라 (`bsp/README.md` "Rebuilding after an overlay/config change").
  - **예외: 프로파일을 바꾸는 재빌드는 증분이 아니다.** `output/<board>/target/`은 누적이라 이전 프로파일의 rootfs가 그대로 남는다. `full` ↔ `minimal` 전환은 `target/`을 비우고 굽는다 (근거는 위 NOW, 2026-08-30 실측).

## 다음 텀에 정리할 작은 빚

- **ION 예약 회수 — Duo S가 지금 148M을 안 쓰고 잡고 있다 (조사 완료, 착수 안 함, 2026-09-01).**
  [측정] `build/boards/cv181x/<board>/memmap.py`의 `ION_SIZE`가 Duo S 170M / Duo 256M 75M이고,
  그 안쪽 예약은 `H26X_BITSTREAM 2M` + `ISP_MEM_BASE 20M`(= `FREERTOS_RESERVED_ION_SIZE` 22M)
  뿐이다. **헤드리스 허브는 ISP도 H.264도 안 쓴다** → assert가 강제하는 바닥 22M까지면
  **Duo S ~148M · Duo 256M ~53M 회수 후보**. 별도로 `BOOTLOGO/FRAMEBUFFER 7.8M`도 디스플레이가
  없으면 미수금이다. **레버 위치**: `memmap.py`는 단일 소스이고 `build/scripts/mmap.mk`가
  `cvi_board_memmap.{h,conf,ld,txt}`를 만들어 u-boot·커널·FreeRTOS 링커가 같이 먹는다 →
  한 파일이 세 층을 움직인다. **다만 `bsp/build.sh`는 지금 `memmap.py`를 주입하지 않는다**
  (defconfig 둘만) → 실작업은 **주입 슬롯 하나 추가**(`bsp/board/<board>/memmap.py`)이지
  포크가 아니다. **미검증 위험 둘**: cvi 멀티미디어 드라이버가 들어있는 채로 ION만 줄이면 부팅
  실패 가능(드라이버 제거와 짝) · `BOOTLOGO`는 u-boot 로고 경로가 참조. 상세 =
  `docs/TARGET_DEVICE.md` "레버 — ION은 카메라 몫이고" 절. **GLG 승인 없이 시작하지 마라.**

- **Duo S 온보드 버튼으로는 런타임 팩토리리셋을 못 묶는다 — 조사 완료, 보류 (2026-08-30).** GLG가 다시 볼 예정이라 `docs/DUO-S-BUTTONS.md`에 따로 남겼다. 요지: 이 이미지엔 `gpio-keys` 노드도 `CONFIG_KEYBOARD_GPIO`도 없어 **어떤 버튼도 이벤트를 못 낸다**(벽 1), 그리고 RST는 하드웨어 리셋·RECOVERY는 BootROM이 전원 인가 시점에 읽는 스트랩이라 런타임 입력이 아니다(벽 2). SoC의 전용 파워버튼 핀 `PWR_BUTTON1`은 Duo S에서 이더넷 속도 LED로 가 있다(`cvi_board_init.c:59`, 4개 변종 전부). 재개하면 **fork 핀 축이라 위 커널 defconfig 주석 빚과 한 번에 묶는 게 싸다**.

- **커널 defconfig 주석이 틀렸다 — 이미지엔 무해 (2026-07-24 fork 실물 확인).** `build/boards/cv181x/sg2000_milkv_duos_glibc_arm64_emmc/linux/cvitek_..._defconfig` 203번 설명주석이 "ZBDongle-E (CH9102F) → CDC-ACM"인데 **실측은 CP210x**(ttyUSB0). **심볼은 전부 맞다** (`USB_ACM=y`·`USB_SERIAL_CP210X=y`·`CH341=y`·`FTDI_SIO=y`) — 거짓인 건 순수 `#` 주석뿐. kconfig가 주석을 무시하므로 고쳐도 **이미지는 바이트 불변 → 실기 검증 불필요**. fork에서 주석만 정정하고 `setup.sh`의 `SDK_COMMIT` pin만 올리면 끝. (이전 NEXT의 "실기 검증이 끝난 뒤에"는 과한 신중함이었다.)
- **corepack은 이미지에 남지만 의도적 유지 (2026-07-24 GLG 판단).** `--without-corepack`이 patch 0002의 `ifeq ($(BR2_RISCV_64),y)` 분기 안에만 있어 arm 레인엔 안 걸리고, corepack 1.2MB가 이미지에 남는다. 원래 "닫을 빚"으로 적었으나 **아직 개발 중이라 corepack이 필요하고 급하지 않으므로 지금은 닫지 않는다.** 제품화 단계에서 재판정(그때 patch 0002의 해당 3줄을 `ifeq/else` 분기 **밖**으로 옮기면 양 레인 공통 적용).
- **`/proc/cmdline`에 `earlycon=sbi riscv.fwsz=0x80000`**가 aarch64 커널에 그대로 남아 있다. 무해하지만 SDK cmdline 템플릿이 레인별로 분리돼 있지 않다는 뜻이다.
- **`bsp/overlay`가 arm64 defconfig에만 연결돼 있다.** riscv 레인 복귀 시 같은 overlay를 붙일지 결정해야 한다.
- **MemTotal 311MB / 512MB**, rootfs 235MB/768MB(Z2M 91MB 추가 전). hub-minimal에서 회수 여지를 안 봤다.
- **Z2M 상태 백업 — 스킬엔 있고 스크립트엔 없다 (2026-07-24 검수로 정정).** `/var/lib/zigbee2mqtt`에 device DB와 **네트워크 키**가 있어 **reflash하면 날아간다**(전 기기 재페어링). `duo-s-flash` 스킬 §7이 이미 백업 한 줄(`ssh root@192.168.42.1 'tar cz -C /var/lib zigbee2mqtt' > …`)을 담고 있다 — 없는 건 `flash-emmc.sh`/README 쪽이다. flash 직전에 자동화/강제할지만 판단하면 된다. 청사진 참고: SMHub 매뉴얼도 OTBR reflash 시 Thread 데이터 소실을 백업 절차와 함께 명시한다(`docs/smhub-manual/pages/17-*`).

## Matter / matter.js 올리기 — 준비 완료, 착수 보류 (언제든)

버전 지도 (2026-07-24 확인):

| 대상 | 스택 | `@matter/*` | 시점 |
|---|---|---|---|
| **우리** (origin lane) | matterjs-server → `matter-server` **0.3.5** | `0.16.9-alpha` | 2026-02-04 |
| upstream `matter-server` 최신 **1.3.1** | — | **`0.17.7-alpha`** | 2026-07-23 |
| 최신 안정 matter.js | — | `0.17.5` | 2026-07-13 |
| 로컬 `~/repos/3rd/ha/matter.js` (develop) | — | `0.17.7-alpha` | 2026-07-24 |

- **관문은 열려 있다**: upstream `matter-server 1.3.1`이 이미 `@matter 0.17.7`을 문다 → 우리가 앞서갈 필요 없이 `matterjs-server`의 두 dep(`matter-server ^1.3.1`, `@matter/nodejs ^0.17.7`) bump + 재번들(`scripts/bundle-backend.sh`) + `npm-shrinkwrap.json` 재생성이면 된다.
- **진짜 부담 = `matter-server 0.3.5 → 1.3.1` major(0.x→1.x)**, `@matter` breaking이 아니다 — 우리는 matter-server 경유라 0.17.0 breaking(Matter 1.5/1.5.1 Namespace rename, `@matter/model` 배열 인덱스 제거, Blob 스토리지 제거)에 직접 노출이 작다. **착수 시 우리 래퍼가 matter-server API를 부르는 표면부터 파악**할 것.
- **0.17 이득이 우리 방향에 정합**: RAM **20–50% 감소**(512MB 보드), `threadNetwork` commissioning 옵션 + Thread Border Router DnssdParameters enrichment(RCP/Thread 경로에 직접 필요).
- **RCP 경로**: GLG "1번 동글" = SONOFF ZBDongle-E를 **RCP 펌웨어**로 flash → `otbr-agent` → matter.js. `VERSION.md`: RCP/OTBR는 **origin(Yocto) lane proven**, **arm64 hub-minimal은 TBD**. 커널 defconfig에 CP210x/ACM이 다 있어 동글 인식은 확보돼 있다.
- **우리 스택 구조**: `matterjs-server`(래퍼) → `matter-server 0.3.5`(`@matter-server/ws-controller`·`ws-client`·`custom-clusters`·`dashboard`) + `@matter/nodejs`. SSOT pin은 `yocto/meta-homeagent/recipes-connectivity/matterjs-server/matterjs-server/npm-shrinkwrap.json`.
- **SMHub과 다른 방향**: SMHub은 `matterbridge`(Zigbee→Matter 노출, bridge). 우리는 **matter.js controller + OTBR**(Zigbee·Thread를 직접 commissioning). 아래 LEDGER "SMHub 라디오 아키텍처" 참조.

## PARKED — RISC-V Node 레인 (재개 대기, 폐기 아님)

- **보관 위치**: branch `feat/riscv64-nodejs-pure-cross` @ `087547cf8` (upstream base `ad920f839`). 전 `develop` 변이는 `stash@{0}`.
- **재개 조건**: upstream [`milkv-duo/duo-buildroot-sdk-v2#74`](https://github.com/milkv-duo/duo-buildroot-sdk-v2/issues/74) 답변, 또는 arm 레인에서 Z2M 스택이 서서 riscv로 되돌릴 여유가 생겼을 때.
- **멈춘 지점**: Node/ICU host generator 링크에 target pkg-config의 `-L<riscv64-musl-sysroot>/usr/lib`가 섞이고, target sysroot의 8-byte musl compatibility archive가 host library를 가린다. `-lm` A안은 반증되어 폐기.
- **유지보수 예산(양 레인 공통)**: Buildroot recipe·defconfig·overlay + 작고 검증 가능한 compatibility patch 소수까지만. Node.js/V8/libc/toolchain downstream fork와 늘어나는 patch series는 금지.
- **riscv 합격선(재개 시 복원용)**: `GLIBC_*` 0건; `GLIBCXX <= 3.4.28`; Node ABI 127; V8 embedded blob 존재; stock C906/RVV 0.7 ISA·musl interpreter; target npm/corepack 부재; ICU 연결; QEMU·native target 실행 0.
- **Read**: `docs/BUILDROOT.md` "Node.js pure cross-compile" + "Native-musl product contract"; `captures/n0-musl-gap-20260722T115500+0900/`.

# RECENT

- **2026-09-01 홈오토메이션 스택 랜드스케이프 조사 — 닫힘 (`docs/ECOSYSTEM-PORTFOLIO.md` 신설).**
  GLG가 SLZB-OS 통합 목록·domoticz·Zigbee for Domoticz를 놓고 "작은 폼팩터에 밀어넣을 가벼운
  솔루션 포트폴리오"를 물어 조사. **측정된 것**: (1) Buildroot 2025.02 패키지 2951개 전수 대조 →
  홈오토메이션 호스트 중 **`domoticz`만 패키징돼 있다**(2024.4), HA·openHAB·ioBroker·Jeedom·
  FHEM은 0건이고 전부 새 런타임을 요구한다. (2) domoticz `hardware/` 149개 드라이버 실사 →
  1Wire·EnOcean·P1·Teleinfo·RFXCom·Z-Wave 등이 **네이티브**고 **빠진 건 Zigbee 하나**,
  입구는 `MQTTAutoDiscover.cpp`(=Z2M)뿐. 설치 정적 자산 **~21M**(`Config` 7.8M은 OpenZWave
  켤 때만). (3) **Zigbee for Domoticz(Z4D)가 그 칸을 메운다** — `Classes/ZigpyTransport/
  AppBellows.py`가 zigpy/bellows로 **EFR32를 직접 문다**. 실물 14M. 빠진 의존
  (`zigpy`·`bellows`·`zigpy_znp`·`zigpy_deconz`·`zigpy-blz`)은 **전부 순수 Python**이고 유일한
  네이티브 의존 `cryptography`는 이미 Buildroot에 있다 → 포크가 아니라 레시피 몇 장.
  **벽 둘**: 플러그인이 `Domoticz>=2025.2`를 요구하는데 Buildroot는 2024.4(올리면 서브모듈
  5개 부채), 그리고 `cryptography<=40.0.2` 핀 vs Buildroot 44.0.0(비호환 여부 **미확인**).
  (4) SMHUB 벤더 매뉴얼 재수집(22/22, **22페이지 중 릴리즈노트 1개만 +2,191B**) → **OS v1.0.0
  정식 2026-07-10** 확인: **커뮤니티 opkg 앱 저장소**, **Z2M을 지운 채로 OTA 유지**,
  **ser2net**, beta3의 **ESPHome을 RTOS 코프로세서 코어에** + HA Bluetooth Proxy.
  즉 벤더의 답도 "다 굽지 않는다"였다. **이미지·보드·커밋 손 안 댐.** 실증은 회사 레인으로 갔다.

- **2026-08-31 gecko WiFi 소유 원칙 조사 회신 — 닫힘 (다음 행동은 GLG 승인 대기).** gecko(sks-hub-gecko RAIL 6)가 GLG의 "OS는 wlan0를 존재하게, 정책은 펌웨어가" 원칙 위반 후보로 `S99wpa_supplicant`를 지목해 세 질문 조사 요청. (1) 그 스크립트는 homeagent-config 자체 overlay 파일(`bsp/overlay/common/etc/init.d/S99wpa_supplicant`)이지 Buildroot 기본이 아니고, 바이너리(`BR2_PACKAGE_WPA_SUPPLICANT`/`HOSTAPD`)와 분리해서 스크립트만 제거 가능함을 확인. (2) `dhcpcd`의 wlan0 관리는 설계가 아니라 Milk-V 벤더 패치가 usb0만 배제한 부산물 — 제거해도 유지됨. (3) wlan0를 `up`시키는 건 wpa_supplicant가 아니라 `stable-mac`(`bsp/overlay/common/usr/bin/stable-mac:56`)이고 순서상 wpa보다 먼저 뜨므로, **wpa_supplicant 없이도 wlan0는 UP으로 남는다** — 실기 없이 소스로 닫음. 이미지 재빌드/커밋 안 함, 보드도 안 만짐. 전문은 gecko 콜백(`20260831T172806-ed4c31`)에 fire-and-forget 전송. 다음 행동(제거 착수 여부)은 GLG 승인 대기.

- **2026-08-30 프로파일 가드를 `target/`까지 확장 — 닫힘.** `bsp/build.sh`가 `.config`만 보던 구멍을 닫았다. (1) **빌드 전 거부**: 비-`full` 프로파일인데 `target/`에 full 마커(`usr/bin/node`·`node_modules`·`mosquitto`·`S70zigbee2mqtt` 등 7개)가 있으면 굽기 전에 exit 1 하고 `rm -rf <sdk>/buildroot/output/<board>`를 알려준다. (2) **빌드 후 rootfs 단언**: 통과 시 `[bsp] profile verified in target/`을 찍고, 실패 시 방금 만든 산출물을 `out/quarantine/`으로 옮긴다 — `flash-emmc.sh`가 glob 최신본을 집으므로 미검증 이미지를 `out/`에 두면 보드까지 한 명령 거리다. 되돌리는 방향만 막는다(`minimal` 트리에 `full`은 안전). **검증**: 부정 방향은 오염 트리를 흉내내 가드 로직만 떼어 실행 → `exit=1` + 오염 파일 열거. 긍정 방향은 랩탑 클린 minimal 실빌드 → `profile verified in target/` 출력, `EXIT=0`. `bsp/README.md`의 "증분 ~2-3분" 절에도 예외를 적었다.

- **2026-08-30 클린 minimal이 두 호스트에서 일치.** gpu1i `…-minimal_2026-0830-1410.zip` **59,560,594B** / 랩탑 `…-minimal_2026-0830-1432.zip` **59,561,194B** — **차이 600바이트**. 양쪽 다 `target/` 152M, init.d 목록 동일, common overlay 9개+`hostapd` 10/10, Node/Z2M/mosquitto 0건. **클린 소요는 gpu1i 9분 2초 < 랩탑 14분 32초**(둘 다 16코어, host 툴체인까지 새로 굽는다). NEXT에 있던 "랩탑 minimal 3분 55초"는 **클린이 아니라 warm 트리 수치**였다 — 그 빌드(11:37, 59,748,834B)만 다른 두 개와 188KB 어긋나는 것도 같은 이유로 보인다. 오늘 이후 클린 기준선은 위 두 수치다.

- **2026-08-30 gpu1i 크로스호스트 재현 대조 — 닫힘, 그리고 receipt의 구멍 하나.** 랩탑 `…-minimal_2026-0830-1137.zip`(57M)과 같은 입력으로 gpu1i에서 minimal을 구웠다. **1차(warm 트리, 2분 52초)는 실패**: `resolved package set`·`BR2_ROOTFS_OVERLAY`·`container:` 다이제스트가 전부 일치했는데 **zip이 104M**이었다 — `target/`에 7월 full의 잔재(`usr/bin/node` 49.5M, `node_modules` 92M, `S50mosquitto`@07-23, `S70zigbee2mqtt`@07-24)가 남아 산출물에 실렸다(`zigbee2mqtt` 4608건). 가드가 `.config`만 보므로 통과했다 → 위 NOW 4번. 오염 zip은 `bsp/sdk/out/quarantine/`으로 격리. **GLG 판단으로 12G output 트리를 지우고 2차(클린, 9분 2초) → 재현 확인**: `…-minimal_2026-0830-1410.zip` **59,560,594B**(랩탑 59,748,834B, 차이 0.3%), 오염 7항목 전부 absent, 산출물 grep `zigbee2mqtt`/`mosquitto`/`node_modules` **0건**, common overlay 9개 + `hostapd` **10/10**, init 순서 계약 일치. bit-identical은 애초에 기대 대상이 아니다(빌드 타임스탬프). **`container:` 줄은 `594f20c`가 추가해 랩탑 receipt엔 없다** — 그 축은 랩탑 docker 이미지를 직접 읽어 `sha256:63d71ea6…` 동일로 확인했다.

- **2026-08-30 gpu1i 복귀 + 세션 인계**: 오후에 gpu1i가 다시 닿았다(점프 `s3i` 복구). 거기 arm64 트리에 V8이 스탬프돼 있어 재빌드가 싸다는 걸 확인하고, GLG 판단으로 **minimal을 새 담당자에게 넘겼다**(그 인계는 같은 날 닫혔다 — 바로 위 항목). 이 세션에서 랩탑 클린 `full`을 시도했다가 중단됨 — Z2M을 굽는 결정을 GLG에 안 묻고 시작한 것이 원인이고, 그 과정에서 랩탑 arm64 output 트리가 지워졌다(`out/` 산출물과 `buildroot/dl`은 무사). 랩탑에서 다시 구우려면 클린 ~15분.

- **2026-08-30 빌드 프로파일 신설 + minimal 이미지 실증 (랩탑)**: gpu1i 불통(점프 호스트 `s3i`가 kex에서 reset)이라 로컬로 돌렸다. 랩탑 트리를 재보니 **타깃 V8은 애초에 빌드된 적이 없었고**(`nodejs/.stamp_built` 없음, `target/`·`images/` 비어 있음, 159/162만 스탬프) — 그래서 Node를 빼도 지불한 것을 버리는 게 아니었다. `HOMEAGENT_BSP_PROFILE=full|minimal` 도입, `bsp/overlay`를 `common`/`z2m`으로 분리, 산출물 이름·매니페스트로 버전 관리. **minimal 빌드 3분 55초**, zip 57M(full 104M, −47M). 6개 표면 파일 확인, Node/Z2M/mosquitto 0건. 보드는 안 만졌다.
- **2026-08-28 gecko 패키징 표면 (레시피만, 미빌드)**: sks-hub-gecko SoftAP가 이미지에 없어 막힘. arm64에 hostapd(개방망) + mdev `/dev/serial/by-id` + stable-mac(eMMC CID, #8 MAC 조각) 넣음. 보드 `.164` 안 만짐. 다음 = gpu1i 증분 빌드.
- **2026-07-24 (2세션) 방향 정리 — Matter 준비 + SMHub 대조**: matter.js bump 경로 조사 완료(관문 열림 — 위 "Matter / matter.js 올리기"), **corepack은 개발 중이라 의도적 유지**로 재판정, 커널 defconfig 주석은 **이미지 불변이라 실기 검증 불필요**로 확정, SMHub Nano 단일 MG24 배타 / 벤더 매뉴얼의 "별도 칩"은 상위 모델 전제임을 교정(LEDGER). **다음 실질 축 = 제품화 수준의 Duo S 구성 준비**([#8](https://github.com/junghan0611/homeagent-config/issues/8) — 선행 세대의 ssh push/제조사 이관을 반면교사로, 이미지가 소유해야 할 것 대조표 + 남은 축 5개). 회사 레인의 z2m 허브 개발은 병행, Matter는 언제든. **문서 조이기**: 리포 문서는 토픽 이슈로 이전(#7·#8·#9), absorbed 스텁 5개 제거 → `docs/` 25→18, 루트는 표준 7개.
- **2026-07-24 flash-and-go 완성 + v2026.7.24 태그**: 보드 91에서 flash → host전환 → 동글 = Z2M 자동 기동을 config 손 안 대고 실증. flash 신뢰성(cdc_acm bind-then-unbind, 거짓완료 UUID 대조), Z2M seed serial pin(udevadm 부재 회피), 증분 빌드 2m37s. `duo-s-flash` 스킬 + `bsp/usb-recovery-prepare.sh` + `bsp/BOARDS.md` 신설. **상세 전부 CHANGELOG v2026.7.24.**
- 그 이전(arm64 전환, Node 22, Z2M 통합, riscv pure-cross 등)은 CHANGELOG v2026.7.24 및 v2026.7.15.

# LEDGER

- **zip 안의 `rootfs_ext4.emmc`가 CVITEK `CIMG`라는 건 이 리포가 이미 알고 있었다 — 내가 다시 발견한 게 아니다 (2026-08-30 정정).** `flash-emmc.sh:356-357`이 "vendor wraps the partition in a 64-byte CIMG header … locate the superblock by its magic instead of assuming"이라 적고 그렇게 구현돼 있다. 내가 처음에 이걸 새 발견처럼 LEDGER에 올렸는데, 알려진 사실을 재발견으로 적는 건 다음 사람에게 "이 리포는 자기가 아는 걸 모른다"고 가르치는 셈이라 고친다. **새로운 건 실패 모드 쪽이다**: `debugfs -R "stat <path>"`가 어떤 경로에도 조용히 빈 결과를 주므로, 있어야 할 6개가 전부 `MISSING`으로 **그리고 없어야 할 Node/Z2M도 전부 `absent`로** 나온다 — 두 답이 다 무효인데 절반은 원하던 답처럼 보인다. `100%/complete는 증거가 아니다`와 같은 계열. 파일 단위 확인은 `buildroot/output/<board>/target/`에서, 산출물 확인은 `LC_ALL=C grep -a -c`로. (구조: 64B 파일 헤더 + 청크당 64B 헤더, 이 이미지는 48청크. 형식 SSOT `build/tools/common/image_tool/raw2cimg.py`.)
- **`flash-emmc.sh` step 5가 `usb-recovery-prepare.sh`와 정반대를 말하고 있었다 (2026-08-30 정정, sks-hub-gecko가 플래시 전 두 파일을 대조해 발견).** 헤더는 "installs the udev rule that stops cdc_acm from ever being loaded"라 적었는데, 스크립트는 **cdc_acm을 일부러 `modprobe`하고 차단 룰을 발견하면 지운다**(`usb-recovery-prepare.sh:66-70, 86`). 즉 헤더가 설명하던 그 룰이 스크립트가 삭제하는 그 룰이다 — 헤더만 읽은 사람은 `removed …` 로그를 이상 징후로 읽거나 룰을 손으로 되살려 `config cdc(0x22) failed: TIMEOUT`을 부른다. **계약은 "막는다"가 아니라 "붙였다 뗀다"**이고, 그건 이 리포가 이틀 걸려 반증한 것이다. 문서가 그 값을 되돌리고 있었다.
- **제품 ISA/libc는 여전히 RISC-V C906 + SDK-native musl이다.** arm64는 2026-07-23부터 **개발 레인**이지만 제품 ISA로 승격된 것이 아니다.
- **커널 config는 우리가 소유할 수 있다 (2026-07-23 정정).** 어제 NEXT는 "`linux_5.10`의 `cvitek_*` 계열이라 우리가 소유하지 않은 파일"이라 적었는데, 실제 경로는 `build/boards/cv181x/<board>/linux/cvitek_<board>_defconfig` — **보드 디렉토리 안**이다. 소유 범위를 넓힐지 고민할 문제가 아니었다.
- **SDK의 `board/milkv/<board>/overlay`는 클린 트리에 없다.** `build/Makefile:646`이 빌드 중 `tmp-rootfs`에서 만들고 `:666`에서 지운다. `/mnt/system/*`이 거기서 온다. 그래서 SDK 빌드 스크립트를 우회해 `make -C output`만 돌리면 target-finalize에서 rsync가 실패한다.
- **`/mnt/system`은 별도 파티션이 아니라 rootfs 안의 디렉토리다** (`/dev/root`, ext4 rw). 그래서 그 아래 파일도 overlay로 덮어쓸 수 있다. `/var`도 tmpfs가 아니라 실제 디렉토리라 Z2M/mosquitto 상태가 재부팅을 넘긴다.
- **per-package 디렉토리의 함정**: `BR2_PER_PACKAGE_DIRECTORIES=y`면 각 패키지가 자기 `host/` 트리를 의존성에서 rsync 받는다. 이미 빌드된 패키지에 의존성을 추가하고 `<pkg>-reinstall`만 돌리면 그 트리는 갱신되지 않아 `host/bin/npm`이 없다고 실패한다. 클린 빌드는 이 문제를 정의상 겪지 않는다.
- Buildroot 이미지가 기준 산출물이다. SMHub식 `.ipk`/OpenRC/별도 `/opt` 지속면은 상용 배포 모델 참고이며 blocker가 아니다.
- SG2000은 같은 다이에 A53과 C906을 얹고 **물리 스위치**로 하나를 고른다 (eFuse 아님, 되돌릴 수 있음). 보드 defconfig가 동일해 ISA 전환에 보드 브링업이 필요 없다.
- `BR2_PACKAGE_NODEJS_ARCH_SUPPORTS = arm/aarch64/i386/x86_64 — no riscv`는 2026-06-30 SMHub 포렌식에 이미 있었다. arm 전환의 근거는 새 발견이 아니라 **한 달 전 증거의 재판정**이다.
- **SMHub 라디오 아키텍처 — "별도 칩"의 정확한 뜻 (2026-07-24 교정).** 실물 **SMHub Nano는 MG24 하나뿐**이라 Zigbee coordinator **또는** Thread RCP **배타**다(`docs/SMHUB.md §2`; RCP로 재플래시하면 Zigbee 상실 → Thread/OTBR 보류). 벤더 매뉴얼(`docs/smhub-manual/pages/`)의 "Thread(EFR32MG series) native OTBR", "별도 EFR32MG `/dev/ttyS2`", "OTBR + Matterbridge 통합"은 **§6 제네릭 = 상위 모델(Essential/Premium) 전제** 문서이지 Nano 실물 능력이 아니다 — `§2.2`가 "Nano 검수 시 §6 표를 그대로 따르면 안 됨"으로 못 박았다. **matterbridge는 앱 계층(IP 위 Zigbee→Matter 노출)이라 Thread 지원 여부와 별개 축**이며, 한 제품에서 OTBR와 공존한다. 우리 Duo S의 **USB 2동글(NCP+RCP)이 그 상위 모델의 "별도 칩 2개"에 대응** → 단일 MG24 Nano가 못 하는 **Zigbee+Thread 동시**가 개발 단계에서 가능하다. 지금 USB인 건 온보드 라디오가 없어서일 뿐, 제품화는 **MG24(단일→배타)/MG26(concurrent multiprotocol)/별도 칩** 중 하드웨어 결정. **Thread/OTBR는 우리가 처음 실증하는 영역**(Nano도 안 세웠고, 매뉴얼은 상위 모델용이라 절차 청사진이지 검증 근거가 아니다). SMHub은 낮춰볼 대상이 아니라 **지향하는 완성형 참조 제품**이다.
