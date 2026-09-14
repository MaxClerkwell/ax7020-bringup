#!/bin/sh
# Dump the kernel printk buffer from DDR via a mem_ap target (no CPU halt).
# Usage: jtag-logbuf.sh [out.bin]   (needs the kernel build dir for System.map)
cd "$(dirname "$0")/../.."
OUT=${1:-logbuf.bin}
B=yocto/build/tmp/work/ax7020-poky-linux-gnueabi/linux-xlnx/6.6.40+git/linux-ax7020-standard-build
V=$(grep ' __log_buf$' $B/System.map | cut -d' ' -f1)
SHIFT=$(sed -n 's/^CONFIG_LOG_BUF_SHIFT=//p' $B/.config)
PHYS=$(printf '0x%08x' $((0x$V - 0xC0000000)))
LEN=$(printf '0x%x' $((1 << SHIFT)))
openocd -f openocd/ft232h.cfg -f target/zynq_7000.cfg \
  -c 'target create zynq.axi mem_ap -dap zynq.dap -ap-num 0' \
  -c "init; targets zynq.axi; dump_image $OUT $PHYS $LEN; shutdown" >/dev/null 2>&1
strings -n 8 "$OUT" | tail -40
