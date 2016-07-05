#!/usr/bin/python

from __future__ import division
from __future__ import print_function
from __future__ import absolute_import

import sys
sys.path.append('../plinksrc')

from timings import TimingSolver
import numpy as np
# np.random.seed(42)

do_link_scramble = np.random.choice([True, False])

m2s_tdata_width = min(32, np.random.geometric(0.1));
m2s_tuser_width = min(32, np.random.geometric(0.5) - 1);

s2m_tdata_width = min(32, np.random.geometric(0.1));
s2m_tuser_width = min(32, np.random.geometric(0.5) - 1);

m2s_data = []
s2m_data = []

for i in range(100+np.random.randint(400)):
    if not i or np.random.randint(100) < 5:
        m2s_data.append([np.random.randint(2 ** m2s_tdata_width), np.random.randint(2 ** m2s_tuser_width), 0])
    else:
        m2s_data.append([np.random.randint(2 ** m2s_tdata_width), m2s_data[-1][1], 0])
    if np.random.randint(100) == 0:
        m2s_data[-1][2] = 1

for i in range(100+np.random.randint(400)):
    if not i or np.random.randint(100) < 5:
        s2m_data.append([np.random.randint(2 ** s2m_tdata_width), np.random.randint(2 ** s2m_tuser_width), 0])
    else:
        s2m_data.append([np.random.randint(2 ** s2m_tdata_width), s2m_data[-1][1], 0])
    if np.random.randint(100) == 0:
        s2m_data[-1][2] = 1

while True:
    master_parbits = np.random.choice([1, 2, 4])
    slave_parbits = np.random.choice([1, 2, 4])

    master_period = np.random.randint(5, 20)
    slave_period = np.random.randint(5, 20)

    master_pulse_jitter = np.random.uniform(0.01, 0.3 * (master_period / master_parbits))
    slave_pulse_jitter = np.random.uniform(0.01, 0.3 * (slave_period / slave_parbits))

    print("/* --- TIMING SOLVER REPORT --- **")
    print()
    print("  master_clk_period   = %6.3f" % master_period)
    print("  master_bit_period   = %6.3f" % (master_period / master_parbits))
    print("  master_pulse_jitter = %6.3f" % master_pulse_jitter)
    print("  master_parbits = %d" % master_parbits)
    print()
    print("  slave_clk_period   = %6.3f" % slave_period)
    print("  slave_bit_period   = %6.3f" % (slave_period / slave_parbits))
    print("  slave_pulse_jitter = %6.3f" % slave_pulse_jitter)
    print("  slave_parbits = %d" % slave_parbits)
    print()

    solver = TimingSolver()
    solver.find_config(0, master_period / master_parbits, slave_period / slave_parbits, master_pulse_jitter)
    solver.find_config(1, slave_period / slave_parbits, master_period / master_parbits, slave_pulse_jitter)

    print()
    print("** --- TIMING SOLVER REPORT --- */")
    print()

    all_configs_ok = True
    for v in solver.results["M2S_TT"] + solver.results["S2M_TT"] + solver.results["M2S_ST"] + solver.results["S2M_ST"]:
        if v > 255: all_configs_ok = False

    if all_configs_ok:
        break

    print("// A timing parameter is out of range: restart random timing generation")

print("`define m2s_tdata_width %d" % m2s_tdata_width)
print("`define m2s_tuser_width %d" % m2s_tuser_width)
print("`define s2m_tdata_width %d" % s2m_tdata_width)
print("`define s2m_tuser_width %d" % s2m_tuser_width)

print("`define master_clk_period_ns %.2f" % master_period)
print("`define slave_clk_period_ns %.2f" % slave_period)

print("`define master_bit_period_ns %.2f" % (master_period / master_parbits))
print("`define slave_bit_period_ns %.2f" % (slave_period / slave_parbits))

print("`define master_pulse_jitter_ns %.2f" % master_pulse_jitter)
print("`define slave_pulse_jitter_ns %.2f" % slave_pulse_jitter)

print("`define master_parbits %d" % master_parbits)
print("`define slave_parbits %d" % slave_parbits)

print("`define master_timings 80'h%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x" % (
    solver.results["M2S_TT"][4], solver.results["M2S_TT"][3], solver.results["M2S_TT"][2], solver.results["M2S_TT"][1], solver.results["M2S_TT"][0],
    solver.results["S2M_ST"][4], solver.results["S2M_ST"][3], solver.results["S2M_ST"][2], solver.results["S2M_ST"][1], solver.results["S2M_ST"][0]))

