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
> **기준 보드는 Duo S 512MB다 (GLG 2026-09-01: "보드 기준은 512M Duo S로 잡아").**
> Milk-V Duo 256M(SG2002)은 **조건부 후보로 열어만 둔다** — Node 제거가 성공하면 등급을 한 칸
> 내릴 수 있다는 뜻이고, 지금 타깃은 아니다. 보드 쪽 실사는 `docs/TARGET_DEVICE.md`
> "256MB 후보" 절.
>
> **그리고 이 리포가 재현성을 만드는 방식 (GLG 2026-09-01)**: *"NixOS로 x86을 하든 Buildroot로
> 하든, **패키징을 잘하면 재현 가능한 솔루션이 된다.**"* 두 레인이 서로 경쟁하는 게 아니라
> 같은 원리를 두 타깃에서 실행하는 것이다(§0.1). 그래서 이 문서의 판정 기준은 "무엇이 좋은
> 스택인가"가 아니라 **"무엇을 재현 가능하게 패키징할 수 있는가"**다.
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

### 0.1 두 레인은 역할이 다르다 — x86에서 점검, 임베디드에서 검수

**GLG 2026-09-01**: *"거기는 NixOS로 하는 거야. 임베디드 작업 아니다 — 리눅스 머신에 올리는
거고. x86에서 점검하고 임베디드로 우리가 또 검수하면 되니까."*

| | 실증 레인 (회사, x86 리눅스/NixOS) | **이 리포 (임베디드, Buildroot 크로스)** |
|---|---|---|
| 무엇을 답하나 | **이 조합이 도는가** — 스택·버전·의존이 서로 맞물리나 | **이 조합이 이 등급에 들어가는가** — 크로스빌드·풋프린트·RAM |
| 실패했을 때 뜻 | 스택 선택이 틀렸다 | 스택은 맞고 **우리 축**이 문제다 |
| 조달 | 배포판 패키지 / 휠 | 소스 크로스빌드 |

**그래서 그쪽에서 넘어오는 사실은 결론이 아니라 검수 대상이다.** 그대로 옮겨 적으면 "x86에서
됐다"가 "보드에서 된다"로 조용히 승격된다. 이 문서는 인계분을 **[인계 — 실증 레인 보고, 우리
측정 아님]** 으로 표시하고, 그 위에 우리가 무엇을 다시 재야 하는지를 적는다.

