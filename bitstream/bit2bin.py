#!/usr/bin/env python3
"""Convert a Xilinx .bit to the .bin the Zynq FPGA manager expects:
drop the BIT header, byte-swap every 32-bit word."""
import sys, struct

raw = open(sys.argv[1], "rb").read()
sync = raw.find(bytes.fromhex("AA995566"))
if sync < 0:
    sys.exit("no sync word found — not a bitstream?")
# keep the 0xFF padding words directly before the sync word
start = sync
while start >= 4 and raw[start-4:start] == b"\xff\xff\xff\xff":
    start -= 4
data = raw[start:]
if len(data) % 4:
    sys.exit("bitstream data not word-aligned")
out = bytearray(len(data))
for i in range(0, len(data), 4):
    out[i:i+4] = data[i:i+4][::-1]
open(sys.argv[2], "wb").write(out)
