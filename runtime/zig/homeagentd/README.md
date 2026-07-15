# homeagentd — L3 Zig hub state machine

**Scope (fixed): SG2000-class only — Milk-V Duo S / SMHUB Nano MG24, RISC-V C906 boot (`riscv64-linux-musl`).**
This is the one runtime we push forward. It is not a portable abstraction over every
board; it is the deterministic hub loop for this hardware lane. Architecture context:
[`../../README.md`](../../README.md).

`homeagentd` is the L3 application-core runtime: a Zig process on RISC-V C906 Linux that wakes
on a fixed cadence or event edge, reasserts hub identity, observes radio / network /
device state, advances bounded state transitions, emits commands, and returns to idle.

> I am the hub. What should happen next?

## First milestone

```text
wake every 100ms (or on an event edge)
I am the hub
is MG24 alive?
is MQTT alive?
is Zigbee2MQTT alive?
what is my state?
if needed, issue a recovery command
```

## Loop shape

```zig
while (true) {
    wait_until_next_tick_or_event();  // timerfd + epoll + monotonic clock, never a busy loop

    collect_inputs();                 // MQTT, Zigbee, Matter events, radio presence
    advance_state_machines();         // device state table, command queue
    emit_outputs();                   // commands out
    persist_important_edges();        // journal/log
}
```

Rules (inherited from repo invariants):

- No busy loop — wake on the next tick *or* an event edge, whichever is first.
- The 100ms tick is a cadence, not a polling spin.
- State transitions are bounded; failure surfaces as a bounded error, not an infinite wait.
- LLM/agent output is data to parse, never code to execute.

## Planned layout

```text
homeagentd/
  README.md          this file
  build.zig          (TODO) pin Zig toolchain + aarch64-linux target
  src/
    main.zig         (TODO) 100ms tick loop entry
    tick.zig         (TODO) timerfd/epoll cadence
    state.zig        (TODO) device state table + bounded transitions
    mqtt.zig         (TODO) MQTT in/out
    radio.zig        (TODO) MG24 presence check
    mailbox.zig      (TODO) L2 C906 mailbox client (see ../../c906/rtos-agent)
```

## Board-less prep (do now)

- [ ] Pin Zig version + `aarch64-linux` cross-build target in `build.zig`.
- [ ] Decide the cadence primitive (`timerfd` + `epoll`) and write `tick.zig` against it.
- [ ] Define the device-state table shape and the bounded transition contract.
- [ ] Specify the mailbox command set shared with `../../c906/rtos-agent`.

Hardware-gated work (Phase 0+) starts when a Duo S / SMHUB board boots in ARM mode.
