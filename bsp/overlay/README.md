# bsp/overlay — rootfs files baked into the image

Files here land in the target rootfs via Buildroot's `BR2_ROOTFS_OVERLAY`. They are the
reproducible counterpart to editing a running board over SSH: anything you fix by hand on the
board disappears the next time you flash, so it belongs here instead.

## Two overlays, split by profile

`BR2_ROOTFS_OVERLAY` takes a **list** of directories, and we use that to make the package
profile and the rootfs files move together:

| Directory | Ships in | Holds |
|---|---|---|
| `common/` | **both profiles** | the BSP surface — stable MAC, serial by-id, wpa_supplicant, USB mode |
| `z2m/` | `full` only | the hub application — Z2M init + seed config, mosquitto config |

The split is by *profile*, not by topic. An init script whose binary is not in the rootfs
is a boot-time error, so `S70zigbee2mqtt` has to leave the image at the same moment
`BR2_PACKAGE_NODEJS` does — and the one place that can guarantee "same moment" is a single
fragment that edits both (`bsp/buildroot/profiles/<board>_minimal.fragment`). Put a new
file in `common/` only if a Node-less image would still want it; otherwise it belongs in
`z2m/`.

That guarantee covers the *config*, not the tree it is built into. Dropping `z2m/` from
`BR2_ROOTFS_OVERLAY` stops those files being copied in; it does not remove ones a previous
`full` build already copied, because Buildroot's `output/<board>/target/` is cumulative.
Measured 2026-08-30: a `minimal` build on a warm `full` tree shipped `S70zigbee2mqtt` and
`etc/mosquitto/` anyway. `bsp/build.sh` now refuses that before building — see
`bsp/README.md`, "Rebuilding after an overlay/config change".

`common/` is also meant for both ISA lanes. Per-board subdirectories can be added later if
the lanes ever need to differ.

**Wired in since 2026-07-23 (arm64 lane).** `bsp/buildroot/milkv-duos-glibc-arm64-emmc_defconfig`
sets `BR2_ROOTFS_OVERLAY="board/milkv/<board>/overlay /bsp/overlay/common /bsp/overlay/z2m"`,
and `/bsp` is where `bsp/build.sh` mounts this repo inside the build container. Ours come
after the SDK's, so they win any collision with it. The riscv64 lane is not wired yet.

One thing that is easy to misread: the SDK's `board/milkv/<board>/overlay` does not exist
in a clean tree. `build/Makefile:646` creates it from `tmp-rootfs` mid-build and
`:666` deletes it again, so it is only there while a build is running. That is where
`/mnt/system/*` comes from — and `/mnt/system` is a plain directory on the rootfs, not a
separate partition, so anything under it can be overridden from here.

## Contents

### `common/usr/bin/stable-mac` + `S39stablemac` + `S99v_stablemac`

This board has **no fused MAC**. eth0 (bm-dwmac) and wlan0 (aic8800, no efuse, no
`aic_userconfig` MAC section) both randomize every boot — three boots, three
values, measured on the gecko bench (`GECKO_PORT.md §7.15`). The MAC is product
identity: SoftAP SSID, the phone-app AES key/IV, and the server-issued hub id
all derive from `wlan0`. A reflash that drops these scripts breaks that chain.

`stable-mac` hashes the **eMMC CID** (`/sys/block/mmcblk0/device/cid`) into an LAA
address (`02:` eth0, `06:` wlan0). Same chip → same MAC across reflash; different
board → different MAC. This is the #8 identity slice for Duo S, not a file in
rootfs. Scripts came from `sks-hub-gecko/board/duo-s/`; this overlay is the
durable home.

**Init order is half the contract** (measured):

| script | sorts | why |
|---|---|---|
| `S39stablemac` | before `S40network` / `S41dhcpcd` | eth0 MAC before the lease |
| `S99v_stablemac` | `S99user` < this < `S99wpa_supplicant` | wlan0 appears late; set MAC before wpa associates. Foreground wait on purpose. |

Do not rename them. A random MAC lease first is the failure mode.

### `common/usr/bin/homeagent-serial-by-id` + `common/etc/mdev.conf` + `S99serial-by-id`

The image has busybox mdev, not udev, so `/dev/serial/by-id/` never existed.
sks-hub-gecko's resolver **opens that directory, demands exactly one entry, and
realpath's it** — without the links, peripheral init fails every boot. We do
**not** add eudev (Z2M already works around missing `udevadm`; a second device
manager is a bigger change than this contract needs).

`homeagent-serial-by-id` walks sysfs (manufacturer/product/serial/interface/port)
and writes udev-shaped `usb-…-if00-port0` symlinks. mdev.conf runs it on ttyUSB/
ttyACM add and remove. S99serial-by-id is the boot safety net: `mdev -s` runs
before USB host mode, so it backgrounds a wait like `S99wpa_supplicant` and
scans when a node appears. Name is cosmetic — the resolver only cares that the
count is 1.

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

### `z2m/etc/init.d/S70zigbee2mqtt`

Starts Zigbee2MQTT after `S50mosquitto`. Z2M is installed by Buildroot as an npm module
(`BR2_PACKAGE_NODEJS_MODULES_ADDITIONAL="zigbee2mqtt@2.10.1"`), so the entry point is
`/usr/bin/zigbee2mqtt`, npm's symlink to `cli.js` — there is no `/opt` tree.

It **no-ops when no coordinator is attached**, which is the normal state on this board:
the USB port defaults to gadget mode and carries the NCM network instead. Without that
check init would log a Z2M failure on every boot. State (device database, network key,
the runtime-rewritten `configuration.yaml`) lives in `/var/lib/zigbee2mqtt` — real ext4,
so it survives a reboot but **not a reflash**. Back it up or re-pair every device.

### `z2m/etc/mosquitto/mosquitto.conf`

Replaces the stock config Buildroot installs. mosquitto 2.0 denies anonymous clients by
default, which would leave Z2M in a connect/deny loop against its own broker. Bound to
`127.0.0.1` on purpose: an unauthenticated broker on the LAN is a control path into every
paired Zigbee device.

### `common/mnt/system/usb-host.sh`

Overrides the SDK's copy, which **never switches the role**. Its last line is
`echo host > /proc/cviusb/otg_role >> /tmp/usb.log 2>&1` — two redirections, so stdout
ends up on the log and the proc file is opened but never written. Measured 2026-07-23:
running the vendor script left `otg_role` reading `device`; writing the same value by
hand switched it instantly and a coordinator enumerated within a second. Since S99user
sources this at boot, the bug means a board configured for host mode still comes up as
a gadget. Also rewritten in POSIX shell — the original used bash's `function name()`,
which BusyBox ash does not accept.

### `common/usr/bin/homeagent-usb-mode`

Flips `/mnt/system/usb.sh` between the Type-C gadget and the Type-A host port. SG2000 has
one dual-role controller behind a GPIO mux, so the Zigbee dongle and `192.168.42.1` are
mutually exclusive. `host` costs you the USB recovery path — `eth0`/`wlan0` keep SSH
alive, but a reflash then needs the recovery button. Takes effect on reboot.

### `z2m/var/lib/zigbee2mqtt/configuration.yaml`

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
