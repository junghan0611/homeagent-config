# 홈오토메이션 스택 랜드스케이프 — 작은 폼팩터에 무엇을 밀어넣을 수 있나

> **상태 (2026-09-01)**: **조사 자료다. 채택 결정이 아니다.** `docs/HUBS.md`가 하드웨어
> 랜드스케이프인 것처럼, 이 문서는 그 짝인 **소프트웨어 랜드스케이프**다. 여기 실린 어떤
> 스택도 이 리포의 방향으로 승격되지 않았다.
>
> **이 리포의 중심은 "다 만든다"가 아니다.** 512MB급 작은 폼팩터 보드에 이 주제를
> 밀어넣는 것이고, 그래서 남이 이미 만든 것을 **참고하고 재는 것**이 일이다. 고집할
> 스택은 없다.
>
> **놓치면 안 되는 맥락 (GLG 2026-09-01)**: 타깃은 **Duo S급 저사양에 꽉 눌러담는 것**이다.
> 큰 기계에서 되는 걸 확인하는 게 아니라, 작은 기계에 들어가느냐가 유일한 질문이다.
> 그래서 이 문서의 모든 표는 "되나"가 아니라 **"512MB에 들어가나"**로 읽는다.
>
> **그리고 512MB도 종착지가 아니다 (GLG 2026-09-01)**: §4의 Node 제거가 성공하면 타깃 보드가
> **Milk-V Duo 256M (SG2002, 256MB)** 으로 내려갈 수 있다. 즉 이 문서의 스택 선택은 소프트웨어
> 취향이 아니라 **하드웨어 등급을 한 칸 내리는 조건**이다. 보드 쪽 실사는
> `docs/TARGET_DEVICE.md` "256MB 후보" 절.
>
> **버전 방침 (GLG 2026-09-01)**: domoticz는 **최신 `2026.3`으로 간다.** Buildroot가 pin한
> `2024.4`가 아니다 — 아래 §5·§6이 재 놓은 서브모듈 부채는 **모르고 지는 게 아니라 알고
> 지는 것**이다. 그 값은 회사 레인의 실증 결과를 보고 확정한다.

---

## 0. 이 문서가 답하는 질문

> "홈오토메이션 플랫폼이 이미 여럿 있는데, 512MB 보드에 **무엇을 얹고 무엇을 얹지 않나**?"

핵심 판정은 크기가 아니라 **런타임 개수**다. 파일 크기는 눈에 보이지만, 실제로 보드를
잡아먹는 건 "이 스택을 돌리려고 새 런타임(Node/JVM/PHP/Python)을 한 벌 더 들이는가"다.

---

## 1. 층위를 먼저 가른다 — 섞으면 512MB가 터진다

| 층 | 뜻 | 온박스 비용 |
|---|---|---|
| **A⁰ 라디오만 내준다** | 시리얼 코디네이터를 네트워크로 노출(`ser2net` 류). Zigbee 호스트는 남의 기계에서 돈다 | **0** |
| **A 굽는다** | 라디오 + 브리지 + 브로커 + 상태머신 | 여기만 싸움 |
| **A′ 코프로세서로 내린다** | 실시간·저지연 일을 RTOS 코어(C906L)로 | Linux RAM 0 |
| **B 말만 건다** | 외부 플랫폼(HA·openHAB·domoticz·ioBroker·Node-RED·n8n·Frigate)에 HTTP/MQTT로 붙는다 | **0 — 어댑터 문서뿐** |
| **C 선택 설치** | 온박스 호스트를 옵션으로 얹는다 | 크다 |

**B의 값이 제일 크다.** MQTT(+HA discovery)와 REST 한 면만 발행하면, 저쪽 플랫폼들이
우리를 문다 — 우리가 어댑터를 짜지 않아도 된다.

---

## 2. 참고: 벤더 둘이 같은 문제를 푼 방식

두 제품 다 **한 벤더**(SMLIGHT)이고, 스케일마다 답이 다르다. 이 대비가 이 문서의 뼈대다.

### 2.1 코디네이터 스케일 — 어댑터 모델

[측정] SLZB-OS 스크립팅 문서(`smlight-tech/slzb-os-scripts`, 2026-08-29 시점):

