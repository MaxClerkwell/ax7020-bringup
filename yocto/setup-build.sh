#!/bin/bash
# Create (or refresh) the Yocto build directory for the Alinx AX7020.
#
#   source yocto/setup-build.sh        # sets up and enters the build env
#   bitbake ax7020-image
#
# Layers are expected next to this script (clone them with the commands in the
# top-level README if they are missing).
# poky's oe-init-build-env references unset variables, so no "set -u" here
set -e

YOCTO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${YOCTO_DIR}/build"

# Yocto's HOSTTOOLS list still wants "lz4c", a name Debian's lz4 >= 1.10 no
# longer ships. hostbin/ carries a symlink so this needs no root.
case ":${PATH}:" in
    *":${YOCTO_DIR}/hostbin:"*) ;;
    *) PATH="${YOCTO_DIR}/hostbin:${PATH}"; export PATH ;;
esac

for l in poky meta-xilinx meta-openembedded meta-arm meta-ax7020; do
    if [ ! -d "${YOCTO_DIR}/${l}" ]; then
        echo "missing layer: ${YOCTO_DIR}/${l}" >&2
        return 1 2>/dev/null || exit 1
    fi
done

# poky's script creates conf/ on first run and then leaves it alone
source "${YOCTO_DIR}/poky/oe-init-build-env" "${BUILD_DIR}" >/dev/null || \
    { echo "oe-init-build-env failed" >&2; return 1 2>/dev/null || exit 1; }

cat > "${BUILD_DIR}/conf/bblayers.conf" <<CONF
POKY_BBLAYERS_CONF_VERSION = "2"
BBPATH = "\${TOPDIR}"
BBFILES ?= ""

BBLAYERS ?= " \\
  ${YOCTO_DIR}/poky/meta \\
  ${YOCTO_DIR}/poky/meta-poky \\
  ${YOCTO_DIR}/poky/meta-yocto-bsp \\
  ${YOCTO_DIR}/meta-openembedded/meta-oe \\
  ${YOCTO_DIR}/meta-openembedded/meta-python \\
  ${YOCTO_DIR}/meta-openembedded/meta-networking \\
  ${YOCTO_DIR}/meta-arm/meta-arm-toolchain \\
  ${YOCTO_DIR}/meta-arm/meta-arm \\
  ${YOCTO_DIR}/meta-xilinx/meta-xilinx-core \\
  ${YOCTO_DIR}/meta-xilinx/meta-xilinx-bsp \\
  ${YOCTO_DIR}/meta-ax7020 \\
  "
CONF

cat > "${BUILD_DIR}/conf/local.conf" <<CONF
MACHINE ?= "ax7020"
DISTRO ?= "poky"
PACKAGE_CLASSES ?= "package_ipk"

# systemd on both images: the API is a systemd service, and one init system
# for maintenance and development image keeps the recipes simple.
INIT_MANAGER = "systemd"

# 3 of 6 cores, so the workstation stays usable during builds
BB_NUMBER_THREADS ?= "3"
PARALLEL_MAKE ?= "-j 3"

# Shared across rebuilds; safe to delete to reclaim space
DL_DIR ?= "${YOCTO_DIR}/downloads"
SSTATE_DIR ?= "${YOCTO_DIR}/sstate-cache"
TMPDIR = "\${TOPDIR}/tmp"

# meta-xilinx wants to know which release the kernel/u-boot recipes track
XILINX_RELEASE_VERSION ?= "v2024.2"

# We supply our own U-Boot from mainline (see uboot/), so Yocto only needs to
# produce a kernel, a device tree and a root filesystem.
PREFERRED_PROVIDER_virtual/bootloader = ""

# Accept the Xilinx licence for the microcode-free bits we do use
LICENSE_FLAGS_ACCEPTED += "xilinx"

CONF_VERSION = "2"
CONF

echo "build dir:  ${BUILD_DIR}"
echo "machine:    ax7020"
echo
echo "next:  bitbake virtual/kernel   # kernel + DTB + initramfs -> one FIT"
