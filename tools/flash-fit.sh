#!/bin/sh
# Write a FIT into the "fit" partition of the running board over SSH (no JTAG,
# no jumper). Uploads the file, writes it through /dev/mtdblock3 (which erases
# by itself), reads it back and compares md5. Takes ~10 min at QSPI speed.
# Usage: flash-fit.sh <board-ip> <fitImage>
set -eu
BOARD=$1; FIT=$2
SZ=$(stat -c %s "$FIT"); MD5=$(md5sum < "$FIT" | cut -d' ' -f1)
echo "local:    $MD5  ($SZ bytes)"
ssh -o BatchMode=yes "root@$BOARD" "cat > /tmp/fitImage" < "$FIT"
ssh -o BatchMode=yes "root@$BOARD" "
  echo \"uploaded: \$(md5sum < /tmp/fitImage | cut -d' ' -f1)\"
  dd if=/tmp/fitImage of=/dev/mtdblock3 bs=64k conv=fsync 2>/dev/null; sync
  echo \"flash:    \$(dd if=/dev/mtdblock3 bs=64k count=$(( (SZ + 65535) / 65536 )) 2>/dev/null | head -c $SZ | md5sum | cut -d' ' -f1)\"
" 2>&1 | grep -v -i 'quantum\|decrypt\|pq.html'
echo "expected: $MD5 - all three lines must match"
