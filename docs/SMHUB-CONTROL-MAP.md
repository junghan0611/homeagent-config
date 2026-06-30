# SMHub Nano (SG2000) 통제 경계 + 재현 세트 매트릭스

**목적**: 벤더(SMLIGHT)가 SMHUB OS의 부트로더/커널/rootfs 소스를 공개하지 않으므로,
"우리가 어디까지 통제·재현 가능한가"를 컴포넌트별로 못박는다. 각 행은 **재현 세트
(upstream repo + commit/version + 벤더 diff)** 기준으로 평가한다. **없으면 "없음"이라
확실히 적어** 다음 세션이 그 공백 때문에 헤매지 않게 한다.

- **분석 대상**: SMHUB OS `1.0.0.beta5` (OTA stable). 출고기는 `0.9.8`(live, 별도 캡처).
- **방법**: beta5 fastboot zip → `simg2img` → 파티션 분리 → ext4 `debugfs` + F2FS `mount -ro`
  정적 추출. 실기 mutate 없음(0.9.8 보존). 소스 없이 **바이너리 이미지에서 ground truth**.
- **원본 아티팩트(로컬, git-ignored)**: `captures/smhub-beta5-20260630/`
  (이미지/zip은 벤더 config·feed 크레덴셜 포함 → **절대 stage 금지**). 파생 텍스트는
  같은 디렉토리 `extracted/` · `meta/` · `artifacts/`.
- **재현 가능성 등급**:
  - ✅ **완전** — 공개 repo + 정확 버전 확인, 우리가 직접 빌드/교체 가능.
  - ⚠️ **부분** — upstream은 공개지만 벤더 defconfig/패치/DT diff가 비공개. 베이스는
    재현되나 벤더와 bit-identical은 아님.
  - ❌ **불가** — 바이너리만. 소스·repo 없음. 역설계 또는 SMLIGHT 협조 필요.

---

## 0. 하드웨어 플랫폼 — SG2000 (Milk-V Duo S 호환 + MG24)

SMHub Nano 보드는 **Milk-V Duo S급 SG2000 베이스 + EFR32MG24 무선칩 추가**로 보면 된다.
SoC가 동일(Sophgo SG2000)하고, 보드 레벨 Wi-Fi/BT도 기본 OS에서 살아있다(0.9.8 실측
`aic8800_*` 드라이버 계열). **Zigbee/Thread/Matter 무선은 온보드 MG24가 담당**한다.
핵심 부품(SG2000 + MG24 + 보드 레벨 Wi-Fi/BT)은 공개·구매 가능한 조합이므로,
전원/RF/인증/보드 설계는 별도 과제지만 **같은 계열의 오픈 hub BOM을 구성할 수 있다**.

- **SoC**: Sophgo **SG2000** (CV181x 계열). big core **C906B**(RISC-V app, Linux) +
  small core **C906L**(RISC-V RTOS 코프로세서). 512MB RAM. 0.5TOPS TPU(INT8, hub에선 미사용).
  RISC-V↔ARM 부팅 스위치 지원(제품 SMHUB OS는 RISC-V 고정).
- **datasheet/TRM 공개**: `github.com/milkv-duo/duo-files/tree/main/duo-s/datasheet` (SG2000 공개).
- **BSP 계보**: `milkv-duo/duo-buildroot-sdk-v2` (SG2000=cv181x 보드 정의 `sg2000_milkv_duos_*`,
  freertos/C906L 트리 포함). SMHub은 같은 SG2000 위에 자체 보드 정의 `smlight,nano`를 올림
  (Duo S 보드 파생이 아니라 같은 SoC + 같은 BSP 라인).

### Milk-V Duo S(개발보드) ↔ SMHub Nano(제품) 호환 경계

| 레이어 | Duo S | SMHub Nano | 호환 |
|---|---|---|---|
| SoC | SG2000 (C906B+C906L) | SG2000 (C906B+C906L) | ✅ 동일 |
| ISA / 타깃 | riscv64 (ARM 스위치) | riscv64 고정 | ✅ 동일 |
| RAM | 512MB | 512MB(~490 실측) | ✅ 동일 |
| C906L 코프로세서 | 있음(freertos SDK 공통) | 있음(RPMsg/remoteproc) | ✅ 동일 |
| Wi-Fi / BT | 보드 내장 Wi-Fi6/BT5(Duo S 문서) | 보드 내장 Wi-Fi/BT, AIC8800 계열 실측 | ⚠️ 보드 레벨 동형 |
| Zigbee/Thread/Matter | **없음** | **온보드 EFR32MG24** | ❌ MG24가 추가분 |
| OS 이미지 | milkv SDK(linux 5.10) | SMHUB OS(mainline 6.18, RAUC) | ❌ 비호환 |
| 저장/부팅 | SD + eMMC | eMMC + RAUC A/B | ⚠️ 부분 |

