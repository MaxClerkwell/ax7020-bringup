SUMMARY = "AX7020 development image: the bitstream REST API, started by systemd"
DESCRIPTION = "Fetched over the network by the maintenance system and started \
with kexec; never written to flash. Carries Python, FastAPI, uvicorn and uv. \
It deliberately does NOT carry ax7020-updater: with IMAGE_URL set it would \
kexec into itself forever."
LICENSE = "MIT"

require recipes-core/images/core-image-minimal.bb

IMAGE_FSTYPES = "cpio.gz"

# Python plus its modules make ~140 MB uncompressed; the default cap of 128 MB
# is meant for boards with far less than our 1 GiB. Half the RAM is the rule.
INITRAMFS_MAXSIZE = "524288"
IMAGE_NAME_SUFFIX = ""
IMAGE_FEATURES += "ssh-server-dropbear"

IMAGE_INSTALL:append = " \
    ax7020-api \
    ax7020-ssh-key \
    uv \
    python3-core python3-modules \
    curl ca-certificates ethtool \
    "

IMAGE_OVERHEAD_FACTOR = "1.0"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"
