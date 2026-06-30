# NOW — SMHub Nano Mg24 제품 검수 → RISC-V Zig 런타임

- **Stem**: 벤더 **SMHUB OS는 무수정**으로 쓰고, 제품 기능을 먼저 끝까지 검증한다. 그 결과를 바탕으로 **RISC-V Zig `homeagentd`**(100ms 상태머신)와 C906L mailbox executor를 얹는다.
- **현재 상태 (2026-06-30)**: 출고 OS **0.9.8** 실기 캡처 완료(`captures/smhub-0.9.8-20260630/`, gitignored). 업데이트는 아직 안 함. 복구 이미지 beta5 + 0.9.9는 로컬 캐시에 sha256 검증 완료. live 좌표/SSH 절차/키 경로는 `PRIVATE.md`만 본다.
- **결정**: 제품 레인은 **RISC-V 락**. SMHUB OS가 riscv64 실측이므로 on-product Zig `homeagentd`도 `riscv64-linux-*` 타깃. 구 “ARM A53 고정”은 폐기하고, 남은 문서의 ARM 잔재는 다음 세션에서 정리한다.
- **검증 순서**: ① 0.9.8 비파괴 확인 + 백업 → ② OTA beta5 → ③ beta5 post-capture(C906L/ESPHome/remoteproc) → ④ **Zigbee 먼저**(Z2M + MQTT + 1기기 페어링) → ⑤ **Matter/Thread**(OTBR + Matterbridge/matter.js) → ⑥ `homeagentd` 스켈레톤.
- **다음 세션 첫 행동 (Opus 권장, 브라우저 admin 대시보드 사용)**: 업데이트하지 말고 먼저 `rauc status --detailed`/`/etc/rauc/system.conf`/`fw_printenv` 확인 후 0.9.8 최소 `dd` 백업을 뜬다. 그 다음에만 Web UI OTA beta5.
- **Do not touch**: Type-C full flash를 OTA보다 먼저 하지 말 것(A/B rollback 전제 깨짐). live IP/MAC/SSH 키/기기 좌표를 공개 파일에 쓰지 말 것. “service running”을 “working”으로 판정하지 말 것.

# ACTIVE

## 0. Mutate 전 안전 게이트 — 0.9.8 보존

목표: 정확한 출고 0.9.8 이미지는 manifest에서 다시 받을 수 없으므로, OTA 전에 슬롯/RAUC 상태와 최소 백업을 확보한다.

- [ ] `rauc status --detailed` 및 가능하면 JSON 출력 저장.
- [ ] `/etc/rauc/system.conf`, `/mnt/misc/rauc`, `fw_printenv BOOT_ORDER BOOT_A_LEFT BOOT_B_LEFT rauc_slot active_boot_slot root_uuid rootfs0_uuid rootfs1_uuid slot_num` 저장.
- [ ] 최소 백업: `mmcblk0boot0/1`, `p1 KERNEL0`, `p5 ROOTFS0`, `p3 ENV`, `p4 MISC`, `etc-overlay.img`, Z2M coordinator/network key/configuration backup.
- [ ] `collect.sh` 보강: RAUC, `/etc/opkg/*`, app catalog, `/opt/*/package.json`, `/var/log`, HCI/btmgmt, remoteproc/rpmsg/mailbox, zram/F2FS 항목 추가.
- [ ] 백업 후 **OTA beta5**(Web UI) 진행. Type-C full `emmc.img` flash는 rollback 검증 뒤.

## 1. 통제 경계 + 재현 세트 매트릭스 — ✅ 1차 산출 (2026-06-30, beta5 이미지 정적 추출)

**SSOT = `docs/SMHUB-CONTROL-MAP.md`** (tracked). 각 컴포넌트를 **repo + commit/version +
벤더 diff** 기준으로 재현 가능성(✅완전/⚠️부분/❌불가) 평가. "없으면 없다"고 명시해 다음
세션이 공백 때문에 헤매지 않게 함. 원본 아티팩트는 `captures/smhub-beta5-20260630/`
(git-ignored; 이미지/zip에 벤더 feed 크레덴셜 포함 → **절대 stage 금지**).