**개발 전략 (제품 검수와 병렬 가능)**: Duo S를 쓰면 **C906L mailbox(§3, RPMsg/remoteproc) +
Zig `homeagentd`(NEXT §3, riscv64) + 듀얼코어 런타임**을 별도로 개발/검증할 수 있다(SoC·BSP
동일). **MG24가 필요한 Zigbee/Thread/Matter 무선만** SMHub 실기 또는 USB Zigbee 동글로 대체.
즉 런타임 stratification L2/L3는 Duo S, L0 라디오는 SMHub로 분담.

---

## 1. 베이스 OS (부트체인 / 커널 / rootfs) — 전부 ⚠️ 부분

| 컴포넌트 | 버전 (실측) | upstream repo | 로컬 클론 commit | 벤더 diff | 재현 |
|---|---|---|---|---|---|
| FIP / OpenSBI | OpenSBI, fip build `2026-03-04` | `github.com/sophgo/bootloader-riscv` · `github.com/milkv-duo/duo-buildroot-sdk-v2` | `bootloader-riscv` ad9750c0(SG2042용) · `duo-buildroot-sdk-v2` ad920f839 | ❌ 벤더 빌드 config 비공개 | ⚠️ |
| 커널 | Linux `6.18.17` riscv64 (build 2025-12-11) | mainline + sophgo/cvitek 패치 | — | ❌ 벤더 `.config` + DT diff 비공개 | ⚠️ |
| rootfs | Buildroot `2026.02-18-g60430d6802` | `git.buildroot.net/buildroot` | — | ❌ 벤더 BR2_external/defconfig/overlay 비공개 | ⚠️ |
| 파티션/RAUC | A/B (p1-7), RAUC | `github.com/rauc/rauc` | — | ⚠️ 벤더 `system.conf` 미확보(라이브 필요) | ⚠️ |

- **커널 DT compatible (재현 타깃)**: `sophgo,sg2000` + `sophgo,cv1800b-mailbox` /
  `cv1800b-*`(pwm/dma/usb-phy/dwmac/dwcmshc) → mainline **CV1800B/SG2000** 계열.
  `sophgo,cv1812cp-c906l` 노드 = C906L 코프로세서가 DT에 선언됨.
- **파티션 레이아웃** (fastboot 이미지 기준, `meta/partition-table.txt`):
  p1/p2 KERNEL0/1 (FAT12, `boot.itb`) · p3 ENV · p4 MISC · p5 ROOTFS0 (ext4, populated) ·
  **p6 ROOTFS1 (이 이미지에선 비어있음/data)** · p7 USER (F2FS 512MiB).
- ⚠️ **fastboot 이미지 ≠ 라이브 eMMC**: raw 2.02GiB(fastboot 최소)이지 라이브 7.6GB 덤프가
  아니다. USER 512MiB는 첫 부팅에 resize 추정. p6는 OTA/RAUC 라이브에서만 채워짐.

**재현 공백 #1**: 베이스 OS를 bit-identical로 재현하려면 벤더 **Buildroot defconfig +
BR2_external + 커널 .config/DT diff**가 필요 — 전부 비공개. → SMLIGHT 연락 후보(§4).

---

## 2. 앱 레이어 (프로토콜 스택) — z2m은 ✅, 설치형 앱은 ⚠️ 후보

