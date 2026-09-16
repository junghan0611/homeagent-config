---
name: smhub
description: "SMHUB Nano(SG2000 riscv64, 온보드 EFR32MG24) 총체 작업면 — 벤더 리포 12개 갱신, 업데이트 포인트 파악, 리서치, 그리고 그 끝에 있는 플래시. 핵심은 «보드에 안 붙고 얼마나 아는가»다: 벤더 opkg 피드를 호스트에서 인증 조회하고 ipk를 해부하면 Depends·OpenRC depend()·postinst/prerm을 전부 읽을 수 있다. 「설치됨」이 다섯 가지 다른 뜻을 갖는 평면 구분, 무엇이 RTOS 코프로세서 사슬이고 무엇이 아닌지, 그리고 절대 건드리면 안 되는 셋을 담는다. 트리거: 'smhub', 'smhub 업데이트', '벤더 리포 갱신', 'smlight', '피드 조회', 'opkg', 'ipk', 'Packages', 'esphome-bin', 'smhub-broker', 'remoteproc', 'C906L', 'RTOS 코어', 'matterbridge', 'picoclaw', 'Apps 화면', '앱 카탈로그', '무엇을 깔까', '의존성', 'ASH', 'MG24', 'Nano'."
user_invocable: true
---

# smhub — SMHUB Nano 총체 작업면

Repo: `~/repos/gh/homeagent-config`. 벤더 클론: `~/repos/3rd/smlight-smhub/`.

절차 SSOT는 `smhub/RUNBOOK.md`, 기기 사실 SSOT는 `docs/SMHUB.md`, 좌표·계정은 `PRIVATE.md`다.
**이 스킬은 그 문서들이 담지 못하는 「어디를 보고 무엇을 믿을 것인가」를 담는다.**

> ⚠️ 이 작업에서 제일 비싼 실수는 보드를 잘못 만지는 게 아니다.
> **보드에 붙지 않고 알 수 있는 것을 보드에 붙어서 알아내려는 것**이다.
> §2를 먼저 읽어라. **패키지 선언과 그 ipk 구현은 보드 없이 읽는다** —
> 다만 *현재 상태*(설치됨·running·remoteproc state·Apps 표기)는 거기 없다. 그건 §4다.

---

## 0. 시퀀스 — 「smhub 업데이트하고 리서치하자」가 오면

```bash
# 1. 벤더 클론 12개가 움직였나 (몇 분)
cd ~/repos/3rd/smlight-smhub
for d in */; do [ -d "$d/.git" ] && { git -C "$d" fetch -q;
  echo "$d $(git -C "$d" rev-list --left-right --count HEAD...@{u} 2>/dev/null)"; }; done
# 출력 "0 0" = 제자리. 뒤 숫자가 있으면 upstream이 움직였다.
# 로컬 변경이 있으면 fast-forward 하지 말고 보고만 한다.

# 2. 벤더 피드가 움직였나 (초 단위, 보드 무접촉) — §2.1
# 3. 궁금한 패키지를 해부 (초 단위, 보드 무접촉) — §2.2
# 4. 그래도 남는 질문만 보드에 읽기 전용으로 — §4
```

**1→2→3까지가 거의 전부다.** 보드는 마지막이고, 대개 필요 없다.

---

## 1. 나무가 하나가 아니다 — 리포 12개의 정체

`~/repos/3rd/smlight-smhub/` 아래 12개가 **세 갈래**다. 이걸 섞으면 엉뚱한 리포를 읽는다.

### (a) C906L RTOS 빌드체인 — 8개 (`smlight-smhub` org)

```
esphome               벤더 ESPHome 포크. platformio.ini:7 default_envs = rtos-smhub
platform-sg2000       PlatformIO 플랫폼. boards/smhub.json = core:c906l, framework:freertos
framework-sg2000-rtos C906L 베어메탈 SDK
rtos-config           nano-esphome.yaml — 코어에 실제로 컴파일되는 선언
open-amp · libmetal   rpmsg/remoteproc 기반 (업스트림 미러)
nanopb                protobuf — GPIO RPC가 쓴다
smhub-rtos-dev        위 7개를 묶는 개발 메타리포
```

