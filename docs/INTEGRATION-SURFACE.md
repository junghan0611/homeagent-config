# SLZB-OS Integrations 표 실사 — 우리에게 무엇이 붙나

> **초안 — 리뷰 전. 채택 결정 아님.**

이 문서는 `docs/ECOSYSTEM-PORTFOLIO.md`의 §1 층위 모델·§0.1 두 레인 규약·근거상태 표기를
그대로 이어 쓴다. 대상은 `~/repos/3rd/milkv/slzb-os-scripts` README의 **Integrations 표**
(총 37행, `docs/modules/*.md` 각 1개) — `Domoticz`는 제외(§5·§6에서 이미 끝남). **36개**를 다룬다.

**답하는 질문**: 우리가 무엇을 발행하면 몇 개가 비용 0으로 붙고, 온박스 코드를 실제로
요구하는 건 몇 개인가.

---

## 0. 결론 먼저 — 숫자로

[측정, 이 세션] SLZB 36개 통합 전부를 `docs/modules/*.md`의 `## Notes` 절과 소스 예제로
전송 축을 실측했다. 결과:

| 발행하면 | 붙는 개수 | 근거 |
|---|---|---|
| **HTTP/HTTPS 클라이언트** (이미 `libcurl` `=y`, `docs/ECOSYSTEM-PORTFOLIO.md §5`) | **34 / 36** | 아래 §2 표 — SMTP·ICMP·UDP·순수계산 4개를 뺀 나머지 전부가 HTTP(S) GET/POST다 |
| **MQTT 클라이언트** (이미 `mosquitto` `=y`, §7) | **+1** (Frigate, 이미 HTTP로도 셀 수 있어 중복 아님 — 권장 경로가 MQTT) | `frigate.md:1-6` |
| 위 둘 다 우리 defconfig에 **이미 있다** | → **35/36이 새 온박스 코드 없이 붙는다** | — |
| ~~진짜 새 코드가 필요한 것 1개(EMAIL)~~ → **0개** | **36/36** — `libcurl`의 SMTP가 `default y`로 이미 켜져 있다 | **§6.1 (리뷰에서 닫힘)** |
| ICMP(Ping) · UDP(WoL) · 순수계산(Sun) | 각 1개, "새 클라이언트"가 아니라 **표준 소켓 syscall 3줄** — 사실상 0 | §2 표 |
| **온박스 통째 호스팅 후보 9개**(Node-RED·n8n·InfluxDB·ESPHome·OpenWrt·Frigate·openHAB·ioBroker·Jeedom) | **Buildroot 2951개 중 0개 존재** | §3 |

**놀란 지점**: SLZB 통합 36개 중 34개가 결국 "URL 하나에 GET/POST 한 번"이다.
Berry가 `TELEGRAM`·`HA`·`DISCORD`처럼 이름을 따로 붙였을 뿐, 밑은 전부 같은 HTTP 클라이언트다
(§2.1 근거). **우리는 그 클라이언트를 이미 갖고 있다** — 새로 만들 것이 없고, 남는 일은
"어느 URL에 어떤 JSON을 보내느냐"라는 **설정/문서 작업**이지 런타임 작업이 아니다.
이건 `ECOSYSTEM-PORTFOLIO.md` §2.1이 SLZB에 대해 내린 판정("한계비용 ≈ 0")이 **우리 쪽에서도
그대로 성립한다**는 뜻이고, 심지어 SLZB보다 우리가 유리하다 — 저쪽은 5120바이트 Berry VM
예산 안에서 이걸 다 하는데, 우리는 이미 풀 Buildroot 이미지에 `libcurl`을 갖고 있다.

---

## 1. 층위 배치 — `ECOSYSTEM-PORTFOLIO.md` §1 기준

36개가 균질하지 않다. 기존 A⁰/A/A′/B/C에 안 맞는 결이 하나 나와서 새 하위 범주를 둔다.

