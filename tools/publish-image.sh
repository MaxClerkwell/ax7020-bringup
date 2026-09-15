#!/bin/sh
# Publish a Yocto build for the ax7020 updater: kernel, dtb and initrd plus a
# manifest, either into a local web root or onto the image server over SSH.
#
#   publish-image.sh [-i <initrd-image>] <target> [deploy-dir]
#
#   <target>   local directory            e.g. build/images
#              or  user@host:/path        e.g. AI-heimdall:/srv/ax7020-images
#   -i         which image's cpio.gz to take (default: ax7020-api-image;
#              use ax7020-initramfs for the maintenance system)
#
# Layout on the server:
#   <root>/<stamp>/{zImage,zynq-ax7020.dtb,initramfs.cpio.gz,manifest}
#   <root>/ax7020-latest -> <stamp>          (what the board fetches)
set -eu
IMG=ax7020-api-image
while getopts i: o; do case $o in i) IMG=$OPTARG;; *) exit 2;; esac; done
shift $((OPTIND-1))
TARGET=${1:?target}; DEPLOY=${2:-$(dirname "$(realpath "$0")")/../yocto/build/tmp/deploy/images/ax7020}
STAMP=$(date -u +%Y%m%d-%H%M%S)-$IMG

K=$(realpath "$DEPLOY/fitImage-linux.bin-ax7020")
D=$(realpath "$DEPLOY/zynq-ax7020-ax7020.dtb")
I=$(realpath "$DEPLOY/$IMG-ax7020.cpio.gz")

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir "$T/$STAMP"
cp "$K" "$T/$STAMP/zImage"; cp "$D" "$T/$STAMP/zynq-ax7020.dtb"; cp "$I" "$T/$STAMP/initramfs.cpio.gz"
( cd "$T/$STAMP" && {
    echo "# ax7020 image $STAMP, initrd from $IMG"
    echo "kernel zImage $(sha256sum zImage | cut -d' ' -f1)"
    echo "dtb    zynq-ax7020.dtb $(sha256sum zynq-ax7020.dtb | cut -d' ' -f1)"
    echo "initrd initramfs.cpio.gz $(sha256sum initramfs.cpio.gz | cut -d' ' -f1)"
  } > manifest )

case "$TARGET" in
*:*)
    HOST=${TARGET%%:*}; ROOT=${TARGET#*:}
    ssh "$HOST" "mkdir -p '$ROOT'"
    scp -q -r "$T/$STAMP" "$HOST:$ROOT/"
    ssh "$HOST" "cd '$ROOT' && ln -sfn '$STAMP' ax7020-latest && ls -la ax7020-latest && cat ax7020-latest/manifest"
    ;;
*)
    mkdir -p "$TARGET"; cp -r "$T/$STAMP" "$TARGET/"; ln -sfn "$STAMP" "$TARGET/ax7020-latest"
    cat "$TARGET/ax7020-latest/manifest"
    ;;
esac
