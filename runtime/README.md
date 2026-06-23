# HomeAgent Runtime Stratification — ARM Linux + Zig state machine + C906 coprocessor

This document is the **architecture center** for the SG2000 hub lane. It is the
public-portfolio reconstruction of a hub runtime that was previously built and
shipped as proprietary work: a deterministic Zig state machine on an embedded
SigmaStar-class platform. The production repository is closed; the *architecture
idea* is not. HomeAgent rebuilds that idea in the open.

The showcase target of this lane is a clean, public **ARM Linux ↔ C906 FreeRTOS
mailbox integration base** — not a benchmark, but a readable reference for how a
hub splits its life across an application core and a real-time coprocessor.

> A hub is not a server. A hub is a bounded state machine that keeps remembering:
> "I am the hub. What should happen next?"

---

## Why this lane exists

The earlier strategy treated the in-hand Tuya THP23-ZB-X (SSD202D / 128MB) as the
active bring-up target. That board stays in the repo only as **128MB lower-bound
evidence** — proof that an open Linux hub *can* be liberated at the bottom of the
spec range. It is no longer the active runtime lane.

The active runtime lane is **SG2000-class** (Milk-V Duo S / SMHUB Nano MG24),
where 512MB RAM, eMMC, and a multi-core SoC make a product-shaped hub realistic.

---

## Decision: boot SG2000 in ARM mode

SG2000 / Duo S can boot its big core as **RISC-V (C906) or ARM (Cortex-A53)**.
For HomeAgent the big core is **fixed to ARM A53**.

| Reason | Why ARM A53 wins for this hub |
|--------|-------------------------------|
| Package ecosystem | Node.js, Zigbee2MQTT, Matter, Go, Rust, Zig, Python are less awkward on aarch64 |
| Debugging | aarch64 embedded Linux is a well-trodden field path |
| Portability | connects cleanly to the RPi5/OPi5 high-spec origin lane |
| Tooling | Matter/Thread/Zigbee surrounding tools are more realistic on ARM |
| Portfolio read | "product-shaped ARM Linux hub", not "rare-ISA experiment" |

RISC-V is interesting, but the center of this portfolio is **product-shaped local
hub optimization**, not exotic-ISA novelty. The C906 cores still matter — just as
the **real-time / always-on layer below Linux**, not as the application head.

How ARM boot is selected and verified (from the Milk-V docs):

- **Build**: SDK V2 supports both cores (recommended for Duo S). Pick an **`arm64`
  board config** in `build.sh` (board names carry `-arm64-`, e.g. the published
  `milkv-duo256m-glibc-arm64-sd`); Docker build is recommended.
- **Physical switch**: Duo S selects RISC-V vs ARM with an **on-board switch** — it must
  match the firmware, or the board will not boot.
- **Verify**: the **first line of the boot log** starts with `B` for the ARM core and
  `C` for the RISC-V core. Phase 0 success = a `B` boot log.

RISC-V is not dismissed — it is kept as a **future open-ISA comparison lane**, because the
same SoC opens it for the price of a boot switch and a second rootfs. ARM gives open
software on a licensed ISA; the RISC-V option closes the **"open all the way down"** loop
(open ISA → open bootloader → open kernel → open runtime → open A2A/A2UI agent surface)
that the rest of this project already lives by. Rationale and the roadmap placement are in
[`../ROADMAP.md`](../ROADMAP.md) (*ISA Lanes*). For the product runtime now, ARM is fixed.

---

## Runtime stratification (L0–L4)

The hub is layered onto the SoC's heterogeneous cores instead of being one large
Linux blob.

| Layer | Where it runs | Responsibility |
|-------|---------------|----------------|
| **L4** Agent / orchestration | ARM Linux | HomeAgent policy, local API, logs, cloudless orchestration, garden/agent connection |
| **L3** Application | ARM Cortex-A53 Linux | `homeagentd` (Zig), MQTT, Zigbee2MQTT, Matterbridge / matter.js, update / storage / SSH |
| **L2** Real-time control | C906 FreeRTOS small core | 100ms tick, heartbeat, watchdog, LED/button, radio reset, MG24 bootloader pins |
| **L1** Always-on | 8051 RTC domain | sleep/wake, RTC, power state, emergency recovery (future) |
| **L0** Radio | EFR32MG24 | Zigbee NCP **or** Thread RCP, firmware-switched |

The prior production experience maps onto **L3/L2** exactly: a Zig hub state
machine on the application core, with hard real-time edges pushed to a coprocessor.

---

