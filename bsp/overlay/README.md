# bsp/overlay — rootfs files baked into the image

Files here land in the target rootfs via Buildroot's `BR2_ROOTFS_OVERLAY`. They are the
reproducible counterpart to editing a running board over SSH: anything you fix by hand on the
board disappears the next time you flash, so it belongs here instead.

`common/` is meant for both ISA lanes. Per-board subdirectories can be added later if the
lanes ever need to differ.

> **Not wired into `bsp/build.sh` yet.** The Buildroot defconfigs still point
> `BR2_ROOTFS_OVERLAY` at the SDK's own `board/milkv/<board>/overlay`. Until the lane's
> `bsp/buildroot/<board>_defconfig` exists and points here, apply these by hand after
> flashing (see below). Tracked in `NEXT.md`.

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
