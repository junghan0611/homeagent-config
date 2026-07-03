# SMHUB Nano Mg24 — 제품 검수 · 통제 경계 · 설정 모델 (단일 SSOT)

이 문서는 SMHub Nano Mg24 제품 검수 레인의 **단일 SSOT**다. 이전에 나뉘어 있던
`PRODUCT-CONFIG-MODEL` · `SMHUB-CONTROL-MAP` · `SMHUB-MANUAL-REVIEW` 를 하나로 합쳤다.

- **분석 대상**: 출고 **0.9.8** (무변형 SSH 실측, §4) + **1.0.0.beta5** (fastboot 정적 추출 §5 + **OTA 후 라이브 실측 §5.4**). **현재 기기 = beta5 부팅(슬롯 B)**.
- **좌표/크레덴셜**은 `PRIVATE.md`, 원본 아티팩트는 `captures/`(gitignored). **이 문서엔 secret 없음.**
- **재현 등급**: ✅ 완전(공개 repo+정확 버전, 직접 빌드/교체 가능) / ⚠️ 부분(upstream 공개, 벤더
  defconfig·patch·DT diff 비공개 → bit-identical 아님) / ❌ 불가(바이너리만, 역설계 또는 SMLIGHT 협조).
- **원칙**: "running ≠ installed ≠ enabled ≠ working". 서비스가 떠 있다고 동작으로 판정하지 않는다.

---

## 1. 하드웨어 플랫폼 — SG2000 + MG24

SMHub Nano = **Milk-V Duo S급 SG2000 베이스 + EFR32MG24 무선칩 추가**. SoC 동일(Sophgo SG2000),
보드 레벨 Wi-Fi/BT도 기본 OS에서 살아있음(`aic8800_*` 계열). **Zigbee/Thread 라디오**는 온보드 MG24가 담당하고, Matter는 그 위 **앱 계층**(matterbridge over IP, §2)이지 라디오가 아니다.

- **SoC**: Sophgo **SG2000** (CV181x 계열). big core **C906B**(RISC-V app/Linux, ARM 스위치 가능) +
  small core **C906L**(RISC-V RTOS 코프로세서). 512MB RAM. 0.5TOPS TPU(hub 미사용). 제품은 **RISC-V 고정**.
- **DT compatible (0.9.8 라이브 확정)**: `smlight,nano  smlight,sg2000  sophgo,sg2000`.
  → 벤더 자체 보드 정의 **`smlight,nano`** 확정(Duo S 파생 아님, 같은 SoC + 같은 BSP 라인 위 자체 보드).
- **datasheet/TRM 공개**: `github.com/milkv-duo/duo-files` → `duo-s/datasheet` (SG2000 공개).
- **BSP 계보**: `milkv-duo/duo-buildroot-sdk-v2` (SG2000=cv181x 보드 정의 `sg2000_milkv_duos_*`,
  freertos/C906L 트리 포함).

### Milk-V Duo S(개발보드) ↔ SMHub Nano(제품) 호환 경계

| 레이어 | Duo S | SMHub Nano | 호환 |
|---|---|---|---|
| SoC | SG2000 (C906B+C906L) | SG2000 (C906B+C906L) | ✅ 동일 |
| ISA / 타깃 | riscv64 (ARM 스위치) | riscv64 고정 | ✅ 동일 |
| RAM | 512MB | 512MB(~490 실측) | ✅ 동일 |
| C906L 코프로세서 | 있음(freertos SDK 공통) | 있음 — **단 beta 라인 OS부터**(0.9.8엔 미노출, §4) | ⚠️ 조건부 |
| Wi-Fi / BT | 보드 내장 Wi-Fi6/BT5 | 보드 내장, AIC8800 계열 실측 | ⚠️ 보드 레벨 동형 |
| Zigbee/Thread/Matter | **없음** | **온보드 EFR32MG24** | ❌ MG24가 추가분 |
| OS 이미지 | milkv SDK(linux 5.10) | SMHUB OS(mainline 6.18, RAUC) | ❌ 비호환 |
| 저장/부팅 | SD + eMMC | eMMC + RAUC A/B | ⚠️ 부분 |

**개발 전략(제품 검수와 병렬)**: C906L mailbox + Zig `homeagentd`(riscv64) + 듀얼코어 런타임은
Duo S에서 선행 개발(SoC·BSP 동일). MG24 Zigbee/Thread만 SMHub 실기 또는 USB 동글. L2/L3=Duo S, L0 라디오=SMHub.

---

## 2. 라디오/프로토콜 — 세트의 뼈대 (0.9.8 라이브 확정)

제품 세트가 "무엇을 엮느냐"의 중심은 단일 MG24 라디오를 어떻게 쓰느냐다.

- **MG24 = EmberZNet Zigbee coordinator**(라이브 grounded, z2m `bridge/info`): coordinator.type=`EmberZNet`,
  **펌웨어 revision `7.4.2 [GA]`**(major7/minor4/patch2, ezsp13, build0), `adapter: ember`, port `/dev/ttyS1`,
  baudrate 115200, ch11, pan_id 59232, permit_join=False, bridge state=**online**. IEEE `0x403802fffed4b896`
  = coordinator_backup `96b8d4feff023840`(바이트 역순, 동일). **paired end-device 0**(z2m `database.db` 1행=type
  Coordinator = 자기 자신). → adapter는 `ember`. 증거: `captures/…/logs/phaseA-recapture-0.9.8.txt`.
  (backend.db appsettings 의 `zstack` 은 EEPROM 실패 시 폴백 default 일 뿐 — 실동작=ember.)
- **Zigbee / Thread = 라디오 계층, 배타적**. 단일 MG24 는 Zigbee coordinator **또는** Thread RCP 중 하나.
  동시 운용은 Silabs multiprotocol 별도 근거 필요, 현재 미가정.
- **Matter = 앱 계층(라디오 아님)**. `matterbridge` + `matterbridge-z2m` = Zigbee 기기를 Matter endpoint 로
  **IP 위에서 브리지**. 가장 많은 디바이스 프로파일을 품는 길:
  `MG24(ember) → Zigbee2MQTT → matterbridge-z2m → Matter bridge over IP → HA/Apple/Google`.
- **Z-Wave = 이 보드 native 미지원**: (증거 provenance = **2026-06-30 prior 실측**: lsusb=root hub 만, cp210x/ftdi
  없음, dmesg 무 — 현재 verify 로그 번들엔 미포함, 재캡처 대상) + 벤더 §6.3 EFR32ZG23 는 제네릭 상위모델용. `zwavejsui`
  는 벤더 공통 카탈로그(외장 USB 동글용)일 뿐 — "지원"으로 해석 금지, 세트에 넣지 않는다.
- **Thread/OTBR 보류**: MG24 를 Thread RCP 로 재플래시하면 Zigbee coordinator 상실. Matter-only 고민 시 별도 취급.

### 2.1 EmberZNet / EZSP 버전 좌표계 — host↔NCP 호환 계약 (2026-07-03 라이브 재확인)

MG24 코디네이터를 **어떤 host 스택으로 구동하느냐**의 핵심은 EmberZNet 빌드 일치가 아니라 **EZSP protocol 버전 일치**다.