## L3 — the Zig 100ms state machine

The core runtime model is a deterministic hub loop:

```text
I am the hub          = identity
What should I do?     = state transition
wake every 100ms      = cadence / scheduler
assert / emit         = heartbeat / event emission
sleep                 = low-power / bounded loop
```

As a loop on ARM Linux:

```zig
while (true) {
    wait_until_next_tick_or_event();  // timerfd + epoll + monotonic clock

    collect_inputs();                 // MQTT, Zigbee, Matter, radio presence
    advance_state_machines();         // device state table, command queue
    emit_outputs();                   // commands out
    persist_important_edges();        // journal/log
}
```

Rules for this loop:

- **No busy loop.** Use `timerfd`, `epoll`, and a monotonic clock — wake on the
  next tick *or* an event edge, whichever comes first.
- The 100ms tick is a **cadence**, not a polling spin.
- State transitions are **bounded**; a failure surfaces as a bounded error, not an
  infinite wait (matches the repo invariant).
- LLM/agent output is **data to parse**, never code to execute (repo invariant).

First milestone goal for `homeagentd.zig`:

```text
wake every 100ms
I am the hub
is MG24 alive?
is MQTT alive?
is Zigbee2MQTT alive?
what is my state?
if needed, issue a recovery command
```

---

## L2 — the C906 FreeRTOS integration base (the showcase)

This is the part of the lane meant to be a **great public base**: the ARM Linux
application core and the C906 FreeRTOS small core cooperating over the SoC
**mailbox**.

Big core (ARM Linux) does the thinking:

```text
Zigbee / Matter / MQTT state
user commands
network
logs
OTA / update
rule evaluation
```

Small core (C906 FreeRTOS) does short, hard, deterministic work:

```text
100ms heartbeat
LED state patterns
button debounce
watchdog kick
radio reset pin control
MG24 bootloader-entry pin control
Linux-hang detection
fail-safe fallback
```

Wiring:

```text
homeagentd.zig  (ARM Linux, L3)
      │  mailbox commands
      ▼
rtos-agent      (C906 FreeRTOS, L2)
      │  GPIO / reset / LED / watchdog
      ▼
physical hub body
```

Example mailbox command set from L3 → L2:

```text
LED_SET
RADIO_RESET
WATCHDOG_KICK
BUTTON_STATE
HEARTBEAT_QUERY
```

The published base should be **readable and reproducible** over clever: a Linux
app sending mailbox commands to a FreeRTOS coprocessor that owns the real-time
pins. Vendor mailbox examples (big-core Linux app → small-core FreeRTOS LED
control) are the starting reference; HomeAgent shapes them into a hub lifecycle
supervisor.

The C906 side may start in **C** (preserve the official FreeRTOS example
structure first) before any attempt to bring Zig onto the small core.

---

## L1 — 8051 always-on (future)

The 8051 RTC domain is independently powered and stays awake when almost
everything else is asleep: sleep/wake conditions, RTC, power state, emergency
recovery. It is the hub's autonomic nervous system.

It is **too low to host the application** and is deliberately deferred. Early
portfolio value is fully carried by **ARM A53 + C906 + MG24**; 8051 is documented
as a future recovery layer, not a Phase-1 task. Starting point when it is time:
`milkv-duo/duo-8051` (SDCC build; SRAM-mode firmware ≤ 8KB; its own Mailbox IP).

---

## BSP base — Milk-V dev SDK, then diff the SMHUB product

The base is **`milkv-duo/duo-buildroot-sdk-v2` (`develop` branch)**. It carries the
**whole boot chain in one tree** — `fsbl`, `opensbi`, `u-boot-2021.10`, `linux_5.10`,
`ramdisk`, and crucially **`freertos`** for the C906 small core (the L2 mailbox base
starts here). We boot the **Milk-V Duo S dev board** from the bootloader up on this SDK
first, in ARM A53 mode.

Both boards were bought: **Milk-V Duo S (dev)** and **SMHUB Nano MG24 (product)**. The
SMHUB Nano is a Duo S / SG2000 product, but SMLIGHT does **not** ship the vendor SDK as
is — they run a **separate, more mainline product Buildroot set**. From the SMHUB-OS
release notes:

