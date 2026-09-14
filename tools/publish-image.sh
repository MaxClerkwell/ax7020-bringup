#!/bin/sh
# Publish a Yocto build for the ax7020 updater: copy kernel, dtb and initrd
# from the deploy directory into a web root and write a manifest.
# Usage: publish-image.sh <webroot> [deploy-dir]   (updates <webroot>/latest.manifest)
set -eu
WEB=$1
DEPLOY=${2:-$(dirname "$(realpath "$0")")/../yocto/build/tmp/deploy/images/ax7020}
STAMP=$(date -u +%Y%m%d-%H%M%S)
mkdir -p "$WEB"
K=$(realpath "$DEPLOY/fitImage-linux.bin-ax7020")
D=$(realpath "$DEPLOY/zynq-ax7020-ax7020.dtb")
I=$(realpath "$DEPLOY/ax7020-initramfs-ax7020.cpio.gz")
cp "$K" "$WEB/zImage-$STAMP"; cp "$D" "$WEB/zynq-ax7020-$STAMP.dtb"; cp "$I" "$WEB/initramfs-$STAMP.cpio.gz"
M="$WEB/$STAMP.manifest"
{
  echo "# ax7020 image, published $STAMP from $DEPLOY"
  echo "kernel zImage-$STAMP $(sha256sum "$WEB/zImage-$STAMP" | cut -d' ' -f1)"
  echo "dtb    zynq-ax7020-$STAMP.dtb $(sha256sum "$WEB/zynq-ax7020-$STAMP.dtb" | cut -d' ' -f1)"
  echo "initrd initramfs-$STAMP.cpio.gz $(sha256sum "$WEB/initramfs-$STAMP.cpio.gz" | cut -d' ' -f1)"
} > "$M"
ln -sfn "$STAMP.manifest" "$WEB/latest.manifest"
cat "$M"
