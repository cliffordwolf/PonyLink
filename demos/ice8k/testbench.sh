#!/bin/bash
set -ex
iverilog -DSIM -o testbench.exe -s testbench icedemo.v testbench.v ../../plinksrc/*.v
./testbench.exe
