
# vivado -nojournal -nolog -mode batch -source zybo_synth.tcl

create_project -part xc7z010clg400-2 -in_memory

read_verilog zybo.v
read_xdc zybo.xdc

read_verilog ../../plinksrc/ponylink_master.v
read_verilog ../../plinksrc/ponylink_slave.v
read_verilog ../../plinksrc/ponylink_pack.v
read_verilog ../../plinksrc/ponylink_txrx.v
read_verilog ../../plinksrc/ponylink_8b10b.v
read_verilog ../../plinksrc/ponylink_crc32.v

synth_design -top top
opt_design
place_design
route_design
report_timing

write_bitstream -force zybo.bit

