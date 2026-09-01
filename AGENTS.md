# HomeAgent Config - Agent Instructions

@README.md
@OFFICE.md (private)

## 방향 — 1주일 뒤에도 변하지 않을 기준

HomeAgent는 **미니멀 스펙 오픈소스 hub BSP** 리포다. 목표는 닫힌 상용 허브를 공개 Buildroot/Linux 이미지, 온보드 EFR32 라디오, Matter/Zigbee 서비스로 재현 가능하게 여는 것이다.

RPi5 + Yocto + Hailo 작업은 삭제하지 않는다. 그것은 Matter/Thread, matter.js, Go controller, Flutter, Hailo/sLLM을 검증한 **high-spec origin lane**이다. 현재 제품 크기의 중심은 **SG2000 / SMHUB Nano / Milk-V Duo S / 512MB / onboard EFR32** 쪽이다.

**런타임 중심축 (2026-07-15)**: SG2000/Duo S는 **RISC-V C906 boot lane**(제품 ISA; 런타임 타깃 `riscv64-linux-musl`, 2026-07-14 실기 부팅 확인). 그 위에 **Zig 100ms 상태머신 `homeagentd`**, 그 아래에 **C906L FreeRTOS mailbox 코프로세서**를 둔다. 공개 쇼케이스 베이스는 이 **RISC-V Linux ↔ C906L mailbox 연동**이다. arm64 빌드는 historical(제품 아님). Tuya THP23-ZB-X는 능동 작업이 아니라 **128MB 하한 증거로만 보존**한다. 상세: `runtime/README.md`.

살아있는 문서 세트는 `README.md`, `AGENTS.md`, `NEXT.md`, `CHANGELOG.md`, `ROADMAP.md`다. 장비·버전·스택 상태는 `VERSION.md`로 합친다. br/beads는 폐기되었고 다시 도입하지 않는다.

---

## 현재 방향 & 연결고리 (2026-07-15)

**북극성**: 커스텀 Buildroot로 **샘플 허브 + 앱 + 서버를 통으로 패키징**해 전 기능 동작을 공개 증명하는
**제품화 틀**. SMHub는 참고(버전/설치면)일 뿐, 우리 Buildroot를 소유한다. **비즈니스 로직 없음.**

| 무엇을 보나 | 어디 |
|---|---|
| 다음에 뭘 할지 (실작업 핸드오프) | `NEXT.md` → **Phase F** |
| 왜 / 방향 / 제품화 틀 (North star, 페이즈 그리드) | `ROADMAP.md` |
| Buildroot 경험·전략 / 운영 how-to | `docs/BUILDROOT.md` / `bsp/README.md` |
| SMHub 실측 버전·설치면 (참고 근거, 벤더 비공개분 포함 좌표) | `docs/SMHUB.md` |
| Duo S 라디오 펌웨어 (보드 정렬 7.4.2) | `firmware/zbdonglee/` |
| 런타임 아키텍처 (Zig `homeagentd` + C906L 메일박스) | `runtime/README.md` |
| 라이브 좌표 / 계정 / 키 | `PRIVATE.md` (공개 파일엔 금지) |

작업 규칙: SDK는 `~/repos/3rd/milkv/duo-buildroot-sdk-v2` — `junghan0611/duo-buildroot-sdk-v2`
`feat/riscv64-nodejs-pure-cross`의 pin `087547cf8`을 쓴다(upstream base `ad920f839`). 제품 설정은
계속 `bsp/`의 defconfig+overlay로 소유하고, SDK 공통 Buildroot 수정만 포크 브랜치에서 관리한다.

---

## Stable Role

- `homeagent-config`: hub-level BSP and runtime surface.
- `edgeagent-config`: ESP32 edge nodes and NodeCard producers.
- `legoagent-config`: toy / education / experiment track.

Keep this repo focused on the hub: Linux host, onboard radio, protocol bridge, reproducible image, and recovery path.

---

## Living Docs

| File | Purpose |
|------|---------|
| `README.md` | public landing and thesis |
| `AGENTS.md` | week-stable operating rules only |
| `NEXT.md` | current handoff and next actions |
| `CHANGELOG.md` | closed work, CalVer release notes |
| `ROADMAP.md` | phase direction and open lanes |
| `VERSION.md` | stack, version, physical device matrix |
| `runtime/README.md` | SG2000 runtime architecture (RISC-V C906 boot, L0–L4, Zig + C906L); front-door for `runtime/` code |
| `docs/BUILDROOT.md` / `bsp/README.md` | 커스텀 Buildroot 코어 레인 — 경험·전략 / 운영 how-to (제품화 틀의 실제 빌드면) |
| `docs/SMHUB.md` | SMHub Nano 실측 SSOT — HW/라디오/설치면/버전 (제품이 뭘 깔아주나의 참고 근거) |
| `docs/TARGET_DEVICE.md` | board/radio strategy details |
| `docs/HUBS.md` | 인증 Zigbee/Matter 허브 랜드스케이프 (조사 자료 — 우리 방향 아님), SoC/라디오 비교, 지원 제품군 |
| `docs/MULTIPROTOCOL.md` | 단일 라디오 Zigbee+Thread 동시 — 전략·시점 (MG21/24/26 → Series 3). "언제 단일칩으로 가나" |
| `docs/README.md` | docs map |

If a detail will go stale quickly, keep it out of `AGENTS.md`. Put it in `NEXT.md` while active, or `VERSION.md` / `CHANGELOG.md` when it becomes state/history.

