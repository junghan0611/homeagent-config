#!/bin/sh
# Put the dual-role USB controller into host mode so the Type-A port powers and
# enumerates a device (our Zigbee coordinator).
#
# This REPLACES the SDK's own /mnt/system/usb-host.sh, which never actually
# switches the role. Its last line is:
#
#     echo host > /proc/cviusb/otg_role >> /tmp/usb.log 2>&1
#
# Two redirections on one command: the shell opens stdout on the proc file, then
# immediately reopens it on the log. The proc file gets truncated-opened and never
# written, so otg_role stays "device". Measured 2026-07-23 -- running the vendor
# script left /proc/cviusb/otg_role reading "device", and writing the same value by
# hand switched it instantly. S99user sources this at boot, so the bug means a board
# configured for host mode still comes up as a gadget.
#
# It also used bash's `function name()` syntax, which BusyBox ash does not accept.
usb_en=453       # XGPIOB[5]
usb_select=510   # XGPIOA[30]

set_gpio() {
	gpio_num=$1
	gpio_val=$2
	gpio_path="/sys/class/gpio/gpio${gpio_num}"

	[ -d "${gpio_path}" ] || echo "${gpio_num}" > /sys/class/gpio/export

	echo out > "${gpio_path}/direction"
	sleep 0.1
	echo "${gpio_val}" > "${gpio_path}/value"
}

set_gpio ${usb_select} 1
sleep 0.5
set_gpio ${usb_en} 1
sleep 0.5

echo host > /proc/cviusb/otg_role
