#!/bin/sh
# Halt each core briefly, print pc/cpsr, resume. Resolve with System.map.
cd "$(dirname "$0")/../.."
B=yocto/build/tmp/work/ax7020-poky-linux-gnueabi/linux-xlnx/6.6.40+git/linux-ax7020-standard-build
openocd -f openocd/ft232h.cfg -f target/zynq_7000.cfg -c '
  init
  targets zynq.cpu0; halt; reg pc; reg cpsr; resume
  targets zynq.cpu1; halt; reg pc; reg cpsr; resume
  shutdown' 2>&1 | grep -E 'cpsr|Error' | while read -r l; do
    pc=$(echo "$l" | sed -n 's/.*pc: 0x\([0-9a-f]*\).*/\1/p')
    sym=$(awk -v A="$pc" '$1<=A' $B/System.map | sort | tail -1)
    echo "$l   -> $sym"
  done