- 통합 **40여 개**(Telegram·HA·openHAB·domoticz·ioBroker·Jeedom·Node-RED·n8n·Frigate·
  Hue·WLED·ESPHome·InfluxDB·Kodi…)를 표로 싣는다.
- 그런데 각 통합의 실체는 **Berry 스크립트 몇 줄**이다. domoticz 문서는 대놓고 말한다 —
  *"This integration uses the WEBHOOK or HTTP module directly. **No separate module needed**."*
- 스크립트 기본 스택 = **5120 바이트**. 통합이 "fully supported"인 하드웨어의 차이는
  **PSRAM 2MB 추가**(U-series). 무선칩은 ESP32.

> **통합 1개의 한계비용 ≈ 0.** 40개가 온보드에 존재하지 않기 때문이다. 온보드엔 HTTP
> 클라이언트 1개, MQTT 클라이언트 1개, 스크립트 VM 1개가 있고 나머지는 **문서**다.
> (그 문서들이 기기 내장 AI 어시스턴트의 skill로 로딩되는 구조까지 같이 설계돼 있다.)

### 2.2 Linux 허브 스케일 — 앱 레지스트리 모델

[측정] SMHUB-OS 벤더 릴리즈노트 스냅샷(`docs/smhub-manual/pages/06-*`, 2026-09-01 재수집):

- **OS v1.0.0 정식, 2026-07-10.** 이전 스냅샷(2026-07-02)은 정식 8일 전이었다.
- **Community App Repository** — *"community app repository directly in `opkg` … lays the
  groundwork for allowing community-published apps"*. **벤더가 앱을 다 만들지 않겠다고 선언했다.**
- **Uninstalled App Persistence** — *"Allowed `zigbee2mqtt` to remain uninstalled after an
  OTA upgrade"*. **Z2M조차 베이스가 아니라 지울 수 있는 앱이다.**
- **`ser2net` v4.6.7 + 전용 설정 페이지.** 시리얼을 네트워크로 내보낸다 → 위 표의 **A⁰**.
- beta3(2026-06-14): **ESPHome을 RTOS 코프로세서 코어에** 올리고(`esphome-bin`·broker
  프리번들), **HA Bluetooth Proxy 동시 16 연결**을 낸다 → **A′** 그리고 **B**(플랫폼을
  호스팅하지 않고 플랫폼의 주변장치가 된다).
- beta2(2026-05-27): 초경량 온박스 AI 어시스턴트도 **앱 페이지 설치물**이다.

**벤더 문서 ≠ 실기.** 매뉴얼 `4.2`/`7.5`는 z2m·matterbridge·node-red·mosquitto 4개가
preinstalled라 하지만, [측정] 출고 실기 opkg는 5개뿐이고 **matterbridge 미설치·nodered
enabled=0**이었다(`docs/SMHUB.md §5`). 이 리포의 원칙 그대로다 —
**"running ≠ installed ≠ enabled ≠ working."**

### 2.3 스냅샷 재수집 기록 (2026-09-01)

`docs/smhub-manual/fetch.sh` 재실행, 22/22 성공. **22페이지 중 1페이지만 변했다**:
`06-smhub-os-release-notes.md` **101,533B → 103,724B (+2,191B)**, 나머지 21개 바이트 동일.
그 +2,191B가 §2.2의 v1.0.0 항목 전부다. (이 디렉터리는 gitignore라 `git diff`가 없어,
fetch 직전에 찍어둔 파일 크기와 대조했다.)

---

## 3. 온박스 호스트 후보 — Buildroot 기준 실사

[측정] 우리 SDK가 pin한 **Buildroot 2025.02**의 패키지 **2951개** 전수 대조.

| 후보 | 런타임 | Buildroot 패키지 | RAM ¹ | 판정 |
|---|---|---|---|---|
| **Domoticz** | **C++ (인터프리터 0)** | ✅ **있다** (2024.4) | ~50MB idle / 100–200MB loaded | **유일한 현실 후보** |
| Home Assistant | Python | ❌ | ~300MB idle | 311MB 보드에서 out |
| openHAB | JVM | ❌ (`openjdk`는 있음) | JVM만 수백MB | out |
| ioBroker | Node.js | ❌ | Node 재도입 | Node를 빼려는 판에 다시 넣는다 |
| Node-RED | Node.js | ❌ | 위와 동일 | B층으로 |
| Jeedom | PHP + DB | `php` 8.3.19는 있음 | LAMP 한 벌 | out |
| FHEM | Perl | ❌ | perl + 모듈 | out |

