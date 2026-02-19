# HomeAgent: OTBR 설정 오버라이드
# - backbone interface: eth0 (RPi5 내장 이더넷)
# - Thread RCP: /dev/ttyUSB0 (ZBDongle-E, baudrate 460800)
# - Thread 네트워크: 첫 부팅 시 자동 생성
# - SRP server: Thread 시작 후 자동 enable (Matter commissioning 필수)

FILESEXTRAPATHS:prepend := "${THISDIR}/ot-br-posix:"

SRC_URI += " \
    file://otbr-agent.default \
    file://otbr-thread-init.sh \
    file://otbr-thread-init.service \
    file://otbr-srp-enable.sh \
    file://otbr-srp-enable.service \
"

inherit systemd

SYSTEMD_SERVICE:${PN} += "otbr-thread-init.service otbr-srp-enable.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install:append() {
    install -d ${D}${sysconfdir}/default
    install -m 0644 ${WORKDIR}/otbr-agent.default ${D}${sysconfdir}/default/otbr-agent

    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/otbr-thread-init.sh ${D}${sbindir}/otbr-thread-init.sh
    install -m 0755 ${WORKDIR}/otbr-srp-enable.sh ${D}${sbindir}/otbr-srp-enable.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/otbr-thread-init.service ${D}${systemd_system_unitdir}/otbr-thread-init.service
    install -m 0644 ${WORKDIR}/otbr-srp-enable.service ${D}${systemd_system_unitdir}/otbr-srp-enable.service
}
