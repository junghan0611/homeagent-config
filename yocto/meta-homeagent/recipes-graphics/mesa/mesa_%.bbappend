# HomeAgent: Mesa 24.0.7 → 24.1.7 업그레이드
# 이유: RK3588S Mali-G610 (panthor 커널 드라이버) GPU 가속에 Mesa 24.1+ 필요
# - Mesa 24.0.x: panfrost만 있고 panthor kmod 백엔드 없음 → softpipe fallback
# - Mesa 24.1+: panfrost 안에 panthor_kmod.c 추가 → CSF GPU 하드웨어 가속
#
# 24.1.7은 Scarthgap(mesa.inc) 호환성이 좋음:
# - kmsro, swrast 옵션 여전히 유효
# - wayland-protocols >= 1.34 필요 (별도 bbappend)
#
# RPi5(vc4/v3d)에도 영향 — 24.1.7은 안정 릴리즈라 호환성 문제 없음

PV = "24.1.7"

SRC_URI = "https://mesa.freedesktop.org/archive/mesa-${PV}.tar.xz"
SRC_URI[sha256sum] = "ecd2e7b1c73998f4103542f39c6b8c968d251637ccc8caa42641aecb86cd2566"

LIC_FILES_CHKSUM = "file://docs/license.rst;md5=63779ec98d78d823a9dc533a0735ef10"

# OPi5 (RK3588S): panfrost gallium + kmsro (panthor kmod 자동 탐지)
PACKAGECONFIG:append:rk3588s = " kmsro panfrost"

# Mesa 24.1+ 빌드 의존성 추가 (PyYAML)
DEPENDS += "python3-pyyaml-native"
