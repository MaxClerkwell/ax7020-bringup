#!/bin/sh
# Write an image into a flash partition of the running board over SSH (no
# JTAG, no jumper): upload, write through /dev/mtdblockN (erases by itself),
# read back and compare md5. ~10 min for a 20 MB FIT at QSPI speed.
#
#   flash-fit.sh <board-ip> <image> [mtd-index]
#
#   mtd-index  3 = "fit" (default), 1 = "u-boot" (u-boot.img). Never 0 or 2
#              from here: boot.bin needs the JTAG procedure, the env is U-Boot's.
set -eu
BOARD=$1; IMG=$2; MTD=${3:-3}
case "$MTD" in 1|3) ;; *) echo "refusing to write mtd$MTD from this script" >&2; exit 1;; esac
SZ=$(stat -c %s "$IMG"); MD5=$(md5sum < "$IMG" | cut -d' ' -f1)
[ $((SZ % 4)) -eq 0 ] || { echo "size not a multiple of 4, read-back uses bs=4" >&2; exit 1; }
echo "local:    $MD5  ($SZ bytes) -> mtd$MTD"
ssh -o BatchMode=yes "root@$BOARD" "cat > /tmp/flash.img" < "$IMG"
ssh -o BatchMode=yes "root@$BOARD" "
  echo \"uploaded: \$(md5sum < /tmp/flash.img | cut -d' ' -f1)\"
  grep -q '^mtd$MTD:' /proc/mtd || { echo 'no such mtd partition' >&2; exit 1; }
  dd if=/tmp/flash.img of=/dev/mtdblock$MTD bs=64k 2>&1 | tail -1; sync; echo \"dd exit: \$?\"
  echo \"flash:    \$(dd if=/dev/mtdblock$MTD bs=4 count=$(( SZ / 4 )) 2>/dev/null | md5sum | cut -d' ' -f1)\"
" 2>&1 | grep -v -i 'quantum\|decrypt\|pq.html'
echo "expected: $MD5 - all three lines must match"