| 하위범주 (신설) | 뜻 | 몇 개 | 층위 대응 |
|---|---|---|---|
| **B-out 단방향 알림** | 허브 → 외부 서비스로 메시지만 던진다. 응답을 안 읽는다 | 12 | B의 부분집합, 가장 싼 쪽 |
| **B-peer LAN 주변기기 제어** | 허브 → 같은 LAN의 다른 장치(WLED·Hue·Tasmota 등)를 HTTP로 직접 민다 | 12 | B와 비슷하지만 **외부 플랫폼이 아니라 우리가 컨트롤러 쪽** — B의 방향이 뒤집힌 형태 |
| **B-in 상위 플랫폼 편입** | 허브가 HA·OpenHAB·Node-RED 같은 **상위 오케스트레이터**의 하위 장치로 편입된다 | 8 | B 그대로 — "우리가 어댑터를 안 짜도 저쪽이 문다"의 정의 사례 |
| **A′ 물리 실행** | 네트워크가 아니라 로컬 인터페이스(GPIO 레벨 프로토콜)로 나간다 | 2 (Ping=ICMP, WoL=UDP) | A′에 가깝다 — 코프로세서는 아니지만 "Linux 사용자공간 라이브러리 없이 되는 것" |
| **순수 로컬 계산** | 네트워크 자체가 필요 없다 | 1 (Sun) | 층위 밖 — 비용 0, 논의 불필요 |
| **C 후보(문서상)** | README가 "wraps 플랫폼"이라 적었지만 실체는 그 플랫폼에 대한 B-in 클라이언트일 뿐, 우리가 호스팅한다는 뜻이 아니다 | 0 | 아래 §3에서 "그렇다면 그 플랫폼 자체를 우리가 올릴 수 있나"를 별도로 검사 |

**이 결이 값이다**: README의 "Integrations 표"는 이름 그대로 다 "통합"이라 뭉뚱그려 읽기
쉽지만, 실제로는 **누가 컨트롤러이고 누가 컨트롤 대상인지**가 항목마다 다르다.
B-in(HA/OpenHAB/Node-RED 등)은 SLZB가 **하위 장치**로 편입되는 경로이고, B-peer(WLED/Hue/
Tasmota 등)는 SLZB가 **컨트롤러**로 군림하는 경로다. 우리 HomeAgent 허브에 이 목록을 그대로
옮기면, 방향이 우리 쪽으로 완전히 뒤집힌다 — **우리가 오케스트레이터**이므로 B-in 8개는
"우리가 HA/OpenHAB/Node-RED 밑에 들어가는 어댑터"로 그대로 값이 있고, B-peer 12개는
"우리가 그 LAN 장치들을 직접 문다"로 값이 있다. 둘 다 같은 HTTP 클라이언트로 붙는다는 점은
같다.

---

## 2. 전 항목 표 — 층위 · 전송축 · 온박스 실체 · 오프라인 판정

[측정] 전부 `docs/modules/<name>.md`의 `## Notes` 절 원문 확인. 표에는 근거 줄 번호를 담지
않고(38개 파일이라 표가 무너짐), §2.1~§2.4에 발췌를 인용한다.

