#
# HomeAgent Flutter App — systemd autostart service
#

SUMMARY = "HomeAgent Flutter App autostart"
DESCRIPTION = "Systemd service to launch homeagent Flutter app via flutter-pi on boot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SYSTEMD_AUTO_ENABLE = "enable"
SYSTEMD_SERVICE:${PN} = "homeagent-app.service"

SRC_URI = "file://homeagent-app.service"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/homeagent-app.service ${D}${systemd_system_unitdir}/
}

RDEPENDS:${PN} += "homeagent-app ivi-homescreen"
