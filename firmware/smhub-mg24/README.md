# SMHub Nano Mg24 — onboard EFR32MG24 coordinator firmware

**The `.gbl` files are deliberately not committed** (`.gitignore`). They are closed vendor
blobs, and as of 2026-09-09 their provenance is unresolved. What lives here is the *path* to
them, which is the part worth keeping reproducible.

## What the vendor offers this unit

The device backend asks one index, and the radio id for SMHub Nano Mg24 is `SMHUB-MG24` = **67**
(`pysmlight/const.py` Devices map, `smhub_backend/api/routes/radio.py` `DEVICE_MAPS["nanomg24"]`):

```sh
curl -sS 'https://updates.smlight.tech/services/api/slzb-06x-ota.php?type=ZB&format=slzb&device=67&channel=dev'
```

A snapshot taken 2026-09-09 is kept as `fwlist-device67.json`. It answered with exactly two
coordinator images, **both `hwFlow: true`**:

| type | version | baud | notes |
|---|---|---|---|
| 0 coordinator | 8.0.2.0 | 115200 | "Factory coordinator firmware" |
| 0 coordinator | 7.4.4.0 | 115200 | "Coordinator firmware, 7x (old) SDK" |
| 1 router | 8.0.2.0 · 9.0.1.0 (dev) | 115200 | |
| 2 thread rcp | 2.4.5.0 · 2.4.4.0 · 3.0.1 (dev) | 460800 | |

**The 7.4.2.0 that actually shipped on our unit is not in that list**, so there is no published
rollback image.

## ⛔ Why nothing here has been flashed

Measured on the unit 2026-09-09 (`docs/SMHUB.md` §5.5 Q5): the running 7.4.2.0 is a **`no_flow`**
build — neither host RTS state nor XON/XOFF stops the NCP transmitting. Both offered images are
`ncp-uart-hw`, i.e. RTS/CTS builds, and whether MG24's CTS is wired to the SoC's UART1_RTS pad on
this board **has not been measured**. Flashing either is therefore a bet on unverified wiring
with no way back to the build that works today.

The device itself stays recoverable — GPIO bootloader entry works (proven 2026-09-09), so another
image can always be written. What cannot be recovered is the 7.4.2.0 baseline.

## ⚠️ The vendor index is currently serving dead links

On 2026-09-09 the index changed its download link form mid-afternoon:

```text
14:45  https://updates.smlight.tech/services/api/fw-dl.php?device=slzb-07mg24&file=<name>.gbl   → 200
later  https://updates.smlight.tech/firmware/slzb-07mg24/dl.php?file=<name>.gbl                 → 404
```

The Web UI's Radio page fails with `HTTP Error 404` because of this — the backend downloads
`firmware.link` verbatim (`radio.py:372 → :535`). Confirmed from the device itself:

```sh
curl -s --unix-socket /run/smhub-backend.sock \
  'http://localhost/api/v1/radio/0/firmware_list?type=0'
```

Whether this is a routing regression or a withdrawal is **not decided**. Until the vendor answers,
treat any copy already downloaded as *provenance hold*, not as an approved image.

## Fetching (when the images are wanted again)

```sh
curl -sSL -o ncp-uart-hw-v7.4.4.0-slzb-07mg24-115200.gbl \
  'https://updates.smlight.tech/services/api/fw-dl.php?device=slzb-07mg24&file=ncp-uart-hw-v7.4.4.0-slzb-07mg24-115200.gbl'
```

Verified 2026-09-09:

```text
ncp-uart-hw-v7.4.4.0-slzb-07mg24-115200.gbl   252,508 B  sha256 408676dd18bee51bb336dbd86df5aa7a420178530357b29787bcf143c2f0eb10
slzb07Mg24_zigbee_ncp_8.0.2.0_115200.gbl      256,116 B  sha256 07c4c388fb9df0140e4ee907cf57bdd0f1b7568e8144fcc2d4f88daf2162d918
```

Read the metadata out of the image rather than trusting the file name:

```sh
universal-silabs-flasher dump-gbl-metadata --firmware <file>.gbl
```

## Flashing — `flash-mg24.py`

Runs **on the device** with the vendor venv interpreter, and does what the Web UI does and
nothing more: inject the vendor's NANO GPIO reset target, enter the Gecko bootloader, write the
GBL, run the firmware, then **probe to prove what is actually on the chip**.

```sh
sudo rc-service zigbee2mqtt stop          # /dev/ttyS1 must be free
/opt/smhub-services/venv/bin/python flash-mg24.py <image>.gbl
```

The NANO reset pattern (`/dev/gpiochip2`, lines 11 and 12) was read out of the vendor's own
`smhub_backend/api/routes/radio.py` on OS 1.0.2. If the vendor changes it, re-read it there
rather than guessing.

**A banner is not evidence.** On 2026-09-08 the Web UI reported a successful 8.0.2.0 flash while
the chip still held 7.4.2.0 — the probe at the end of this script exists because of that.