| 통합 | 하위범주 | 전송 | 실제 대상 | 오프라인 생존 |
|---|---|---|---|---|
| Telegram | B-out | HTTPS | `api.telegram.org` | ❌ 클라우드 필수 |
| WhatsApp | B-out | HTTPS | `api.callmebot.com` | ❌ |
| Teams | B-out | HTTPS webhook | Azure Logic Apps | ❌ |
| Slack | B-out | HTTPS webhook | `hooks.slack.com` | ❌ |
| Discord | B-out | HTTPS webhook | `discord.com` | ❌ |
| Pushover | B-out | HTTPS | `pushover.net` | ❌ |
| Prowl | B-out | HTTPS | `prowlapp.com` | ❌ (iOS 전용) |
| ntfy | B-out | HTTPS | `ntfy.sh` (기본값, 자가호스팅 가능) | ⚠️ 조건부 — 자가호스팅하면 LAN |
| **Email** | B-out | **SMTP + TLS(465)** | 사용자 SMTP 서버(대개 클라우드) | ❌ 대개 |
| IFTTT | B-out | HTTPS | `maker.ifttt.com` | ❌ |
| Weather | B-out | HTTPS | `api.openweathermap.org` | ❌ |
| AirQuality | B-out | HTTPS | `api.openweathermap.org` | ❌ |
| GSheets | B-out | HTTPS | `script.google.com` | ❌ |
| HA | B-in | HTTP(REST) | LAN Home Assistant | ✅ LAN |
| OpenWrt | B-peer | HTTP(ubus JSON-RPC) | LAN 라우터 | ✅ LAN |
| **WoL** | A′ | **UDP 브로드캐스트(포트 9)** | LAN 브로드캐스트 도메인 | ✅ LAN, 클라이언트조차 아님 |
| Hue | B-peer | HTTP(평문, v1 API) | LAN Bridge | ✅ LAN |
| WLED | B-peer | HTTP(평문) | LAN WLED 장치 | ✅ LAN |
| SLWF03 | B-peer | = WLED alias | LAN | ✅ LAN |
| SLWF09 | B-peer | = WLED alias | LAN | ✅ LAN |
| ESPHome | B-peer | HTTP(`web_server` 컴포넌트 필요, 네이티브 API 미지원) | LAN | ✅ LAN |
| SLWF01 | B-peer | = ESPHome alias | LAN | ✅ LAN |
| SLWF08 | B-peer | = ESPHome alias | LAN | ✅ LAN |
| Kodi | B-peer | HTTP(JSON-RPC v12+) | LAN | ✅ LAN, "no cloud" 명시 |
| Tasmota | B-peer | HTTP(`GET /cm?cmnd=`) | LAN | ✅ LAN, "no cloud" 명시 |
| Nuki | B-peer | HTTP(Bridge API) | LAN(Bridge, 락 자체는 BLE) | ✅ LAN, "no cloud" 명시 |
| **Ping** | A′ | **ICMP(ESP-IDF)** | 임의 LAN/WAN 호스트 | ✅ (대상이 로컬이면) |
| Webhook | B-in/out 겸 | HTTP(범용, named) | 임의 URL | ⚠️ 대상 나름 |
| n8n | B-in | HTTP POST(= WEBHOOK 재사용) | 자가호스팅 or 클라우드 | ⚠️ 자가호스팅이면 LAN |
| Node-RED | B-in | HTTP(포트 1880 기본) | 대개 LAN(RPi/Docker) | ✅ 대개 LAN |
| Frigate | B-in | **MQTT 권장**(HTTP도 있음, 포트 5000) | LAN NVR | ✅ LAN |
| OpenHAB | B-in | HTTP REST(포트 8080, Bearer 토큰) | LAN | ✅ LAN |
| Jeedom | B-in | HTTP GET(API 키 쿼리파라미터) | LAN | ✅ LAN |
| ioBroker | B-in | HTTP GET(Simple API, 포트 8087) | LAN | ✅ LAN |
| **Sun** | 순수계산 | 네트워크 없음(NTP 시각만 필요) | — | ✅ 완전 로컬 |

**집계**: B-out(클라우드 전용) 13 · B-in/B-peer(LAN, 대개 오프라인 생존) 20 · A′(ICMP/UDP) 2
· 순수계산 1 = 36.

### 2.1 "이름이 다 다른데 밑은 같다"의 직접 근거

[읽음 `ha.md:258`] *"Uses the Home Assistant REST API over HTTP (not WebSocket)"*.
[읽음 `telegram.md:287`] *"Messages are sent via HTTPS to `api.telegram.org`"*.
[읽음 `wled.md`] *"Uses HTTP (not HTTPS) to communicate with WLED devices"*.
[읽음 `webhook.md`] *"Unlike the built-in `HTTP` module, WEBHOOK returns both the status code
and response body as a map"* — **WEBHOOK 자체가 HTTP 위의 얇은 래퍼임을 문서가 자인한다.**
[읽음 `n8n.md`] *"The WEBHOOK module sends a standard HTTP POST"* — n8n 통합의 정체가
WEBHOOK 재사용이라고 명시.

Berry 쪽엔 `TELEGRAM`·`HA`·`DISCORD`처럼 각자 이름 붙은 네이티브 모듈이 있어 겉보기엔
38개의 별도 구현처럼 보이지만, Notes 절이 밑을 계속 HTTP(S)로 자백한다. **SMLIGHT도 결국
우리와 똑같은 결론에 도달해서 그렇게 나눈 것**으로 읽는다 — Berry 쪽 사정(ESP32 펌웨어에서
모듈 단위로 메모리를 관리해야 한다)이 그 이유이지, 프로토콜이 정말 38가지인 게 아니다.

### 2.2 SMTP가 유일한 새 온박스 요구

[읽음 `email.md`] *"Uses implicit TLS (direct TLS connection on port 465) — STARTTLS on port
587 is not supported"*, *"Only plain text emails are supported"*.
~~[미확인] 우리 arm64 defconfig에 SMTP 클라이언트 라이브러리가 있는지~~
→ **§6에서 닫혔다: 켜져 있다. EMAIL도 새 코드 0이다.**

