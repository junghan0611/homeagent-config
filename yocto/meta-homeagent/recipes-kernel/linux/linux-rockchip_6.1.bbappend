# HomeAgent: Orange Pi 5 (RK3588S) DTS 추가
# JeffyCN linux-rockchip 6.1에는 OPi5 DTS가 없음 (EVB만 포함)
# Armbian linux-rockchip rk-6.1-rkr5.1 브랜치에서 가져온 vendor 호환 DTS
# (카메라 dtsi include만 제거 — headless NPU hub에 불필요)

FILESEXTRAPATHS:prepend := "${THISDIR}/linux-rockchip_6.1:"

SRC_URI += "file://rk3588s-orangepi-5.dts"

# DTS 파일을 커널 소스 트리에 복사
do_patch:append() {
    cp ${WORKDIR}/rk3588s-orangepi-5.dts ${S}/arch/arm64/boot/dts/rockchip/

    # Makefile에 OPi5 DTB 빌드 타겟 추가 (없으면)
    if ! grep -q "rk3588s-orangepi-5" ${S}/arch/arm64/boot/dts/rockchip/Makefile; then
        sed -i '/rk3588s-evb/a dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3588s-orangepi-5.dtb' \
            ${S}/arch/arm64/boot/dts/rockchip/Makefile
    fi
}