**뒤집어 말하면 그쪽이 우리 미측정 목록을 대신 줄여 준다.** 스택 층에서 이미 갈린 것을 우리가
크로스빌드로 다시 갈리게 둘 이유가 없다 — 우리 몫은 **그 다음 질문**이다.

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
2. **cryptography 핀 — 절반 닫혔고, 나머지 절반은 우리 레인에서 다르게 생겼다.**
   플러그인 `constraints.txt`는 `cryptography<=40.0.2`, Buildroot는 **44.0.0**이고
   `SETUP_TYPE = maturin`(Rust 동반).

   **[인계 — 실증 레인 담당자 보고, 우리 측정 아님, 2026-09-01]** 그쪽 x86_64 환경에서
   `constraints.txt`를 전수 대조한 결과 **Zigbee 스택 전체가 핀을 정확히 통과**했다:
   `zigpy 2.1.0` · `zigpy_znp 1.1.0` · `zigpy_deconz 1.0.0` · `zigpy-blz 0.1.0` ·
   `bellows 1.0.0` · `pyserial>=3.5` · `serialx>=1.4.0`. 못 채운 셋
   (`charset-normalizer==2.0.11` · `jsonschema==4.17.3` · `cryptography<=40.0.2`)은
   **전부 Zigbee와 무관한 부수 라이브러리**이고 **Z4D가 2022년 핀을 그대로 들고 있는 자리**로
   판정됐다. `cryptography==40.0.2`는 `cp36-abi3` 휠이 있어 조달 자체는 되지만, 배포판에 2023년
   암호 라이브러리를 강제하는 건 후퇴라 **채우지 않고 최신으로 진행**하기로 했다.

   **[측정, 이 리포] 그리고 그 핀은 Z4D 자신의 요구가 아니다.** `import cryptography` /
   `from cryptography…`가 소스 전체에 **0건**이다(tests 제외). `requirements.txt`에 이름만 있고
   코드가 쓰지 않는다 → 그 핀은 **zigpy 계열의 전이 의존을 대신 눌러 놓은 것**이고, 실제 판정자는
   `zigpy 2.1.0`이 무엇을 요구하는가다.

   **그리고 그 사실은 우리 레인으로 그대로 복사되지 않는다 — 그게 설계다** (§0.1 참조). [측정]

   | | 실증 레인 (x86 리눅스) | **이 리포 (임베디드 크로스)** |
   |---|---|---|
   | 조달 방식 | `…-cp36-abi3-manylinux_2_28_`**`x86_64`**`.whl` | **소스 타르볼 + maturin + Rust 크로스빌드** |
   | 40.0.2로 내리려면 | 휠 하나 받으면 끝 | **다운그레이드 레시피 + 그 시절 Rust/maturin 호환을 우리가 진다** |
   | riscv64 | 해당 없음 | 경로는 있다 — `BR2_PACKAGE_HOST_RUSTC`가 `riscv64gc`를 안다 |

   > **그래서 그쪽이 "핀을 안 채우고 최신으로 간다"고 한 결정이 우리 검수 항목을 하나 정해 준다.**
   > x86에서 최신 `cryptography`로 Z4D가 돌면 **스택 층의 답이 나온 것**이고, 우리가 검수할 것은
   > 그 다음 질문 하나로 좁혀진다 — **같은 조합이 크로스빌드로도 서는가.** 거기서 서면 벽 2는
   > 소멸이고(Buildroot 44.0.0 그대로), 안 서면 그건 스택 문제가 아니라 **우리 축의 문제**다.

   ### 벽 2의 실제 조작면 — `CheckRequirements` 플래그

   **[인계]** 실증 레인은 `CheckRequirements=0`으로 켜 두고, 그 근거를 이렇게 갈랐다:
   *"어제의 우회는 **zigpy가 메이저 갭인 채로** 검사를 끈 것이라 위험했고, 지금은 **zigbee
   코어가 정확히 맞은 상태에서** 부수 셋만 남긴 것이다. 성격이 다르다."*
   → **같은 플래그라도 무엇이 안 맞은 채로 끄느냐가 위험을 가른다.** 이 판단은 그대로 가져온다.

   **[측정, 이 리포] 그런데 우리 쪽에선 그 플래그가 다르게 생겼다.** `plugin.py:476`:

   ```python
   if self.internet_available and self.pluginconf.pluginConf.get("CheckRequirements", True):
       if check_requirements(Parameters["HomeFolder"]):   # True = 요구사항 미충족
           self.onStop()                                   # 플러그인이 스스로 멈춘다
           return
   ```

   두 가지가 따라온다.

   1. **경고가 아니라 fail-closed 게이트다.** 미충족이면 `onStop()`이다. 이미지에 얹었을 때
      "돌다가 로그만 지저분한" 종류가 아니라 **안 뜨는** 종류다.
   2. **`internet_available`이 거짓이면 검사 자체가 건너뛰어진다.** 이 리포의 불변식은
      *"On-device first: cloud may be a fallback, not a dependency"* 다 — 즉 **오프라인 허브에서는
      이 게이트가 통과가 아니라 부재가 된다.** 그건 우리가 내린 결정이 아니라 **네트워크 상태가
      대신 내려 준 결정**이고, 이 리포가 제일 싫어하는 종류다("running ≠ working").
      (설정 자체는 `Classes/PluginConf.py:439`, `default 1`, hidden/Advanced bool.)

   > **그래서 우리 검수 항목은 "플래그를 어떻게 둘까"가 아니라 이것이다 —
   > 오프라인 부팅에서 이 게이트가 조용히 사라지지 않게, 값을 우리가 명시적으로 정한다.**
   > **GLG 2026-09-01: "우리가 할 때는 다시 고민해보면 된다."** 지금 정하지 않는다.

**곁가지**: 이 업스트림은 루트 `AGENTS.md`/`CLAUDE.md` + 하위 디렉터리별 `AGENTS.md`로
에이전트 규약을 계층화해 뒀고, *"의존성 범프를 routine update로 취급하지 말 것"*을 계약으로
못 박아 놨다. 벽 2를 건드릴 때 저쪽에 이미 절차가 있다.

