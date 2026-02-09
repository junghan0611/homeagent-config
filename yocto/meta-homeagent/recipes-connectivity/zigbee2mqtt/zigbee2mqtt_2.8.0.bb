SUMMARY = "Zigbee to MQTT bridge"
DESCRIPTION = "Allows you to use your Zigbee devices without the vendor's bridge or gateway"
HOMEPAGE = "https://www.zigbee2mqtt.io/"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=84dcc94da3adb52b53ae4fa38fe49e5d"

SRC_URI = " \
    npm://registry.npmjs.org/;package=zigbee2mqtt;version=${PV} \
    npmsw://${THISDIR}/${BPN}/npm-shrinkwrap.json \
"

S = "${WORKDIR}/npm"

inherit npm

RDEPENDS:${PN}:append = " mosquitto"
