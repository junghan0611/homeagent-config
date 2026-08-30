# Duo S buttons — can a runtime button exist on this board?

**Status: parked 2026-08-30.** Investigated, not acted on. GLG will revisit. Nothing here
changed the image; no board was touched.

The question that opened this: the Duo S has two buttons, and a product wants a
**hold-10-seconds factory reset**. Can we take the recovery button over after boot?

## Answer

No — not the recovery button, and not the reset button either. But the reason matters,
because it is two separate walls and only one of them is about the buttons.

## Wall 1 — this image has no button input path at all

Measured 2026-08-30 against SDK pin `3a50ffe28`:

| fact | where |
|---|---|
| no `gpio-keys` node in any Duo S DTS | `build/boards/cv181x/sg2000_milkv_duos_*/dts_*/*.dts` — 0 hits; the only `gpio-keys` in the SDK are Rockchip reference boards under `linux_5.10/arch/arm64/boot/dts/rockchip/` |
| `CONFIG_KEYBOARD_GPIO` absent | `build/boards/cv181x/sg2000_milkv_duos_glibc_arm64_emmc/linux/cvitek_*_defconfig` — 0 hits. `CONFIG_INPUT_EVDEV=y` is present, but nothing generates the events |

So a perfectly wired button would produce nothing today. This matters when reading a
negative test on the board: finding no change on the GPIOs that happen to be inputs does
not, by itself, say anything about a button — there is no path either way.

## Wall 2 — neither button is on a pin Linux could read

| button | what it is | why it cannot be borrowed |
|---|---|---|
| RST | chip reset | asserts reset in hardware; nothing to read |
| RECOVERY | power-on strap | Milk-V's own procedure is "hold it, **then** plug in" — the mask BootROM samples it at power-on. That ROM is not in this SDK, and the pin is not muxed as a GPIO anywhere in `cvi_board_init.c` |

Empirically consistent (reported from a board session, 2026-08-30): pressing recovery at
runtime does not reset the board and does not appear on the GPIOs the kernel has open.

**And the pin that *should* have been the answer is spent.** SG2000 has a dedicated
power-button pin in the RTC domain, `PWR_BUTTON1`, with hardware long-press support. On
Duo S it is wired to the Ethernet speed LED:

```
build/boards/cv181x/sg2000_milkv_duos_glibc_arm64_emmc/u-boot/cvi_board_init.c:59
        PINMUX_CONFIG(PWR_BUTTON1, EPHY_SPD_LED);
```

All four Duo S variants (arm64/riscv64 × sd/emmc) do the same. It *can* be remuxed —
`PWR_BUTTON1__PWR_GPIO_8 = 3` in `cv181x_pinlist_swconfig.h` — which would land at
**gpio 360** (porte/PWR_GPIO base 352). But the cost is the Ethernet speed LED, and it
does not help here anyway: no button is physically wired to that pin on Duo S.

**Not known:** the RECOVERY button's actual schematic net. That needs the Duo S schematic,
which was not consulted. It does not change the answer — the pin is not muxed as an input
in the board init regardless — but it is the fact to get first if this is reopened.

## GPIO numbering, for whoever picks this up

From the Milk-V Duo S pinout, cross-checked against this SDK's board init:

| chip | port | base | note |
|---|---|---|---|
| gpiochip0 | porta | 480 | XGPIOA |
| gpiochip1 | portb | 448 | XGPIOB |
| gpiochip2 | portc | 416 | XGPIOC |
| gpiochip3 | portd | 384 | |
| gpiochip4 | porte | 352 | PWR_GPIO |

Cross-check that this mapping is right: the onboard LED reads as gpio **509**, and
509 − 480 = XGPIOA[29], which is exactly `PINMUX_CONFIG(IIC0_SDA, XGPIOA_29)` marked
`// LED` in `cvi_board_init.c`.

## If this is reopened

Three routes. The first two are ours; the third is a hardware decision.

1. **Header pin + an external button.** Needs both gaps from Wall 1 closed:
   `CONFIG_KEYBOARD_GPIO=y` and a `gpio-keys` node. The 10-second hold is then ordinary
   userspace `EV_KEY` timing.
2. **No button — app-side `CONTROL.DELETE`.** Zero image change, same user-facing scenario.
3. **Give `PWR_BUTTON1` back to a button on a future board.** Trades the Ethernet speed LED
   and buys the RTC's hardware long-press. Not possible on Duo S as built.

**Cost note for route 1:** both changes live in the **SDK fork**, not in `bsp/` —
`build/boards/cv181x/<board>/linux/cvitek_*_defconfig` and
`build/boards/cv181x/<board>/dts_*/*.dts`. `bsp/build.sh` injects only the board defconfig
and the Buildroot config, so this needs a fork commit plus a `SDK_COMMIT` bump in
`bsp/setup.sh`. NEXT already carries one other fork-pin debt (the wrong CDC-ACM comment in
the kernel defconfig) — doing both in one pin bump is the cheap ordering.