| 층 | 버전 | EZSP | 근거 |
|---|---|---|---|
| **NCP 펌웨어**(온보드 MG24 라디오) | EmberZNet **7.4.2 GA** | **13** | z2m `coordinator_backup.json → "ezspVersion": 13`, `bridge/info`(§2) |
| **현재 구동 host** = z2m | zigbee-herdsman **10.0.7**, z2m **2.10.1** | 13 | 라이브 `coordinator_backup.json source` + `package.json` |
| **오픈소스 참조 SDK**(Silabs Gecko SDK) | GSDK **4.5.0** = EmberZNet **7.5.1.0** | **13** (`EZSP_PROTOCOL_VERSION 0x0D`) | 공개 Gecko SDK 소스 트리: `EMBER_MAJOR/MINOR/PATCH = 7/5/1` |

- **호환 계약 = EZSP v13.** NCP(7.4.2)와 임의 host 스택(예: GSDK 4.5.0 = 7.5.1)의 EmberZNet 빌드가 달라도 **EZSP 13이 와이어를 묶는다** → 상호운용. z2m(herdsman 10.0.7)이 지금 이 MG24를 EZSP 13으로 구동 중인 게 살아있는 증거.
- **전송 계약(라이브 재확인 2026-07-03)**: `adapter: ember`, port `/dev/ttyS1`, `baudrate: 115200`. `/dev/ttyS1`은 부팅 시 z2m(node) 프로세스가 상시 점유(root:dialout) → **동시 접근 불가**. 대안 host 스택은 z2m 정지 또는 MQTT 브리지 경유로만 라디오 접근.
- **코드레벨 완전 파악 근거(오픈소스)**: Gecko SDK 4.5.0은 host/NCP 전 소스 공개 —
  `protocol/zigbee/app/ezsp-host`(ASH/SPI/CPC 전송), `app/em260`(NCP=MG24 펌웨어 앱), `app/zigbeed`, `stack/*`.
  → Zigbee 스택을 벤더 바이너리 없이 소스에서 재현·이해 가능. 단 **host EmberZNet framework를 SG2000(riscv64) 타깃으로 크로스빌드**하는 작업이 별도로 남음.
- **정확 매칭이 필요하면**: MG24를 GSDK 4.5.0 `em260`으로 7.5.1 NCP 리플래시(`.gbl`, §6.1 재플래시 경로). 껍데기/브리지 목적이면 불필요 — 7.4.2 그대로 EZSP 13으로 충분.

### 벤더 매뉴얼 B-6 대조 — 제네릭 문서임을 확정 (2026-07-01)
벤더 §6 원문은 **SMHUB 시리즈 공통(제네릭)** 문서로 최대 하드웨어 기준 **별도 칩**을 전제 → **Nano Mg24 미적용**:

| 벤더 §6 주장 (제네릭) | Nano Mg24 라이브 | 판정 |
|---|---|---|
| 6.1 Zigbee = **TI CC26xx** `/dev/ttyS1` | 단일 **Silabs MG24**, adapter=`ember`, /dev/ttyS1 | ❌ 칩=MG24/ember (ttyS1 위치만 일치) |
| 6.2 Thread = **별도 EFR32MG** `/dev/ttyS2`, OTBR | 별도 Thread 칩 없음, 같은 MG24 재플래시=Zigbee 상실 | ❌ 별도 칩 아님, **배타** |
| 6.3 Z-Wave = **EFR32ZG23** `/dev/ttyS3` | Z-Wave silicon 없음, 외장 USB만 | ❌ native 미지원 |
| 6.4 4G/LTE = SIM7672G `/dev/ttyS4` (in dev) | 해당 없음 | ❌ Nano 미탑재 |
| 6.7 "Zigbee+Thread+WiFi+BT **동시** 운용" | 단일 MG24라 Zigbee/Thread 배타 | ❌ Nano 미적용 |
| 6.8 Matter Bridge (로컬 브리지) | matterbridge over IP | ✅ 구조 일치(단 0.9.8 **미설치=working 미검증**) |

→ 제네릭 매뉴얼의 다중 라디오 표는 상위 모델(Essential/Premium)용. **Nano 검수 시 §6 표(별도 ttyS2/S3 확인 등)를 그대로 따르면 안 됨.**

---

## 3. 제품 상태 저장 구조 (선언적 세팅본의 대상)

> 원칙(GLG): Web UI로 앱을 하나씩 켜는 인터랙티브 운영(개인 NAS 모델)은 폐기. 제품화 = **모든 설정을
> 리포에 선언**하고 **세팅본 하나를 한 번에 올려** 보드가 완성 상태로 부팅. 이 repo 코어(`flake.nix`
> 재현 가능 buildroot 이미지)와 같은 철학 = 완전 통제.

### 3.1 init/서비스 모델 — OpenRC (systemd 아님)
- `/sbin/init → openrc-init`. 서비스 = `/etc/init.d/*`, 활성 = `/etc/runlevels/<rl>/` 심링크. 감시 = `supervise-daemon`.
- 라이브 관측(`rc-status` grep, runlevel 헤더=`nonetwork`에서 started): zigbee2mqtt · mosquitto · sshd ·
  `smhub-ir-daemon` · `smhub-ambilight-daemon` · **`smhub-mqtt-bridge`(–daemon 접미 없음)** · avahi · bluetoothd ·
  networkmanager · ntpd · rauc-status · watchdog · smhub-services. (default/boot runlevel 심링크 구성은
  `ls -l /etc/runlevels/{boot,default,nonetwork}` 증거 확보 시 분리 표기 — 현재 grep 출력만으로 단정 안 함.)
- boot 런레벨: smhub-services(백엔드), network, watchdog, **firstboot-production / firstboot-upgrade**.
- **⚠️ 라이브 이상**: `smhub-buzzer-daemon = crashed`(0.9.8, 원인 미조사). ESPHome buzzer 컴포넌트가 beta 라인이라 0.9.8에서 동작 불가일 가능성(§5.3).

### 3.2 앱 매니저 = smhub-services (FastAPI :8000)
- venv 평문 Python. 상태 DB **`/opt/smhub-services/config/backend.db`**(SQLite, alembic). = 제품 설정 저장소.

| 테이블 | 역할 |
|---|---|
| `apps` | 앱 레지스트리 `key,name,enabled,start_at_boot,version,watchdog` ← Web UI 토글의 실체 |
| `appsettings` | 앱별 key/value (FK app_id) |
| `pages` / `devicesettings` | UI 페이지 + 페이지별 설정 |
| `user` | admin(email, hashed_password, superuser) — 라이브 1행 |
| `usersettings` | 테마/단위/언어/로케일/TZ/12h — **wide 단일 행 테이블(key/value 아님)**, 라이브 **1행**(공장 기본값, 예: TZ) |
| `alembic_version` | 스키마 버전 — **라이브 head `e1ad05962702`**(add_watchdog_column) |

**공장 0.9.8 backend.db apps 레지스트리**(라이브 V5 = 이 baseline과 완전 동일, 사람 토글 0):

