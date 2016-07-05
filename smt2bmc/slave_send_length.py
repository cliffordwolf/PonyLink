#!/usr/bin/env python3

import sys, getopt, re
from smtio import *
from time import time

steps = 650
so = smtopts()

def usage():
    print("""
python3 slave_send_length.py [options]

    -t <steps>
        default: 650
""" + so.helpmsg())
    sys.exit(1)

try:
    opts, args = getopt.getopt(sys.argv[1:], so.optstr + "t:")
except:
    usage()

for o, a in opts:
    if o == "-t":
        steps = int(a)
    elif so.handle(o, a):
        pass
    else:
        usage()

if len(args) > 0:
    usage()

smt = smtio(opts=so)

print("Solver: %s" % so.solver)
smt.setup("QF_AUFBV", "PonyLink 'slave_send_length.py' test, Powered by Yosys")

debug_nets = set()
debug_nets_re = re.compile(r"^; yosys-smt2-(input|output|register|wire) (\S+) (\d+)")
with open("slave_send_length.smt2", "r") as f:
    for line in f:
        match = debug_nets_re.match(line)
        if match:
            debug_nets.add(match.group(2))
        smt.write(line)

def write_vcd_model(num_steps):
    print("%s Writing model to VCD file." % smt.timestamp())

    vcd = mkvcd(open("slave_send_length.vcd", "w"))
    for netname in sorted(debug_nets):
        width = len(smt.get_net_bin("main", netname, "s0"))
        vcd.add_net(netname, width)

    for step in range(num_steps):
        vcd.set_time(step)
        for netname in debug_nets:
            vcd.set_net(netname, smt.get_net_bin("main", netname, "s%d" % step))

mode="TX"
last_dump_time = time()
last_dump_step = -90

for step in range(steps):
    print("%s Searching for %s sequence of length %d.." % (smt.timestamp(), mode, step+1))
    smt.write("(declare-fun s%d () main_s)" % step)

    if step != 0:
        smt.write("(assert (main_t s%d s%d))" % (step-1, step))

    smt.write("(push 1)")
    smt.write("(assert (|main_n serdes_en| s%d))" % step)

    if smt.check_sat() == "unsat":
            if mode == "TX":
                print("%s Maximum TX length reached." % smt.timestamp())
            else:
                print("%s No TX possible in this cycle." % smt.timestamp())

            smt.write("(pop 1)")
            assert smt.check_sat() == "sat"
            mode="extended TX/RX"

    if last_dump_time + 10 < time() or last_dump_step + 100 < step:
        write_vcd_model(step+1)
        last_dump_time = time()
        last_dump_step = step

if last_dump_step != steps-1:
    write_vcd_model(steps)

print("%s Done." % smt.timestamp())
smt.write("(exit)")
smt.wait()

