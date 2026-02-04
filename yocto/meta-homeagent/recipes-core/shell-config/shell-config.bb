SUMMARY = "Shell configuration for HomeAgent"
DESCRIPTION = "Provides .bashrc and .vimrc with UTF-8/Korean support and terminal compatibility"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://bashrc \
    file://vimrc \
"

S = "${WORKDIR}"

inherit allarch

do_install() {
    # Root home
    install -d ${D}${ROOT_HOME}
    install -m 0644 ${WORKDIR}/bashrc ${D}${ROOT_HOME}/.bashrc
    install -m 0644 ${WORKDIR}/vimrc ${D}${ROOT_HOME}/.vimrc

    # Skeleton for new users
    install -d ${D}${sysconfdir}/skel
    install -m 0644 ${WORKDIR}/bashrc ${D}${sysconfdir}/skel/.bashrc
    install -m 0644 ${WORKDIR}/vimrc ${D}${sysconfdir}/skel/.vimrc
}

FILES:${PN} = " \
    ${ROOT_HOME}/.bashrc \
    ${ROOT_HOME}/.vimrc \
    ${sysconfdir}/skel/.bashrc \
    ${sysconfdir}/skel/.vimrc \
"
