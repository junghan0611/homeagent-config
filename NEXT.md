# NOW — SMHub Nano Mg24: 검증 마무리 → 버전업 → 실제 코드 → 종합 테스트

- **Stem**: 벤더 **SMHUB OS는 무수정**으로 쓰고 제품 기능을 끝까지 검증한 뒤, **버전업(OTA beta5)** 하고
  그 위에 **실제 코드**(RISC-V Zig `homeagentd` 100ms 상태머신 + 선언적 config-set)를 만들어 **종합 테스트**한다.
- **방향 전환 (2026-07-01, GLG)**: 이전 "코드 아직 안 만든다(버전 드리프트 회피)"에서 **"버전업 후 실제 코드로
  종합 테스트"** 로 전환. 버전을 못박지 않기 위해 **배포 시점에 실물에서 값을 읽는 applier + 검수 하네스**로 짓는다.
- **지식 SSOT (단일)**: `docs/SMHUB.md` — HW/라디오/상태모델/라이브 실측/통제경계·재현 매트릭스/정보벽/
  벤더 매뉴얼 검토/열린 설계질문/다음 단계. (구 PRODUCT-CONFIG-MODEL + SMHUB-CONTROL-MAP + SMHUB-MANUAL-REVIEW 병합.)
- **현재 상태**: 출고 **0.9.8** 라이브(Web UI/Console), 블록 백업 완료(`captures/smhub-0.9.8-20260630/`, gitignored),
  V1~V6 + CONTROL-MAP 무변형 실측 완료(`captures/smhub-verify-20260701T113514+0900/logs/`). 아직 OTA 안 함.
  표준 SSH는 host key 0바이트로 부팅 후 죽음(이전 접속은 `/tmp/hk` 우회 sshd였고 리부트로 소실). **0.9.8 sshd 영구수리보다 OS/펌웨어 업데이트를 먼저 한다.**
  복구 이미지 beta5 + 0.9.9 sha256 검증됨. live 좌표/키는 `PRIVATE.md`만.
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

- [ ] **OTA 직전 최소 preflight**(가능한 범위만, SSH 불요): Web UI가 현재 0.9.8/A 슬롯임을 확인하고, 기존 블록백업/RAUC 백업 요약(`captures/smhub-0.9.8-20260630/BACKUP-SUMMARY.md`)을 다시 읽는다. CLI preflight(`rauc status`, `fw_printenv`, sha256)는 SSH/우회가 열릴 때만 수행.
- [ ] Web UI OTA로 **beta5 또는 0.9.9** 부팅(B 슬롯 기록, A=0.9.8 롤백 보존). 부팅 후 Web UI에서 버전/슬롯/서비스 상태 확인.
- [ ] **beta5 post-capture (라이브)**: C906L 등장 확인 — `/sys/class/remoteproc/remoteproc0/{name,state,firmware}`,
  `/dev/rpmsg*`, `dmesg | grep -iE 'remoteproc|rpmsg|c906|rtos|esphome|broker'`, `/opt/firmware/smhub-rtos.elf`,
  `/var/run/smhub-broker.sock`. → `SMHUB.md §5.3` ⚠️/❌ 확정.
- [ ] beta5 앱/커널 재현값: `opkg list-installed` 전체, 모든 앱 `package.json`, `/proc/config.gz`, DTB 분해.
- [ ] MG24: `ezsp version`(EmberZNet/Gecko 빌드), 코디네이터 `.gbl` 경로.

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
