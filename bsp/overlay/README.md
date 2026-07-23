# bsp/overlay — rootfs files baked into the image

Files here land in the target rootfs via Buildroot's `BR2_ROOTFS_OVERLAY`. They are the
reproducible counterpart to editing a running board over SSH: anything you fix by hand on the
board disappears the next time you flash, so it belongs here instead.

`common/` is meant for both ISA lanes. Per-board subdirectories can be added later if the
lanes ever need to differ.

**Wired in since 2026-07-23 (arm64 lane).** `bsp/buildroot/milkv-duos-glibc-arm64-emmc_defconfig`
sets `BR2_ROOTFS_OVERLAY="board/milkv/<board>/overlay /bsp/overlay/common"`, and `/bsp` is
where `bsp/build.sh` mounts this repo inside the build container. Ours comes second, so it
wins any collision with the SDK's own overlay. The riscv64 lane is not wired yet.

One thing that is easy to misread: the SDK's `board/milkv/<board>/overlay` does not exist
in a clean tree. `build/Makefile:646` creates it from `tmp-rootfs` mid-build and
`:666` deletes it again, so it is only there while a build is running. That is where
`/mnt/system/*` comes from — and `/mnt/system` is a plain directory on the rootfs, not a
separate partition, so anything under it can be overridden from here.

## Contents

### `common/etc/init.d/S99wpa_supplicant`

Associates `wlan0` at boot so WiFi survives a reboot. Two non-obvious reasons this is needed:

1. Buildroot declares only `lo` in `/etc/network/interfaces`, so the ifupdown
   `wpasupplicant` hook never fires for `wlan0` and nothing else starts it.
2. The aic8800 WiFi driver is `insmod`'ed by `/mnt/system/duo-init.sh`, which `S99user`
   launches **in the background**. `wlan0` therefore does not exist yet when init reaches
   S39-ish scripts — an earlier numbering silently did nothing (verified by reboot).

So it runs after `S99user` *and* still waits up to 60s for the interface to appear, then
nudges `dhcpcd` for a lease. It no-ops when `/etc/wpa_supplicant.conf` is still the stock
Buildroot template, so an image without credentials boots clean.

### `common/etc/init.d/S70zigbee2mqtt`

Starts Zigbee2MQTT after `S50mosquitto`. Z2M is installed by Buildroot as an npm module
(`BR2_PACKAGE_NODEJS_MODULES_ADDITIONAL="zigbee2mqtt@2.10.1"`), so the entry point is
`/usr/bin/zigbee2mqtt`, npm's symlink to `cli.js` — there is no `/opt` tree.

It **no-ops when no coordinator is attached**, which is the normal state on this board:
the USB port defaults to gadget mode and carries the NCM network instead. Without that
check init would log a Z2M failure on every boot. State (device database, network key,
the runtime-rewritten `configuration.yaml`) lives in `/var/lib/zigbee2mqtt` — real ext4,
so it survives a reboot but **not a reflash**. Back it up or re-pair every device.

### `common/etc/mosquitto/mosquitto.conf`

Replaces the stock config Buildroot installs. mosquitto 2.0 denies anonymous clients by
default, which would leave Z2M in a connect/deny loop against its own broker. Bound to
`127.0.0.1` on purpose: an unauthenticated broker on the LAN is a control path into every
paired Zigbee device.

### `common/usr/bin/homeagent-usb-mode`

Flips `/mnt/system/usb.sh` between the Type-C gadget and the Type-A host port. SG2000 has
one dual-role controller behind a GPIO mux, so the Zigbee dongle and `192.168.42.1` are
mutually exclusive. `host` costs you the USB recovery path — `eth0`/`wlan0` keep SSH
alive, but a reflash then needs the recovery button. Takes effect on reboot.

### `common/var/lib/zigbee2mqtt/configuration.yaml`

Seed config only; Z2M rewrites it at runtime. `serial.port` is deliberately unset because
the two SONOFF dongles land on different nodes (`-E` → `/dev/ttyACM0`, `-P` →
`/dev/ttyUSB0`) and Z2M auto-discovers. Pin it once the board's dongle is known.

## Credentials are not in this repo

`/etc/wpa_supplicant.conf` holds the WiFi PSK and **must not be committed** — the global
commit hook will block it, correctly. Live SSID/PSK live in `PRIVATE.md`.

Configure a freshly flashed board over the USB network gadget (`192.168.42.1`, password
`milkv`), using the hashed form rather than the plaintext PSK:

```bash
ssh root@192.168.42.1
{ echo ctrl_interface=/var/run/wpa_supplicant
  echo ap_scan=1
  echo update_config=1
  echo
  wpa_passphrase '<SSID>' '<PSK>' | grep -v '^\s*#psk'
} > /etc/wpa_supplicant.conf
/etc/init.d/S99wpa_supplicant restart
/etc/init.d/S99wpa_supplicant status
```

## Note on addressing

Both `eth0` and `wlan0` take DHCP leases and **the addresses change across reboots**
(observed: eth0 .119 → .181 → .127). Set MAC-based reservations on the router if you want
stable addresses; `192.168.42.1` over USB is the only fixed one.