---

## 6.1 실측 — 페어링까지 관통한 스택의 풋프린트 (2026-09-01)

**[측정, 이 세션 · 실증 레인이 띄운 프로세스를 이 리포에서 직접 관측]**
`domoticz 2026.3` + Z4D가 스마트플러그 페어링까지 관통한 상태에서 잰 값이다.
호스트는 **x86_64 / glibc / Python 3.14 (nixpkgs)**, 가동 **2분 43초**, 페어링 기기 **1대**.

### 프로세스 — 하나다

```
PID 1217454  .domoticz-wrapped  -www 8080  Threads 29
  fd 76 → /dev/ttyUSB0            ← 동글 직결
```

**`node` 프로세스 0개. 별도 python 데몬 0개. Z2M 0개.** domoticz(C++) · CPython 3.14 ·
zigpy · bellows · aiohttp가 **한 주소공간**에 있다(`cpython-314` 확장 매핑 240건 확인).
이 경로의 브로커 의존도 없다 — Z4D가 시리얼을 직접 쥔다.

### 메모리

| 항목 | 값 |
|---|---|
| `VmRSS` | **123,788 kB ≈ 121 MB** |
| `Pss` | 123,320 kB — `Shared_Clean` 496 kB뿐 → **공유 라이브러리로 부풀린 숫자가 아니다** |
| `Private_Dirty` (힙) | 84,620 kB |
| `Private_Clean` (코드·데이터) | 38,672 kB |
| `VmHWM` | `VmRSS`와 동일 → 아직 최고점 |
| `VmSwap` | 0 |

### 디스크

| 항목 | 값 |
|---|---|
| 바이너리 `.domoticz-wrapped` | **18,228,688 B ≈ 17.4 MB** |
| `share/domoticz` (www·scripts·dzVents) | 25 MB |
| **설치 소계** | **43 MB** |
| userdata (`www` 18M + `plugins` 18M 복사본 + DB 420K) | 37 MB |
| DB (`domoticz.db`, 1기기 페어링 후) | **420 KB** |

§5에서 소스로 추정만 하고 못 쟀던 바이너리가 **17.4MB**로 닫혔다.

### 현재 Z2M 경로와의 대조

| | **domoticz 2026.3 + Z4D** | 현재 Z2M 경로 |
|---|---|---|
| 프로세스 | **1** | Node + 브로커 ≥ 2 |
| 바이너리 | **17.4 M** | node **49.5 M** |
| 앱 자산 | 25 M | `node_modules` **92 M** |
| **디스크 소계** | **43 M** | **141 M** |
| RSS | **121 M** (측정) | **미측정** |

> **디스크는 이겼다 — 1/3.3, 98M 절감.** **RAM은 아직 판정 못 한다.**
> Z2M+Node의 RSS를 우리가 재본 적이 없어서 비교 대상이 없다. 그리고 121MB는 그 자체로
> 가벼운 값이 아니다 — Duo S 실측 `MemTotal` 311MB의 **39%**, Duo 256M 추정 165MB의 **73%**다.

### 이 숫자를 옮길 때의 경계

1. **x86_64 / glibc / Python 3.14다.** 우리 레인은 riscv64 또는 aarch64이고 Buildroot의
   Python은 **3.12.9**다 — 인터프리터 버전부터 다르다(§0.1).
2. **2분 43초, 기기 1대다.** 정상상태도 아니고 규모도 아니다. `VmHWM = VmRSS`는 "아직 안
   올라갔다"이지 "여기가 천장이다"가 아니다.
3. **nix closure는 315.5 MiB**지만 이 값을 우리 rootfs 예산에 그대로 대입하면 안 된다 —
   nix는 의존을 통째로 세고, Buildroot는 시스템 전체가 공유한다. **회계축이 다르다.**
4. **121MB의 분해가 아직 없다.** domoticz 단독 vs +Z4D를 갈라 재야 Python/zigpy 몫이 나온다.
   눌러담기의 다음 한 수는 거기다.

## 6.2 RSS 분해 — 35 MB는 domoticz, 86 MB는 Python (2026-09-01)