| Layer | Milk-V dev SDK (`duo-buildroot-sdk-v2` develop) | SMHUB Nano product (SMLIGHT) |
|-------|--------------------------------------------------|-------------------------------|
| Kernel | linux **5.10** (vendor/cvitek) | linux **6.18** (was vendor 5.4.x) |
| Bootloader | u-boot **2021.10** + opensbi + fsbl (vendor) | mainline **OpenSBI 1.8 + U-Boot 2026.04** |
| Buildroot | SDK-bundled | **2025.11.x** |
| Tuning | — | F2FS (eMMC), zRAM, BFG scheduler, HW crypto (AES/SHA256), HW RNG, ds1307 RTC, opkg, OTA kernel flashing, Nano MG24 radio flashing |

Methodology: **build from the dev SDK first** (own the full vendor boot chain incl. the
C906 FreeRTOS), **then diff against the SMHUB product** to learn exactly what the vendor
tuned to reach mainline kernel 6.18 + mainline bootloader + Buildroot 2025.11. That diff
is itself portfolio content: "here is what a shipped product changed over the dev SDK."

Reference clones (local, `~/repos/3rd/milkv/`, not vendored into this repo):

| Repo | Role |
|------|------|
| `milkv-duo/duo-buildroot-sdk-v2` (`develop`) | the BSP base — full boot chain + C906 FreeRTOS |
| `milk-v/milkv.io` | Milk-V official docs. Key pages under `docs/duo/getting-started/`: `duos.md` (ARM/RISC-V switch), `boot.md` (L0), `rtoscore.md` (C906 FreeRTOS mailbox, L2), `8051core.md` (L1), `buildroot-sdk.md` (build) |
| `milkv-duo/duo-examples` → `mailbox-test` | concrete big-core-Linux → C906-FreeRTOS mailbox example (L2 starting point) |
| `milkv-duo/duo-8051` | 8051 firmware source (SDCC; L1 starting point) |
| `smlight-tech/slzb-os-scripts` | **L4 reference only** — Berry-language on-device automation API for SLZB/SLZB-OS coordinators, *not* a build system |
| SMHUB-OS release notes (`smhub-os-release-notes.org`) | product version/tuning evidence (the table above) |

## Phased plan (hardware-gated)

Boards are on the way; nothing here requires them until Phase 0.

| Phase | Name | Goal |
|------:|------|------|
| 0 | **ARM boot lane fixed** | Build `duo-buildroot-sdk-v2` (develop) for Duo S in ARM A53 mode; serial boot log, `uname`/arch, eMMC layout, package manager, GPIO/UART/MG24 device visible |
| 1 | **Zig `homeagentd`** | 100ms tick, state table, event queue, MQTT in/out, MG24 presence check, watchdog heartbeat |
| 2 | **C906 mailbox base** | ARM ↔ C906 FreeRTOS mailbox (`LED_SET`/`RADIO_RESET`/`WATCHDOG_KICK`/…) — the public showcase |
| 3 | **8051 always-on** | sleep/wake + RTC + emergency recovery (later) |

Do not pull all of Matter in at Phase 1. Start from the well-understood state
machine, then add the mailbox coprocessor, then radio firmware paths.

---

## Portfolio framing

```text
Prior (proprietary, not public)
  - Zig state-machine Zigbee hub
  - SigmaStar-class platform
  - 100ms cadence
  - shipped to production

THP23-ZB-X (public)
  - SSD202D / 128MB
  - closed commercial gateway, 128MB lower-bound evidence
  - bring-up / NAND / UART discovery proof (parked, not active)

SMHUB Nano MG24 / Milk-V Duo S (public, active)
  - SG2000 / ARM A53 / 512MB / EFR32MG24
  - Zig HomeAgent runtime + C906 FreeRTOS coprocessor base
  - product-shaped minimal open hub
```

One sentence:

> Previously I built and shipped a Zig-based Zigbee hub as a deterministic state
> machine on an embedded SigmaStar-class platform. Because the production
> repository is proprietary, HomeAgent reconstructs the same architecture in
> public: an ARM Linux smart-home hub where a Zig runtime is the 100ms hub state
> machine, while SG2000's C906 FreeRTOS / 8051 cores and the EFR32MG24 radio form
> the lower control, recovery, and radio layers.

See [`../docs/TARGET_DEVICE.md`](../docs/TARGET_DEVICE.md) for board/radio strategy and
[`../docs/THP23-LIBERATION.md`](../docs/THP23-LIBERATION.md) for the parked 128MB-evidence lane.

Code in this folder:

- [`zig/homeagentd/`](zig/homeagentd/) — L3 Zig 100ms hub state machine (SG2000 / Milk-V Duo S / SMHUB Nano only).
- [`c906/rtos-agent/`](c906/rtos-agent/) — L2 C906 FreeRTOS mailbox coprocessor base (the public showcase).
