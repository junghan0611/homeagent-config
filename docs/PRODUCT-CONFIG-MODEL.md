# SMHub 제품 설정 모델 — 선언적 세팅본 (config-as-code, 원샷 배포)

> 원칙 (GLG, 2026-07-01): **Web UI로 앱을 하나씩 켜는 인터랙티브 운영은 개인 NAS 모델이라 폐기.**
> 제품화는 **모든 설정을 리포 안에 선언**하고 **세팅본 하나를 한 번에 올려** 보드가 완성 상태로
> 부팅하는 것. 이 repo 코어(`flake.nix` 재현 가능 buildroot 이미지)와 같은 철학 = **완전 통제**.
>
> 라이브 0.9.8 보드 실측(2026-07-01)으로 "제품 전체 상태"가 어디에 저장되는지 매핑함. 좌표/크레덴셜은
> `PRIVATE.md`, 원본 아티팩트는 `captures/`(gitignored). 이 문서엔 secret 없음.

## 1. init/서비스 모델 — OpenRC (systemd 아님)
- `/sbin/init → openrc-init`. 서비스 = `/etc/init.d/*`, 활성 = `/etc/runlevels/<rl>/` 심링크.
- runlevel `default` (부팅 시 기동): **zigbee2mqtt · mosquitto · sshd · smhub-{ir,ambilight,buzzer,mqtt-bridge}-daemon · avahi · bluetoothd · networkmanager · ntpd · rauc-status …**
- runlevel `boot`: `smhub-services`(백엔드), network, watchdog, **`firstboot-production` / `firstboot-upgrade`** 등.
- 데몬 감시는 OpenRC `supervise-daemon`. (예: `supervise-daemon smhub-services … /opt/bin/smhub-services`)

## 2. 앱 매니저 = smhub-services (FastAPI, :8000)
- 패키지 `smhub_backend 0.2.12` (venv 평문 Python). 진입 `smhub_backend.cli:main`, 앱 `main.py`.
- 상태 DB: **`/opt/smhub-services/config/backend.db`** (SQLite, alembic 마이그레이션). = **제품 설정의 단일 진실원.**

### backend.db 스키마
| 테이블 | 역할 |
|---|---|
| `apps` | 앱 레지스트리 — `key,name,enabled,start_at_boot,version,watchdog` ← **Web UI 토글의 실체** |
| `appsettings` | 앱별 `key/value` 설정 (FK app_id) |
| `pages` / `devicesettings` | 기기 UI 페이지 + 페이지별 설정 |
| `user` | admin (`email`, `hashed_password`, superuser) |
| `usersettings` | 테마/단위/언어/로케일/타임존/12h |
| `alembic_version` | 스키마 버전 |

### 앱 enable 메커니즘 (확인)
- 앱 시작은 **`rc-update`가 아니라** backend가 DB `enabled`/`start_at_boot`를 읽어 supervise-daemon으로 관리.
  (백엔드 소스에 `rc-update` 호출 없음; `start_at_boot`가 제어축.)
- 즉 **DB 행을 세팅하면 앱 상태가 결정된다** → 선언적 seed로 완전 대체 가능.

### 공장 0.9.8 앱 레지스트리 (baseline)
| key | version | enabled | start_at_boot |
|---|---|---|---|
| zigbee2mqtt | 2.3.0-1 | **1** | 0 |
| matterbridge | 3.0.2-1 | 0 | 0 |
| matterbridge-z2m | 2.4.7-2 | 0 | 0 |
| nodered | 4.0.9-1 | 0 | 0 |
| zwavejsui | 10.4.0-1 | 0 | 0 |
| openthread | 0.3.0-1 | 0 | 0 |
| nodejs | 22.13.1-1 | 0 | 0 |
| smhub-web | 0.3.1-1 | 0 | 0 (watchdog=1) |
| smhub-services | 0.1.12-1 | 0 | 0 |

→ 공장 상태 = **zigbee2mqtt만 켜짐**, 나머지 옵션 앱은 꺼짐. (버전은 beta5 카탈로그와 다름: z2m 2.3.0 vs 2.10.1 등.)

## 3. 앱/주변장치 설정 파일 (선언 대상)
- Zigbee: `/opt/zigbee2mqtt/data/` (= p7 USER `/mnt/user/opt/…`) — `configuration.yaml`, `coordinator_backup.json`(네트워크키=secret), `database.db`, `state.json`.
- 주변장치: `/etc/peripherals/*.conf` — `smhub-ir.conf` · `smhub-ambilight.conf` · `smhub-buzzer.conf` · `smhub-mqtt-bridge.conf`.
- 기타: `/etc/mosquitto`, `/etc/nginx`, `/etc/stunnel`. (Matter/OTBR/zwave는 설치 시 각 data 디렉토리 생성.)

## 4. 제품화 seam — firstboot
- `/etc/init.d/firstboot-production` (once-ever, 플래그 `/mnt/misc/.production-init` on p4 MISC):
  machine-id(EEPROM UUID) · wifi MAC · zigbee adapter · `rwnx_settings.ini` = **per-unit HW 프로비저닝.**