**[인계 — 실증 레인 담당자 측정, thinkpad 15:52–15:59, `/proc/<pid>/status`. 우리 측정 아님.]**
같은 기계·같은 바이너리(`domoticz 2026.3`, nixpkgs `34ab9907` nixos-unstable, python3=3.14.7)
위에서 세 조건을 갈라 쟀다.

| | 조건 | `VmRSS` | Threads | ttyUSB fd |
|---|---|---|---|---|
| **A′** | domoticz만 (Z4D 하드웨어 `enabled=false`) | **35,864 kB ≈ 35.0 MB** | 17 | 0 |
| **B** | +Z4D 로드, `Mode2=None` (라디오 미기동) | **86,924 kB ≈ 84.9 MB** | 22 | 0 |
| **C** | +Z4D +EZSP +동글 물림 | **124,376 kB ≈ 121.5 MB** | 29 | 1 |

A′는 두 번 재서 34.9 / 35.0 MB로 재현. B·C는 `VmHWM == VmRSS`, `VmSwap 0`.

```
CPython 3.14 + Z4D import 계층   B − A′ = 51,060 kB ≈ 49.9 MB
zigpy / bellows 라디오 스택      C − B  = 37,452 kB ≈ 36.6 MB
────────────────────────────────────────────────────────────
Python 스택 전체                 C − A′ = 88,512 kB ≈ 86.4 MB   ← C의 71%
```

> **"Node를 뺐더니 Python이 들어온 것인가"의 답은 예다.**
> domoticz C++ 본체는 **35 MB**이고, 나머지 **86 MB가 Python**이다. 하드웨어가 없으면
> 플러그인 정의는 로드돼도 CPython 인터프리터 인스턴스가 아예 안 뜬다(A′의 17스레드가 그 상태).

**보고자가 밝힌 한계 — B는 하한선이다.** `Mode2=None`에서 `Z4D loaded 676 certified devices`
로그가 안 나와, certified DB 로드를 포함한 완전 초기화까지 갔는지 확인되지 않았다. 덜 갔다면
진짜 B는 더 크고 그만큼 "zigpy 몫 36.6 MB"는 **과대평가**다. **이 방향으로만 틀린다.**
→ 보수적으로 **`CPython+Z4D 계층 ≥ 50 MB` · `zigpy 라디오 ≤ 37 MB`** 로 읽는다.

**디스크 정정**: userdata 37 MB(`www` 18M + `plugins` 18M)는 nix store가 읽기 전용이라 만든
**쓰기 가능 사본**이고 3rd 리포에 쓰기를 안 내려는 런타임 사본이다. **랩 편의의 산물이지
하한이 아니다** — 배포판에선 심볼릭 링크로 줄일 여지가 있다.

### 이 숫자가 §4 표를 계산 가능하게 만든다

**호스트(UI·DB·자동화)는 싸고, 비싼 것은 Zigbee 호스트다.** 35 MB 위에 무엇을 얹느냐가 전부다.

| 경로 | 호스트 | Zigbee 호스트 | RSS 합계 |
|---|---|---|---|
| domoticz + **Z4D** | 35 M | **+86 M** (CPython+zigpy) | **121 M** (측정) |
| domoticz + **Z2M** | 35 M | + Node **미측정** + 브로커 | **미측정** |
| domoticz + **자체 Zig 게이트웨이** | 35 M | + 작다 (미측정) | **여기가 처음으로 계산 가능해졌다** |
| **A⁰ ser2net** | 35 M(또는 0) | **0** — 남의 기계 | 최소 |

