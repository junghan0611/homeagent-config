# NOW — SMHub Nano Mg24: 검증 마무리 → 버전업 → 실제 코드 → 종합 테스트

- **Stem**: 벤더 **SMHUB OS는 무수정**으로 쓰고 제품 기능을 끝까지 검증한 뒤, **버전업(OTA beta5)** 하고
  그 위에 **실제 코드**(RISC-V Zig `homeagentd` 100ms 상태머신 + 선언적 config-set)를 만들어 **종합 테스트**한다.
- **방향 전환 (2026-07-01, GLG)**: 이전 "코드 아직 안 만든다(버전 드리프트 회피)"에서 **"버전업 후 실제 코드로
  종합 테스트"** 로 전환. 버전을 못박지 않기 위해 **배포 시점에 실물에서 값을 읽는 applier + 검수 하네스**로 짓는다.
- **지식 SSOT (단일)**: `docs/SMHUB.md` — HW/라디오/상태모델/라이브 실측/통제경계·재현 매트릭스/정보벽/
  벤더 매뉴얼 검토/열린 설계질문/다음 단계. (구 PRODUCT-CONFIG-MODEL + SMHUB-CONTROL-MAP + SMHUB-MANUAL-REVIEW 병합.)
- **현재 상태 (2026-07-01 OTA 완료)**: **OTA로 `1.0.0.beta5` 부팅 성공** (0.9.8 → beta5, Web UI Settings→Update and Restore).
  출고 0.9.8 블록 백업은 슬롯 A에 롤백 보존(`captures/smhub-0.9.8-20260630/`, gitignored). 0.9.8 V1~V6 실측은 `captures/smhub-verify-20260701T113514+0900/logs/`.
  **beta5 라이브 post-capture 완료**(SSH=`/tmp/hk` 우회 sshd, `.sshkey` 키인증): C906L RTOS 스택 전면 확정 → `docs/SMHUB.md §5.4`.
  **주의**: beta5도 표준 `/etc/ssh` host key 0바이트·OpenRC sshd crashed 그대로 = EEPROM 지속 가설 반증. 영구 SSH는 overlay `/etc/ssh` host key 재생성+리부트 검증이 남음(§3.6). 캡처 스크립트 `scripts/beta5-postcapture-readonly.sh`. live 좌표/키는 `PRIVATE.md`만.
- **라이브 확정**: MG24=**ember** Zigbee coordinator. 기본 세트 = z2m + matterbridge(-z2m) Matter over IP.
  Z-Wave native 미지원, Thread/OTBR 보류. **C906L/ESPHome/RPMsg 스택은 0.9.8엔 없음 = beta 라인(beta3+) 기능.**
- **Do not touch**: Type-C full flash를 OTA보다 먼저 하지 말 것(A/B rollback 붕괴). live IP/MAC/SSH 키/기기
  좌표를 공개 파일에 쓰지 말 것. 표준 sshd host-key 수리에 더 매달리지 말 것(업데이트 후 재평가). "service running"을 "working"으로 판정하지 말 것. `AGENT_ALLOW_UNSAFE_COMMIT`/`--no-verify` 금지.

# ACTIVE — 할 일 전체 (Phase A → D)

## Phase A. 0.9.8 무변형 검증 마무리 (남은 것, 리부트 전)
증거 축적 → `docs/SMHUB.md §4`. GPT 검수(2026-07-01) 반영 = provenance grounded.