¹ 외부 아티팩트(`selfhosting.sh` 비교표, 2025-12-22). **우리 측정이 아니다.** 보드 실측 없음.

**Domoticz만 두 조건을 동시에 만족한다: Buildroot 패키지 존재 + 인터프리터 0.**
나머지는 전부 "런타임을 하나 더 들여야 한다"에서 죽는다.

---

## 4. Zigbee 호스트 — 선택지 넷 (여기가 진짜 풋프린트 싸움)

| 경로 | Zigbee 호스트 | 런타임 | 온박스 비용 | 우리가 짜나 |
|---|---|---|---|---|
| 현재 | Zigbee2MQTT | **Node 22** | **141M** (node 49.5M + node_modules 92M) | 아니오 |
| **domoticz + Z4D** | zigpy/bellows | **Python 3.12** | 플러그인 14M + zigpy 계열 + domoticz | 아니오 |
| 자체 게이트웨이 | EZSP 직결 | Zig | 최소 | **예** |
| **A⁰ `ser2net`** | 없음(남의 기계) | — | **0** | 아니오 |

- [측정] 우리 arm64 defconfig는 Z2M을 **npm 모듈로** 태운다
  (`BR2_PACKAGE_NODEJS_MODULES_ADDITIONAL="zigbee2mqtt@2.10.1"`). Buildroot에 zigbee2mqtt
  패키지는 **0건**이다.
- [측정] 상용 제품도 같은 값을 지불한다 — SMHUB의 `/opt/bin/node` = **74,808,592B**
  (riscv64, `docs/SMHUB.md §5.2`). 그리고 **v1.0.0에서 그걸 "지울 수 있게" 만들었다.**

> **결론 방향**: 플랫폼 선택보다 **Zigbee를 Node에서 떼는 것**이 압도적으로 크다.
> 그리고 그 방법이 하나가 아니다 — 위 네 줄은 배타가 아니라 **프로파일로 갈릴 수 있다.**

---

## 5. Domoticz 실사

[측정] 업스트림 `domoticz/domoticz`, `development` 브랜치 기준.

**의존성** (`package/domoticz/Config.in`의 select): boost(atomic·date_time·system·thread) ·
cereal · jsoncpp · libcurl · minizip-zlib · mosquitto · openssl · sqlite · zlib.
**`depends on BR2_PACKAGE_LUA_5_3`** — select가 아니라 depends라 손으로 켜야 하고,
Buildroot 2025.02의 lua 기본은 5.4다.

우리 arm64 defconfig에 **이미 있는 것**: `libopenssl` · `libusb` · `libcurl` ·
`mosquitto` · `python3`. **새로 드는 것**: boost 1.83 · lua 5.3.6 · sqlite 3.48 ·
jsoncpp 1.9.6 · minizip-zlib · cereal(헤더 온리, 타깃 0).

**툴체인 게이트**: `!BR2_STATIC_LIBS` · `GCC≥6` · NPTL · `INSTALL_LIBSTDCPP` · `USE_WCHAR` ·
`ALWAYS_LOCKFREE_ATOMIC_INTS`. arm64 Bootlin GCC 13 glibc 레인은 전부 통과.
**riscv64/musl 레인은 안 쟀다.**

**타깃 풋프린트** — 설치 대상(`CMakeLists.txt` install 규칙)만:

```
www 18M · dzVents 1.9M · scripts 488K · plugins 256K   →  정적 자산 ~21M
Config 7.8M 은 들어오지 않는다 (IF(OpenZWave) 안에서만 설치)
바이너리 크기는 미측정 — 275개 .cpp, C++17 + boost 링크
```

**"150+ hardware types"의 실체**: `hardware/` 149개 드라이버를 실제로 세면 —
1Wire · EnOcean(ESP2/ESP3) · P1Meter · Teleinfo · S0Meter · RFXCom · RFLink · ZiBlue ·
OpenZWave · Evohome · KMTronic · USBtin · RAVEn · MySensors 등이 **네이티브**다.
**빠진 건 Zigbee 하나뿐**이고, Zigbee 입구는 `hardware/MQTTAutoDiscover.cpp`(= Z2M) 뿐이다.
→ 그래서 §6이 중요해진다.