**기준 보드는 Duo S 512MB다 (GLG 2026-09-01: "보드 기준은 512M Duo S로 잡아. 내가 그걸로
가니까").** 그 기준에서:

| 보드 | 가용 RAM | `domoticz+Z4D` 121 M | 판정 |
|---|---|---|---|
| **Duo S 512M (기준)** | **311 M** (실측 `MemTotal`) | **39%** | **여유 있다** |
| Duo S + ION 회수 | ~459 M (계산) | 26% | — |
| Duo 256M (조건부 후보) | ~165 M (추정) | 73% | 빡빡 |
| Duo 256M + ION 회수 | ~232 M (계산) | 52% | 가능 |

**Duo S 기준으로는 이 스택이 들어간다.** 256M 줄은 지금 타깃이 아니라 참고이고,
`docs/TARGET_DEVICE.md`의 ION 회수와 곱해지면 그때 다시 본다.

**그리고 Python 86 MB를 "새 비용"으로 읽으면 안 된다 (GLG 2026-09-01: "python은 어차피
들어갈 테니까").** [측정] 우리 arm64 defconfig는 이미 `BR2_PACKAGE_PYTHON3=y`(:107)다 —
**디스크 축에서 Python은 이미 지불된 값이다.** 다만 **RAM 축은 다르다**: 이미지에 있는 것과
인터프리터가 떠서 86 MB를 쥐는 것은 별개다. 두 축을 섞지 않는다. 요지는
**"Node가 빠지는 것이 순이득"**이고, Duo S 기준에서 그 순이득은 충분하다.

## 6.3 ⚠️ Z4D는 기동할 때마다 밖으로 나간다 (2026-09-01)

**[인계 — 실증 레인 담당자가 소스와 로그로 확인. 우리 측정 아님.]** §6의 `CheckRequirements`
게이트를 우리가 지적하자 그쪽이 구현을 열어 더 큰 것을 찾았다.

```python
# Modules/checkingUpdate.py:456-466
def is_internet_available():
    try:
        with urllib.request.urlopen("https://www.google.com", timeout=3) as response:
            return response.status == 200
    except (urllib.error.URLError, socket.timeout):
        return False
```

1. **기동 때마다 `https://www.google.com`으로 아웃바운드**를 시도한다. 오프라인이면
   **3초 타임아웃**을 물고, 그 결과로 §6의 요구사항 게이트가 **사라진다.**
2. **텔레메트리가 기본 ON.** `MatomoOptIn` 기본값 **1 = opt-out** [읽음
   `Classes/PluginConf.py:36`]. 실제로 발신됐다 [측정 15:44:44, 로그 원문]:
   `Z4D sends analytics information.` 대상은 `https://z4d.pipiche.net/matomo.php`
   [읽음 `Modules/matomo_request.py:76`].
3. **런타임 pip 업그레이드 시도.** `Plugin looks to upgrade the Certified Device package` —
   기동 중 외부 패키지를 pip으로 올리려 한다(그쪽 환경은 pip 부재로 실패).

**우리 불변식과 정면으로 만난다** — *"On-device first: cloud may be a fallback, not a
dependency for local control"* · *"Own the box"*. 임베디드 이미지에는 pip이 없고, 제품 허브가
기동할 때마다 제3자에게 신호를 보내는 것은 기본값으로 둘 수 없다.

**GLG 지시 (2026-09-01): 텔레메트리는 끈다.** 실증 레인에 그렇게 지시가 갔다.
남는 것은 나머지 둘 — `is_internet_available()`의 google.com 조회와 런타임 pip 업그레이드다.
**끌 수 있는지, 끄면 무엇이 같이 죽는지가 우리가 검수할 항목**이다(§9). 거부권이 아니라
결정 입력이고, 지금 판정하지 않는다.

## 6.4 라이선스 — 등급이 바뀌지 않는다 (GLG 확인 요청, 2026-09-01)

**결론: 이 스택으로 갈아타도 우리가 지는 라이선스 의무는 달라지지 않는다.
우리는 이미 GPL-3.0을 싣고 있다.**

| 구성요소 | 라이선스 | 근거 |
|---|---|---|
| **domoticz** | **GPL-3.0** | [읽음] `License.txt` 머리말 + Buildroot `domoticz.mk`의 `DOMOTICZ_LICENSE = GPL-3.0` |
| **Z4D** (Zigbee for Domoticz) | **GPL-3.0** | [읽음] `LICENSE.txt` + 소스 헤더 `SPDX-License-Identifier: GPL-3.0` |
| **zigpy · bellows · zigpy-znp** | **GPL-3.0** | [측정] 이 기계 store 산출물의 `dist-info/METADATA` → `License: GPL-3.0` |
| **현재 우리가 싣는 Zigbee2MQTT** | **GPL-3.0** | [측정] `zigbee2mqtt-2.13.0/package.json` → `"license": "GPL-3.0"` |
| Node.js | MIT | 인계·통념, 이 리포에서 확인 안 함 |

> **핵심**: 맨 아래에서 두 번째 줄이 답이다. **현재 이미지가 이미 GPL-3.0 애플리케이션을 싣고
> 있다.** domoticz+Z4D는 같은 등급으로의 교체이지 새 의무의 도입이 아니다.

**임베디드에서 실제로 걸리는 조항은 GPL-3.0 §6 Installation Information(반-티보화)이다** —
"User Product"에 오브젝트 코드를 실어 보내면 **사용자가 수정본을 설치할 수 있게** 해야 한다.
이 리포의 불변식이 이미 그 방향이다 — *"Own the box: serial console, bootloader/recovery,
rootfs, service lifecycle, radio path must be inspectable."* **그리고 이 의무는 지금의 Z2M
경로에도 똑같이 붙어 있다.** 새로 생기는 게 아니다.

**소스 제공 의무의 기계도 이미 있다.** [측정] Buildroot에 `legal-info` 타깃이 있고
(`buildroot/Makefile:144`), `manifest.csv` · `licenses/` · `sources/`를 산출한다(`:226-231`).
**제품 이미지를 굽는 흐름에 `make legal-info`를 한 칸 넣는 것이 이 의무의 구현이다.**
아직 우리 `bsp/build.sh`는 이걸 부르지 않는다 — 등록해 둘 빚이다.

**아직 확인 안 한 것**: `z4d-certified-devices`(별도 pip 패키지, 기기 정의 DB)의 라이선스.
그리고 위 zigpy 계열 근거는 이 기계에 있던 **구버전 산출물**(zigpy 1.4.1 / bellows 0.49.1 /
zigpy-znp 1.0.0)의 메타데이터다 — 실제 사용 버전(2.1.0 / 1.0.0 / 1.1.0)에서 재확인이 남는다.
상류가 라이선스를 바꿨을 가능성은 낮지만 확인 안 한 것은 확인 안 한 것이다.

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

1. **최신 `cryptography`로 Z4D가 실제로 도는가** — 핀 자체는 §6에서 정리됐다(Z4D 코드가
   `cryptography`를 직접 쓰지 않고, Zigbee 스택은 핀을 전부 통과한다). 남은 건 런타임 사실
   하나뿐이고, **실증 레인이 최신으로 진행하기로 했으므로 그 답은 거기서 나온다.** 돌면 우리
   벽 2는 소멸, 안 돌면 우리 쪽 비용이 그쪽보다 크다(휠 vs 크로스빌드).
2. **domoticz `2026.3`을 Buildroot에서 굽는 레시피** — 서브모듈 5개(`libwebem`·`jwt-cpp`·
   `jsoncpp`·`minizip`·`sqlite-amalgamation`) 조달 방식 미결정. **GLG가 버전을 정했으므로
   이건 조사가 아니라 실작업이다.** §5·§6 벽 1.
3. ~~domoticz 바이너리 실측~~ → **닫힘: 17.4 MB** (x86_64, §6.1). 크로스빌드 값은 별개.
4. ~~RSS 분해~~ → **닫힘: 35 M(domoticz) + 86 M(Python) = 121 M** (§6.2, x86). 남은 것:
   (a) **Z2M+Node 대조군** — 실증 레인이 RAIL 1 뒤에 재고 먼저 제안하기로 했다 (b) 기기 수에
   따른 증가 곡선 (c) **riscv64/musl에서 다시 — 이건 우리 몫이다.**
5. **Z4D의 아웃바운드 셋을 끌 수 있는가** (§6.3) — `is_internet_available()`의 google.com 조회 ·
   Matomo 텔레메트리(기본 ON) · 런타임 pip 업그레이드. 설정으로 끄면 무엇이 같이 죽는지까지가
   질문이다. **오프라인 제품 허브의 가부가 여기 달렸다.**
6. **riscv64/musl 가부** — 제품 ISA 레인. domoticz·zigpy 양쪽 다 미측정.
7. **`ser2net`로 EZSP 원격 구동 시 지연·안정성** — A⁰의 유일한 미지수.
8. **SMHUB v1.0.0 실기** — 우리 기기는 아직 beta5 슬롯이다(`docs/SMHUB.md`). §2.2는
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