- [x] z2m `bridge/info` grounded: type=EmberZNet, 펌웨어 **7.4.2 [GA]**, bridge online, ch11, permit_join False, paired end-device 0(db 1행=Coordinator). → `phaseA-recapture-0.9.8.txt`.
- [x] 드리프트 규명: 보드 **손탄 아님/출고 그대로**(z2m 2.8.0=빌드시 설치, backend.db 2.3.0=stale seed). usersettings=1행(wide, 빈값 아님).
- [x] full `/proc/config.gz` full text 확보 + `opkg list-installed` 저장(captures).
- [ ] DTB 덤프(`/sys/firmware/fdt` root-only → **sudo 필요**, 읽기전용 sudo 정책 결정).
- [x] **리부트 boot-start 검증 완료**(2026-07-01, operator go): 리부트 후 포트로 확정 — **z2m 8080·smhub-services 8000·nginx 80/443 자동 기동**(z2m 는 start_at_boot=0 인데도 OpenRC runlevel 로 뜸 → **제어축=OpenRC runlevel, backend.db.start_at_boot 무관**). **단 sshd 22 는 안 뜸.**
- [ ] **SSH 복구는 보류**: 원인 확정(`/etc/ssh/ssh_host_*_key` 0바이트 → sshd `no hostkeys` 즉사, rc-update 문제 아님). Web Console은 복붙이 불편해 제품화 경로로 부적합. 이전 성공 경로는 `/tmp/hk` 우회 sshd였고 리부트 소실. **0.9.8 표준 sshd 영구수리는 하지 말고 OS/펌웨어 업데이트 후 새 이미지에서 SSH 상태 재평가.** CLI가 꼭 필요할 때만 임시 우회 sshd를 재현.
- [ ] `smhub-buzzer-daemon=crashed`: sshd 와 같은 "started 인데 프로세스 죽음" 패턴(OpenRC started 불신). pwmchip0 접근 실패 추정, 보류.
- [ ] MQTT pub/sub 왕복 = **strict 무변형 아님**(broker publish) → retained SUB 만 하거나 unique·retain=false·QoS0 smoke 로 분리 표기.
- [ ] 벤더 매뉴얼 **②A Update/Restore Methods + External SSH** 검토 → OTA/백업 게이트 절차 정본화(`SMHUB.md §7`). **← OTA 진짜 blocker.**

## Phase B. 버전업 = OTA beta5/0.9.9 (operator go 게이트) — **다음 첫 행동**
백업·안전 게이트 통과. 표준 SSH 수리보다 **Web UI로 OS/펌웨어 업데이트를 먼저** 진행한다. **되돌릴 수 있게** 단계별로.

- [x] **OTA 직전 최소 preflight 통과**: 블록백업 완료(160M, gzip -t OK), 슬롯 A=0.9.8 good 롤백 보존, B=빈 슬롯 타깃. 벤더 매뉴얼 ②A(Update/Restore + External SSH) WebFetch 검토 완료 — OTA=`Settings→Updates & Restore→Check for Updates`(data/settings 보존, 정상부팅 시만). A/B·RAUC·롤백은 매뉴얼 미문서화 → 우리 백업이 정본.
- [x] **OTA로 `1.0.0.beta5` 부팅 성공 (2026-07-01, operator go)**. 부팅 슬롯 B 확인 + 서비스 상태 = **Web UI 확인 대기**(operator).
- [x] **SSH 접속 확보**: Web UI Security엔 SSH 토글 없음(beta 빌드), 정식 셸=`Settings→Console`. 실제 접속은 **`/tmp/hk` 우회 sshd**(:22)로 열렸고 에이전트가 `.sshkey/id_ed25519` 키인증으로 붙음(authorized_keys OTA 지속). **beta5도 표준 host key 0바이트·sshd crashed = EEPROM 지속 가설 반증**(§3.6).
- [x] **beta5 post-capture 완료** → `captures/smhub-beta5-live-20260701T171429+0900/logs/{beta5-postcapture.txt, mg24-bridge-info.txt}` + `docs/SMHUB.md §5.4`. **C906L remoteproc running + smhub-rtos.elf + rpmsg 2채널(esphome-rpc/smhub-rpc) + broker 소켓 + FreeRTOS/ESPHome 2026.5.3/open-amp** 라이브 확정. p7=ext4(F2FS 아님), zram 512M, /etc rw overlay, 커널 REMOTEPROC/RPMSG/MAILBOX 활성, riscv64 재확인.
- [x] beta5 앱/커널 재현값: `opkg list-installed`(esphome-bin·smhub-broker·smhub-ui·smhub-services·z2m 2.10.1·nodered·py3.14) + config.gz 마커 확보. **남음**: DTB 분해(`/sys/firmware/fdt`, sudo).
- [ ] MG24: `bridge/info` 라이브(ember 펌웨어/`ezsp version` — mosquitto 인증 경로 필요, retained SUB 빈값) · 코디네이터 `.gbl` 경로.

## Phase B+. 벤더 앱 배선 **학습 레인** — "smhub가 어떻게 하는지 배운다" (설치 없이, read-only)