| key | db version | enabled | start_at_boot |
|---|---|---|---|
| zigbee2mqtt | 2.3.0-1 | **1** | 0 |
| matterbridge | 3.0.2-1 | 0 | 0 |
| matterbridge-z2m | 2.4.7-2 | 0 | 0 |
| nodered | 4.0.9-1 | 0 | 0 |
| zwavejsui | 10.4.0-1 | 0 | 0 |
| openthread | 0.3.0-1 | 0 | 0 |
| nodejs | 22.13.1-1 | 0 | 0 |
| smhub-web | 0.3.1-1 | 0 (watchdog=1) | 0 |
| smhub-services | 0.1.12-1 | 0 | 0 |

**★ 4층 구분 확정 (라이브 반증/보정, 2026-07-01)** — 이 넷은 서로 다르다:
1. **카탈로그**(opkg feed): 설치 가능 목록 전체.
2. **설치**(opkg list-installed, 5개): `zigbee2mqtt 2.8.0-2 · nodejs 22.22.0-1 · nodered 4.1.5-1 ·
   smhub-services 0.2.12-1 · smhub-web 0.3.1-1`. → **opkg 버전 ≠ backend.db.version**(z2m 2.8.0 vs 2.3.0,
   node 22.22.0 vs 22.13.1). **backend.db.version = 레지스트리 seed, opkg = 설치 진실원.** matterbridge/
   openthread/zwavejsui/matterbridge-z2m 는 **미설치**.
3. **enabled**(backend.db): zigbee2mqtt만 1. nodered는 설치됐지만 enabled=0.
4. **running**(OpenRC): z2m·smhub-services·mosquitto 등 started. → **z2m 는 `enabled=1·start_at_boot=0`
   인데도 OpenRC 서비스로 실행 중.** `start_at_boot=0` 이 "실행 안 함"을 뜻하지 않는다. DB 가 유일
   제어축이라 단정 금지 — boot-start 실제 의미는 리부트 검증 전까지 미확정(오늘 무변형).

**드리프트 정체 규명 (2026-07-01)**: "왜 opkg z2m 2.8.0 ≠ backend.db 2.3.0 인가" = **손탄 게 아니라 출고 그대로.**
`/opt/zigbee2mqtt` 전 파일 mtime = `2025-12-11 22:43`(= rootfs 빌드시각, os-release/커널 빌드와 동일), `z2m.sh`/
`updates.smlight` 흔적·shell history **없음**. → **z2m 2.8.0 = 이미지 빌드 시 설치, backend.db 2.3.0 = 빌드 때 구운
stale seed.** backend.db.version 은 벤더가 seed 로 박은 값일 뿐 설치 버전과 무관. 백업 `captures/smhub-0.9.8-20260630/`
는 **유효한 factory baseline**(손탄 상태 아님). opkg `Status: install user installed` 의 "user"=opkg 용어(명시 설치)일 뿐 사람이 설치했다는 뜻 아님.

### 3.3 앱/주변장치 설정 파일 (선언 대상)
- Zigbee: `/opt/zigbee2mqtt/data/` — `configuration.yaml`, `coordinator_backup.json`(네트워크키=secret),
  `database.db`, `state.json`.
- 주변장치: `/etc/peripherals/*.conf` — `smhub-{ir,ambilight,buzzer,mqtt-bridge}.conf`. (정본 스키마는
  벤더 매뉴얼 C Peripheral Control Guide 검토 시 확정 — §7.)
- 기타: `/etc/mosquitto`(mosquitto.conf, 라이브 1883=**127.0.0.1/[::1] localhost-only**, 외부 미개방),
  `/etc/nginx`, `/etc/stunnel`.

### 3.4 제품화 seam — firstboot
- `/etc/init.d/firstboot-production`(once-ever): machine-id(EEPROM UUID)·wifi MAC·zigbee adapter·
  `rwnx_settings.ini` = per-unit HW 프로비저닝. **플래그 라이브 확인**: `/mnt/misc/`에 `.production-init`
  `.resized-fs` `.resized-part` `.openrc-migrated` 존재.
- `firstboot-upgrade` = 업그레이드 후 1회. → 우리 선언적 프로비저너를 붙일 수 있는 벤더 표준 seam.

### 3.5 지속(persistence) 파티션 맵 (라이브 확인)
- `/` = p5 ROOTFS0 **RO**(A/B RAUC, `/dev/root` 739M, 58% used). `/etc` = overlay(loop0 25M, upper on
  `/mnt/user/etc-overlay.img`, **64K used = 극소**).
- **p7 USER(5.7G) = `/mnt/user`** → bind `/home /opt /var`(ext4 rw noatime). **모든 앱/데이터/backend.db** 여기. ← 세팅본 주 타깃.
  **소유권 주의(§5.5)**: `/mnt/user`·`/etc`(overlay)·`/var/lib`는 **root 소유 → non-root 쓰기 불가**. **non-root 프로세스의 지속 쓰기 홈 = `/home/smlight`**(p7, smlight writable, 동일-fs 원자 rename 실측 OK).
- p4 MISC(`/mnt/misc` 1.9M) = firstboot 플래그 + rauc data.
- **swap: 0.9.8=0**(`SwapTotal 0`, zram device 미활성) ↔ **beta5=zram0 512M 활성**(`/proc/swaps` pri=100, 커널 `CONFIG_ZRAM=m` 로드). 라인별 차이 확정(§5.4 B6).
- **beta5 실측 정정(§5.4)**: root=**p6 ROOTFS1**(슬롯 B, ext4 ro). **p7 USER는 여전히 ext4**(beta line F2FS는 full re-install 경로에만 적용 — OTA 업그레이드라 재포맷 안 됨). `/etc`=`/mnt/user/etc-overlay.img` **rw overlay**(0.9.8 loop0 오버레이와 동일 구조, p7 지속).

---

### 3.6 SSH 접근 · host key 프로비저닝 · OpenRC "started" 함정 (2026-07-01)
- **접근 2요소는 별개**: `~smlight/.ssh/authorized_keys`(우리 `.sshkey/id_ed25519.pub` 등록 = 클라이언트 인증,
  "누가 로그인") ↔ `/etc/ssh/ssh_host_*_key`(서버 host key = "sshd 가 자기 신원 증명하며 뜰 수 있는가"). **무관.**
- **이 유닛 팩토리 결함**: `/etc/ssh/ssh_host_{rsa,ecdsa,ed25519}_key` 전부 **0바이트**(mtime=빌드시각) →
  `sshd -t: no hostkeys available -- exiting`. sshd 는 OpenRC `default` 런레벨에 **등록돼 있으나**(rc-update 문제
  아님) 매 부팅 **host key 부재로 즉시 죽음** → 리부트 후 :22 closed.
- **beta5 OTA 후 재확인(2026-07-01, §5.4)**: `/etc/ssh/ssh_host_*_key` **여전히 0바이트(mtime Dec 11 2025 그대로)**, OpenRC sshd
  **여전히 crashed**. 즉 릴노트 "Persistent Device Identity"(EEPROM에 hostname/SSH keys)는 **OTA 업그레이드 경로엔 적용 안 됨**
  (full Type-C flash 전용으로 추정). → **EEPROM 이 SSH 결함을 자동 해소할 것이란 가설은 반증됨.**
- **현재(세션) 접속 경로**: 이번 세션에 띄운 **`/tmp/hk` 우회 sshd**(`sshd -h /tmp/hk -o UsePAM=no …`)가 :22 로 살아있고,
  에이전트는 `.sshkey/id_ed25519`(OTA 넘어 p7 `~smlight/.ssh/authorized_keys` 지속)로 접속. **리부트하면 소실**(tmpfs).