### 2.3 오프라인 판정 — Z4D류 부팅 시 외부조회는 없다

`docs/ECOSYSTEM-PORTFOLIO.md §6.3`이 찾은 함정(Z4D가 기동할 때마다 `google.com`을 조회하고,
그 결과로 내부 게이트가 사라지는 것)을 이 36개에서도 찾았다. **[측정, 이 세션] 결과: 없다.**
36개 전부가 **호출 시점에만** 나간다 — Berry 스크립트가 `TELEGRAM.send()`를 부를 때만 HTTP가
뜨고, SLZB 부팅 시퀀스 자체에 이 모듈들을 자동으로 찔러보는 코드는 `docs/modules/*.md`
어디에도 없다. Notes 절에서 "call"·"each function call makes one HTTP request"라는 표현이
반복되는 것 자체가 **호출-단위 과금**이라는 뜻이고, Z4D의 `is_internet_available()`처럼
모듈 초기화 자체에 박혀 있는 부팅 게이트가 아니다.

**단, 사용 패턴이 위험을 재도입할 수 있다.** [읽음 `telegram.md:284`] *"It is not recommended
to call TELEGRAM module functions in TIMER callbacks because HTTP requests take a long time
and can cause delays"* — 즉 SLZB 자신도 "이걸 상시 폴링에 넣지 마라"고 경고하고 있다.
우리가 이 패턴을 옮길 때 **TIMER/폴링에 클라우드 통합을 넣으면** Z4D와 똑같은 성질(오프라인
허브가 매 주기 타임아웃을 무는 것)이 우리 손으로 재도입된다. **이건 SLZB 문서의 결함이
아니라 우리가 어떻게 쓰느냐의 문제**로 남는다.

### 2.4 ntfy·n8n·Node-RED — "클라우드냐 LAN이냐"가 배포가 아니라 설정값이다