확정된 핵심 버전(beta5): Node `22.22.0` · z2m `2.10.1`(herdsman `10.0.7`/converters
`26.46.0`) · esphome `2026.5.3` · smhub-broker `1.0.3` · 커널 `6.18.17` · Buildroot
`2026.02-18` · 카탈로그 matterbridge `3.5.5`/OTBR `0.3.1-5`/zwavejsui `11.19.0`.

- ✅ **완전 재현**: node + z2m/herdsman/converters/frontend — 공개 OSS, z2m는
  `pnpm-lock.yaml`까지 확보.
- ⚠️ **설치 후 확인**: matterbridge/OTBR/zwavejs — 카탈로그 버전은 확보했지만 미설치라
  lock/내부 commit/native 의존은 live install 뒤 확정.
- ⚠️ **부분**: 베이스 OS(부트/커널/rootfs) — upstream(`sophgo/bootloader-riscv`,
  `milkv-duo/duo-buildroot-sdk-v2`, buildroot, mainline 6.18) 공개나 벤더 defconfig/.config/
  DT diff 비공개. C906L RTOS ELF(esphome+벤더 컴포넌트), smhub-services(Python 평문).
- ❌ **불가(바이너리만)**: smhub-broker/rtos-logger/rtos-notify 소스, 벤더 ESPHome 컴포넌트
  (`sg2000_*`/`smhub_*`), MG24 `.gbl` 펌웨어, matter.js 정확 버전.
- **C906L 통신 = 표준 RPMsg/remoteproc**(`/dev/rpmsg*`, `remoteproc0/state`,
  `/opt/firmware/smhub-rtos.elf` 슬롯) → 비밀 mailbox 아님, 우리 homeagentd/Zig RTOS로
  끼어들기·교체 가능.
- **다음(라이브 beta5에서 확정)**: §5 of CONTROL-MAP — remoteproc/rpmsg 라이브, 커널
  `.config`/DTB, `ezsp version`(MG24 EmberZNet/Gecko), matterbridge 설치 후 `@matter/*`.
- **재현 공백 7건 = SMLIGHT 연락 후보** (CONTROL-MAP §4): Buildroot defconfig + 커널
  config/DT diff + MG24 펌웨어 버전 등. 오픈소스 hub 검증 협업 명분으로 직접 요청 가능.

Known corrections (GPT review, 0.9.8 기준 유지):
- 0.9.8엔 **zRAM/swap 없음**(`SwapTotal=0`). beta5 fstab엔 `/dev/zram0 swap` 존재 — 라인별 차이.
- 0.9.8 `node.real :8080` = **Zigbee2MQTT**(Node-RED 아님, 미실행).
- matterbridge/OTBR/zwavejs는 **카탈로그 사실**, 설치 사실 아님(0.9.8·beta5 공장 시드 둘 다 미설치).
- beta5 **fastboot 이미지(raw 2.02GiB) ≠ 라이브 7.6GB eMMC**. p6 ROOTFS1 비어있음, USER 첫부팅 resize.

## 2. Product verification — running ≠ working

Make `docs/PRODUCT-VERIFY.md` as a pass/fail table. Each row should include: source/manual, observed version, command/browser proof, expected Event, expected Action, pass/fail, log path.

### Zigbee first

- [ ] MQTT broker: `mqtt_broker_listening`, `mqtt_pubsub_ok`, auth/bridge behavior.
- [ ] Z2M: `z2m_process_started`, `z2m_frontend_ready`, `z2m_bridge_online`, `coordinator_serial_opened`, `radio_mode_zigbee`.
- [ ] Pairing: permit join → one Zigbee device joined → report received → command ack → state survives restart.
- [ ] Firmware/backup: MG24 coordinator firmware version, IEEE/EUI64, network key, Z2M coordinator backup.

### Then Matter / Thread

- [ ] OTBR: Thread RCP firmware flash, `otbr_agent_running`, active dataset, border router advertised, NAT64/firewall status.
- [ ] Matterbridge/matter.js: install, start, mDNS advertise, commissioning, plugin load, Matter command → Zigbee command ack.
- [ ] Node.js native risk: find `.node` addons/prebuilds, verify riscv64 ABI, mDNS/Avahi/IPv6/crypto behavior.

### C906L / ESPHome after beta5

