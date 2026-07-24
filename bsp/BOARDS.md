# Board inventory — Milk-V Duo S hub units

Physical boards we flash and manage. The sticker number is an arbitrary label GLG puts on
the board (no meaning beyond identity); everything else is measured after a flash.

Ground truth for "what is on this board" is the rootfs filesystem UUID: it is baked into
each image at build time, so it ties a running board back to the exact image that produced
it. `dumpe2fs -h /dev/mmcblk0p4 | grep -i UUID` on the board, compared against the image
(`bsp/flash-emmc.sh` prints the image UUID when it finishes).

## Images

| Image | rootfs UUID | Notes |
|-------|-------------|-------|
| `milkv-duos-glibc-arm64-emmc_2026-0724-1244.zip` | `f0cd08f2-cb5b-427f-800b-b005120a1121` | Z2M serial pinned in seed (ttyUSB0/ember). Flash-and-go: no post-flash config edit needed. Incremental build over 2026-0723-2019. |
| `milkv-duos-glibc-arm64-emmc_2026-0723-2019.zip` | `1af796f5-cebf-46ba-a42e-6b7a5d3b06ee` | First working Z2M image, but seed leaves `serial` unpinned, so Z2M needs a manual `serial.port`/`adapter` before it starts (no udevadm on the image). Superseded by 1244. |

## Boards

Numbering is a simple running series (90, 91, 92, …) as more units come in; the number is
just an identity sticker.

| Sticker | ISA switch | eth0 MAC | rootfs UUID (flashed) | Status |
|---------|-----------|----------|-----------------------|--------|
| 90 | ARM | _(pending — board was offline at tag time)_ | `1af796f5-…` (2026-0723-2019, hand-fixed) | Development board (first Z2M bring-up). Image predates the seed serial pin, so Z2M needed a manual `serial.port`/`adapter` once; verified end to end 2026-07-24 (EmberZNet 7.4.2, MQTT, :8080). Last seen at eth0 192.168.0.192 in USB host mode. Reflash with 2026-0724-1244 to bring it to flash-and-go parity. |
| 91 | ARM | `fe:d9:3a:ee:a1:2d` | `f0cd08f2-…` (2026-0724-1244) | Flashed 2026-07-24, UUID matches image exactly. eth0 DHCP 192.168.0.162. **flash-and-go proven**: switched to USB host, plugged the dongle, Z2M came up on the seed pin with NO config edit — EmberZNet coordinator (IEEE `0x08b95ffffeb52378`, firmware 7.4.2), MQTT, frontend on :8080 (HTTP 200), 0 devices joined. Now in host mode (usb0 gone; reachable at eth0 192.168.0.162). |

Fill a board's MAC and UUID in from its first boot:

```bash
# over eth0 (find the board's DHCP lease, or check the switch/router)
ssh root@<board-ip> 'ip -br link show eth0; dumpe2fs -h /dev/mmcblk0p4 | grep -i UUID; uname -m'
```
