#
# HomeAgent Flutter App — WebView Shell for Go backend
#
# ivi-homescreen(Wayland/Weston)으로 실행
# flutter-pi는 WebView 미지원이므로 ivi-homescreen 사용
#

SUMMARY = "HomeAgent Flutter App"
DESCRIPTION = "Matter smart home agent app — WebView shell for Go backend UI"
AUTHOR = "junghan"
HOMEPAGE = "https://github.com/junghan0611/homeagent-config"
SECTION = "graphics"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "git://github.com/junghan0611/homeagent-config.git;protocol=https;branch=main"
SRCREV = "${AUTOREV}"

S = "${WORKDIR}/git"

PUBSPEC_APPNAME = "homeagent"
FLUTTER_APPLICATION_PATH = "flutter"

inherit flutter-app

RDEPENDS:${PN} += " \
    ivi-homescreen \
    liberation-fonts \
    "