목표: 우리가 재현할 4개 컴포넌트를 **설치하지 않고** 배선을 역설계해 배운다. 설치된 것=live 파일 직독,
미설치=feed에서 **ipk read-only fetch → `ar x`/tar 추출**(gitignored captures) → init/config/포트/의존 문서화 → 선언적 재현.
버전 pin 필수. **클릭 설치 금지, 설치는 GLG go 게이트.** 근거 `docs/SMHUB.md §5.2/§5.4/§9`.

- [ ] **smhub-broker (설치됨) — 최우선, homeagentd의 원본**: core↔core 통신 + HW 접근 위임. 이미 확보: init `depend needs remoteproc`,
  `--ble-throttle` + `/opt/firmware/bluetooth_proxy_mode`→`--ble-mode` seam, 소켓 `/run/smhub-broker.sock`. **남음**: `remoteproc` OpenRC
  서비스 스크립트 직독(C906L 부팅 계약 = `echo start/stop > remoteproc0/state` + firmware load), broker strings 전체(RpmsgTransport ABI, `smhub-rpc`/`esphome-rpc` 엔드포인트), `opkg files smhub-broker` 파일맵. → homeagentd가 대체/공존할 계약 확정.
- [ ] **nodered (설치됨) — 필수 로직 레인 후보**: flow 엔진. 직독 `/etc/init.d/nodered`(520B), `/opt/nodered`, 포트/settings.js,
  backend.db appsettings 연동, z2m/MQTT 플로우 연결점. → 우리 자동화 로직을 nodered flow로 태울지 판단.
- [ ] **matterbridge 계열 (미설치) — 확실히 pin, Matter-over-IP 노출축**: **matterbridge 3.5.5-2**(Depends nodejs) +
  **matterbridge-z2m 3.0.6-1**(Depends matterbridge>=3.5.0) + matterbridge-hass 1.0.5-1 + matterbridge-shelly 2.2.30-1.
  ipk read-only 추출로 배선 학습(init/config/포트, z2m→matterbridge-z2m→Matter fabric 연동, `@matter/*` 실제 버전). → Matter 레인 재현 설계.
- [ ] **picoclaw / picoclaw-core 0.2.8-2 (미설치) — on-device AI agent(🦀)**: HomeAgent 비전 정렬. ipk 추출로 구조/실행모델/의존 파악(무엇을, 어디서, 어떤 권한으로 도는지). 설치 전 학습만.

## Phase C. 실제 코드 — homeagentd + config-set applier + 종합 테스트 하네스
버전을 못박지 않는다: **applier가 배포 시점 실물에서 backend.db.version/opkg/alembic HEAD를 읽어** 대조.

- [ ] **homeagentd 스켈레톤** (Zig, `riscv64-linux-musl`, root 불필요, user-writable 경로 배포):
  timerfd/epoll monotonic 100ms tick · MQTT health read/write · z2m status read · MG24 presence · watchdog heartbeat.
  (libc/native 의존 회피; system lib 링크 시 Buildroot sysroot/ABI 먼저 확보.)
- [ ] **선언적 config-set applier**: repo 선언 → 실물 적용. backend.db(enabled/start_at_boot/usersettings만) +
  `/opt/zigbee2mqtt/data/configuration.yaml` + `/etc/peripherals/*.conf`. per-unit secret(network key/machine-id)은 건드리지 않음.
  적용 전 실물 read(alembic HEAD 일치 확인) → dry-run diff → apply → verify.
- [ ] **종합 테스트 하네스 (running ≠ working, pass/fail)**: L0 ping → MQTT broker → z2m frontend/bridge_online →
  coordinator serial/ember → 1기기 페어링(report→command ack→restart 생존) → (Matter 설치 시) commissioning → C906L RPMsg round-trip.
  결과 = `captures/…/results.jsonl` + `SMHUB.md §4` 반영. **주의**: 구 GPT 하네스(`tests/smhub_verify/`)는 host 미설정 실패 —
  살릴지/버릴지 먼저 결정(NEXT LEDGER의 "GPT 프레임워크 삭제" 지침과 충돌).
- [ ] 설치 게이트(GLG go): matterbridge/z2m update 등 설치 후 Matter 레인 검수.

## Phase D. Repo docs ARM → RISC-V 정합화 (코드 커밋과 함께)
CHANGELOG history는 손대지 않는다.