---

## Current Work Bias

Prefer work that strengthens:

- Buildroot / BSP bring-up for SG2000-class hubs on the **RISC-V C906 boot lane**.
- The **RISC-V Linux ↔ C906L FreeRTOS mailbox base** as a clean, readable public reference.
- Zig 100ms `homeagentd` state machine (timerfd/epoll, bounded transitions).
- Onboard EFR32 detection, reset, bootloader, and firmware switching.
- Zigbee NCP or Thread RCP proof on one radio, one protocol at a time.
- 512MB lower-bound evidence for MQTT, Zigbee2MQTT, matter.js, and Go.
- Clear boundary between hub and ESP32 edge nodes.

Defer unless explicitly requested:

- Active Tuya THP23-ZB-X liberation/bring-up (parked as 128MB evidence).
- ARM A53 boot for the hub runtime (RISC-V C906 is the active lane; arm64 is historical).
- New high-spec board validation for its own sake.
- Android-specific server deployment expansion.
- OPi5 vendor/RKNN resurrection.
- Hailo benchmark polishing.
- USB-only coordinator productization.

---

## Invariants as Principles

- **Packing is the deliverable.** 이 리포의 값어치는 기능 목록이 아니라 **저사양에 눌러담는 기술**
  그 자체다. 그래서 "큰 보드에서 되더라"는 결과가 아니고, 판정은 언제나 **"이 등급에 들어가나"**다.
  런타임을 하나 더 들이는 선택은 기능이 아니라 **등급을 한 칸 올리는 비용**으로 계산한다
  (`docs/ECOSYSTEM-PORTFOLIO.md` · `docs/TARGET_DEVICE.md`).
- **재현성은 스택이 아니라 패키징에서 나온다 (GLG 2026-09-01).** *"NixOS로 x86을 하든
  Buildroot로 하든, 패키징을 잘하면 재현 가능한 솔루션이 된다."* 두 타깃은 경쟁이 아니라
  같은 원리의 두 실행이다. 그러므로 판정 기준은 "무엇이 좋은 스택인가"가 아니라
  **"무엇을 재현 가능하게 패키징할 수 있는가"**다.
- **쓰지 않는 예약은 낭비가 아니라 미수금이다.** 벤더 memmap의 멀티미디어 예약(ION/ISP/H26X/
  부트로고)은 헤드리스 허브가 쓰지 않는다. 회수 가능한 값은 회수 대상으로 적어 두고, 모르는 채
  두지 않는다.
- Own the box: serial console, bootloader/recovery, rootfs, service lifecycle, and radio path must be inspectable.
- Public repo only: no private business logic, secrets, internal production details, or closed firmware blobs.
- Reproducibility over cleverness: prefer a boring image that can be rebuilt and reflashed.
- **Downstream maintenance budget:** own Buildroot recipes, defconfigs, overlays, and at most a few small auditable compatibility patches. Do not maintain downstream forks of Node.js, V8, libc, or the toolchain. If the vertical slice requires an expanding source-patch stack or runtime semantic changes, stop, ask upstream, and reconsider the baseline instead of repairing the ecosystem locally.
- On-device first: cloud may be a fallback, not a dependency for local control.
- One radio, one protocol: Zigbee and Thread/Matter are firmware-switched unless proven otherwise. Single-chip **concurrent** is a chip-timing question (MG26 / Series 3), tracked in `docs/MULTIPROTOCOL.md`; now = clean separate-stack control, not concurrency.
- USB coordinators are proof tools; the target hub has an onboard radio.
- Keep protocol engines and state ownership separated. The Zig `homeagentd` runtime owns hub state; protocol backends (Z2M, matter.js) do protocol work. (Go is origin-lane.)
- WebSocket reads must have a single owner/read loop.
- LLM output is data to parse, never code to execute directly.
- UI theme values come from tokens/CSS variables, not component-local literals.
- Runtime failure should surface as a bounded error, not an infinite wait.

---

## No Hype

The value is integration, not claiming commodity parts as inventions.

Say:

- “Buildroot/Linux + EFR32 + Z2M/matter.js integrated into a reproducible hub path.”
- “RPi5/Hailo is a verified origin lane.”
- “512MB is the target to measure, not a proven universal minimum.”

Do not say:

- “first”, “novel”, or “production-ready” without hard evidence.
- “benchmark achieved” as the headline when the work was driver/BSP integration.
- “128MB failed” when the result is simply a lower-bound ceiling.

---

## Git / Release Rules

- Use `NEXT.md` for active handoff. Do not use br/beads.
- Use `CHANGELOG.md` for closed work.
- CalVer tags use `vYYYY.M.D[-suffix]`.
- Agent may prepare commits/tags only when asked. The maintainer decides final push.
- Never bypass git hooks. No `--no-verify`, no hook disabling, no unsafe env override.
- Commit logs stay clean: no AI attribution trailers.

---

## First Read Order

1. `NEXT.md`
2. `README.md`
3. `ROADMAP.md`
4. `runtime/README.md` for the SG2000 runtime (Zig + C906L)
5. `VERSION.md`
6. `docs/TARGET_DEVICE.md` when board/radio details matter
7. `PRIVATE.md`

For code changes, inspect the relevant source and tests directly. Do not rely on stale prose when the code is the source of truth. Zig hub logic lives in `runtime/zig/homeagentd/`; the C906L FreeRTOS mailbox base in `runtime/c906/rtos-agent/` — both SG2000-only (Milk-V Duo S / SMHUB Nano).
