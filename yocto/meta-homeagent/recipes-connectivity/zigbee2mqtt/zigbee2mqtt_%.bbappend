FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://zigbee2mqtt.service \
    file://zigbee2mqtt.default \
    file://configuration.yaml \
"

inherit systemd

SYSTEMD_SERVICE:${PN} = "zigbee2mqtt.service"
SYSTEMD_AUTO_ENABLE = "enable"

# npm packages often have pre-stripped binaries and mixed architectures
INSANE_SKIP:${PN} += "already-stripped file-rdeps"

do_install:append() {
    # Configuration directory
    install -d ${D}${sysconfdir}/zigbee2mqtt
    install -m 0644 ${WORKDIR}/configuration.yaml ${D}${sysconfdir}/zigbee2mqtt/

    # Environment variables file
    install -d ${D}${sysconfdir}/default
    install -m 0644 ${WORKDIR}/zigbee2mqtt.default ${D}${sysconfdir}/default/zigbee2mqtt

    # Systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/zigbee2mqtt.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += " \
    ${sysconfdir}/zigbee2mqtt \
    ${sysconfdir}/default/zigbee2mqtt \
    ${systemd_system_unitdir}/zigbee2mqtt.service \
"
