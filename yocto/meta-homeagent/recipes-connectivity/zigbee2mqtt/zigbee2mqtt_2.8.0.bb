SUMMARY = "Zigbee to MQTT bridge"
DESCRIPTION = "Allows you to use your Zigbee devices without the vendor's bridge or gateway"
HOMEPAGE = "https://www.zigbee2mqtt.io/"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464"

SRC_URI = " \
    npm://registry.npmjs.org/;package=zigbee2mqtt;version=${PV} \
    npmsw://${THISDIR}/${BPN}/npm-shrinkwrap.json \
"

S = "${WORKDIR}/npm"

inherit npm

RDEPENDS:${PN}:append = " mosquitto"
