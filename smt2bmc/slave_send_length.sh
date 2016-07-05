#!/bin/bash
set -ex
yosys -v3 slave_send_length.ys
python3 -u slave_send_length.py -d slave_send_length.dbg | tee slave_send_length.log
