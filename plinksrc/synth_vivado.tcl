
# vivado -nojournal -log synth_vivado.log -mode batch -source synth_vivado.tcl

read_verilog ponylink_master.v
read_verilog ponylink_slave.v
read_verilog ponylink_pack.v
read_verilog ponylink_txrx.v
read_verilog ponylink_8b10b.v
read_verilog ponylink_crc32.v
read_xdc synth_vivado.xdc

synth_design -part xc7z010clg400-2 -top ponylink_master
opt_design
place_design
route_design

report_utilization
report_timing

write_verilog -force synth_vivado.v

