SUMMARY = "AX7020 maintenance system: boots from flash, fetches the real image"
DESCRIPTION = "Permanent resident of the QSPI flash. It brings up the network, \
sets the clock, fetches a development image over the network and kexecs into \
it. If any of that fails it stays put and remains reachable over SSH, which is \
why it is kept separate from whatever is being developed."
LICENSE = "MIT"

require recipes-core/images/core-image-minimal.bb

# Root filesystem lives in RAM; the board has 1 GiB, the flash has 32 MiB.
IMAGE_FSTYPES = "cpio.gz"

# scarthgap appends ".rootfs" to image names, but kernel-fitimage looks for
# "<image>-<machine>.cpio.gz" without it. poky's own initramfs recipes clear
# the suffix for exactly this reason.
IMAGE_NAME_SUFFIX = ""

# dropbear, not openssh: with the rootfs resident in QSPI its ~1 MB footprint
# is the deciding factor. Swap for "ssh-server-openssh" once the rootfs moves
# to SD or NFS and size stops mattering.
IMAGE_FEATURES += "ssh-server-dropbear"

IMAGE_INSTALL:append = " \
    ax7020-updater \
    ax7020-ssh-key \
    curl \
    ca-certificates \
    kexec \
    ethtool \
    "

# Key authentication only. "debug-tweaks" is deliberately NOT set: it would
# give root an empty password, which is untenable now that the board lives on
# a shared network. The operator's key comes from ax7020-ssh-key, and dropbear
# is started with -s so no password is ever accepted.

# Keep the cpio small - no spare space, no locales
IMAGE_OVERHEAD_FACTOR = "1.0"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"
