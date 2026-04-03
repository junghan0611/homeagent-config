# HomeAgent: OPi5 커널을 6.14로 업그레이드
# - 6.9: panfrost만 있음 (Mali-G610 미지원)
# - 6.10+: panthor 머지됨 (Valhall CSF)
# - 6.11: VOP2 동작, 하지만 HDMI TX controller (dw-hdmi-qp) 없음
# - 6.13: dw-hdmi-qp + rockchip HDMI glue + DTS 머지
# - 6.14: HDMI 스택 안정화, OPi5 DTS에 hdmi0/vop/connector 완전체
#
# 6.14부터 upstream DTS에 OPi5 HDMI가 포함되어 커스텀 DT 패치 불필요

KBRANCH = "v6.14/standard/base"
LINUX_VERSION = "6.14"

FILESEXTRAPATHS:prepend := "${THISDIR}/linux-yocto-dev:"

SRC_URI += " \
    file://panthor-gpu.cfg \
"
