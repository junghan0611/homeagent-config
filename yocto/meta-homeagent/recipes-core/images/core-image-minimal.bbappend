# HomeAgent: OPi5 GPU firmware
# panthor DRM driver requires mali_csffw.bin for Mali-G610 (Valhall CSF)
IMAGE_INSTALL:append:orangepi-5 = " mali-csffw"