세 개는 표에서 ⚠️로 남겼다. `ntfy.sh`는 공개 서버가 기본값이지만 셀프호스팅 인스턴스로
바꾸면 LAN 전용이 된다(`ntfy.md`: *"For private notifications, use a self-hosted ntfy
instance"*). n8n도 마찬가지로 자가호스팅/클라우드 둘 다 문서가 인정한다(`n8n.md`: *"n8n is
free and open-source for self-hosting, or available as a cloud service"*). **이건 통합
자체의 성질이 아니라 사용자가 무엇을 뒤에 두느냐의 문제**라서, 이 문서 수준에서 "오프라인
생존"을 단정할 수 없다 — 배치 판단이 필요하면 그때 다시 본다.

---

## 3. 온박스 통째 호스팅 후보 — Buildroot 실사

[측정, 이 세션] `~/repos/3rd/milkv/duo-buildroot-sdk-v2/buildroot/package/` 전수 대조,
`ls -d */`로 카운트 **2951개**(`ECOSYSTEM-PORTFOLIO.md §3`이 잰 값과 동일 — 같은 SDK 핀).

과제 지시대로 "온박스 호스팅 후보"로 지목된 9개(§1의 표에 나온 상위 플랫폼들 — 우리가
그 밑에 편입되는 게 아니라 **그 플랫폼 자체를 우리가 올린다면**)를 대조했다:

| 후보 | Buildroot 패키지 | 판정 |
|---|---|---|
| Node-RED | ❌ 0건 | out — Node.js 런타임 재도입, §4의 결론과 동일 사유 |
| n8n | ❌ 0건 | out — Node.js 대형 앱, 논외 |
| InfluxDB | ❌ 0건 | out — Go 바이너리, Buildroot 미지원 |
| ESPHome | ❌ 0건 | out — Python + 컴파일 툴체인 전체, 헤드리스 허브가 짊어질 대상이 아님 |
| OpenWrt | ❌ 0건(당연히 — OpenWrt는 별도 배포판이지 Buildroot 패키지가 아니다) | 논외 — 우리는 이미 Buildroot 노선 |
| Frigate | ❌ 0건 | out — Python + TensorFlow/ffmpeg, NVR 워크로드는 우리 타깃 밖 |
| openHAB | ❌ 0건(`openjdk`는 있음, `ECOSYSTEM-PORTFOLIO.md §3`) | out — JVM 재도입 |
| ioBroker | ❌ 0건 | out — Node.js |
| Jeedom | ❌ 0건(`php` 8.3.19는 있음) | out — LAMP 한 벌, `ECOSYSTEM-PORTFOLIO.md §3`과 동일 |

**9/9 전부 out.** `ECOSYSTEM-PORTFOLIO.md §3`이 Domoticz를 "유일한 현실 후보"로 판정한 것과
정확히 같은 벽 — **Node/JVM/Python 대형앱 런타임을 재도입해야 하는 것은 Buildroot에
없다.** Kodi는 있지만(64개 서브패키지) 미디어센터라 헤드리스 허브 타깃과 무관해 후보에서
제외한다.

> **판정 재확인**: 그래서 이 9개는 §1의 B-in 분류가 맞다 — 우리가 그 플랫폼의 **클라이언트**가
> 되는 것(HTTP 몇 줄)은 비용 0이지만, 그 플랫폼 **자체를 우리가 호스팅하는 것**은 Domoticz와
> 같은 등급의 벽이고 지금 아무것도 뚫지 않았다. 두 질문은 완전히 다른 질문이고, README의
> "통합" 표는 이 둘을 구분해서 보여주지 않는다 — 그 구분이 이 문서의 §1이 하는 일이다.

### 3.1 ⚠️ "9/9 out"은 그릇을 하나로 못 박은 답이다 — 벤더는 Buildroot로 굽지 않는다

**GLG 지적 (2026-09-01, 이 세션 중): "이 업체가 디바이스랑 같이 해서 임베디드 보드 패키징을
어떻게 가지고 가는가? 이 솔루션들이 업계에서 요구한다는 거거든."** — §3의 판정은
**"Buildroot 소스 트리에 패키지가 있는가"**만 물었다. 그런데 벤더가 무거운 스택을 실제로
얹을 때 쓰는 그릇은 **Buildroot가 아니다.**

[읽음, `docs/smhub-manual/pages/06-smhub-os-release-notes.md:19`] *"**Community App Repository
[📦]**: Added support for the community app repository directly in `opkg`. … lays the
groundwork for allowing community-published apps in the smhub ecosystem!"*

[읽음, GLG가 이 세션 중 인용, 같은 파일:92] *"**PicoClaw Support [🦀]**: Added underlying
system support for PicoClaw, allowing you to run this ultra-lightweight personal AI assistant
directly on the system. **Available to install from the apps page.**"*

**이게 답이다.** PicoClaw(경량 온보드 AI 어시스턴트)도, `zigbee2mqtt`도(`ECOSYSTEM-PORTFOLIO.md
§2.2` — *"Allowed `zigbee2mqtt` to remain uninstalled after an OTA upgrade"*), 벤더 base
이미지에 **굽혀 있지 않다.** `opkg` 앱 레지스트리로 **부팅 후 쓰기 가능 파티션에 설치**된다.
base rootfs는 얇게 유지하고, 무거운 선택 스택은 별도 빌드·별도 설치 경로로 뗀다 — **Buildroot
소스 트리의 패키지 존재 여부는 애초에 벤더가 묻지 않는 질문이다.**

**§3의 "9/9 out"이 틀린 게 아니다 — 질문이 하나였다는 게 부족했다.** "이걸 우리 Buildroot
소스 빌드에 넣을 수 있나"엔 여전히 0/9로 답한다(그건 사실이고 값도 있다 — 크로스빌드 부담을
드러낸다). 그런데 GLG가 묻는 건 그게 아니라 **"이 업계가 요구하는 조합을 하나의 그릇에 담을
방법이 있는가"**다. 그 답은 §3이 아니라 여기다:

| 그릇 | 무엇을 넣나 | 우리 쪽 대응물 |
|---|---|---|
| **Buildroot 소스 빌드** (§3이 잰 것) | 베이스 이미지 자체 — 부팅에 필수인 것 | `bsp/buildroot/<board>_defconfig` |
| **opkg 앱 레지스트리** (벤더가 PicoClaw·z2m에 쓰는 것) | 선택 스택 — 부팅 후 쓰기 파티션에 설치, base 이미지 예산과 분리 | **없다 — 이게 미수금이다** |
| **우리 프로파일 프래그먼트** (`ECOSYSTEM-PORTFOLIO.md §8`) | 빌드 타임 선택 조합 | `bsp/buildroot/profiles/*.fragment` — 이것도 여전히 빌드 타임이지 런타임 앱스토어가 아니다 |