### (b) SLZB 제품군 — 우리 보드가 아니다 (`smlight-tech` org)

```
slzb-esphome      ESP32 계열 SLZB용 ESPHome 컴포넌트. SG2000/nano/rpmsg 참조 0건
                  [인계, `PRIVATE.md` §클론 표 — 이 스킬에서 직접 재검색하지 않았다]
slzb-os-scripts   SLZB-class OS 스크립트. Berry 언어 온디바이스 자동화 API — L4 참고자료
```

### (c) 도구·애드온

```
smhub-flasher   최종 사용자용 MG24 .gbl 플래시 GUI (Inno 번들)
smhub-addons    ⚠️ 이름에 속지 마라 — Home Assistant Supervisor add-on 저장소 정의다.
                arch: [amd64, aarch64]. 우리 riscv64 보드 위에서 도는 게 아니다.
                opkg `esphome-bin`과 전혀 다른 물건이다.
```

---

## 2. ⭐ 보드에 안 붙고 아는 법 — 이 스킬의 핵심

2026-09-16에 열린 경로다. 여기서 얻는 것은 **벤더가 선언한 것**이다 — 카탈로그·메타데이터,
그리고 각 패키지의 maintainer 스크립트와 init 스크립트. **현재 상태는 여기 없다.**

### 2.1 피드 인덱스 조회

```bash
AUTH=$(sed -n 's/.*option http_auth \([^`]*\)`.*/\1/p' ~/repos/gh/homeagent-config/PRIVATE.md | head -1)
curl --fail --silent --show-error -u "$AUTH" https://pkg.smlight.tech/v1/Packages -o /tmp/smpkgs.txt
wc -c /tmp/smpkgs.txt    # 2026-09-16 기준 14,282 B
```

⚠️ **경로는 `v1/Packages` 하나다.** `v1/riscv64/Packages`·`v1/smhub_core/Packages` 전부 404다
(arch 하위 디렉토리 구조가 아니다). 그리고 `curl -s`만 쓰면 **401 HTML 179 B를 성공으로 저장한다** —
`--fail`을 꼭 붙여라. 붙이지 않으려면 크기를 눈으로 확인해라.

피드에는 **여러 버전이 공존한다.** 그래서 버전 드리프트를 그대로 읽을 수 있다.

### 2.2 ipk 해부 — Depends보다 깊이

```bash
FN=$(awk 'BEGIN{RS=""}/^Package: smhub-broker/{n=split($0,L,"\n");v="";f="";
  for(i=1;i<=n;i++){if(L[i]~/^Version: /)v=substr(L[i],10);if(L[i]~/^Filename: /)f=substr(L[i],11)}
  if(v=="1.0.4-1")print f}' /tmp/smpkgs.txt)

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT       # 현재 디렉토리에 풀지 마라
mkdir -p "$work/control" "$work/payload"            # ← 이 mkdir을 빼면 tar가 실패한다
curl --fail -sS -u "$AUTH" "https://pkg.smlight.tech/v1/$FN" -o "$work/pkg.ipk"
( cd "$work" && ar x pkg.ipk \
  && tar xzf control.tar.gz -C control \
  && tar xJf data.tar.xz  -C payload )
ls "$work/control"      # control · postinst · prerm · postrm · openrc · CHANGELOG.md
```

⚠️ `ar x`는 **현재 디렉토리에** 풀고 `tar -C <dir>`는 **그 디렉토리를 만들어 주지 않는다.**
둘 다 임시 작업판 안에서 하고 trap으로 지운다. 위 형태는
`smhub-broker 1.0.4-1`에서 실행 검증됐다 [측정 2026-09-16].

**control.tar.gz 안에 OpenRC init 스크립트(`openrc`)가 들어 있다.** 즉 `depend()`를
보드 없이 읽는다. 실측 예 (`smhub-broker 1.0.4-1`):

```sh
depend() { need localmount remoteproc; before status-login-ready }
start_pre() { /opt/firmware/bluetooth_proxy_mode 를 읽어 --ble-mode= 주입 }
```