| 컴포넌트 | 버전 | upstream repo | 벤더 diff | 재현 |
|---|---|---|---|---|
| Node.js | `22.22.0-2` | `github.com/nodejs/node` (v22.22.0) | none | ✅ |
| Python | `3.14` | cpython | none | ✅ |
| **zigbee2mqtt** | `2.10.1` | `github.com/Koenkk/zigbee2mqtt` (v2.10.1) | none — `pnpm-lock.yaml` 확보 | ✅ |
| zigbee-herdsman | `10.0.7` | `github.com/Koenkk/zigbee-herdsman` | none | ✅ |
| zigbee-herdsman-converters | `26.46.0` | `github.com/Koenkk/zigbee-herdsman-converters` | none | ✅ |
| z2m frontend / windfront | `0.9.21` / `2.11.2` | `github.com/Koenkk/zigbee2mqtt-frontend`, windfront | none | ✅ |
| matterbridge | `3.5.5` (카탈로그) | `github.com/Luligu/matterbridge` (v3.5.5) | **미설치**, lock/의존 미확보 | ⚠️ 설치 후 확인 |
| matterbridge-z2m/-hass/-shelly | `3.0.6` / `1.0.5` / `2.2.30` | Luligu 플러그인 repos | **미설치**, lock/의존 미확보 | ⚠️ 설치 후 확인 |
| **matter.js** | ❌ **버전 미확보** | `github.com/project-chip/matter.js` | — | ❌ |
| openthread / OTBR | `0.3.1-5` (벤더 ipk) | `github.com/openthread/openthread` · `ot-br-posix` | ⚠️ ipk=벤더 패키징, 내부 commit 미상 | ⚠️ |
| zwavejsui | `11.19.0` (카탈로그) | `github.com/zwave-js/zwave-js-ui` (v11.19.0) | **미설치**, 런타임 모듈 유무 별도 | ⚠️ 설치 후 확인 |

- **설치됨 vs 카탈로그**: beta5 공장 시드에 **실제 설치**된 것은 nodejs/python3/
  zigbee2mqtt/esphome-bin/smhub-broker/smhub-services/smhub-ui 뿐. matterbridge·OTBR·
  zwavejsui는 **opkg 카탈로그(피드)에만** 있고 미설치 — running ≠ installed ≠ catalog.
- **재현 lock 확보**: z2m는 `artifacts/opt/zigbee2mqtt/{package.json,pnpm-lock.yaml}` →
  의존 트리 정확 재현 가능.

**재현 공백 #2 (matter.js)**: matterbridge가 미설치라 `@matter/*` 의존 정확 버전이
이미지에 없다. matterbridge 3.5.5의 package.json(npm) 또는 beta5 실기 설치 후
`node_modules/@matter/*/package.json`에서만 확정 가능. **현재 "없음"** — npm/라이브 필요.

---

## 3. C906L RTOS + 코어간 통신 — 벤더 커스텀, 일부 ❌

C906L(small core) RTOS와 Linux(C906B) 사이 통신은 **표준 RPMsg / remoteproc** 축이다
(비밀 mailbox 아님). 이게 통제 가능성의 핵심 — 표준 인터페이스라 우리가 끼어들 수 있다.

| 컴포넌트 | 버전 | 형태 | repo / 소스 | 재현 |
|---|---|---|---|---|
| esphome (코어) | `2026.5.3` | — | `github.com/esphome/esphome` (2026.5.3) | ✅ |
| **벤더 ESPHome 컴포넌트** | — | ELF 내 심볼 | ❌ **없음** | ❌ |
| `esphome-bin.smhub.elf` / `.nano.elf` | 2026.5.3-2 | RISC-V static ELF, **not stripped** | (위 esphome + 벤더 컴포넌트 빌드) | ⚠️ ELF 확보, 소스 부분 비공개 |
| **smhub-broker** | `1.0.3-1` | RISC-V PIE, **not stripped** | ❌ **없음** (벤더 빌드 마커만 있음) | ❌ 바이너리만 |
| rtos-logger / rtos-notify | (broker 동반) | RISC-V PIE, not stripped | ❌ **없음** | ❌ 바이너리만 |
| smhub-services (백엔드) | `1.0.4-1` | **Python venv 평문 소스** | ❌ repo 없음, 단 `.py` 읽힘 | ⚠️ 소스 가독 |
| smhub-ui | `1.0.3-1` | (웹 자산) | ❌ 없음 | ❌ |
| C906L RTOS 펌웨어 | — | `/opt/firmware/smhub-rtos.elf` | esphome 기반 추정 | ⚠️ ELF 슬롯 교체 가능 |

- **벤더 ESPHome 커스텀 컴포넌트** (ELF 심볼에서 확인): `sg2000_pwm` `sg2000_set`
  `sg2000_sg` `sg2000_ws` · `smhub_buzzer` `smhub_hal` `smhub_ipc` `smhub_pwm`
  `smhub_time`. 특히 **`smhub_ipc`** = RTOS 측 inter-processor comm. 소스 비공개.
