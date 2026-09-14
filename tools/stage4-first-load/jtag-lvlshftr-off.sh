#!/bin/sh
# Counter-test: disconnect PL from PS by clearing LVL_SHFTR_EN (SLCR must be unlocked).
cd "$(dirname "$0")/../.."
exec openocd -f openocd/ft232h.cfg -f target/zynq_7000.cfg -c '
  init
  zynq.dap apreg 0 0x00 0x23000052
  zynq.dap apreg 0 0x04 0xF8000008; zynq.dap apreg 0 0x0C 0xDF0D
  zynq.dap apreg 0 0x04 0xF8000900; zynq.dap apreg 0 0x0C 0x0
  echo "LVL_SHFTR_EN [zynq.dap apreg 0 0x0C]"
  shutdown' 2>&1 | grep -E '^LVL|Error'