- **OpenRC "started" 는 진실 아님**: `rc-status` 가 sshd·smhub-buzzer-daemon 을 started 로 표시해도 프로세스
  없음(crashed). **진실원 = `pgrep -x`/`ss :22`/`sshd -t`**, rc-status 아님. (제품 검수 전반의 running≠working 축.)
- **접근 우회**: 이전 성공 SSH는 표준 sshd가 아니라 `/tmp/hk` 우회 sshd였고, 리부트로 소실됐다. Web UI Console
  (port 80, `#/console`)은 SSH 없이 smlight 셸 + sudo(pw=smlight)를 제공하지만 복붙이 어려워 제품화/장기 운용면으로는 부적합하다.
- **복구/영구화 안전 순서**(필요 시): ① authorized_keys 무손상 확인만(건드리지 말 것) ② host key 크기
  확인 ③ `sshd -t` ④ **0바이트 host key 삭제 후** `ssh-keygen -A`(0바이트를 "존재"로 보고 skip → 삭제 필수)
  ⑤ `mkdir -p /run/sshd`(priv-sep 2차 문제) ⑥ `sshd -t` 통과 뒤 restart. `/etc`=`/mnt/user/etc-overlay.img` rw overlay(p7)라
  **키가 리부트 유지될 것으로 기대**(단 이전 시도에서 `/etc/ssh` write 반영이 불확실했으므로 재생성 후 리부트 검증 필수).
- **결정(2026-07-01)**: beta5에서도 표준 sshd 는 host key 0바이트로 죽으므로, 영구 SSH가 필요하면 **overlay `/etc/ssh` 에 host key
  재생성(0바이트 삭제 → `ssh-keygen -A`) 후 리부트로 지속성 검증**한다. 그 전까지는 `/tmp/hk` 우회(세션 한정) 또는 `Settings→Console`(SSH 불요)로 접근.
  벤더 매뉴얼상 SSH 는 별도 토글 없이 부팅 완료(LED chase 종료) 시 기동 전제 — 이 유닛은 host key 결함으로 그 전제가 깨져 있다.

## 4. 라이브 실측 로그 — 0.9.8 무변형 (2026-07-01)

증거(gitignored): `captures/smhub-verify-20260701T113514+0900/logs/{V1-V6_readonly.txt, controlmap-0.9.8-readonly.txt}`.
META: **SMHUB 0.9.8**, Buildroot `2025.11-33-g52d9e5043c-dirty`, kernel **6.18.17-patch0 riscv64**(build 2025-12-11).

| # | 항목 | 결과 |
|---|---|---|
| V1 | 서비스(OpenRC) | z2m·smhub-services·mosquitto·sshd·avahi·rauc 등 started. **smhub-buzzer-daemon=crashed** |
| V2 | 포트 | mosquitto **127.0.0.1:1883**(localhost-only), 8000=services, 8080=z2m, 80/443=nginx, 22=sshd |
| V3 | z2m frontend/bridge | `:8080 → HTTP 200` ✅ + z2m process started. `bridge/state={"state":"online"}` ✅(**grounded**, recapture log) → **z2m_bridge_online**. running 버전 **2.8.0**(package.json, ≠ backend.db 2.3.0) |
| V4 | coordinator | grounded(`bridge/info`): type=**EmberZNet**, 펌웨어 **7.4.2 [GA]**, ezsp13, adapter=ember@/dev/ttyS1, ch11, pan_id 59232, permit_join=False, IEEE 0x403802fffed4b896(=96b8…3840 역순), **paired end-device 0**(db 1행=Coordinator) |
| V5 | backend.db | apps=공장 baseline과 동일, alembic head e1ad05962702, **usersettings 1행(wide, 공장 기본값)**, user 1(superuser) |
| V6 | 지속/오버레이 | p7→/mnt/user·/home·/opt·/var, /etc overlay 64K, root RO 58%, **Swap 0** |
| C1 | DT compatible | `smlight,nano smlight,sg2000 sophgo,sg2000`; DT에 C906L/remoteproc/mailbox 노드 **없음** |
| C2 | remoteproc/rpmsg | `/sys/class/remoteproc` 없음, `/dev/rpmsg*` 없음, `/opt/firmware` 없음, 관련 모듈 미로드 |
| C3 | 커널 .config | `/proc/config.gz` 5178줄 라이브. ARCH_SOPHGO·ERRATA_THEAD·PINCTRL_SOPHGO_SG2000·CV1800 clk/pwm/rtc/usb-phy·DWMAC_SOPHGO. **REMOTEPROC/RPMSG/MAILBOX 없음** |
| C4 | opkg installed | 5개(§3.2 목록). 카탈로그 앱(matterbridge/zwave/otbr) 미설치 |

**핵심 함의**: C2+C3+C1 → **C906L/ESPHome/RPMsg 스택은 0.9.8 factory에 통째로 없음.** 커널이 remoteproc/rpmsg를
안 켰고 DT에 C906L 노드도 없다. 이 코프로세서 레이어는 **beta 라인(beta3+, 2026-06-14~) 추가분**이다(§5.3).

**남은 무변형 검증**: 리부트 boot-start 검증(리부트=경미 변형; start_at_boot=0 의미 확정용), full DTB 덤프
(`/sys/firmware/fdt` root-only → sudo 필요), OTA 직전 preflight(rauc status·fw_printenv slot·df·backend.db+z2m
data sha256). (bridge online·ember 7.4.2·config.gz full text·opkg·buzzer.conf 는 captures 저장 완료. buzzer
crash=pwmchip0 접근 실패 추정, 비결정적 보류.) **주의**: MQTT pub/sub 왕복은 broker publish라 strict 무변형 아님 → retained SUB 만 하거나 unique·retain=false·QoS0 smoke 로 분리.

---

## 5. 통제 경계 + 재현 세트 매트릭스 (beta5 정적 추출 + 0.9.8 라이브)

**방법**: beta5 fastboot zip → `simg2img` → 파티션 분리 → ext4 `debugfs` + F2FS `mount -ro` 정적 추출.
소스 없이 **바이너리 이미지에서 ground truth**. 원본 `captures/smhub-beta5-20260630/`(ignored, 벤더 feed 크레덴셜 포함 → stage 금지).

### 5.1 베이스 OS (부트체인/커널/rootfs) — 전부 ⚠️ 부분

| 컴포넌트 | 버전 | upstream | 벤더 diff | 재현 |
|---|---|---|---|---|
| FIP / OpenSBI | fip build 2026-03-04 | `sophgo/bootloader-riscv`(로컬 clone `ad9750c0`) · `milkv-duo/duo-buildroot-sdk-v2`(`ad920f839`) | ❌ 빌드 config 비공개 | ⚠️ |
| 커널 | Linux **6.18.17**(0.9.8·beta5 **동일 version/build string** 6.18.17 2025-12-11 관측; bit-identical 여부는 별도) | mainline + sophgo/cvitek 패치 | ⚠️ 0.9.8 **full `.config` text 확보**(config.gz 5178줄), DT diff 남음 | ⚠️ |
| rootfs | Buildroot 0.9.8=`2025.11-33` / beta5=`2026.02-18` | `git.buildroot.net/buildroot` | ❌ BR2_external/defconfig/overlay 비공개 | ⚠️ |
| 파티션/RAUC | A/B(p1-7), RAUC | `rauc/rauc` | system.conf 라이브 확보(0.9.8 백업) | ⚠️ |

