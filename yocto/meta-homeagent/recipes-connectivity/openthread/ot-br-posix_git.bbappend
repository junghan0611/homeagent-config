# HomeAgent: OTBR 설정 오버라이드
# - backbone interface: eth1 (RPi5 USB-Ethernet)
# - Thread RCP: /dev/ttyUSB0 (ZBDongle-E, baudrate 460800)

FILESEXTRAPATHS:prepend := "${THISDIR}/ot-br-posix:"

SRC_URI += "file://otbr-agent.default"

do_install:append() {
    install -d ${D}${sysconfdir}/default
    install -m 0644 ${WORKDIR}/otbr-agent.default ${D}${sysconfdir}/default/otbr-agent
}
