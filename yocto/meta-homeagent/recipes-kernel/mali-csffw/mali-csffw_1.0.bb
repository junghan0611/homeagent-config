SUMMARY = "Arm Mali CSF firmware for panthor (Mali-G610/G710)"
DESCRIPTION = "Installs mali_csffw.bin required by the panthor DRM driver for Valhall CSF GPUs."
HOMEPAGE = "https://gitlab.com/kernel-firmware/linux-firmware"
LICENSE = "Firmware-Abilis"
LIC_FILES_CHKSUM = "file://LICENCE.mali_csffw;md5=e064aaec4d21ef856e1b76a6f5dc435f"
NO_GENERIC_LICENSE[Firmware-Abilis] = "LICENCE.mali_csffw"

SRC_URI = " \
  https://gitlab.com/kernel-firmware/linux-firmware/-/raw/c01388616e35c2f9dbcc4a207703e1ae0b47fcd9/arm/mali/arch10.8/mali_csffw.bin;downloadfilename=mali_csffw.bin;sha256sum=43c3c36b914c031d88ae152fd89019d8f99ad41d9879fb5ab7496ed13f7b378b \
  https://gitlab.com/kernel-firmware/linux-firmware/-/raw/c01388616e35c2f9dbcc4a207703e1ae0b47fcd9/LICENCE.mali_csffw;downloadfilename=LICENCE.mali_csffw;sha256sum=ebedc86d1767186a66dcb59ce8dcb97c5fd9ac10de2adaacad226714e4712f6d \
"

S = "${WORKDIR}"

inherit allarch

do_install() {
    install -d ${D}${nonarch_base_libdir}/firmware/arm/mali/arch10.8
    install -m 0644 ${WORKDIR}/mali_csffw.bin ${D}${nonarch_base_libdir}/firmware/arm/mali/arch10.8/mali_csffw.bin

    install -d ${D}${docdir}/${PN}
    install -m 0644 ${WORKDIR}/LICENCE.mali_csffw ${D}${docdir}/${PN}/LICENCE.mali_csffw
}

FILES:${PN} += " \
  ${nonarch_base_libdir}/firmware/arm/mali/arch10.8/mali_csffw.bin \
  ${docdir}/${PN}/LICENCE.mali_csffw \
"
