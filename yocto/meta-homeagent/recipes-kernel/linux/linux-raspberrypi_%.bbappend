# Disable in-tree Hailo PCIe driver (4.19.0) — meta-hailo provides hailo-pci 4.23.0
# 커널 내장 모듈이 meta-hailo out-of-tree 모듈과 충돌하므로 비활성화
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://hailo.cfg"