**"어떤 방식으로든 담아서 하나의 그릇으로 만든다"(GLG)의 실제 조작면은 opkg류 런타임
설치자다.** 지금 우리에게 그 그릇이 없다 — `bsp/`는 빌드 타임 프로파일만 갖고 있고, 부팅 후
설치 가능한 별도 파티션·패키지 포맷·앱 페이지는 설계된 적이 없다. **n8n이 여기 목록에 왜
있는지 모른다는 GLG의 관찰이 정확하다** — SLZB 표에 n8n이 있는 이유는 "ESP32에 n8n을
올린다"가 아니라 "우리 통합이 n8n을 **호출**한다"이고, 그건 §2의 B-in으로 이미 값이 있다.
반대로 PicoClaw는 **진짜로 온보드에 올라간다** — 이 둘을 구분하지 않으면 "업계가 요구한다"는
관찰이 잘못된 항목(9개 대형 플랫폼)에 걸려 오독된다. **업계가 실제로 요구·공급하는 건
opkg 그릇이지, 이 9개 플랫폼을 Buildroot로 굽는 게 아니다.**

**따라서 "n8n을 왜 임베디드 보드에 넣었나"의 정답은 "안 넣었다"다** — SLZB 문서 어디에도
"n8n을 ESP32에 설치한다"는 문장이 없다(`n8n.md`는 반대로 *"n8n is free and open-source for
self-hosting, or available as a cloud service"* — n8n은 **저쪽에서 돈다**). SMHUB(Linux
허브) 쪽에서 opkg로 실제 설치되는 건 지금까지 문서에서 확인된 게 z2m·matterbridge·
node-red·mosquitto(§2.2, 전부 preinstalled 후보로 언급)·PicoClaw뿐이다. **Node-RED는
표에서 "n8n류 통합 클라이언트"가 아니라 SMHUB 앱 레지스트리에 실제 설치되는 항목으로
한 번 더 등장한다** — 그러니 9개 후보 중 최소 Node-RED 하나는 "그쪽 벤더가 opkg로 이미
설치한다"는 사실 위에 있다. Buildroot에 없다는 §3의 사실과, opkg로 벤더가 이미 배포한다는
이 사실은 **모순이 아니다** — 둘이 다른 빌드 파이프라인을 쓴다는 뜻이다.

**안 잰 것 (§4에 추가할 항목)**: opkg 패키지가 어떻게 만들어지는가 — 벤더가 Buildroot 밖에서
별도 크로스빌드해서 `.ipk`로 포장하는지, 아니면 자체 SDK가 있는지. 이걸 알아야 "우리도 같은
그릇을 만들 수 있는가"에 답할 수 있다.

### 3.2 PicoClaw 정체 — `ECOSYSTEM-PORTFOLIO.md` §3 표에 없던 다섯 번째 후보일 수 있다

**[인계 — 형제 세션(`entwurf/claude-opus-5`)이 exa-search로 확인, 이 리포 측정 아님, 2026-09-01]**
PicoClaw = `github.com/sipeed/picoclaw` · **Go** · MIT · 29,918★. 벤더 자체 주장(README, 검증
안 됨): *"<10MB RAM"* · *"<1s 부팅(0.8GHz 코어)"* · *"95% Agent가 생성"*. 최근 빌드는
*"10-20MB로 늘 수 있다"*는 단서도 스스로 붙였다.

**[측정, 이 세션]** 우리 SDK가 pin한 Buildroot에 **`go` 1.23.7이 있고**, `package/go/
Config.in.host:10`의 지원 아키텍처 목록에 **`BR2_riscv`가 포함된다.** §3의 9개 후보(Node.js/
JVM/PHP 대형 런타임)와 성질이 다르다 — Go는 **정적 바이너리, 인터프리터 재도입이 아니다.**
`docs/ECOSYSTEM-PORTFOLIO.md §3` 표의 "인터프리터 0" 조건(Domoticz가 유일하게 통과한 조건)을
PicoClaw도 **문서상으로는** 통과한다.

**[미확인] 이건 이 문서의 범위 밖이다.** PicoClaw 자체 패키지가 Buildroot에 있는지, 실측 RAM/
바이너리 크기가 벤더 주장과 맞는지 이 세션은 재지 않았다. §3.1의 opkg 발견과 별개로 —
**opkg 그릇이 아니라 우리 Buildroot에 직접 구울 수 있는 다섯 번째 온박스 호스트 후보**로
보이므로, 다음에 이 항목을 재는 세션에 남긴다. 판단하지 않는다.

