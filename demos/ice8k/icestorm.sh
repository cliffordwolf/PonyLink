#!/bin/bash
set -ex
yosys -v9 -p 'synth_ice40 -top icedemo -blif icedemo_out.blif' icedemo.v \
		../../plinksrc/ponylink_{8b10b,crc32,master,pack,slave,txrx}.v
arachne-pnr -d 8k -o icedemo_out.txt -p icedemo.pcf icedemo_out.blif
icepack icedemo_out.txt icedemo_out.bin
