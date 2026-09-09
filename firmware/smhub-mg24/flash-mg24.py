#!/usr/bin/env python3
"""Flash the SMHub Nano Mg24 onboard EFR32MG24 NCP, reproducibly, from the CLI.

Runs ON THE DEVICE with the vendor venv interpreter:
    /opt/smhub-services/venv/bin/python flash-mg24.py <image.gbl>

It does what the vendor Web UI does, and nothing else: inject the NANO GPIO
reset target into universal-silabs-flasher, enter the Gecko bootloader, write
the GBL, run the firmware, then probe to prove what is actually on the chip.

The caller owns stopping/starting zigbee2mqtt -- this script only needs
/dev/ttyS1 to be free.
"""

import asyncio
import logging
import sys

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

from universal_silabs_flasher.const import (  # noqa: E402
    RESET_CONFIGS,
    ApplicationType,
    GpioPattern,
    GpioResetConfig,
    ResetTarget,
)
from universal_silabs_flasher.firmware import parse_firmware_image  # noqa: E402
from universal_silabs_flasher.flasher import Flasher  # noqa: E402

# Vendor's own NANO reset pattern, read from
# smhub_backend/api/routes/radio.py `_ensure_usf_initialized` on OS 1.0.2.
NANO_RESET = GpioResetConfig(
    chip="/dev/gpiochip2",
    chip_type=None,
    pattern=[
        GpioPattern(pins={11: True, 12: True}, delay_after=0.1),
        GpioPattern(pins={11: False, 12: False}, delay_after=0.1),
        GpioPattern(pins={11: True, 12: False}, delay_after=0.1),
        GpioPattern(pins={11: True, 12: True}, delay_after=0.5),
    ],
)

PORT = "/dev/ttyS1"


def inject_nano_target() -> ResetTarget:
    target = object.__new__(ResetTarget)
    target._name_ = "NANO"
    target._value_ = "nano"
    ResetTarget._value2member_map_["nano"] = target
    ResetTarget._member_map_["NANO"] = target
    ResetTarget._member_names_.append("NANO")
    RESET_CONFIGS[target] = NANO_RESET
    return target


def progress(current, total):
    print(f"  {current}/{total} bytes", end="\r", flush=True)


async def main(path: str) -> None:
    target = inject_nano_target()

    with open(path, "rb") as fh:
        image = parse_firmware_image(fh.read())
    print(f"image:    {path}")
    print(f"metadata: {image.get_nabucasa_metadata()}")

    flasher = Flasher(
        probe_methods=((ApplicationType.GECKO_BOOTLOADER, 115200),),
        device=PORT,
        bootloader_baudrate=115200,
        bootloader_reset=(target,),
    )
    await flasher.enter_bootloader()
    await flasher.flash_firmware(
        firmware=image, progress_callback=progress, run_firmware=True
    )
    print()

    await asyncio.sleep(2)

    verify = Flasher(
        probe_methods=(
            (ApplicationType.EZSP, 115200),
            (ApplicationType.EZSP, 460800),
            (ApplicationType.GECKO_BOOTLOADER, 115200),
        ),
        device=PORT,
        bootloader_baudrate=115200,
        bootloader_reset=(target,),
    )
    await verify.probe_app_type()
    print(f"VERIFY: app={verify.app_type} version={verify.app_version} baud={verify.app_baudrate}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <image.gbl>")
    asyncio.run(main(sys.argv[1]))