- **DT compatible**: `smlight,nano` + `sophgo,sg2000` → mainline CV1800B/SG2000 계열. beta5 DT엔
  `sophgo,cv1812cp-c906l` C906L 노드 존재(0.9.8엔 없음, §4 C1).
- **파티션**: p1/p2 KERNEL0/1(FAT, boot.itb) · p3 ENV · p4 MISC · p5 ROOTFS0(ext4) · p6 ROOTFS1(OTA/RAUC
  라이브에서만 채워짐) · p7 USER. fastboot 이미지(raw 2.02GiB) ≠ 라이브 7.6GB eMMC.
- **재현 공백 #1**: bit-identical 재현엔 벤더 Buildroot defconfig + BR2_external + 커널 DT diff 필요 — 비공개(§6).

### 5.2 앱 레이어 (프로토콜 스택) — z2m ✅, 설치형 ⚠️

| 컴포넌트 | 버전 | upstream | 재현 |
|---|---|---|---|
| Node.js | 22.22.0 | `nodejs/node` | ✅ |
| Python | 3.14 | cpython | ✅ |
| **zigbee2mqtt** | beta5 2.10.1 / 0.9.8-opkg 2.8.0 | `Koenkk/zigbee2mqtt` — `pnpm-lock.yaml` 확보 | ✅ |
| zigbee-herdsman / -converters | 10.0.7 / 26.46.0 | Koenkk | ✅ |
| z2m frontend / windfront | 0.9.21 / 2.11.2 | Koenkk | ✅ |
| matterbridge (+z2m/hass/shelly) | 3.5.5 (3.0.6/1.0.5/2.2.30) | `Luligu/matterbridge` | ⚠️ **미설치** — lock/의존 미확보 |
| **matter.js (@matter/*)** | ❌ 버전 미확보 | `project-chip/matter.js` | ❌ 설치 후 확정 |
| openthread / OTBR | 0.3.1-5 (벤더 ipk) | `openthread/openthread`·`ot-br-posix` | ⚠️ 내부 commit 미상 |
| zwavejsui | 11.19.0 (카탈로그) | `zwave-js/zwave-js-ui` | ⚠️ 미설치 |

- beta5 공장 시드 **실제 설치** = nodejs/python3/zigbee2mqtt/esphome-bin/smhub-broker/smhub-services/smhub-ui.
  matterbridge·OTBR·zwavejsui는 opkg **카탈로그에만**(미설치).
- **재현 공백 #2 (matter.js)**: matterbridge 미설치 → `@matter/*` 정확 버전 없음. npm 또는 라이브 설치 후 확정.

**Apps 설치 경로 = opkg mutation (라이브 실측 2026-07-01, `apps-catalog-readonly.txt`)**: Web UI `Apps → Install/OS Update` 버튼은
`opkg install <pkg>` 를 벤더 feed `smhub_core`(`/etc/opkg/smlight.conf`, **per-unit `http_auth` 시크릿 → captures(gitignored)/PRIVATE 만**)에서 당긴다.
- **버전 드리프트 증거**(feed에 다중 버전 공존): matterbridge `3.5.4-1 / 3.5.5-1 / 3.5.5-2`, matterbridge-z2m `2.8.0-1 / 3.0.4-1 / 3.0.6-1`
  (`Depends: matterbridge (>= 3.5.0)`), zwavejsui `11.15.1-3 / 11.19.0-1 / 11.21.0-1`, openthread `0.3.1-3/4/5`, tailscale `1.78.1-3/4/7`,
  picoclaw(-core) `0.2.8-2`. **"Latest" 클릭 = 클릭 시점 버전 고정 = 비재현.** ipk 다수 `Architecture: all`(nodejs 앱).
- **우리 정책(§9)**: **클릭 설치 금지.** 필요한 앱은 (1) **정확 버전 pin + ipk provenance 기록**(filename/size/Depends, 위 캡처) →
  (2) 선언적 applier 가 pin 된 버전으로 설치 후 **verify**, 또는 소스에서 이미지에 bake. 설치는 **GLG go 게이트**.

### 5.3 C906L RTOS + 코어간 통신 — 벤더 커스텀, 일부 ❌ (**beta 라인 기능, 0.9.8엔 없음**)

C906L(small core) RTOS ↔ Linux(C906B) 통신은 **표준 RPMsg / remoteproc** 축(비밀 mailbox 아님).
이게 통제 가능성의 핵심 — 표준 인터페이스라 끼어들 수 있다. **단 이 전체 스택은 0.9.8 factory엔 부재**(§4 C1-C3).

| 컴포넌트 | 버전 | 형태 | 재현 |
|---|---|---|---|
| esphome (코어) | 2026.5.3 | — | ✅ `esphome/esphome` |
| 벤더 ESPHome 컴포넌트 (`sg2000_*`/`smhub_*`) | — | ELF 심볼 | ❌ 없음 |
| `esphome-bin.{smhub,nano}.elf` | 2026.5.3-2 | RISC-V static ELF, not stripped | ⚠️ ELF 확보 |
| **smhub-broker** | 1.0.3-1 | RISC-V PIE, not stripped | ❌ 바이너리만 |
| rtos-logger / rtos-notify | (broker 동반) | RISC-V PIE | ❌ 바이너리만 |
| smhub-services (백엔드) | 1.0.4-1 | **Python venv 평문** | ⚠️ 소스 가독 |
| C906L RTOS 펌웨어 | — | `/opt/firmware/smhub-rtos.elf` | ⚠️ ELF 슬롯 = 교체 후보 seam(확정은 beta5 live 검증 후) |

- **통신 메커니즘**(smhub-broker strings): transport `/dev/rpmsg{0,1,_ctrl}`, `smhub::hal::RpmsgTransport`,
  채널 `smhub-rpc`/`esphome-rpc`; 라이프사이클 `echo {start,stop} > /sys/class/remoteproc/remoteproc0/state`;
  펌웨어 슬롯 `/opt/firmware/smhub-rtos.elf`(+`.new`); 소켓 `/var/run/smhub-{broker,openamp}.sock`.
- **ESPHome on C906L (숨은 핵심 능력)**: HA native API(허브 자체가 ESPHome 노드) · Native Bluetooth Proxy
  (`bluetooth_proxy`, 최대 16 동시연결, 활성 시 host `bluetoothd` 자동 비활성) · 실시간 주변장치
  (GPIO/PWM `sg2000_pwm`, WS2812 RGB `sg2000_ws`=ambilight, buzzer `smhub_buzzer`, IR, RTC ds1307) ·
  코어간 IPC `smhub_ipc_*`(gpio_edge_cb/request_mac/request_restart/send_rpc/time_cb).
- **선례**: SMLIGHT ESP32 repo [`slzb-esphome`](https://github.com/smlight-tech/slzb-esphome)(GPL-3.0)의 패키지
  (buzzer·ws2812·ir·bluetooth·leds·ioexp) = C906L ELF 능력과 동종. SG2000 포트는 ESP32 컴포넌트를 C906L로 이식한 것으로 추정.

**통제 가능성 — beta5 LIVE 확정 (2026-07-01, §5.4)**: ① 통신=표준 RPMsg/remoteproc **확인**(`/dev/rpmsg{0,1,_ctrl0}`
라이브, virtio_rpmsg) → 우리 `homeagentd`가 `/dev/rpmsg*` 직결 또는 smhub-broker 대체 **가능**. ② RTOS=ELF 슬롯
(`/opt/firmware/smhub-rtos.elf`, smlight 소유 355KB) + `remoteproc0/state` write → **우리 Zig RTOS 교체 후보 seam 확정**.
③ ELF strings로 FreeRTOS+ESPHome 2026.5.3+open-amp 구조·config 출처 노출 → 역설계 비용 낮음. **가설 전부 라이브로 뒷받침됨**(§5.4).

---

### 5.4 beta5 라이브 실측 — C906L RTOS + 스택 확정 (2026-07-01, OTA 후)

증거(gitignored): `captures/smhub-beta5-live-20260701T171429+0900/logs/{beta5-postcapture.txt, mg24-bridge-info.txt}`.
META: **SMHUB 1.0.0.beta5**, Buildroot `2026.02-18-g60430d6802`, kernel **6.18.17-patch21 riscv64**(build 2026-03-04).
경로: 0.9.8 → Web UI `Settings→Update and Restore` OTA → **슬롯 B(kernel.1/rootfs.1) 부팅 good**, 슬롯 A(0.9.8)는 `boot status bad`·inactive(잔존, 블록백업이 실질 롤백).

| # | 항목 | 라이브 결과 (0.9.8 대비 = 등장) |
|---|---|---|
| B1 | **C906L remoteproc** | `remoteproc0/{name=remoteproc@0, state=**running**, firmware=**smhub-rtos.elf**}` ✅ (0.9.8=부재) |
| B2 | **RPMsg 채널** | `/dev/rpmsg0·rpmsg1·rpmsg_ctrl0` + dmesg `virtio_rpmsg_bus … esphome-rpc addr 0x400` · `smhub-rpc addr 0x401` ✅ |
| B3 | **RTOS 펌웨어** | `/opt/firmware/smhub-rtos.elf`(355216B, **smlight 소유 = user-writable**) + `esphome_data.dat`. strings: **C906L RTOS / FreeRTOS / ESPHome 2026.5.3 / open-amp `framework-sg2000-rtos` / config `github://smlight-smhub/rtos-config//nano-esphome.yaml@main`** |
| B4 | **broker 브리지** | `smhub-broker`(pid, `--ble-throttle --ble-mode=hci`) + `/run/smhub-broker.sock`·`/var/run/smhub-broker.sock` ✅. BLE=`hciattach /dev/ttyS4 … 1500000` |
| B5 | **opkg 설치(정본)** | esphome-bin 2026.5.3-3 · smhub-broker 1.0.3-3 · **smhub-services 1.0.4-1** · **smhub-ui 1.0.3-1**(+구 smhub-web 0.3.1-1) · zigbee2mqtt 2.10.1-2 · nodered 4.1.5-1 · nodejs 22.22.0 · python3 3.14. (matterbridge/OTBR/zwave 여전히 **미설치**) |
| B6 | **persistence** | root=**p6 ROOTFS1 ext4 ro**(슬롯 B). **p7 USER = ext4**(F2FS 아님 — OTA 경로라 재포맷 안 됨). `/etc`=`/mnt/user/etc-overlay.img` **rw overlay**. **zram0 512M swap 활성**(0.9.8=swap 0). |
| B7 | **커널 .config** | `REMOTEPROC=y·REMOTEPROC_CDEV=y·RPMSG_CHAR/CTRL/NS/VIRTIO=y·MAILBOX=y·ZRAM=m·F2FS_FS=y` — beta 라인 코프로세서/압축/F2FS 전부 **커널에 활성**(0.9.8엔 REMOTEPROC/RPMSG/MAILBOX 없었음). |
| B8 | **프로세스 매니저** | OpenRC `supervise-daemon`(z2m·smhub-broker 감독). ESPHome는 Linux userspace 프로세스 **없음** = **C906L 코어에서 실행**(smhub-rtos.elf), broker가 소켓 브리지. |

**앱 배선 (OpenRC init 직독, `app-wiring-readonly.txt`)**:
- `smhub-broker`: `command=/opt/bin/smhub-broker --ble-throttle`, supervise-daemon. **`depend() { need localmount remoteproc; before status-login-ready }`**
  → 별도 **`remoteproc` OpenRC 서비스가 C906L 부팅**, broker가 이를 의존(부팅 순서 계약). `start_pre`가 **`/opt/firmware/bluetooth_proxy_mode`**(off/hci/bluez/dbus) 파일을 읽어 `--ble-mode=` 주입 = **선언적 config seam**(user-writable `/opt/firmware`).
- `smhub-services`: `/opt/bin/smhub-services`, `SMHUB_SERVICES_DATA=/opt/smhub-services`, `retry=TERM/30/KILL/5`(웹UI 업데이트가 graceful shutdown 블록).

**핵심 함의**: §4(0.9.8)에서 "C906L/ESPHome/RPMsg = beta 라인 추가분"이라던 가설이 **beta5 라이브로 전면 확정**됐다.
L2 코프로세서 아키텍처(C906L FreeRTOS + ESPHome, open-amp/RPMsg 2채널, broker 소켓 브리지, user-writable ELF 슬롯)가
**우리 `runtime/` RISC-V 재구성의 정확한 ground truth**다. 커널이 riscv64 6.18.17 = 제품이 RISC-V임도 재확인(→ Phase D 문서 정합화 근거).

### 5.5 포팅 derisk 실측 — 자원 여유 + 지속 경로 (2026-07-03, beta5)

우리 RISC-V 펌웨어(riscv64 static, AWS IoT MQTT+TLS)를 **z2m 곁에 얹기 전** board-level blocker를 실측 검증. Zigbee는 껍데기(stub) 전제.

- **Q1 자원 — 🟢 GREEN**: Mem total 488M / used 272M / **available 216M** / buff-cache 206M(회수가능). z2m(node) RSS **105.7M**. **zram 512M swap = 348KB(0.06%) 사용** = 사실상 미사용(백스톱 여유). Committed_AS 501M / CommitLimit 756M(66%). → 단일 gateway 프로세스(TLS 세션 1개, 수~수십 MB) OOM 위험 없음. **조건**: ① 실제 RSS는 빌드 후 측정 확정(추정 금지, RSS 규율), ② EmberZNet **host framework 전체 동시 구동**(node급 2번째 footprint)은 별도 재평가 — 쉘은 stub이라 무관.
- **Q2 지속 경로 — ✅ non-root면 `/home/smlight`(p7 ext4)**: `/`=p6 ext4 **ro**, `/etc`=rw overlay이나 **root 소유(non-root 쓰기 불가)**, `/mnt/user`=p7 rw이나 root 소유, **`/home/smlight`=p7 ext4 rw + smlight writable + 동일-fs `mv` 원자쓰기 실측 성공** ✅, `/tmp`=tmpfs(휘발). → 우리 코드의 `/etc/hub_state.json`(단일 writer)은 **non-root에선 /etc 불가** → 권고 `$HOME/.local/state/…`(=/home/smlight, p7). root 구동이면 /mnt/user·/etc overlay 열림. §3.5 정합.
- **Q3 버전 좌표 독립 재확인 — ✅**: `coordinator_backup.json`에서 `ezspVersion 13` + `source zigbee-herdsman@10.0.7` + pan_id `e760`(=59232, §2 일치) 독립 확인. (EmberZNet 7.4.2 GA는 backup에 없음 = 런타임 `bridge/info` 값 축, §2/§4 V4 의존.)
- **Q4 EZSP 13 내 7.4↔7.5 델타 — ⚠️ 열림(§9)**: 로컬은 GSDK 4.5.0=7.5.1만 보유 → 진짜 frame-ID diff엔 7.4.2 `ezsp-enum.h` 필요. 단 `ezsp.c` 하위호환 경로(*initial EZSP_VERSION old packet format*)로 코어 코디네이터 커맨드 상호운용은 안전. 잔여 리스크=7.5 전용 신규 frame 호출. Phase 2(직접구동 b) 착수 시 확정.
- **Q5 MG24 NCP 리플래시 이미지 — `ncp-uart-hw` (단 flow control 텐션)**: GSDK "em260" 후신 = `app/ncp/sample-app/ncp-uart-hw/ncp-uart-hw.slcp`, **MG24=Cortex-M33**(prebuilt `build/gcc/cortex-m33/zigbee-ncp-uart`), 출력 `.gbl`, 툴=벤더 `smhub-flasher`(릴노트 "Radio page supports Nano Mg24 flashing")/`universal-silabs-flasher`. GSDK UART NCP 샘플은 이 hw판만(`-sw` 부재).
  ⚠️ **flow control 텐션(사실로 굳히지 않음)**: 라이브 동작 정본 = z2m **`rtscts: false`(no-flow)** @115200. 그런데 stock `ncp-uart-hw`는 기본 **RTS/CTS on**(`SL_IOSTREAM_USART_VCOM_FLOW_CONTROL_TYPE=usartHwFlowControlCtsAndRts`, `EMBER_SERIAL1_RTSCTS`). → 벤더 flashed 이미지는 **no-flow 빌드**이거나 그렇게 구동 중이며, **stock hw판을 그대로 리플래시 후 no-flow 호스트로 몰면 부하 시 바이트 드롭 가능**. Phase 2 직접구동 전 flow-control 정합(NCP를 no-flow로 빌드 vs 양단 RTS/CTS — `ttyS1` RTS/CTS 배선 미검증) **재조정 항목**. (§6.1 재플래시 경로.)

**derisk 종합**: Q1·Q2 🟢 = **Phase 1(쉘) 실착수 막는 board blocker 없음**. Q3 확인사살 통과, Q4·Q5는 Phase 2 경계 명확.

---

## 6. 정보 벽 = 재현 공백 (없는 것 확실히) + SMLIGHT 연락 후보

이미지에서 **얻을 수 없는** 것들. 역설계 우회 가능하나 SMLIGHT 직접 요청이 양쪽에 득(오픈소스 hub 검증 협업 명분).

1. **opkg 피드 소스** `pkg.smlight.tech/v1` — ipk 바이너리만, 빌드 소스 ❌ (URL에 http-auth 크레덴셜 → redacted만 안전).
2. **벤더 Buildroot defconfig + BR2_external + overlay** — 베이스 OS 재현 최대 공백.
3. **커널 `.config` + 벤더 DT diff** — **0.9.8 full `.config` text 확보**(config.gz 5178줄, §4 C3); DT diff + raw gz 원본 남음.
4. **smhub-broker / rtos-logger / rtos-notify 소스** — RISC-V 바이너리만.
5. **벤더 ESPHome SG2000/SMHub 컴포넌트 소스**(`sg2000_*`, `smhub_*`). **GPLv3 근거 있음**: esphome-bin.elf가
   ESPHome GPLv3 C++ 코어와 static-link → 파생저작물이면 소스 제공 의무. 선례=`slzb-esphome` GPL 공개.
   전수 조사(2026-06-30) 결과 SG2000/C906L ESPHome 포트 **공개분 없음** — GPL 근거 직접 요청이 유일 경로. (재조사 불필요.)
6. **MG24 코디네이터 펌웨어 `.gbl`** — 이미지에 .gbl 없음. flash 툴 공개(`universal-silabs-flasher`+`bellows`/EZSP).
   **EmberZNet 펌웨어 = `7.4.2 [GA]`, ezsp13 라이브 grounded**(`bridge/info`). `.gbl` 원본 파일만 남음(재플래시용).
7. **matter.js(`@matter/*`) 정확 버전** — matterbridge 미설치 → npm 또는 라이브 필요.

---

## 7. 벤더 매뉴얼 검토 (공식 22페이지 체크리스트)

출처: <https://smlight.tech/support/manuals/books/smhub> (BookStack). 각 페이지 "벤더 절차 ↔ 라이브 실측" 대조.
`[ ]`=미검토, `[x]`=완료. **매뉴얼은 SMHUB 시리즈 공통(제네릭)** — Nano Mg24와 다를 수 있음(§2 B-6 참조).

### A. Restore & Updating (OTA/복구/접근)
- [ ] [Update & Restore Methods](https://smlight.tech/support/manuals/books/smhub/page/smhub-os-update-restore-methods) — A/B·RAUC 총론. **OTA beta5 게이트 전 필독.**
- [ ] [Update/Restore using Type-C](https://smlight.tech/support/manuals/books/smhub/page/updaterestore-using-type-c) — full flash. rollback 검증 뒤에만.
- [ ] [Update/Restore using SD-Card](https://smlight.tech/support/manuals/books/smhub/page/updaterestore-using-sd-card)
- [ ] [Quick Start Guide](https://smlight.tech/support/manuals/books/smhub/page/smhub-early-adopter-quick-start-guide)
- [ ] [Access via External SSH client](https://smlight.tech/support/manuals/books/smhub/page/access-smhub-via-external-ssh-client) — 벤더 공식 SSH 활성 절차. 우리 접근과 대조.
- [ ] [Release notes](https://smlight.tech/support/manuals/books/smhub/page/smhub-os-release-notes) — 로컬 `smhub-os-release-notes.org`(PRIVATE) 대조.

### B. Product Description (1~8·10)
- [ ] 1. Introduction / [ ] 3. Getting Started / [ ] 5. Network / [ ] 10. Glossary
- [ ] [2. Hardware Overview](https://smlight.tech/support/manuals/books/smhub/page/2-hardware-overview) — MG24/SG2000 스펙, Z-Wave 부재 대조.
- [ ] [4. Software & System](https://smlight.tech/support/manuals/books/smhub/page/4-software-system) — backend.db·OpenRC 라이브 대조.
- [x] [6. Radios & Protocols](https://smlight.tech/support/manuals/books/smhub/page/6-radios-protocols) — **완료(2026-07-01)**: 제네릭 문서 확정, §2 대조표. Nano=단일 MG24(ember), 라이브가 정본.
- [ ] [7. User Interface](https://smlight.tech/support/manuals/books/smhub/page/7-user-interface) — 앱 토글=backend.db.apps 대조.
- [ ] [8. Modules & Extensions](https://smlight.tech/support/manuals/books/smhub/page/8-modules-extensions) — 모듈 카탈로그.

### C. Task Guides
- [x] [Zigbee2MQTT → Home Assistant](https://smlight.tech/support/manuals/books/smhub/page/connecting-zigbee2mqtt-on-smhub-to-home-assistant) — **완료(2026-07-01)**:
  최소 펌웨어(smhub-os≥0.3.7·services≥0.2.4·web≥0.2.18) 우리 0.9.8 충족. 연결 2모델 — ①직결: Web UI
  `Apps→Zigbee2MQTT` → Broker `mqtt://HA_IP:1883` + HA 크레덴셜 → `Home Assistant Settings` + `Experimental
  Events` 켜기 → Save → z2m 재시작. ②로컬 브리지: `Settings→MQTT` `Allow External`+`Allow Anonymous`+
  `Bridge Mode=True`, Remote `HA_IP:1883`, `Bridge Topic = # both 1` → reboot. **z2m 업데이트=`curl -fsSL
  https://updates.smlight.tech/z2m.sh | sudo sh`(pw `smlight`) = 설치성 mutation → §9 설치 게이트.** 토글은 전부 backend.db appsettings.
- [ ] [Thread Border Router for Matter](https://smlight.tech/support/manuals/books/smhub/page/using-smhub-as-thread-border-router-for-matter-devices) — 보류 레인.
- [ ] [Run Thread networks](https://smlight.tech/support/manuals/books/smhub/page/run-thread-networks) — 보류.
- [ ] [Change IEEE address on radio](https://smlight.tech/support/manuals/books/smhub/page/change-ieee-address-on-smhub-radio) — per-unit 프로비저닝 연관.
- [ ] [Peripheral (IR, Buzzer, Ambilight) Control Guide](https://smlight.tech/support/manuals/books/smhub/page/smhub-peripheral-ir-buzzer-ambilight-control-guide) — **`/etc/peripherals/*.conf` 정본**(지어낸 값 대체). buzzer crash(§3.1)와 대조.
- [ ] [Tailscale](https://smlight.tech/support/manuals/books/smhub/page/tailscale-set-up) / [ ] [Troubleshooting](https://smlight.tech/support/manuals/books/smhub/page/troubleshooting) — 선택/레퍼런스.

**검토 우선순위**: ① B-6 + C Zigbee2MQTT ✅완료 → **② A Update/Restore + External SSH**(OTA/백업 게이트
정본화) → ③ B-2/4/7/8(HW/SW/UI/모듈 = backend.db·OpenRC 대조) → ④ C Peripheral conf 정본 → ⑤ 나머지(Thread/Tailscale/Glossary).

---

## 8. 버전 드리프트 원칙 (설계 기준)

- OS 버전업(0.9.8 → beta5 → 0.9.9 …) 하면 앱 버전·appsettings 기본값·alembic HEAD·패키지 목록이 또 바뀐다.
  → **버전을 못박은 config/코드를 미리 만들면 매번 깨진다.** 그래서 지금은 프레임워크를 짓지 않는다.
- **버전에 안 흔들리는 것 = 구조**: backend.db 상태 저장소, OpenRC runlevel, p7 USER 지속, firstboot seam,
  MG24=ember Zigbee, Matter=matterbridge 브리지, C906L=RPMsg/remoteproc(beta 라인). 세트는 이 구조 위에 엮는다.
- 버전 종속값(§3 표, opkg 버전, z2m 키)은 특정 스냅샷 관측이며 SSOT 아님 — 배포 시점에 실물에서 다시 읽는다.
- **backend.db.version ≠ 설치 버전**(§3.2 4층). 설치 버전은 opkg, running 은 OpenRC 로 확인.

---

## 9. 제품화 세트 — 열린 설계 질문 (미결, 고민 단계)

아직 코드/번들을 만들지 않는다. 먼저 아래를 정한다.

- **재현 기판**: (A) 벤더 beta5 이미지 오프라인 커스터마이즈(p7/rootfs 주입 후 repack) vs (B) 우리 buildroot
  이미지(flake.nix, repo 코어)에 처음부터 포함.
- **상태 원본**: (a) 손 선언 vs (b) 보드를 원하는 상태로 만든 뒤 **golden 스냅샷**(backend.db + /etc overlay
  + p7 앱-data + 패키지 집합)을 이미지 seed 로. 후자가 adapter=zstack 류 손선언 실수를 막는다.
- **backend.db 취급**: 벤더 alembic DB 보존하고 enabled/start_at_boot/usersettings 만 손대는 게 안전.
  이미지에 굽는다면 **alembic HEAD 일치 필요**(라이브 `e1ad05962702`).
- **per-unit secret**(zigbee network key, machine-id): 이미지에 굽지 않는다. 벤더 firstboot 가 unit 별 처리.
- **설치 게이트**: matterbridge/z2m update 등 설치=mutation. **GLG go 필요.** OTA beta5 는 별개 게이트(백업 있어 롤백 가능).
- **검수**: 배포 후 "running ≠ working" pass/fail. 매트릭스 미리 고정 말고 라이브 근거 쌓일 때 최소본으로.

---

## 10. 다음 검증 단계

**0.9.8 라이브가 이미 해소한 것**(beta5 불필요): DT compatible(§4 C1) · 커널 .config 마커(C3) ·
opkg 설치 목록(C4) · remoteproc/C906L 부재 확정(C2) · adapter=ember(V4) · 지속/overlay/swap(V6).

**남은 무변형(0.9.8, 다음 세션)**: z2m `bridge/info`(ember 펌웨어 빌드 버전, z2m_bridge_online) · buzzer
crash 로그 · full `config.gz` 덤프 · 벤더 매뉴얼 ②A(Update/Restore + SSH).

**beta5 OTA 후 확정(2026-07-01, §5.4)**: ✅ C906L 라이브(remoteproc running + smhub-rtos.elf) · RPMsg 2채널
(esphome-rpc/smhub-rpc) · broker 소켓 브리지 · ESPHome 2026.5.3 on FreeRTOS(open-amp) · opkg 정본 · p7 ext4/zram/etc-overlay ·
커널 REMOTEPROC/RPMSG/MAILBOX 활성 · riscv64 재확인 · **EEPROM SSH 지속 가설 반증**(host key 여전히 0바이트).

**beta5 남은 것(셸 확보 상태, 다음)**: MG24 `bridge/info` 라이브(ember 펌웨어/ezsp — mosquitto 인증 경로 필요) · DTB/FIT 분해
(`/sys/firmware/fdt`, sudo) · MG24 `.gbl` 경로 · `homeagentd`용 RPMsg ABI/`smhub-rtos.elf` 로드 contract · (설치 게이트 후) matterbridge `@matter/*`.

**영구화 결정 대기**: overlay `/etc/ssh` host key 재생성 후 리부트 지속성 검증(§3.6).
**경미 변형(별도 판단)**: 기기 페어링(permit_join).
**금지**: Type-C full flash를 OTA보다 먼저(A/B rollback 전제 붕괴) · live 좌표/키를 공개 파일에.