print("`define slave_timings 80'h%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x" % (
    solver.results["S2M_TT"][4], solver.results["S2M_TT"][3], solver.results["S2M_TT"][2], solver.results["S2M_TT"][1], solver.results["S2M_TT"][0],
    solver.results["M2S_ST"][4], solver.results["M2S_ST"][3], solver.results["M2S_ST"][2], solver.results["M2S_ST"][1], solver.results["M2S_ST"][0]))

print("""
`timescale 1 ns / 1 ps

module testbench;
    reg master_clk, slave_clk;
    reg master_resetn = 0;
    wire slave_resetn;

    wire master_linkerror;
    wire master_linkready;

    wire slave_linkerror;
    wire slave_linkready;

    reg [`m2s_tdata_width-1:0] master_in_tdata = 0;
    reg [`m2s_tuser_width-1:0] master_in_tuser = 0;
    reg master_in_tlast = 0;
    reg master_in_tvalid = 0;
    wire master_in_tready;

    wire [`s2m_tdata_width-1:0] master_out_tdata;
    wire [`s2m_tuser_width-1:0] master_out_tuser;
    wire master_out_tlast;
    wire master_out_tvalid;
    reg master_out_tready = 0;

    reg [`s2m_tdata_width-1:0] slave_in_tdata = 0;
    reg [`s2m_tuser_width-1:0] slave_in_tuser = 0;
    reg slave_in_tlast = 0;
    reg slave_in_tvalid = 0;
    wire slave_in_tready;

    wire [`m2s_tdata_width-1:0] slave_out_tdata;
    wire [`m2s_tuser_width-1:0] slave_out_tuser;
    wire slave_out_tlast;
    wire slave_out_tvalid;
    reg slave_out_tready = 0;

    reg [7:0] master_gpio_in = 0;
    wire [7:0] master_gpio_out;
    reg [7:0] slave_gpio_in = 0;
    wire [7:0] slave_gpio_out;

    reg link_scramble_m = 0;
    reg link_scramble_s = 0;
    reg link_scramble_idle = 0;
    wire link_scramble = link_scramble_m || link_scramble_s;
    wire link_collision;

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("testbench.vcd");
            $dumpvars(0, testbench);
        end
    end

    ponylink_test #(
        .M2S_TDATA_WIDTH(`m2s_tdata_width),
        .M2S_TUSER_WIDTH(`m2s_tuser_width),
        .S2M_TDATA_WIDTH(`s2m_tdata_width),
        .S2M_TUSER_WIDTH(`s2m_tuser_width),
        .MASTER_PARBITS(`master_parbits),
        .MASTER_TIMINGS(`master_timings),
        .SLAVE_PARBITS(`slave_parbits),
        .SLAVE_TIMINGS(`slave_timings),
        .MASTER_BIT_PERIOD_NS(`master_bit_period_ns),
        .SLAVE_BIT_PERIOD_NS(`slave_bit_period_ns),
        .MASTER_PULSE_JITTER_NS(`master_pulse_jitter_ns),
        .SLAVE_PULSE_JITTER_NS(`slave_pulse_jitter_ns)
    ) tester (
        .master_clk(master_clk),
        .master_resetn(master_resetn),
        .master_linkerror(master_linkerror),
        .master_linkready(master_linkready),

        .master_gpio_i(master_gpio_in),
        .master_gpio_o(master_gpio_out),

        .master_in_tdata(master_in_tdata),
        .master_in_tuser(master_in_tuser),
        .master_in_tlast(master_in_tlast),
        .master_in_tvalid(master_in_tvalid),
        .master_in_tready(master_in_tready),

        .master_out_tdata(master_out_tdata),
        .master_out_tuser(master_out_tuser),
        .master_out_tlast(master_out_tlast),
        .master_out_tvalid(master_out_tvalid),
        .master_out_tready(master_out_tready),

        .slave_clk(slave_clk),
        .slave_resetn(slave_resetn),
        .slave_linkerror(slave_linkerror),
        .slave_linkready(slave_linkready),

        .slave_gpio_i(slave_gpio_in),
        .slave_gpio_o(slave_gpio_out),

        .slave_in_tdata(slave_in_tdata),
        .slave_in_tuser(slave_in_tuser),
        .slave_in_tlast(slave_in_tlast),
        .slave_in_tvalid(slave_in_tvalid),
        .slave_in_tready(slave_in_tready),

        .slave_out_tdata(slave_out_tdata),
        .slave_out_tuser(slave_out_tuser),
        .slave_out_tlast(slave_out_tlast),
        .slave_out_tvalid(slave_out_tvalid),
        .slave_out_tready(slave_out_tready),

        .link_scramble(link_scramble),
        .link_scramble_idle(link_scramble_idle),
        .link_collision(link_collision)
    );

    always begin
        master_clk <= 1; #(`master_clk_period_ns / 2.0);
        master_clk <= 0; #(`master_clk_period_ns / 2.0);
    end

    always begin
        slave_clk <= 1; #(`slave_clk_period_ns / 2.0);
        slave_clk <= 0; #(`slave_clk_period_ns / 2.0);
    end

    reg ok_m2s_send = 0;
    reg ok_m2s_recv = 0;
    reg ok_s2m_send = 0;
    reg ok_s2m_recv = 0;
    reg ok_gpio = 0;

    initial begin
        repeat (100) @(posedge master_clk);
        master_resetn <= 1;
        while (!(&{ok_m2s_send, ok_m2s_recv, ok_s2m_send, ok_s2m_recv, ok_gpio})) @(posedge master_clk);
        repeat (100) @(posedge master_clk);
        $display("OK!");
        @(posedge master_clk);
        $finish;
    end

    initial begin
        @(posedge master_resetn);
        @(posedge slave_resetn);
        @(posedge link_collision);
        $display("Detected link collision at %t.", $time);
        repeat (10) @(posedge master_clk);
        repeat (10) @(posedge master_clk);
        $stop;
    end
""")

