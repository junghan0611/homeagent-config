#!/bin/sh
# beta5-postcapture-readonly.sh — SMHub Nano Mg24 beta5 무변형(read-only) post-OTA 실측.
# Phase B post-capture: C906L RTOS/RPMsg 등장·opkg·커널·SSH키(EEPROM)·F2FS/zRAM 확인.
# 원칙: 어떤 상태도 바꾸지 않는다(no opkg update/upgrade, no service start/stop, no write).
# 실행: 디바이스 셸(SSH 또는 Web UI Console)에 붙여넣기. sudo -n 필요한 항목은 실패해도 계속.
# 출력은 stdout — 호스트에서 tee 로 로그 파일에 저장한다.
set -u
sec(){ printf '\n===== %s =====\n' "$1"; }

sec "0. identity / version / slot"
cat /etc/os-release 2>/dev/null
echo "-- uname --"; uname -a
echo "-- rauc status --"; (sudo -n rauc status 2>/dev/null || rauc status 2>/dev/null || echo "rauc: n/a")
echo "-- boot slot env --"; (sudo -n fw_printenv 2>/dev/null | grep -iE 'boot_order|rauc_slot|active_boot_slot|slot_num|boot_a_left|boot_b_left' || echo "fw_printenv: n/a")
echo "-- uptime --"; uptime

sec "1. C906L RTOS co-processor (beta 라인 핵심 — 0.9.8엔 부재)"
for f in /sys/class/remoteproc/remoteproc0/name /sys/class/remoteproc/remoteproc0/state /sys/class/remoteproc/remoteproc0/firmware; do
	printf '%s = ' "$f"; cat "$f" 2>/dev/null || echo "(none)"
done
echo "-- remoteproc dirs --"; ls -l /sys/class/remoteproc/ 2>/dev/null || echo "(no remoteproc class)"
echo "-- /dev/rpmsg* --"; ls -l /dev/rpmsg* 2>/dev/null || echo "(no rpmsg dev)"
echo "-- rtos elf / firmware --"; ls -l /opt/firmware/ /lib/firmware/ 2>/dev/null | grep -iE 'rtos|c906|esphome|\.elf' || echo "(no rtos elf found in common paths)"
echo "-- broker socket --"; ls -l /var/run/smhub-broker.sock /run/smhub-broker.sock 2>/dev/null || echo "(no broker sock)"
echo "-- dmesg co-proc lines --"; (dmesg 2>/dev/null || sudo -n dmesg 2>/dev/null) | grep -iE 'remoteproc|rpmsg|c906|rtos|esphome|broker|mailbox' | head -40 || echo "(dmesg not readable / no match)"

sec "2. esphome / broker / picoclaw / bluetooth proxy 프로세스"
(ps w 2>/dev/null || ps aux 2>/dev/null) | grep -iE 'esphome|smhub-broker|picoclaw|bluetooth|hciattach|matterbridge|zigbee2mqtt|mosquitto' | grep -v grep || echo "(none of the tracked procs running)"

sec "3. opkg installed (설치 버전 정본)"
opkg list-installed 2>/dev/null || echo "opkg: n/a"

sec "4. app package.json versions (smhub-services / smhub-ui 개명 확인)"
for pj in /opt/*/package.json /opt/*/*/package.json; do
	[ -f "$pj" ] || continue
	printf '%s : ' "$pj"; grep -E '"(name|version)"' "$pj" 2>/dev/null | tr -d '\n ,'; echo
done
echo "-- /opt tree --"; ls -l /opt 2>/dev/null

sec "5. persistence: fstab (F2FS vs ext4, zRAM swap)"
cat /etc/fstab 2>/dev/null
echo "-- mounts --"; mount 2>/dev/null | grep -iE 'mmcblk|f2fs|ext4|zram|/opt|/home|/var|/mnt/user'
echo "-- swap --"; (cat /proc/swaps 2>/dev/null; free -h 2>/dev/null)
echo "-- blkid --"; (sudo -n blkid 2>/dev/null || blkid 2>/dev/null || echo "blkid: n/a")

sec "6. SSH host key provisioning (EEPROM fix 검증 — 0.9.8은 0바이트였음)"
ls -l /etc/ssh/ssh_host_*_key 2>/dev/null || echo "(no host keys)"
echo "-- sshd in rc --"; (rc-status 2>/dev/null | grep -i ssh; rc-update show 2>/dev/null | grep -i ssh) || echo "(rc info n/a)"
echo "-- sshd proc --"; (ps w 2>/dev/null || ps aux 2>/dev/null) | grep -i '[s]shd' || echo "(sshd not running)"

sec "7. kernel config marker (remoteproc/rpmsg/f2fs/zram in kernel)"
if [ -r /proc/config.gz ]; then
	zcat /proc/config.gz 2>/dev/null | grep -iE 'REMOTEPROC|RPMSG|MAILBOX|F2FS|ZRAM|ZSMALLOC' | head -40
else
	echo "(no /proc/config.gz)"
fi

sec "8. MG24 zigbee coordinator (z2m bridge/info — running != working)"
echo "z2m frontend port:"; (netstat -ltn 2>/dev/null || ss -ltn 2>/dev/null) | grep -E ':8080|:8000|:80|:443|:1883' || echo "(no ports listed)"
echo "NOTE: coordinator ember 펌웨어/ezsp 버전은 z2m frontend(:8080) bridge/info 또는 mosquitto SUB zigbee2mqtt/bridge/info 로 별도 확인."

sec "DONE"
