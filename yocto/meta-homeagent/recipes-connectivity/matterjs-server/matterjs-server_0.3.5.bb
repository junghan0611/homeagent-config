SUMMARY = "OHF Matter Server (matter.js based)"
DESCRIPTION = "WebSocket-based Matter controller server built on matter.js SDK. \
Drop-in replacement for python-matter-server in Home Assistant."
HOMEPAGE = "https://github.com/matter-js/matterjs-server"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=034ed9796f7ed1e1e1e64267953217f7"

SRC_URI = " \
    npm://registry.npmjs.org/;package=matter-server;version=${PV} \
    npmsw://${THISDIR}/${BPN}/npm-shrinkwrap.json \
"

S = "${WORKDIR}/npm"

inherit npm