- [ ] `runtime/README.md` · `runtime/zig/homeagentd/README.md`: ARM A53 → riscv64 타깃.
- [ ] `AGENTS.md`: runtime baseline ARM A53 잔재 정리.
- [ ] `ROADMAP.md`: ISA lanes 제품 정합 RISC-V 재작성.
- [ ] `bsp/README.md`: arm64 빌드=historical, riscv64 제품 variant 계획 추가.
- [ ] `README.md`/`VERSION.md`: 버전 매트릭스 grounded 후에만.
- [ ] `docs/README.md` "Current Direction" 문단의 ARM Cortex-A53 표현 갱신.

# 결정 대기 (설계, SMHUB.md §9)
- (1) 재현 기판: 벤더 beta5 이미지 커스터마이즈 vs 우리 buildroot(flake.nix).
- (2) 상태 원본: 손 선언 vs **golden 스냅샷**(backend.db+/etc overlay+p7 data+패키지).
- (3) 구 GPT 하네스 `tests/smhub_verify/` 처리(삭제 vs 재활용) — Phase C 전에 결정.

# RECENT

- 2026-07-01: **Apps 카탈로그 read-only 회수 + 재현 정책 확정.** Web UI Apps 설치=`opkg install` (벤더 feed `smhub_core`, per-unit `http_auth` 시크릿→captures(gitignored)/PRIVATE). feed에 다중 버전 공존(matterbridge 3.5.4~3.5.5-2, matterbridge-z2m 2.8.0~3.0.6, zwavejsui 11.15~11.21, openthread 0.3.1-3~5, tailscale, picoclaw) = **"Latest" 클릭=비재현**. **정책: 클릭 설치 금지 → 정확 버전 pin + ipk provenance 기록 → 선언적 applier 설치+verify 또는 소스 bake, GLG go 게이트.** 문서 `SMHUB.md §5.2/§9`. 캡처 `apps-catalog-readonly.txt`(secret 마스킹). 캡처 스크립트 `beta5-postcapture-readonly.sh`=순수 read-only(sh -n OK, mutation 0) 검수 완료.
- 2026-07-01: **beta5 post-capture 완료 — C906L RTOS 스택 라이브 확정.** SSH는 `/tmp/hk` 우회 sshd로 붙음(`.sshkey` 키인증). `remoteproc0` state=running·firmware=smhub-rtos.elf, `/dev/rpmsg{0,1,_ctrl0}`, dmesg rpmsg 채널 `esphome-rpc 0x400`+`smhub-rpc 0x401`, `/run/smhub-broker.sock`(smhub-broker `--ble-mode=hci`, hciattach ttyS4), ELF strings=**C906L RTOS/FreeRTOS/ESPHome 2026.5.3/open-amp `framework-sg2000-rtos`/config `github://smlight-smhub/rtos-config//nano-esphome.yaml@main`**. opkg 정본(esphome-bin·smhub-broker 1.0.3·smhub-services 1.0.4·smhub-ui 1.0.3·z2m 2.10.1). persistence: root=p6 ext4 ro(슬롯 B), **p7=ext4(F2FS 아님, OTA 경로)**, zram0 512M, /etc rw overlay. 커널 REMOTEPROC/RPMSG/MAILBOX/ZRAM/F2FS 활성, riscv64 6.18.17. **EEPROM SSH 지속 가설 반증**(host key 여전히 0바이트). 문서: `SMHUB.md §5.4` 신설 + §3.5/§3.6/§10 정합. 증거 `captures/smhub-beta5-live-20260701T171429+0900/`.
- 2026-07-01: **OTA 완료 — 0.9.8 → `1.0.0.beta5` 부팅 성공** (Web UI Settings→Update and Restore, ~5–20분 스트리밍 설치). 벤더 매뉴얼 ②A(Update/Restore Methods + External SSH) WebFetch 검토 완료. 로컬 release notes(`~/repos/3rd/milkv/smhub-os-release-notes.org`)에서 **beta line 전모 grounded**: beta1=EEPROM SSH keys 지속·F2FS·zRAM·dual-core RTOS 토대·`smhub-web`→`smhub-ui` 개명, beta2=Recovery Console·PicoClaw·MISC fsck, beta3=**ESPHome on RTOS core + `esphome-bin`·`smhub-broker` 사전설치**·BT proxy·OS+App 채널 lockstep. beta5 라이브 도달성 = ping/80 OK, **SSH 22 refused**(Web UI 활성화 필요, EEPROM 키로 지속 기대). 캡처 스크립트 `scripts/beta5-postcapture-readonly.sh` 준비. **다음**: operator가 Web UI로 SSH 켜면 post-capture 실행 → §5.3 C906L ⚠️/❌ 확정.
- 2026-07-01: **리부트 boot-start 실측 + SSH host key 문제 규명.** z2m/services/nginx 는 리부트 후 자동 기동(포트 확정) = OpenRC runlevel 제어축. sshd 는 default 등록됐으나 `/etc/ssh/ssh_host_*_key` **0바이트**로 부팅마다 즉사 → SSH 끊김(로그인키 문제 아님). **OpenRC "started" 불신**(sshd·buzzer 죽어도 started 표시). 이전 성공 접속은 `/tmp/hk` 우회 sshd였고 리부트로 소실. Web UI Console은 복붙이 불편하므로 **0.9.8 sshd 수리 보류, OS/펌웨어 업데이트 우선**. 상세 `SMHUB.md §3.6`.
- 2026-07-01: **SMHub 문서 3종(PRODUCT-CONFIG-MODEL + SMHUB-CONTROL-MAP + SMHUB-MANUAL-REVIEW) → `docs/SMHUB.md` 단일 SSOT로 병합.** 방향을 "버전업 → 실제 코드 → 종합 테스트"로 전환.
- 2026-07-01: **0.9.8 라이브 무변형 실측** V1~V6 + CONTROL-MAP(DT `smlight,nano`, remoteproc/C906L 부재=beta 라인, opkg≠backend.db.version 4층 확정, 커널 config.gz 부분 확보, ember 라이브). 증거 `captures/smhub-verify-20260701T113514+0900/logs/`.
- 2026-07-01: 벤더 매뉴얼 B-6(제네릭 문서, 별도 칩 전제 → Nano 미적용) + C Zigbee2MQTT→HA(2연결 모델, z2m update=설치 게이트) 검토. 결과 `SMHUB.md §2/§7`.
- 2026-06-30: beta5 이미지 정적 추출 → 통제 경계/재현 매트릭스. C906L=RPMsg/remoteproc 표준. 재현 공백 7건=SMLIGHT 연락 후보. 원본 `captures/smhub-beta5-20260630/`(ignored).
- 2026-06-30: SMHub bring-up, factory 0.9.8 캡처, RISC-V 확인. GPT 교정: zRAM 없음, Node-RED 미실행, 카탈로그≠설치.