- **통신 메커니즘** (`smhub-broker` strings):
  - transport: `/dev/rpmsg0` `/dev/rpmsg1` `/dev/rpmsg_ctrl`, `smhub::hal::RpmsgTransport`,
    채널 `smhub-rpc` / `esphome-rpc`
  - C906L 라이프사이클: `echo {start,stop} > /sys/class/remoteproc/remoteproc0/state`
  - 펌웨어 슬롯: `/opt/firmware/smhub-rtos.elf`(+`.new`, OTA 후 remoteproc reboot)
  - 소켓: `/var/run/smhub-broker.sock`, `/var/run/smhub-openamp.sock`
  - BLE: `Native NimBLE Bluetooth Backend` / `DBus Bluetooth Backend`
- **백엔드 소스 가독**: `smhub-services`는 컴파일 바이너리가 아니라 Python venv →
  `smhub_backend/rtos.py`, alembic `preseed_rtos_default_settings.py` 등 평문. RTOS 제어
  로직 일부를 소스로 읽을 수 있다(완전 비공개 아님).

**통제 결론**: 벤더 소스가 없어도 통제 가능한 이유 — ① 통신이 **표준 RPMsg/remoteproc** →
우리 `homeagentd`가 `/dev/rpmsg*`로 직접 대화하거나 smhub-broker 대체 가능 ② RTOS는
`/opt/firmware/smhub-rtos.elf` 슬롯 + remoteproc state → **우리 Zig RTOS로 교체 가능**
③ 핵심 바이너리가 not-stripped + 백엔드 Python 평문 → 프로토콜 역설계 비용 낮음.

### ESPHome on C906L — 이 제품의 숨은 핵심 능력

**ESPHome이란**: 원래 ESP8266/ESP32 MCU용 펌웨어 프레임워크(이름의 ESP가 거기서 유래).
**YAML 선언만으로 펌웨어를 자동 생성**하고 **Home Assistant와 native API로 직통** 통합한다.
센서·조명·스위치·climate·display·IR/RF·BLE·voice 등 **수백 개 컴포넌트**, 클라우드 없는
local control, 무선 OTA가 특징. 지금은 ESP를 넘어 RP2040/LibreTiny/nRF52/host로 확장됨.
공식 프로젝트 `github.com/esphome/esphome` (CalVer; 우리 제품은 **2026.5.3**). 라이선스 =
**GPLv3**(C++ 런타임) + MIT(Python). **공식엔 SG2000/C906 플랫폼이 없다 → SMLIGHT 자체 포트**.

**SMHub에서 (beta3, 2026-06-14~)**: 숨겨진 C906L RTOS 코프로세서에 **native ESPHome**을
올려, Linux(C906B)와 완전 분리된 **ultra-low-latency 실시간 제어 + offline 자동화**를 한다.
ELF 심볼 + release notes로 확인된 능력:

- **HA native API** (ELF에서 가장 빈번) → **허브 자체가 ESPHome 노드**로 Home Assistant에
  직접 노출. ESP 기기를 따로 안 붙여도 허브가 ESPHome 디바이스.
- **Native Bluetooth Proxy** (`bluetooth_proxy`) → HA BLE proxy, **최대 16 동시 연결**.
  활성 시 host `bluetoothd`를 자동 비활성화하고 raw HCI 직결(코릭션 제로).
- **실시간 주변장치 제어**: GPIO/PWM(`sg2000_pwm`), **WS2812 RGB(`sg2000_ws`, ambilight)**,
  buzzer(`smhub_buzzer`), IR, I2C RTC(`ds1307`, offline 시계). DIY expansion 헤더 노출.
- **코어간 IPC**: `smhub_ipc_*`(gpio_edge_cb / request_mac / request_restart / send_rpc /
  time_cb) = Linux↔C906L RPMsg RPC 명령 집합.

**의미**: SMHub 1대가 **Zigbee/Thread/Matter 코디네이터 + ESPHome 실시간 노드 + BLE proxy**를
동시에 한다 — 보통 ESP32 기기를 따로 두는 일을 허브 내부 전용 코어가 처리. **그리고 이
ESPHome RTOS 슬롯(`/opt/firmware/smhub-rtos.elf`)이 우리 Zig RTOS 교체의 L2 ground truth다.**

