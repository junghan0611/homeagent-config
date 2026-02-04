SUMMARY = "Zigbee to MQTT bridge"
DESCRIPTION = "Allows you to use your Zigbee devices without the vendor's bridge or gateway"
HOMEPAGE = "https://www.zigbee2mqtt.io/"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464"

SRC_URI = "git://github.com/Koenkk/zigbee2mqtt.git;branch=master;protocol=https \
           file://zigbee2mqtt.service \
           file://configuration.yaml \
          "
SRCREV = "1.42.0"
PV = "1.42.0"

S = "${WORKDIR}/git"

DEPENDS = "nodejs-native"
RDEPENDS:${PN} = "nodejs nodejs-npm mosquitto"

inherit systemd

SYSTEMD_SERVICE:${PN} = "zigbee2mqtt.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_compile() {
    cd ${S}
    npm ci --production
}

do_install() {
    # Install application
    install -d ${D}/opt/zigbee2mqtt
    cp -r ${S}/* ${D}/opt/zigbee2mqtt/

    # Configuration directory
    install -d ${D}${sysconfdir}/zigbee2mqtt
    install -m 0644 ${WORKDIR}/configuration.yaml ${D}${sysconfdir}/zigbee2mqtt/

    # Systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/zigbee2mqtt.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = " \
    /opt/zigbee2mqtt \
    ${sysconfdir}/zigbee2mqtt \
    ${systemd_system_unitdir}/zigbee2mqtt.service \
"