**버전 부채 — 알고 진다 ⚠️**: Buildroot 레시피는 **2024.4** 타르볼이다. 최신 트리엔
서브모듈이 5개(`libwebem`은 필수 빌드 타깃, `jwt-cpp`는 Buildroot에 패키지 없음)이고
**타르볼엔 서브모듈이 안 온다.** 즉 `2024.4`로 쓰면 부채 0, 올리면 부채가 생긴다.

[측정] 업스트림 태그: `… 2025.1 · 2025.2 · 2026.1 · 2026.2 · **2026.3**`.

> **GLG 판정 (2026-09-01): `2026.3`으로 간다.** 부채 0을 사자고 2년 묵은 버전을 신지
> 않는다. 그러면 레시피는 우리가 쥔다 — 서브모듈 5개를 어떻게 조달할지가 **첫 번째 실작업**이
> 된다(vendoring / `_EXTRA_DOWNLOADS` / 별도 패키지 중 택1, 미결정).
> `jwt-cpp`는 Buildroot에 패키지가 없으므로 그것 하나는 새로 쓴다.

(레시피가 옛 버전 기준이라는 증거: `.mk`가 넘기는 `-DUSE_BUILTIN_MQTT=OFF`는 현재
`CMakeLists.txt`에 없는 옵션이다.)

---

## 6. Zigbee for Domoticz (Z4D) — Node 없이 Zigbee를 무는 경로

[측정] 업스트림 `zigbeefordomoticz/Domoticz-Zigbee`, `stable9.9.1.004` (2026-08-27).

**정체는 zigpy 스택이다.** 트랜스포트 4종 중 하나가 우리 라디오다:

```
Classes/ZigpyTransport/AppBellows.py   ← EZSP / EFR32   (import bellows.zigbee.application)
Classes/ZigpyTransport/AppZnp.py       ← TI CC26xx
Classes/ZigpyTransport/AppDeconz.py    ← deCONZ
Classes/ZigpyTransport/AppBlz.py       ← BLZ
```

**크기**: 소스 131M 중 `.git`이 117M → **실물 14M**(www 6.7M · Modules 2.0M · images 1.7M ·
Classes 1.3M), `.py` 344개.

**Buildroot 커버리지**:

| ✅ 있다 | ❌ 없다 |
|---|---|
| `python3` 3.12.9 · `python-serial` 3.5 · `python-cryptography` 44.0.0 · `python-jsonschema` 4.23.0 · `python-dnspython` 2.7.0 · `python-requests` · `python-distro` · `python-charset-normalizer` | **`zigpy` · `bellows` · `zigpy_znp` · `zigpy_deconz` · `zigpy-blz`** · `pyserial-asyncio-fast` · `serialx` · `z4d-certified-devices` |

**빠진 것들은 전부 순수 Python이고, 유일한 네이티브 의존(`cryptography`)은 이미 Buildroot에
있다.** 그래서 이건 포크가 아니라 **`python-package` 레시피 몇 장**이다 — `AGENTS.md`의
downstream budget이 명시적으로 허용하는 범주다. Node 레인과 성질이 다르다.
(그리고 우리 arm64 defconfig엔 `BR2_PACKAGE_PYTHON3=y`가 이미 켜져 있다.)

**벽 둘 ⚠️**

1. **버전 사슬 — GLG 결정으로 방향이 정해졌다.** 플러그인 요구는
   `Domoticz >= 2025.2 (2025.1 minimum)` · `Python >= 3.11`. Buildroot가 주는 건
   **domoticz 2024.4** / python 3.12.9 → Python 통과, **Domoticz 미달**.
   즉 **Z4D를 쓰려면 도마티즈를 올릴 수밖에 없고**, GLG는 `2026.3`으로 가기로 했다(§5).
   그래서 이건 "막힌 벽"이 아니라 **첫 작업 항목**이다 — 서브모듈 조달.
