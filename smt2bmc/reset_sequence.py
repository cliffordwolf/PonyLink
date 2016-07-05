#!/usr/bin/env python3

import sys, getopt, re
from smtio import *
from time import time
from shutil import copyfile

so = smtopts()


def usage():
    print("""
python3 reset_sequence.py [options]
""" + so.helpmsg())
    sys.exit(1)


try:
    opts, args = getopt.getopt(sys.argv[1:], so.optstr)
except:
    usage()

for o, a in opts:
    if so.handle(o, a):
        pass
    else:
        usage()

if len(args) > 0:
    usage()


print("Solver: %s" % so.solver)

smt = smtio(opts=so)
smt.setup("QF_AUFBV", "PonyLink 'reset_sequence.py' test, Powered by Yosys")

debug_nets = set()
debug_nets_re = re.compile(r"^; yosys-smt2-(input|output|register|wire) (\S+) (\d+)")
with open("reset_sequence.smt2", "r") as f:
    for line in f:
        match = debug_nets_re.match(line)
        if match:
            debug_nets.add(match.group(2))
        smt.write(line)


last_dump_time = time()
last_dump_step = -90
mode_min = True
step = -1


def add_step():
    global step
    step += 1

    print("%s Adding time step %d." % (smt.timestamp(), step))
    smt.write("(declare-fun s%d () main_s)" % step)

    if step == 0:
        smt.write("(assert (|main_n reset| s%d))" % step)

    else:
        smt.write("(assert (not (|main_n reset| s%d)))" % step)
        smt.write("(assert (main_t s%d s%d))" % (step-1, step))


def write_vcd_model():
    print("%s Writing model to VCD file." % smt.timestamp())

    vcd = mkvcd(open("reset_sequence.vcd", "w"))
    for netname in sorted(debug_nets):
        width = len(smt.get_net_bin("main", netname, "s0"))
        vcd.add_net(netname, width)

    for i in range(step):
        vcd.set_time(i)
        for netname in debug_nets:
            vcd.set_net(netname, smt.get_net_bin("main", netname, "s%d" % i))


print("%s PHASE 1: Minimal length search" % smt.timestamp())

add_step()

while True:
    for i in range(10):
        add_step()

    print("%s Searching for minimal length reset sequence.." % smt.timestamp())

    smt.write("(push 1)")
    smt.write("(assert (|main_n out_finish| s%d))" % step)

    if smt.check_sat() == "unsat":
        print("%s [unsat] no such reset sequence." % smt.timestamp())
        smt.write("(pop 1)")

        if step % 50 == 0:
            print("%s Creating unconstrained model.." % smt.timestamp())
            assert smt.check_sat() == "sat"
            write_vcd_model()

    else:
        print("%s [sat] reset sequence found." % smt.timestamp())
        write_vcd_model()
        copyfile("reset_sequence.vcd", "reset_sequence_min.vcd")
        smt.write("(pop 1)")
        break


print("%s PHASE 2: Maximal length search" % smt.timestamp())

while True:
    for i in range(10):
        add_step()

    print("%s Searching for maximal length reset sequence.." % smt.timestamp())

    smt.write("(push 1)")
    smt.write("(assert (not (|main_n out_finish| s%d)))" % step)

    if smt.check_sat() == "unsat":
        print("%s [unsat] maximal length reached." % smt.timestamp())
        smt.write("(pop 1)")
        break

    else:
        print("%s [sat] reset sequence found." % smt.timestamp())
        write_vcd_model()


print("%s PHASE 3: Maximal length refinement" % smt.timestamp())

for i in range(step-10, step+1):
    print("%s Testing length %d.." % (smt.timestamp(), i))

    smt.write("(push 1)")
    smt.write("(assert (not (|main_n out_finish| s%d)))" % i)

    if smt.check_sat() == "unsat":
        print("%s [unsat] maximal length reached." % smt.timestamp())
        smt.write("(pop 1)")
        copyfile("reset_sequence.vcd", "reset_sequence_max.vcd")
        break

    else:
        print("%s [sat] reset sequence found." % smt.timestamp())
        write_vcd_model()


print("%s Done." % smt.timestamp())
smt.write("(exit)")
smt.wait()