### 2.3 Depends를 뽑을 때 — awk 상태 누수를 조심해라

레코드마다 `Depends:`가 **있을 수도 없을 수도** 있다. 줄 단위로 훑으면서 변수를 리셋하지
않으면 **앞 패키지의 Depends가 다음 패키지로 흘러간다.** 2026-09-16에 내가 이 버그로
「tailscale이 smhub-services에 의존한다」는 없는 사실을 만들어 형제를 반박할 뻔했다.

```bash
# 안전 — 레코드 단위(RS="")로 읽고 매 레코드에서 초기화
awk 'BEGIN{RS=""}{pkg="";v="";d="-없음-";n=split($0,L,"\n");
  for(i=1;i<=n;i++){
    if(L[i]~/^Package: /)pkg=substr(L[i],10);
    else if(L[i]~/^Version: /)v=substr(L[i],10);
    else if(L[i]~/^Depends: /)d=substr(L[i],10)}
  printf "%-18s %-13s %s\n",pkg,v,d}' /tmp/smpkgs.txt | sort -u
```

**의심스러우면 원문 레코드를 직접 봐라.** 형제의 영수증을 의심하기 전에 내 추출기를 의심한다.

---

## 3. 「설치됨」이 다섯 가지 뜻이다 — 평면을 섞지 마라

이걸 섞으면 없는 모순을 만든다 (2026-09-16에 실제로 만들었다).

**정본은 `docs/SMHUB.md:143-152`의 4층 구분**(2026-07-01 라이브 확정)이다. 새로 쓰지 말고 그걸 써라:

| 층 | 무엇이 말하나 | 어떻게 읽나 |
|---|---|---|
| 1 **카탈로그** | 깔 수 있는 것 전체 | 피드 `Packages` (§2.1) |
| 2 **설치(P)** | 패키지가 깔려 있나 — **설치 진실원** | `opkg list-installed` |
| 3 **enabled** | 벤더 `backend.db` 레지스트리 | backend.db. ⚠️ `backend.db.version ≠ opkg 버전` |
| 4 **running(R)** | 프로세스가 살아 있나 | `ps`, RSS. ⚠️ `rc-service started`만으로 확정하지 마라 |

여기에 2026-09-16에 **다섯 번째 표기면**이 하나 더 있다는 것이 드러났다:

| 5 **Web UI Apps의 「설치됨」** | 위 넷 중 어느 것과도 일치하지 않는다 |

실측: `esphome-bin`·`smhub-services`는 opkg에 **설치돼 있는데** Apps 화면엔 「미설치」이고,
`smhub-os-base`·`smhub-web`은 Apps 화면에 **아예 없다**. 시스템이 소유한 것(코프로세서 펌웨어·
OS 베이스·웹·백엔드)이 그 목록에 안 뜨는 것으로 *보인다* — **다만 Apps의 실제 predicate가
무엇인지(`enabled` DB인지 별도 레지스트리인지)는 소스로 확인하지 않았다 [인계, harvest]. `?`로 둬라.**

부팅 순서는 위 다섯 층과 또 다른 축이다 — ipk 안의 `openrc` `depend()`가 그걸 말한다(§2.2).

> GLG 프레이밍: *«모순이라고 말하기 보단 의존성이라. 의존성 자체가 탐구 대상이야.»*

### P와 R을 섞으면 생기는 대표 오독

`smhub-ui 1.0.6-1`과 `smhub-web 0.3.1-1`은 **둘 다 `smhub-services`에 패키지 의존**한다
[측정 2026-09-16, 피드 원문]. 그렇다고 `rc-service smhub-services stop`이 UI를 지우지 않는다 —
**stop은 패키지 그래프를 안 건드린다.** 잃는 것은 UDS API와 동적 화면(정적 shell은 200, API는 502)이다.
`opkg remove`는 다른 이야기고, 그때 비로소 두 전면이 깨진다.

## 4. 보드 접속 — 읽기는 싸고 쓰기는 비싸다

```bash
cd ~/repos/gh/homeagent-config
ssh -i .sshkey/id_ed25519 smlight@<기기>    # 좌표는 PRIVATE.md
```