- `firstboot-upgrade` = 업그레이드 후 1회. → **우리 선언적 프로비저너를 붙일 수 있는 벤더 표준 seam.**

## 5. 지속(persistence) 파티션 맵
- `/` = p5 ROOTFS0 **RO** (A/B RAUC). `/etc` = loop overlay(rw, 상단 극소).
- **p7 USER (5.8G)** = `/mnt/user` → bind `/home /opt /var`. **모든 앱/데이터/backend.db가 여기.** ← 세팅본의 주 타깃.
- p4 MISC = firstboot 플래그 + rauc data.

## 6. 라디오/프로토콜 사실 (2026-07-01 라이브 확정) — 세트의 뼈대
제품 세트가 "무엇을 엮느냐"의 중심은 단일 MG24 라디오를 어떻게 쓰느냐다.

- **MG24 = EmberZNet Zigbee coordinator** (라이브 확정): z2m 로그 `zh:ember [NCP/ASH COUNTERS]`,
  `configuration.yaml adapter: ember`, coordinator backup `ezspVersion: 13`. → **adapter 는 `ember`**.
  (backend.db.appsettings 의 `zstack` 은 EEPROM 실패 시 폴백 default 일 뿐 — 마이그레이션
  `ac49055b2b34` 가 모델에 `mg` 포함이면 ember 로 도출. 실동작=ember.)
- **Zigbee / Thread = 라디오 계층, 배타적**. 단일 MG24 는 Zigbee coordinator **또는** Thread RCP 중 하나.
  동시 운용은 Silabs multiprotocol 별도 근거가 있어야 하며 지금은 가정하지 않는다.
- **Matter = 앱 계층(라디오 아님)**. `matterbridge` + `matterbridge-z2m` = Zigbee 기기를 Matter endpoint 로
  **IP 위에서 브리지**. 라디오를 Matter/Thread 로 바꾸는 게 아니다.
- **디바이스 프로파일을 가장 많이 품는 길** = MG24 를 Zigbee coordinator 로 두고 matterbridge 로 Matter 노출:
  `MG24(ember) → Zigbee2MQTT → matterbridge-z2m → Matter bridge over IP → HA/Apple/Google`.
- **Z-Wave = 이 보드 native 미지원**: lsusb 는 root hub 만, cp210x/ftdi 없음, dmesg 무. `zwavejsui` 는
  벤더 공통 카탈로그 항목(외장 USB Z-Wave 동글용)일 뿐 — "지원"으로 해석 금지, 세트에 넣지 않는다.
- **Thread/OTBR 는 지금 보류**: MG24 를 Thread RCP 로 재플래시해야 하며 Zigbee coordinator 를 잃는다.
  Matter-only 를 고민할 때 별도로 다룬다. 어설픈 선반영 금지.

## 7. 버전 드리프트 원칙 (설계 기준)
- OS 버전업(0.9.8 → beta5 → 0.9.9 …) 하면 **앱 버전·appsettings 기본값·alembic HEAD·패키지 목록이 또 바뀐다.**
  → **버전을 못박은 config/코드를 미리 만들면 매번 깨진다.** 그래서 지금은 프레임워크를 짓지 않는다.
- **버전에 안 흔들리는 것 = 구조**: backend.db 가 상태 저장소라는 것, OpenRC runlevel, p7 USER 지속,
  firstboot seam, MG24=ember Zigbee, Matter=matterbridge 브리지. **세트는 이 구조 위에 엮는다.**
- 버전 종속값(§2 표, §3 z2m 키)은 특정 스냅샷의 관측이며 SSOT 아님 — 배포 시점에 실물에서 다시 읽는다.

## 8. 제품화 세트 — 열린 설계 질문 (미결, 고민 단계)
아직 코드/번들을 만들지 않는다. 먼저 아래를 정한다.

- **재현 기판**: (A) 벤더 beta5 이미지를 오프라인 커스터마이즈(p7/rootfs 주입 후 repack) vs
  (B) 우리 buildroot 이미지(flake.nix, repo 코어, bring-up 중)에 처음부터 포함.
- **상태 원본**: (a) 손으로 선언 vs (b) 보드를 원하는 상태로 한 번 만든 뒤 **golden 스냅샷**
  (backend.db + /etc overlay + p7 앱-data + 패키지 집합)을 떠서 이미지 seed 로. 후자가 adapter=zstack 류
  손선언 실수를 막는다.
- **backend.db 취급**: 벤더가 alembic 로 만든 DB 를 보존하고 enabled/start_at_boot/usersettings 만 손대는 게 안전.
  이미지에 굽는다면 alembic HEAD 일치 필요.
- **per-unit secret**(zigbee network key, machine-id): 이미지에 굽지 않는다. 벤더 firstboot 가 이미 unit 별로
  처리 → 우리는 정적 제품 config 만 엮는다.
- **검수(verify)**: 배포 후 "running ≠ working" 을 pass/fail 로 확인. 지금은 매트릭스를 미리 고정하지 말고,
  라이브 근거가 쌓일 때 최소본으로 작성.
