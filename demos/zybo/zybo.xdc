
set_property PACKAGE_PIN L16 [get_ports iclk]
set_property IOSTANDARD LVCMOS33 [get_ports iclk]
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports iclk]

set_property PACKAGE_PIN P14 [get_ports master_pin]
set_property IOSTANDARD LVCMOS33 [get_ports master_pin]

set_property PACKAGE_PIN V17 [get_ports slave_pin]
set_property IOSTANDARD LVCMOS33 [get_ports slave_pin]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets iclk_IBUF] 