**SMLIGHT의 ESPHome 패턴 (ESP32 → C906L 이식 추정)**: 회사 공개 repo
[`slzb-esphome`](https://github.com/smlight-tech/slzb-esphome)(ESP32-S3, GPL-3.0; 로컬
`~/repos/3rd/milkv/slzb-esphome`)의 패키지 구성 — `buzzer`·`ws2812`·`ir`·`bluetooth`·
`leds`·`ioexp`·`diagnostics` — 가 SMHub C906L ELF에서 본 능력과 **동종**이다. 즉 SG2000
포트는 ESP32에서 검증된 ESPHome 컴포넌트를 C906L(RISC-V)로 옮긴 것으로 보이며, 소스를
받으면 이 구조 기반일 것이다. **단 SG2000/C906L 포트 자체는 미공개**(§4 #5 전수 조사).

---

## 4. 정보 벽 = 재현 공백 (없는 것 확실히) + SMLIGHT 연락 후보

다음은 이미지에서 **얻을 수 없는** 것들이다. 역설계로 우회 가능하나, SMLIGHT에 직접
요청하는 게 양쪽에 득(오픈소스 hub 개발 검증 = 벤더에도 가치). 연락 시 이 목록을 그대로.

1. **opkg 피드 소스** — `pkg.smlight.tech/v1`. ipk 바이너리만 받음. 빌드 소스 ❌.
   (피드 URL에 http-auth 크레덴셜 포함 → `extracted/smlight.conf.redacted`만 안전.)
2. **벤더 Buildroot defconfig + BR2_external + overlay** — 베이스 OS 재현의 최대 공백.
3. **커널 `.config` + 벤더 DT diff** (mainline 6.18 대비).
4. **smhub-broker / rtos-logger / rtos-notify 소스** — C++ RISC-V 바이너리만 확보.
5. **벤더 ESPHome SG2000/SMHub 컴포넌트 소스** (`sg2000_*`, `smhub_*`). **단 GPLv3 근거 있음**:
   `esphome-bin.elf`는 ESPHome GPLv3 C++ 코어와 static-link → 파생저작물이면 SMLIGHT은 소스
   제공 의무. **선례**: SMLIGHT이 ESP32용 [`slzb-esphome`](https://github.com/smlight-tech/slzb-esphome)을
   이미 GPL-3.0으로 공개 → SG2000/C906L 포트도 요청 시 공개 가능성 높음. (`smhub-broker`는
   ESPHome 아님 → GPL 무관, 별도 비공개.)
   **전수 조사 (2026-06-30, 미공개 확정)**: ① smlight-tech org 11 repo — ESP32용
   `slzb-esphome`·`slwf-01pro-esphome`만 GPL 공개, SG2000 ESPHome 없음 ② ESPHome upstream
   공식 플랫폼 목록(ESP/RP2040/LibreTiny/nRF52)에 SG2000/C906 없음 ③ milkv/sophgo는 ESPHome
   안 함(buildroot SDK / NuttX 라인) ④ github 코드검색 `smhub_ipc`/`smhub-rtos`/`esphome
   sg2000` 0건. → **SG2000/C906L ESPHome 포트 소스는 공개분 없음.** GPL 근거로 SMLIGHT 직접
   요청이 유일 경로. (다시 뒤지지 말 것 — 위 4축 전부 확인 완료.)
6. **MG24 코디네이터 펌웨어 `.gbl` + EmberZNet/Gecko SDK 정확 버전** — 이미지에 .gbl 없음.
   flash 툴은 공개(`universal-silabs-flasher` + `bellows`/EZSP). 버전은 라이브
   `ezsp version`으로만 확인 가능.
7. **matter.js(`@matter/*`) 정확 버전** — matterbridge 미설치 → npm 또는 라이브 필요.

---

## 5. 다음 재현/검증 단계 (라이브 beta5)

mutate 전 0.9.8 RAUC/`dd` 백업(NEXT §0) 완료 후, OTA로 beta5 부팅하여 라이브 확보:

1. **C906L 라이브**: `/sys/class/remoteproc/remoteproc0/{name,state,firmware}` ·
   `/dev/rpmsg*` · `/sys/class/rpmsg/*` · `dmesg | grep -iE 'remoteproc|rpmsg|c906|rtos|esphome|broker'`
   · `/etc/init.d/{remoteproc,smhub-broker}` · `/var/log/*broker*`.
2. **베이스 재현용**: 커널 `.config`(`/proc/config.gz`) · DTB/FIT 분해 · `opkg list-installed`
   전체 · 모든 앱 `package.json` · Buildroot 패키지 목록.
3. **MG24**: `ezsp version`(EmberZNet/Gecko 버전) · 코디네이터 `.gbl` 경로.
4. **matter.js**: matterbridge 설치 후 `node_modules/@matter/*/package.json`.

라이브에서 위를 받으면 이 매트릭스의 ⚠️/❌ 다수가 확정되거나 SMLIGHT 요청 항목으로
정리된다.
