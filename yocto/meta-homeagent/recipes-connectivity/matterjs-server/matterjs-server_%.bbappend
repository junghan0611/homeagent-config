FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://matterjs-server.service \
    file://matterjs-server.default \
"

inherit systemd

SYSTEMD_SERVICE:${PN} = "matterjs-server.service"
SYSTEMD_AUTO_ENABLE = "enable"

INSANE_SKIP:${PN} += "already-stripped file-rdeps"

do_install:append() {
    # Environment variables file
    install -d ${D}${sysconfdir}/default
    install -m 0644 ${WORKDIR}/matterjs-server.default ${D}${sysconfdir}/default/matterjs-server

    # Systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/matterjs-server.service ${D}${systemd_system_unitdir}/

    # Storage directory
    install -d ${D}/var/lib/matterjs-server
}

FILES:${PN} += " \
    ${sysconfdir}/default/matterjs-server \
    ${systemd_system_unitdir}/matterjs-server.service \
    /var/lib/matterjs-server \
"
