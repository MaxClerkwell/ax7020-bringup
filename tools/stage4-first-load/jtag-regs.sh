#!/bin/sh
# Read devcfg / SLCR / GEM registers over the DAP's AHB-AP while Linux keeps running.
cd "$(dirname "$0")/../.."
exec openocd -f openocd/ft232h.cfg -f target/zynq_7000.cfg -c '
  init
  zynq.dap apreg 0 0x00 0x23000052
  foreach {n a} {BOOT_MODE 0xF800025C DEVCFG_CTRL 0xF8007000 DEVCFG_INT_STS 0xF800700C
                 DEVCFG_STATUS 0xF8007014 DMA_SRC 0xF8007018 DMA_SRC_LEN 0xF8007020
                 FPGA_RST_CTRL 0xF8000240 LVL_SHFTR_EN 0xF8000900 SLCR_LOCKSTA 0xF800000C
                 GEM0_NWCTRL 0xE000B000 GEM0_NWSR 0xE000B008} {
    zynq.dap apreg 0 0x04 $a; echo "$n [zynq.dap apreg 0 0x0C]" }
  shutdown' 2>&1 | grep -E '^[A-Z_0-9]+ 0x|Error'
