################################################################################
#
# domoticz — HomeAgent override of Buildroot's package, bumped 2024.4 -> 2026.3.
#
# Two reasons this file exists instead of the upstream recipe:
#
# 1. VERSION. Buildroot pins 2024.4 (still true on master, 2026-08-27), which
#    is years behind and not what the evidence lane runs. 2026.3 is the version
#    verified and shipped here, and the one the evidence lane runs.
#
# 2. DOWNLOAD METHOD. The GitHub tag tarball ships extern/ as five EMPTY
#    directories, and CMakeLists.txt:151-162 turns that into a fatal error.
#    Turning every USE_BUILTIN_* off does not help: extern/libwebem is pulled in
#    unconditionally (CMakeLists.txt:471, `target_link_libraries(domoticz webem)`).
#    So the submodules are not optional -> git method with submodules, whose
#    revisions the tag's gitlinks pin, keeping the download reproducible.
#
################################################################################

DOMOTICZ_VERSION = 2026.3
DOMOTICZ_SITE = https://github.com/domoticz/domoticz.git
DOMOTICZ_SITE_METHOD = git
DOMOTICZ_GIT_SUBMODULES = YES
DOMOTICZ_LICENSE = GPL-3.0
DOMOTICZ_LICENSE_FILES = License.txt
DOMOTICZ_CPE_ID_VENDOR = domoticz
DOMOTICZ_DEPENDENCIES = \
	boost \
	cereal \
	host-pkgconf \
	libcurl \
	lua \
	mosquitto \
	openssl \
	sqlite \
	zlib

# Disable precompiled header as it needs cmake >= 3.16
DOMOTICZ_CONF_OPTS = -DUSE_PRECOMPILED_HEADER=OFF

# Due to the dependency on mosquitto, domoticz depends on
# !BR2_STATIC_LIBS so set USE_STATIC_BOOST and USE_OPENSSL_STATIC to OFF.
# Boost cannot be static here anyway: Buildroot builds it link=shared only
# unless BR2_STATIC_LIBS is set globally, which domoticz forbids. The four
# boost libraries therefore ride along in the .ipk.
DOMOTICZ_CONF_OPTS += \
	-DUSE_STATIC_BOOST=OFF \
	-DUSE_OPENSSL_STATIC=OFF

# Swallow statically what the device lacks, use the rootfs copy of what it has.
# Measured on the live unit (docs/SMHUB.md §4.1): sqlite, curl, ssl, mosquitto,
# jsoncpp, zlib and libpython3.14 are present; minizip is NOT. Keeping jsoncpp
# and jwt-cpp builtin costs nothing and removes two ABI surfaces from the .ipk.
# (2026.3 dropped USE_BUILTIN_MQTT entirely - `find_library(libmosquitto.so)`
# is now unconditional, so the system library is the only path.)
DOMOTICZ_CONF_OPTS += \
	-DUSE_BUILTIN_JSONCPP=ON \
	-DUSE_BUILTIN_MINIZIP=ON \
	-DUSE_BUILTIN_JWTCPP=ON \
	-DUSE_BUILTIN_SQLITE=OFF

ifeq ($(BR2_PACKAGE_LIBEXECINFO),y)
DOMOTICZ_DEPENDENCIES += libexecinfo
DOMOTICZ_CONF_OPTS += -DEXECINFO_LIBRARIES=-lexecinfo
endif

ifeq ($(BR2_PACKAGE_LIBUSB),y)
DOMOTICZ_DEPENDENCIES += libusb
DOMOTICZ_CONF_OPTS += -DWITH_LIBUSB=ON
else
DOMOTICZ_CONF_OPTS += -DWITH_LIBUSB=OFF
endif

ifeq ($(BR2_PACKAGE_OPENZWAVE),y)
DOMOTICZ_DEPENDENCIES += openzwave
DOMOTICZ_CONF_OPTS += -DUSE_STATIC_OPENZWAVE=OFF
endif

# 2026.3 replaced the old PythonLibs probe with
# `find_package(Python3 3.4 COMPONENTS Development)` (CMakeLists.txt:508).
# FindPython3 drives its search from a *target* interpreter, which a cross
# build does not have, so it reports Development as missing even though the
# sysroot holds both halves. Handing it the two cache variables directly is
# the documented way out; the paths are the ones python3 staged.
ifeq ($(BR2_PACKAGE_PYTHON3),y)
DOMOTICZ_DEPENDENCIES += python3
DOMOTICZ_CONF_OPTS += \
	-DUSE_PYTHON=ON \
	-DPython3_INCLUDE_DIR=$(STAGING_DIR)/usr/include/python$(PYTHON3_VERSION_MAJOR) \
	-DPython3_LIBRARY=$(STAGING_DIR)/usr/lib/libpython$(PYTHON3_VERSION_MAJOR).so
else
DOMOTICZ_CONF_OPTS += -DUSE_PYTHON=OFF
endif

# Install domoticz in a dedicated directory (/opt/domoticz) as domoticz expects
# by default that all its subdirectories (www, Config, scripts, ...) are in the
# binary directory. On SMHub /opt is p7 — the only surface that survives OTA.
DOMOTICZ_TARGET_DIR = /opt/domoticz
DOMOTICZ_CONF_OPTS += -DCMAKE_INSTALL_PREFIX=$(DOMOTICZ_TARGET_DIR)

# Delete License.txt and updatedomo files installed by domoticz in target
# directory. Do not delete History.txt as it is used in source code.
define DOMOTICZ_REMOVE_UNNEEDED_FILES
	$(RM) $(TARGET_DIR)/$(DOMOTICZ_TARGET_DIR)/License.txt
	$(RM) $(TARGET_DIR)/$(DOMOTICZ_TARGET_DIR)/updatedomo
endef

DOMOTICZ_POST_INSTALL_TARGET_HOOKS += DOMOTICZ_REMOVE_UNNEEDED_FILES

# No init script is installed: SMHub runs OpenRC, not Buildroot's sysV/systemd,
# and its service file belongs to the .ipk (smhub/pack-ipk.sh), not here.

$(eval $(cmake-package))