`:22`는 기본 닫혀 있고 **Web UI에서 켜야 열린다.** 닫혀 있으면 Web UI `#/console`이 유일한 셸.

### 안전한 읽기 (부작용 없음)

```sh
opkg list-installed
cat /sys/class/remoteproc/remoteproc0/{state,name,firmware}
ls -l /opt/firmware/
ps -eo rss,pid,comm --sort=-rss | head -12
free -m; uptime
grep -o "\[ASH COUNTERS\].*" /tmp/zigbee2mqtt.log
```

### ⛔ 하지 않는 것

| 금지 | 왜 |
|---|---|
| **RTOS 코어 정지/재기록** | 원복 경로가 어느 문서에도 없다. 벽돌 위험 |
| **OTA** | RAUC A/B 슬롯을 뒤집는다. 별도 결정 사안 |
| **z2m 재기동** | §5의 크래시 패턴 — 재기동 자체가 트리거 용의선상. 그리고 관측 로그가 날아간다 |
| **MG24 재플래시** | Zigbee 망 전체를 잃는다. 되돌리려면 재페어링(이력 소실) |
| `opkg install/remove` | GLG 판단 사안. 특히 `esphome-bin`은 §6 |

---

## 5. ASH 관측 — 읽는 법과 함정

z2m이 **어댑터 기동 시각 기준 매시간** `[ASH COUNTERS]` CSV 27칸을 찍는다
(`WATCHDOG_COUNTERS_FEED_INTERVAL = 3600000`). 벽시계 정각이 아니다.

```
 1 txData  2 txAllFrames  3 txDataFrames  4 txAckFrames  5 txNakFrames
 6 txReDataFrames  7 txN1  8 txCancelled
 9 rxData 10 rxAllFrames 11 rxDataFrames 12 rxAckFrames 13 rxNakFrames
14 rxReDataFrames 15 rxN1 16 rxCancelled
17 rxCrcErrors 18 rxCommErrors 19 rxTooShort 20 rxTooLong 21 rxBadControl
22 rxBadLength 23 rxBadAckNumber 24 rxNoBuffer 25 rxDuplicates 26 rxOutOfSequence
27 rxAckTimeouts          ← 크래시가 찍는 그 칸
```

**17번부터가 전부 오류 카운터다.**

### 함정 셋

1. **`log_level: warning`에서는 이 두 줄이 아예 없다** — `logger.info`라서. 관측하려면
   `smhub/tune.sh --ash-on`. 끝나면 `--ash-off` (페어링 버스트에서 `info`는 진짜 부하다).
2. **콘솔 로그는 `/tmp` = tmpfs다. 재부팅하면 전부 사라진다.** 읽기 전에 재부팅 금지.
   `log_output`에 `file`을 더하면 eMMC로 가는데 `tune.sh`가 **일부러 그러지 않는다** —
   그 경로 불변식이 `--ash-on`의 소유물이다. 손으로 `configuration.yaml`을 고치지 마라.
3. **`rxAckFrames=0`은 고장이 아니다.** 이 NCP는 standalone ACK를 안 보내고 piggyback한다.
   정상 구간도 0이다. 이걸 근거로 쓰면 틀린다.

### 읽을 때 기억할 기준선 [측정 2026-09-16, `.agent-reports/2026-09-16-board-harvest.md`]

```
정상 운전 43시간 15분 · 2대 · 덤프 46개 → 오류 비영 1개
그 1개도 rxCrcErrors=1 → txNak=1 → rxReData=1 = ASH가 제 일을 한 기록
rxAckTimeouts : 46덤프 전부 0
```

옆 레인 x86(114덤프 오류 0)과 **등급이 같다.**
⚠️ 우리는 `adapter_concurrent: 1`이라 **「1코어라서」는 아직 채택도 기각도 못 한다.**

### 🔴 크래시는 재기동에 붙어 있다 [측정 2026-09-16, n=2]

