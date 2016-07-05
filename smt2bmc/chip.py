#!/usr/bin/env python3

import sys, getopt
from smtio import *

steps = 1000
so = smtopts()

def usage():
    print("""
python3 slave_send_length.py [options]

    -t <steps>
        default: 1000
""" + so.helpmsg())
    sys.exit(1)

try:
    opts, args = getopt.getopt(sys.argv[1:], "s:t:vd")
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
smt.setup("QF_AUFBV", "PonyLink 'chip.py' test, Powered by Yosys")

with open("chip.smt2", "r") as f:
    for line in f:
        smt.write(line)

found_max_range = False

for step in range(steps):
    print("%s Searching for send sequence of length %d.." % (smt.timestamp(), step+1))
    smt.write("(declare-fun s%d () chip_s)" % step)
    smt.write("(assert (|chip_n pin_F16| s%d))" % step)

    if step != 0:
        smt.write("(assert (chip_t s%d s%d))" % (step-1, step))

    if smt.check_sat() == "unsat":
            found_max_range = True
            print("%s Maximum send length reached.\n")
            break

print("%s Done." % smt.timestamp())
smt.write("(exit)")
smt.wait()