- [ ] `remoteproc0_present`, firmware name/state, dmesg remoteproc/rpmsg/mailbox.
- [ ] `smhub-broker_socket_ready`, ESPHome RTOS firmware path, RTOS restart works.
- [ ] BLE proxy native mode: host `bluetoothd` conflict behavior and 16-connection claim.
- [ ] Treat C906L as **Action executor**, not state owner. Linux `homeagentd` owns HubState.

## 3. RISC-V `homeagentd` lane

- **개발보드 = Milk-V Duo S** (= SG2000, SMHub 형제; SMHub은 Duo S급 SG2000 베이스 + MG24). SoC·BSP·
  C906L·RPMsg가 동일하므로 **L2 mailbox + L3 Zig homeagentd를 제품 검수와 병렬로 Duo S에서
  선행 개발** 가능. MG24 Zigbee/Thread만 SMHub 실기 또는 USB 동글. → `docs/SMHUB-CONTROL-MAP.md` §0.
- [ ] Build pure Zig smoke binary for `riscv64-linux-musl` first; deploy under user-writable path and run without root.
- [ ] Skeleton: timerfd/epoll/monotonic 100ms tick, MQTT health read/write, Z2M status read, MG24 presence, watchdog heartbeat.
- [ ] Avoid libc/native deps until sysroot is known. If linking to system libs, capture Buildroot sysroot/ABI first.
- [ ] C906L Zig/freestanding is **not first**. First reverse beta5 vendor `remoteproc` + `smhub-broker` + `esphome-bin` ELF loading and mailbox ABI.

## 4. Repo docs punch-list — ARM → RISC-V 정합화

Do this before or with the next code/doc commit, but keep CHANGELOG history untouched.

- [ ] `runtime/README.md`: title/Decision/rationale/phase text still says ARM A53.
- [ ] `AGENTS.md`: current work bias and runtime baseline still mention ARM A53.
- [ ] `ROADMAP.md`: ISA lanes / ARM-vs-RISC-V sections need product-aligned RISC-V rewrite.
- [ ] `runtime/zig/homeagentd/README.md`: aarch64 target → riscv64 target.
- [ ] `bsp/README.md`: current arm64 board build is historical; add riscv64 product variant plan.
- [ ] `README.md`/`VERSION.md`: update only after version matrix is grounded.

# RECENT

- 2026-06-30: **beta5 이미지 정적 추출 → 통제 경계/재현 세트 매트릭스 `docs/SMHUB-CONTROL-MAP.md` 신설(tracked)**. fastboot zip → simg2img → 파티션 분리 → ext4 debugfs + F2FS mount(-ro)로 소스 없이 버전·repo·재현가능성 확정. 원본은 `captures/smhub-beta5-20260630/`(ignored, GPT 정리 + Opus 검수). C906L=RPMsg/remoteproc 표준 확인. 재현 공백 7건 = SMLIGHT 연락 후보로 명시. (uncommitted — GLG push; docs/만 tracked, captures/는 ignored)
- 2026-06-30: SMHub Nano Mg24 bring-up. Factory 0.9.8 captured locally; `captures/` added to `.gitignore`. RISC-V confirmed from device (`riscv64`, `thead,c906`) and beta image strings (OpenSBI/riscv). No OS update yet.
- 2026-06-30: GPT adversarial review corrected the handoff: zRAM absent on 0.9.8, Node-RED not running, app catalog ≠ installed apps, `/etc/ssh` writeability unproven, A/B rollback needs `dd` backup before mutation.
- 2026-06-23: `v2026.6.23` cut — SG2000 runtime pivot, C906L/C906B naming, buildroot SDK Docker path. Historical ARM image build remains as origin evidence, not the current product lane.

# LEDGER

- Durable direction: **vendor SMHUB OS unmodified → full product verification → RISC-V Zig `homeagentd`**.
- Core naming: big core **C906B** = product-aligned RISC-V Linux app core; small core **C906L** = RISC-V RTOS coprocessor / mailbox executor.
- Runtime ownership: Linux `homeagentd` owns `HubState`; C906L executes bounded actions (`RADIO_RESET`, `LED_SET`, `WATCHDOG_KICK`, etc.).
- Protocol split: keep Node ecosystem for protocol-heavy layers (Z2M, Matterbridge/matter.js, Node-RED); use Zig for tight hardware/state-machine layer.
- THP23 remains parked as 128MB lower-bound evidence. br/beads, Android/python-matter-server resurrection, secrets/private coordinates in public files remain forbidden.
