
# vivado -nojournal -nolog -mode batch -source zybo_prog.tcl

connect_hw_server
open_hw_target [lindex [get_hw_targets] 0]
set_property PROGRAM.FILE zybo.bit [lindex [get_hw_devices] 1]
program_hw_devices [lindex [get_hw_devices] 1]

