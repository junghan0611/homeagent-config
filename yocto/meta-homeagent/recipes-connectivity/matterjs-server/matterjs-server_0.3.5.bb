SUMMARY = "OHF Matter Server (matter.js based)"
DESCRIPTION = "WebSocket-based Matter controller server built on matter.js SDK. \
Drop-in replacement for python-matter-server in Home Assistant."
HOMEPAGE = "https://github.com/matter-js/matterjs-server"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=86d3f3a95c324c9479bd8986968f4327"

SRC_URI = " \
    npm://registry.npmjs.org/;package=matter-server;version=${PV} \
    npmsw://${THISDIR}/${BPN}/npm-shrinkwrap.json \
"

S = "${WORKDIR}/npm"

inherit npm
