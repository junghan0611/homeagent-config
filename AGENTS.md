# HomeAgent Config - Agent Instructions

@README.md
@OFFICE.md (private)

## 방향 — 1주일 뒤에도 변하지 않을 기준

HomeAgent는 **미니멀 스펙 오픈소스 hub BSP** 리포다. 목표는 닫힌 상용 허브를 공개 Buildroot/Linux 이미지, 온보드 EFR32 라디오, Matter/Zigbee 서비스로 재현 가능하게 여는 것이다.

RPi5 + Yocto + Hailo 작업은 삭제하지 않는다. 그것은 Matter/Thread, matter.js, Go controller, Flutter, Hailo/sLLM을 검증한 **high-spec origin lane**이다. 현재 제품 크기의 중심은 **SG2000 / SMHUB Nano / Milk-V Duo S / 512MB / onboard EFR32** 쪽이다.

**런타임 중심축 (2026-06-23)**: SG2000/Duo S는 **ARM Cortex-A53 boot lane으로 고정**(RISC-V 아님). 그 위에 **Zig 100ms 상태머신 `homeagentd`**, 그 아래에 **C906 FreeRTOS mailbox 코프로세서**를 둔다. 공개 쇼케이스 베이스는 이 **ARM Linux ↔ C906 mailbox 연동**이다. Tuya THP23-ZB-X는 능동 작업이 아니라 **128MB 하한 증거로만 보존**한다. 상세: `runtime/README.md`.

살아있는 문서 세트는 `README.md`, `AGENTS.md`, `NEXT.md`, `CHANGELOG.md`, `ROADMAP.md`다. 장비·버전·스택 상태는 `VERSION.md`로 합친다. br/beads는 폐기되었고 다시 도입하지 않는다.

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
| `runtime/README.md` | SG2000 runtime architecture (ARM boot, L0–L4, Zig + C906); front-door for `runtime/` code |
| `docs/TARGET_DEVICE.md` | board/radio strategy details |
| `docs/README.md` | docs map |

If a detail will go stale quickly, keep it out of `AGENTS.md`. Put it in `NEXT.md` while active, or `VERSION.md` / `CHANGELOG.md` when it becomes state/history.

---

## Current Work Bias

Prefer work that strengthens:

- Buildroot / BSP bring-up for SG2000-class hubs on the **ARM A53 boot lane**.
- The **ARM Linux ↔ C906 FreeRTOS mailbox base** as a clean, readable public reference.
- Zig 100ms `homeagentd` state machine (timerfd/epoll, bounded transitions).
- Onboard EFR32 detection, reset, bootloader, and firmware switching.
- Zigbee NCP or Thread RCP proof on one radio, one protocol at a time.
- 512MB lower-bound evidence for MQTT, Zigbee2MQTT, matter.js, and Go.
- Clear boundary between hub and ESP32 edge nodes.

Defer unless explicitly requested:

- Active Tuya THP23-ZB-X liberation/bring-up (parked as 128MB evidence).
- Booting SG2000 in RISC-V mode for the hub runtime.
- New high-spec board validation for its own sake.
- Android-specific server deployment expansion.
- OPi5 vendor/RKNN resurrection.
- Hailo benchmark polishing.
- USB-only coordinator productization.

---

## Invariants as Principles

- Own the box: serial console, bootloader/recovery, rootfs, service lifecycle, and radio path must be inspectable.
- Public repo only: no private business logic, secrets, internal production details, or closed firmware blobs.
- Reproducibility over cleverness: prefer a boring image that can be rebuilt and reflashed.
- On-device first: cloud may be a fallback, not a dependency for local control.
- One radio, one protocol: Zigbee and Thread/Matter are firmware-switched unless proven otherwise.
- USB coordinators are proof tools; the target hub has an onboard radio.
- Keep protocol engines and state ownership separated. Go owns hub state; protocol backends do protocol work.
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