09-14의 두 크래시 모두 `Network up` 직후다 — +8분14초, 그리고 **+18초**(Last Frame
`GET_EUI64` = 초기화 질의). 그 뒤 무접촉 43시간은 완전히 깨끗하다.
**고장의 축이 「부하·대수」가 아니라 「어댑터 (재)초기화」일 수 있다.**
그래서 §4가 z2m 재기동을 금지 목록에 넣는다.

---

## 6. esphome-bin은 앱이 아니다 — C906L 코프로세서 펌웨어다

이 보드에서 가장 오해하기 쉬운 자리다.

```
피드   smhub-broker 1.0.4-1  Depends: esphome-bin (>= 2026.5.3-5)   ← 벤더가 선언한 하드 의존
ipk    esphome-bin postinst  → 패키지 안의 ELF를 /opt/firmware/smhub-rtos.elf 로 복사
                             → .ota-deployed 표지가 없으면 rtos-notify restart
보드   remoteproc0/state = running · firmware = smhub-rtos.elf (422,792 B)
소스   platform-sg2000/boards/smhub.json : core c906l · freertos · upload.protocol custom
       esphome/platformio.ini:7 : default_envs = rtos-smhub
```

즉 **`.ota-deployed` 표지가 없으면 `opkg install/configure esphome-bin`이 C906L 펌웨어를
교체하고 RTOS를 restart할 수 있다.** 그 조건을 빼고 단정하지 마라 — 위 `postinst` 줄이 조건부다.

⚠️ **그런데 install과 remove를 같은 문장으로 묶지 마라.** 그 버전 archive에는 `prerm`이
**없다** — 확인된 것은 `postinst`의 복사·restart뿐이다. remove가 target ELF와 remoteproc을
어떻게 남기는지는 **모른다**. 둘 다 금지이지만 **위험의 메커니즘이 다르다.**
(대조: `smhub-broker`는 `prerm`·`postrm`이 있고 서비스를 정지시킨다.)

그 코어가 지금 하는 일: **LED 2개 · 공장초기화 버튼 · HA Bluetooth Proxy**
[읽음 `docs/SMHUB.md:607-629` §5.6].
Zigbee는 이 축에 **없다** — 「z2m 부담을 코프로세서로 넘긴다」는 그림은 이 제품에서 성립하지 않는다.

---

## 7. 플래시 — 이 작업의 작은 끝

두 가지가 완전히 다르다.

| 무엇 | 대상 | 도구 |
|---|---|---|
| **MG24 라디오 펌웨어** | EFR32MG24 (Zigbee NCP ↔ Thread RCP) | 벤더 `.gbl` 공개 배포, `smhub-flasher` |
| **C906L RTOS 펌웨어** | 코프로세서 | opkg `esphome-bin` (§6) — ⛔ |

Nano는 **MG24 한 개**라 Zigbee와 Thread가 **배타**다(동시 아님, 순차 재플래시).
Zigbee로 되돌리는 경로는 있지만 **재페어링이 필요하다** = 기기 이력이 남지 않는다.
`docs/MULTIPROTOCOL.md`가 「언제 단일칩 동시로 가나」의 SSOT다.

Milk-V Duo S eMMC 굽기는 **별개 스킬** `duo-s-flash`다. 섞지 마라.

---

## 8. 리서치 결과를 어디에 두나

| 성격 | 자리 |
|---|---|
| 진행 중 핸드오프 | `NEXT.md` |
| 기기 사실이 새로 확정됨 | `docs/SMHUB.md` |
| 절차가 생기거나 바뀜 | `smhub/RUNBOOK.md` |
| 값·설정의 소유자 | `smhub/tune.sh` (손으로 `configuration.yaml` 고치지 말 것) |
| 좌표·계정·키 | `PRIVATE.md` (공개 파일엔 금지) |
| 초안·중간 산출물 | `.agent-reports/` (gitignored) |
| 닫힌 일 | `CHANGELOG.md` |

**사실 문장에는 증거 상태를 달아라** — [측정](영수증), [읽음 `file:line`], [인계, 미확인](출처).
영수증 없는 문장은 사실이 아니라 가설이다. 그리고 **호스트 경로에 둔 증거는 형제에게 안 보인다** —
건너가는 문서에 결정적인 줄은 붙여 넣어라.