# LEDGER

- Durable direction: **vendor SMHUB OS unmodified → 검증 → 버전업 → RISC-V Zig `homeagentd` + 선언적 config-set → 종합 테스트.**
- Core naming: big core **C906B** = RISC-V Linux app core; small core **C906L** = RISC-V RTOS coprocessor / mailbox executor.
- Runtime ownership: Linux `homeagentd` owns `HubState`; C906L executes bounded actions (`RADIO_RESET`, `LED_SET`, `WATCHDOG_KICK`).
- Protocol split: Node 생태계 = 프로토콜 무거운 층(Z2M, Matterbridge/matter.js, Node-RED); Zig = tight 하드웨어/상태머신 층.
- 4층 구분 불변: **catalog ≠ installed(opkg) ≠ enabled(backend.db) ≠ running(OpenRC)**. backend.db.version=seed, opkg=설치 진실원.
- **OpenRC "started" 는 진실 아님**: sshd·smhub-buzzer 가 started 표시라도 프로세스 죽어있을 수 있음. 진실원 = `pgrep -x`/`ss :22`/`sshd -t`.
- **접근은 SSH 단일 의존 금지**: Web UI Console(`#/console`, port 80)은 응급 셸이지만 복붙이 불편해 장기 운용면 아님. 필요 시 `/tmp/hk` 우회 sshd를 임시 재현. 표준 SSH = `.sshkey`(client authorized_keys) + host key(server, /etc/ssh, overlay p7) 둘 다 필요.
- 코드는 Claude가 짓고 GPT엔 검수만. THP23 parked(128MB 하한 증거). secrets/private 좌표 공개 파일 금지.
