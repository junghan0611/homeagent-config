# HomeAgent: OPi5 커널을 6.11로 업그레이드 (panthor GPU 드라이버 필요)
# - 6.9: panfrost만 있음 (Mali-G610 미지원)
# - 6.10+: panthor 머지됨 (Valhall CSF)
# - 6.11: 안정성 개선

KBRANCH:orangepi-5 = "v6.11/standard/base"
LINUX_VERSION:orangepi-5 = "6.11"

FILESEXTRAPATHS:prepend:orangepi-5 := "${THISDIR}/linux-yocto-dev:"

SRC_URI:append:orangepi-5 = " file://panthor-gpu.cfg"