2. **cryptography 핀.** 플러그인 `constraints.txt`는 `cryptography<=40.0.2`, Buildroot는
   **44.0.0**이고 `SETUP_TYPE = maturin`(Rust 툴체인 동반). **그 핀이 실제 비호환인지
   보수적 핀인지는 안 쟀다** — 값이 큰 한 줄짜리 확인.

**곁가지**: 이 업스트림은 루트 `AGENTS.md`/`CLAUDE.md` + 하위 디렉터리별 `AGENTS.md`로
에이전트 규약을 계층화해 뒀고, *"의존성 범프를 routine update로 취급하지 말 것"*을 계약으로
못 박아 놨다. 벽 2를 건드릴 때 저쪽에 이미 절차가 있다.

---

## 7. 스크립트 면이 필요해지면

[측정] Buildroot 2025.02에 **이미 있는 것**: `duktape` 2.7.0 · `quickjs` 2024-01-13 ·
`micropython` 1.22.0 · `lua` 5.4.7/5.3.6 · `luajit`.
**`berry`는 없다** — §2.1이 쓰는 그 VM은 패키지가 없어서 쓰려면 우리가 패키징한다.
SLZB식 사용자 스크립트 면이 필요하면 `quickjs`/`duktape`로 **부채 없이** 같은 자리를 채운다.

MQTT: `mosquitto` 2.0.20(우리 이미지에 이미 `=y`) · `paho-mqtt-c` · `paho-mqtt-cpp`.
프로토콜: `openzwave` · `owfs`(1-Wire) · `rtl_433`(433MHz).

---

## 8. 우리 쪽 기계와의 접점

- **프로파일 프래그먼트가 우리 버전의 앱 레지스트리다.** SMHUB이 `.ipk`로 하는 것을
  우리는 `HOMEAGENT_BSP_PROFILE`로 한다(`bsp/buildroot/profiles/`). domoticz를 얹는다면
  defconfig가 아니라 `profiles/<board>_<name>.fragment`가 맞는 자리다.
  **차이는 정직하게**: 우리 건 빌드 타임, 저쪽은 런타임 설치다.
- **A′(코프로세서) 슬롯은 우리도 이미 갖고 있다.** `runtime/`의 C906L mailbox 축이
  §2.2에서 벤더가 ESPHome을 올린 바로 그 코어다. 아직 안 쓴 슬롯이다.

---

## 9. 안 잰 것 (값 붙는 순서)

1. **`cryptography<=40.0.2`가 실제 비호환인가** — 업스트림 체인지로그 한 번. §6 벽 2의 전부.
2. **domoticz `2026.3`을 Buildroot에서 굽는 레시피** — 서브모듈 5개(`libwebem`·`jwt-cpp`·
   `jsoncpp`·`minizip`·`sqlite-amalgamation`) 조달 방식 미결정. **GLG가 버전을 정했으므로
   이건 조사가 아니라 실작업이다.** §5·§6 벽 1.
3. **domoticz 바이너리 실측** — minimal 트리에 domoticz만 켜서 굽는다(V8 없어 싸다).
4. **RSS 실측** — MemTotal 311MB 보드에서. §3의 RAM 열은 전부 남의 숫자다.
5. **riscv64/musl 가부** — 제품 ISA 레인. domoticz·zigpy 양쪽 다 미측정.
6. **`ser2net`로 EZSP 원격 구동 시 지연·안정성** — A⁰의 유일한 미지수.
7. **SMHUB v1.0.0 실기** — 우리 기기는 아직 beta5 슬롯이다(`docs/SMHUB.md`). §2.2는
   전부 릴리즈노트 문서지 실측이 아니다.

---

## 10. 읽을 곳

| 무엇 | 어디 |
|---|---|
| 하드웨어 랜드스케이프(짝 문서) | `docs/HUBS.md` |
| 단일 라디오 동시 프로토콜 | `docs/MULTIPROTOCOL.md` |
| SMHUB 실측 SSOT (실기가 정본) | `docs/SMHUB.md` |
| 벤더 매뉴얼 스냅샷 | `docs/smhub-manual/` (gitignore, `fetch.sh`로 재수집) |
| 프로파일 기계 | `bsp/README.md` "Profiles" · `bsp/buildroot/profiles/` |
| 코프로세서 축 | `runtime/README.md` |
| 로컬 클론 경로 · 비공개 좌표 | `PRIVATE.md` |
