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
    # Root home only
    # Note: /etc/skel은 base-files와 충돌하므로 제외
    # HomeAgent는 별도 'agent' 계정으로 동작 예정 (제한된 권한)
    # 운영 계정 설정은 별도 레시피로 관리
    install -d ${D}${ROOT_HOME}
    install -m 0644 ${WORKDIR}/bashrc ${D}${ROOT_HOME}/.bashrc
    install -m 0644 ${WORKDIR}/vimrc ${D}${ROOT_HOME}/.vimrc
}

FILES:${PN} = " \
    ${ROOT_HOME}/.bashrc \
    ${ROOT_HOME}/.vimrc \
"