---

## 4. 안 잰 것

1. ~~SMTP가 우리 `libcurl` 빌드에 켜져 있는가~~ → **§6.1 닫힘(켜져 있다).** 이하 원문: — `CURL_DISABLE_SMTP`류 옵션 미확인. 켜져
   있으면 §0의 "새 온박스 코드 1개(EMAIL)"가 0개로 줄어든다. 값이 큰 확인이라 먼저 잴 항목.
2. ~~HTTPS(TLS) 자체를 우리 이미지가 갖고 있는가~~ → **§6.2에서 사실상 닫힘**(생성 `.config` 확인만 남음). 이하 원문: — `libopenssl`은 §5(`ECOSYSTEM-PORTFOLIO.md`)
   기준 이미 `=y`이지만, `libcurl`이 그 위에서 HTTPS를 실제로 협상하는지(빌드 플래그)는
   이 세션에서 다시 확인하지 않았다. B-out 13개 전부가 HTTPS라서 이게 막히면 13개가 한꺼번에
   막힌다.
3. **인바운드 웹훅(WEBSERVER 대응물)** — B-in 8개 중 상당수가 "양방향이 되려면
   `WEBSERVER.md`류 수신 서버가 필요하다"고 명시한다(n8n·Node-RED·Frigate·OpenHAB·Jeedom·
   ioBroker 전부 Notes에 이 문구가 있다). 우리가 **단방향 리포트만** 할 거면 필요 없고,
   외부 플랫폼이 우리를 **제어**하게 하려면 리슨 소켓 하나가 새로 필요하다 — 이건 있다/없다가
   아니라 "요구 시나리오가 뭐냐"의 문제라 지금 판정하지 않는다.
4. **각 알림 서비스의 페이로드 크기·인증 방식** — 표는 전송축만 쟀다. 실제 붙이려면 서비스별
   토큰 관리(예: Telegram Bot Token, Slack Webhook URL)가 필요하고 그건 이 문서의 범위를
   넘는 배치 작업이다.
5. ~~opkg 앱이 어떻게 만들어지는가~~ → **§6.4 닫힘: `host-opkg-utils`가 그 파이프라인이다.** 남은 건 이미지 레이아웃 설계. 이하 원문: — 벤더가 PicoClaw·z2m·Node-RED를 Buildroot 밖
   어느 파이프라인으로 크로스빌드해서 `.ipk`로 포장하는지 미확인. **이게 "패키징을 잘하면
   재현 가능한 솔루션이 된다"(AGENTS.md 불변식)를 우리 쪽에 옮기는 첫 실작업 후보다** —
   Buildroot 소스 빌드와 별개로 **런타임 앱 레지스트리 그릇**을 우리가 가질지가 여기 달렸다.

---

## 6. 리뷰 — 미확인 셋이 닫혔고, §3.1 결론 하나가 뒤집힌다

**[측정, 검토 세션 `20260901T135628-68bbae`, 2026-09-01]** 이 문서를 리뷰하며 §4의 항목들을
직접 쟀다. 원 조사의 판정은 유지되고, 숫자 하나와 결론 하나가 움직인다.

### 6.1 §4-1 닫힘 — SMTP는 이미 켜져 있다. **새 온박스 코드는 0개다**

[읽음 `package/libcurl/Config.in:39-50`]

```kconfig
config BR2_PACKAGE_LIBCURL_EXTRA_PROTOCOLS_FEATURES
	bool "enable extra protocols and features"
	default y                       ← 이것
	help
	  - LDAP / LDAPS
	  - POP3 / IMAP / SMTP          ← 여기 있다
```

우리 defconfig는 이 심볼을 **적지 않았다**. 그런데 defconfig에서 빠진 심볼은 기본값을 따르고
그 기본값이 `y`다 → **SMTP는 켜져 있다.**

> **따라서 §0의 "진짜 새 코드가 필요한 것 = 1개(EMAIL)"는 0개다. 36/36이 붙는다.**
> 새 온박스 코드 0, defconfig 변경 0.

### 6.2 §4-2 닫힘 — HTTPS도 선다

