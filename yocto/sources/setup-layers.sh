#!/bin/bash
# HomeAgent Yocto Layer Setup Script
#
# Usage: ./setup-layers.sh [--link]
#   --link: 기존 클론된 레이어 심볼릭 링크 (기본: git clone)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YOCTO_BRANCH="scarthgap"  # Yocto 5.0 LTS

# 기존 클론 위치 (심볼릭 링크용)
EXISTING_META_RPI="/home/junghan/repos/3rd/meta-raspberrypi"
EXISTING_META_FLUTTER="/home/junghan/repos/3rd/meta-flutter-sony"

echo "============================================"
echo "  HomeAgent Yocto Layer Setup"
echo "  Branch: ${YOCTO_BRANCH}"
echo "============================================"

cd "$SCRIPT_DIR"

setup_link() {
    # 기존 클론된 레이어를 심볼릭 링크로 연결
    echo "[INFO] Linking existing layers..."

    # meta-raspberrypi
    if [ -d "$EXISTING_META_RPI" ]; then
        ln -sfn "$EXISTING_META_RPI" meta-raspberrypi
        echo "  - meta-raspberrypi -> $EXISTING_META_RPI"
    else
        echo "  [WARN] meta-raspberrypi not found, will clone"
        git clone git://git.yoctoproject.org/meta-raspberrypi -b ${YOCTO_BRANCH}
    fi

    # meta-flutter-sony
    if [ -d "$EXISTING_META_FLUTTER" ]; then
        ln -sfn "$EXISTING_META_FLUTTER" meta-flutter
        echo "  - meta-flutter -> $EXISTING_META_FLUTTER"
    else
        echo "  [WARN] meta-flutter-sony not found, will clone"
        git clone https://github.com/sony/meta-flutter.git -b kirkstone meta-flutter
    fi
}

setup_clone() {
    echo "[INFO] Cloning layers..."

    # poky (Yocto base)
    if [ ! -d "poky" ]; then
        echo "  - Cloning poky..."
        git clone git://git.yoctoproject.org/poky -b ${YOCTO_BRANCH}
    else
        echo "  - poky exists, skipping"
    fi

    # meta-openembedded (meta-oe, meta-python, meta-networking)
    if [ ! -d "meta-openembedded" ]; then
        echo "  - Cloning meta-openembedded..."
        git clone git://git.openembedded.org/meta-openembedded -b ${YOCTO_BRANCH}
    else
        echo "  - meta-openembedded exists, skipping"
    fi

    # meta-raspberrypi
    if [ ! -d "meta-raspberrypi" ] && [ ! -L "meta-raspberrypi" ]; then
        echo "  - Cloning meta-raspberrypi..."
        git clone git://git.yoctoproject.org/meta-raspberrypi -b ${YOCTO_BRANCH}
    else
        echo "  - meta-raspberrypi exists, skipping"
    fi

    # meta-clang (Flutter 빌드용)
    if [ ! -d "meta-clang" ]; then
        echo "  - Cloning meta-clang..."
        git clone https://github.com/kraj/meta-clang.git -b ${YOCTO_BRANCH}
    else
        echo "  - meta-clang exists, skipping"
    fi

    # meta-flutter (Sony)
    # Note: Sony 버전은 kirkstone 기준이므로 호환성 확인 필요
    if [ ! -d "meta-flutter" ] && [ ! -L "meta-flutter" ]; then
        echo "  - Cloning meta-flutter (Sony)..."
        git clone https://github.com/sony/meta-flutter.git -b kirkstone meta-flutter
        echo "  [WARN] meta-flutter-sony is kirkstone based, may need patches for ${YOCTO_BRANCH}"
    else
        echo "  - meta-flutter exists, skipping"
    fi
}

# Parse arguments
if [ "$1" == "--link" ]; then
    setup_link
fi

setup_clone

echo ""
echo "============================================"
echo "  Layer Setup Complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. source poky/oe-init-build-env ../build"
echo "  2. Edit conf/local.conf:"
echo "       MACHINE = \"raspberrypi5\""
echo "  3. Edit conf/bblayers.conf to add layers"
echo "  4. bitbake core-image-weston"
echo ""
