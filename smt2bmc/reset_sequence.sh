#!/bin/bash
set -ex
yosys -v3 reset_sequence.ys
python3 -u reset_sequence.py -d reset_sequence.dbg | tee reset_sequence.log
