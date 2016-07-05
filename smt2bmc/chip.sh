#!/bin/bash
set -ex
# iceunpack chip.bin chip.txt
# icebox_vlog -ls chip.txt > chip.v
yosys -v3 chip.ys
python3 -u chip.py -d chip.dbg | tee chip.log