[읽음 `package/libcurl/Config.in`의 `choice "SSL/TLS library to use"`] 이 choice에는 명시적
`default`가 없고, 첫 항목 `BR2_PACKAGE_LIBCURL_OPENSSL`이 `depends on BR2_PACKAGE_OPENSSL`이다.
우리 defconfig에 `BR2_PACKAGE_LIBOPENSSL_BIN=y`·`_ENGINES=y`(:116-117)가 있어 OpenSSL이 보이므로
**kconfig가 첫 visible 항목인 OpenSSL 백엔드를 고른다.** 그러면
[읽음 `libcurl.mk:68-70`] `--with-openssl` + `--with-ca-path=/etc/ssl/certs`가 붙고,
**`BR2_PACKAGE_CA_CERTIFICATES=y`가 이미 우리 defconfig(:115)에 있다.**

**[근거상태 주의]** 이건 kconfig 해석이지 **생성된 `.config`를 읽은 것이 아니다.** 다음 빌드에서
한 줄로 확정할 수 있다:
```
grep -E 'LIBCURL_(OPENSSL|EXTRA_PROTOCOLS)' <output>/.config
```
→ B-out 13개가 한꺼번에 막히는 시나리오는 **일어나지 않을 가능성이 높다**로 내려간다.

### 6.3 §3의 0/9 — 독립 재현됨

검토 세션이 같은 트리를 따로 grep했다. `influxdb`·`node-red`/`nodered`·`n8n`·`esphome`·
`frigate`·`openhab`·`iobroker`·`jeedom`·`openwrt` **전부 0건.** 원 조사와 일치한다.

### 6.4 ⚠️ §3.1 정정 — 그릇이 없는 게 아니라, 부품이 선반에 있는데 조립을 안 했다

§3.1의 통찰("Buildroot에 있냐는 베이스 이미지 질문이고, 업계의 그릇은 런타임 앱 레지스트리다")
은 **맞고, 이 문서에서 제일 값이 큰 문장이다.** 그런데 거기 붙은 결론 —
*"우리에게 그 그릇이 없다"* — 은 측정으로 뒤집힌다.

[측정, `package/` 트리 2951개 대조] 우리가 pin한 Buildroot **2025.02** 안에 이미 있다:

| 패키지 | 버전 | 무엇인가 |
|---|---|---|
| `opkg` | 0.7.0 | 타깃 쪽 설치기 — 벤더가 쓰는 그것 |
| **`opkg-utils`** | 0.7.0 | **host 설치 커맨드 있음**(`HOST_OPKG_UTILS_INSTALL_CMDS`) → `opkg-build`·`opkg-make-index` |
| `rauc` | 1.13 | **SMHub이 쓰는 A/B 업데이트 기계**(`docs/SMHUB.md`) |
| `swupdate` · `mender` · `libostree` | — | 대안 업데이트 프레임워크 |

**그리고 이것이 §4-5("벤더가 어떤 파이프라인으로 크로스빌드하는가")의 답이기도 하다.**
특별한 파이프라인이 아니다:

```
Buildroot로 빌드 → host `opkg-build`로 .ipk 포장 → `opkg-make-index`로 피드 색인
                                                  → 타깃의 `opkg`가 설치
```

**그래서 미수금의 정확한 문장은 이렇게 바뀐다:**

> 형식도 도구도 없는 게 아니다. **한 번도 세워본 적이 없는 것**이다 — 피드, 쓰기 가능한 앱
> 파티션, 설치 생명주기. 부품은 있고 조립을 안 했다.

이건 "새 축을 열어야 한다"가 아니라 **"있는 걸 안 켰다"**라서 값이 훨씬 싸다.
`docs/TARGET_DEVICE.md`의 ION 148M과 같은 성질이다 — **미수금이지 낭비가 아니다.**

**남는 미확인**: 피드를 어디에 두고 어떤 파티션에 설치하며 OTA를 어떻게 넘길지. 그건 도구
문제가 아니라 **이미지 레이아웃 설계**라 별도 판단이다. `bsp/`의 프로파일 프래그먼트(빌드 타임)와
이 그릇(런타임)의 관계도 같이 정해야 한다 — `ECOSYSTEM-PORTFOLIO.md` §8.

## 5. 읽을 곳

| 무엇 | 어디 |
|---|---|
| 층위 모델·근거상태 규약·Buildroot 실사 방법론(짝 문서) | `docs/ECOSYSTEM-PORTFOLIO.md` |
| 보드 기준(Duo S 512MB) | `docs/TARGET_DEVICE.md` |
| 1차 사료 | `~/repos/3rd/milkv/slzb-os-scripts/README.md`, `docs/modules/*.md` |