gpio_xor = np.random.randint(256);

print("    always @(posedge slave_clk)")
print("      slave_gpio_in <= slave_gpio_out ^ %d;" % gpio_xor)

print("    initial begin")
print("        @(posedge master_resetn);")
print("        repeat (100) @(posedge master_clk);")
for i in range(np.random.randint(100)):
    if np.random.randint(4) == 0:
        v = 0 if np.random.randint(2) else gpio_xor
    else:
        v = np.random.randint(256)
    print("        master_gpio_in <= %d;" % v)
    print("        while (master_gpio_out !== %d) @(posedge master_clk);" % (v ^ gpio_xor))
print("        $display(\"Finished GPIO test.\");")
print("        ok_gpio <= 1;")
print("    end")

scramble_m_countdown = np.random.randint(len(s2m_data))
scramble_s_countdown = np.random.randint(len(m2s_data))

if do_link_scramble:
    print("    initial begin")
    print("        link_scramble_idle = 1;")
    print("    end")

    print("    initial begin")
    print("        @(posedge link_scramble_m);")
    print("        repeat (%d) @(posedge master_clk);" % np.random.randint(np.random.choice([10, 20, 50, 100, 200])))
    print("        link_scramble_m = 0;")
    print("    end")

    print("    initial begin")
    print("        @(posedge link_scramble_s);")
    print("        repeat (%d) @(posedge slave_clk);" % np.random.randint(np.random.choice([10, 20, 50, 100, 200])))
    print("        link_scramble_s = 0;")
    print("    end")

else:
    print("    always @(posedge master_clk) begin")
    print("        if (master_linkerror === 1) begin")
    print("            $display(\"Master detected link error at %t.\", $time);")
    print("            repeat (20) @(posedge master_clk);")
    print("            $stop;")
    print("        end")
    print("    end")

    print("    always @(posedge slave_clk) begin")
    print("        if (slave_linkerror === 1) begin")
    print("            $display(\"Slave detected link error at %t.\", $time);")
    print("            repeat (20) @(posedge slave_clk);")
    print("            $stop;")
    print("        end")
    print("    end")

print("    initial begin")
print("        @(posedge master_resetn);")
print("        repeat (100) @(posedge master_clk);")
if np.random.choice([True, False]):
    print("        while (!master_linkready) @(posedge master_clk);")
print("        master_in_tvalid <= 1;")
for d in m2s_data:
    print("        master_in_tlast <= %d;" % d[2])
    print("        master_in_tuser <= %d;" % d[1])
    print("        master_in_tdata <= %d;" % d[0])
    print("        @(posedge master_clk);")
    print("        while (!master_in_tready) @(posedge master_clk);")
