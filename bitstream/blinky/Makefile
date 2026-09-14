# Open bitstream flow for the AX7020 (XC7Z020-2CLG400):
#   yosys -> nextpnr-xilinx -> fasm2frames -> xc7frames2bit
# Toolchain built from source under ../../build/ (see README).

TOP      := blinky
PART     := xc7z020clg400-1
BUILD    := ../../build
NEXTPNR  := $(BUILD)/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB   := $(BUILD)/nextpnr-xilinx/xilinx/xc7z020.bin
DB_ROOT  := $(BUILD)/nextpnr-xilinx/xilinx/external/prjxray-db
PYTHON   := $(BUILD)/venv/bin/python
F2F      := $(BUILD)/prjxray/utils/fasm2frames.py
FRM2BIT  := $(BUILD)/prjxray/build/tools/xc7frames2bit

all: $(TOP).bit

$(TOP).json: $(TOP).v
	yosys -p "synth_xilinx -flatten -abc9 -arch xc7 -top $(TOP); write_json $@" $<

$(TOP).fasm: $(TOP).json $(TOP).xdc
	$(NEXTPNR) --chipdb $(CHIPDB) --xdc $(TOP).xdc --json $(TOP).json \
	    --write $(TOP)_routed.json --fasm $@

$(TOP).frames: $(TOP).fasm
	$(PYTHON) $(F2F) --part $(PART) --db-root $(DB_ROOT)/zynq7 $< > $@

$(TOP).bit: $(TOP).frames
	$(FRM2BIT) --part_file $(DB_ROOT)/zynq7/$(PART)/part.yaml \
	    --part_name $(PART) --frm_file $< --output_file $@

clean:
	rm -f $(TOP).json $(TOP)_routed.json $(TOP).fasm $(TOP).frames $(TOP).bit

.PHONY: all clean

# .bin for the kernel's Zynq FPGA manager: strip the BIT header, byte-swap
# each 32-bit word (same layout bootgen produces).
$(TOP).bin: $(TOP).bit
	$(PYTHON) ../bit2bin.py $< $@
