# rtos-agent — L2 C906 FreeRTOS mailbox base (public showcase)

**Scope (fixed): SG2000-class only — Milk-V Duo S / SMHUB Nano MG24.**
Architecture context: [`../../README.md`](../../README.md).

This is the part of the lane meant to be a clean, readable **public base**: the ARM
Linux application core (`../../zig/homeagentd`) and the C906 FreeRTOS small core
cooperating over the SoC **mailbox**. The goal is reproducible and readable, not clever.

## Split of work

Big core (ARM Linux, L3) does the thinking; small core (C906 FreeRTOS, L2) does short,
hard, deterministic work:

```text
homeagentd (ARM Linux, L3)
      │  mailbox commands
      ▼
rtos-agent (C906 FreeRTOS, L2)
      │  GPIO / reset / LED / watchdog
      ▼
physical hub body
```

C906 responsibilities:

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

## Mailbox command set (L3 → L2)

```text
LED_SET
RADIO_RESET
WATCHDOG_KICK
BUTTON_STATE
HEARTBEAT_QUERY
```

This command set is the shared contract with `../../zig/homeagentd/src/mailbox.zig`.
It extends the vendor `CMD_DUO_LED` / `param_ptr` pattern from the mailbox example.

**Frame constraint (from Milk-V docs):** the command queue unit (`cmdqu`) is **8 bytes**
— the mailbox buffer size. Keep each message within that frame.

## Approach

- Start from the FreeRTOS tree already in the BSP base: **`duo-buildroot-sdk-v2/freertos`**
  (develop branch), and the working **`milkv-duo/duo-examples` → `mailbox-test`** example
  (big-core Linux app → mailbox driver → C906 FreeRTOS toggles the LED). Docs:
  `milkv.io/docs/duo/getting-started/rtoscore.md`. Preserve their structure first.
- The C906 side may start in **C** before any attempt to bring Zig onto the small core.
- Shape the vendor example into a **hub lifecycle supervisor**, not a demo.
- Note: the stock firmware blinks the LED from a big-core boot script; disable it before
  testing the mailbox path (per `rtoscore.md`).

## Board-less prep (do now)

- [ ] Collect the official SG2000/Duo S mailbox example + FreeRTOS small-core docs (links into `../../README.md`).
- [ ] Freeze the mailbox command set and message framing (shared with homeagentd).
- [ ] Sketch the C906 main loop: heartbeat + watchdog + mailbox command dispatch.

Hardware-gated bring-up starts when a Duo S / SMHUB board is in hand.