print("        master_in_tvalid <= 0;")
print("        $display(\"Finished sending M2S data.\");")
print("        ok_m2s_send <= 1;")
print("    end")

print("    initial begin")
print("        @(negedge slave_resetn);")
print("        @(posedge slave_resetn);")
print("        repeat (100) @(posedge slave_clk);")
if do_link_scramble or np.random.choice([True, False]):
    print("        while (!slave_linkready) @(posedge slave_clk);")
print("        slave_in_tvalid <= 1;")
for d in s2m_data:
    print("        slave_in_tlast <= %d;" % d[2])
    print("        slave_in_tuser <= %d;" % d[1])
    print("        slave_in_tdata <= %d;" % d[0])
    print("        @(posedge slave_clk);")
    print("        while (!slave_in_tready) @(posedge slave_clk);")
print("        slave_in_tvalid <= 0;")
print("        $display(\"Finished sending S2M data.\");")
print("        ok_s2m_send <= 1;")
print("    end")

print("    initial begin")
print("        @(negedge slave_resetn);")
print("        @(posedge slave_resetn);")
if np.random.choice([True, False]):
    print("        while (!slave_linkready) @(posedge slave_clk);")
print("        slave_out_tready <= 1;")
for d in m2s_data:
    if do_link_scramble:
        if scramble_s_countdown == 0:
            print("        link_scramble_s = 1;")
        scramble_s_countdown -= 1
    print("        @(posedge slave_clk);")
    print("        while (!slave_out_tvalid) @(posedge slave_clk);")
    if m2s_tuser_width == 0:
        print("        if (slave_out_tlast !== %d || slave_out_tdata !== %d) begin" % (d[2], d[0]))
        print("            $display(\"M2S: Expected %%b::%%b, got %%b::%%b\", 1'd%d, %d'd%d, slave_out_tlast, slave_out_tdata);" % (d[2], m2s_tdata_width, d[0]))
    else:
        print("        if (slave_out_tlast !== %d || slave_out_tuser !== %d || slave_out_tdata !== %d) begin" % (d[2], d[1], d[0]))
        print("            $display(\"M2S: Expected %%b:%%b:%%b, got %%b:%%b:%%b\", 1'd%d, %d'd%d, %d'd%d, slave_out_tlast, slave_out_tuser, slave_out_tdata);" % (d[2], m2s_tuser_width, d[1], m2s_tdata_width, d[0]))
    print("            repeat (5) @(posedge slave_clk);")
    print("            $stop;")
    print("        end")
print("        slave_out_tready <= 0;")
print("        $display(\"Finished receiving M2S data.\");")
print("        ok_m2s_recv <= 1;")
print("    end")

print("    initial begin")
print("        @(posedge master_resetn);")
if np.random.choice([True, False]):
    print("        while (!master_linkready) @(posedge master_clk);")
print("        master_out_tready <= 1;")
for d in s2m_data:
    if do_link_scramble:
        if scramble_m_countdown == 0:
            print("        link_scramble_m = 1;")
        scramble_m_countdown -= 1
    print("        @(posedge master_clk);")
    print("        while (!master_out_tvalid) @(posedge master_clk);")
    if s2m_tuser_width == 0:
        print("        if (master_out_tlast !== %d || master_out_tdata !== %d) begin" % (d[2], d[0]))
        print("            $display(\"S2M: Expected %%b::%%b, got %%b::%%b\", 1'd%d, %d'd%d, master_out_tlast, master_out_tdata);" % (d[2], s2m_tdata_width, d[0]))
    else:
        print("        if (master_out_tlast !== %d || master_out_tuser !== %d || master_out_tdata !== %d) begin" % (d[2], d[1], d[0]))
        print("            $display(\"S2M: Expected %%b:%%b:%%b, got %%b:%%b:%%b\", 1'd%d, %d'd%d, %d'd%d, master_out_tlast, master_out_tuser, master_out_tdata);" % (d[2], s2m_tuser_width, d[1], s2m_tdata_width, d[0]))
    print("            repeat (5) @(posedge master_clk);")
    print("            $stop;")
    print("        end")
print("        master_out_tready <= 0;")
print("        $display(\"Finished receiving S2M data.\");")
print("        ok_s2m_recv <= 1;")
print("    end")

print("endmodule")

