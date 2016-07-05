#!/usr/bin/python
#
# Example usage:
# python timings.py 6 19 0.25 1.5

from __future__ import division
from __future__ import print_function

import sys
import numpy as np
import matplotlib.pyplot as plt

class TimingSolver:
    def __init__(self):
        # the values for self.lendist come from bitdist.py
        self.lendist = [ 0.32735297, 0.36519647, 0.21898804, 0.07264801, 0.0158145 ]
        self.results = { }

    def test_recv_timings(self, transmit_period, sample_period, pulse_jitter, transmit_timings, verbose):
        sample_timings = [ ]
        last_maxsamples = 0
        if verbose:
            print("Timing for transmit_period=%.3f ns (%.2f MHz) and sample_period=%.3f ns (%.2f MHz)" % (transmit_period, 1000 / transmit_period, sample_period, 1000 / sample_period))
            print("    transmit timings: %s" % transmit_timings)
        for bits in range(1, len(transmit_timings)+1):
            minsamples = int((transmit_timings[bits-1] * transmit_period - pulse_jitter) / sample_period)
            maxsamples = int((transmit_timings[bits-1] * transmit_period + pulse_jitter) / sample_period + 1)
            if verbose:
                print("    %2d - %2d identical samples  -> %d bit%s" % (minsamples, maxsamples, bits, "s" if bits != 1 else ""))
            if minsamples <= last_maxsamples:
                if verbose:
                    print("    collision!")
                return []
            last_maxsamples = maxsamples
            sample_timings.append(minsamples)
        return sample_timings

    def find_config(self, direction, send_period, recv_period, pulse_jitter):
        print()
        print("** FINDING TIMING CONFIG FOR DIRECTION '%s' **" % ("MASTER -> SLAVE" if direction == 0 else "SLAVE -> MASTER"))
        transmit_timings = []
        for bits in range(1, 6):
            transmit_timings.append(1 if bits <= 1 else transmit_timings[-1] + 1)
            while True:
                sample_timings = self.test_recv_timings(send_period, recv_period, pulse_jitter, transmit_timings, False)
                if len(sample_timings) > 0:
                    break
                transmit_timings[-1] += 1
        self.test_recv_timings(send_period, recv_period, pulse_jitter, transmit_timings, True)
        print("Bitrate vs. pulse length:");
        avgbitrate = 0
        for bits in range(1, 6):
            print("    @%d: %6.2f MBit/s  (expected %2d%%)" % (bits, (1000 / send_period) * bits / transmit_timings[bits-1], 100*self.lendist[bits-1]))
            avgbitrate += self.lendist[bits-1] * (1000 / send_period) * bits / transmit_timings[bits-1]
        print("    ==> %6.2f MBit/s  (expected avg.)" % avgbitrate)
        self.results["M2S_BW" if direction == 0 else "S2M_BW"] = avgbitrate
        self.results["M2S_TT" if direction == 0 else "S2M_TT"] = transmit_timings
        self.results["M2S_ST" if direction == 0 else "S2M_ST"] = sample_timings
        print("TRANSMIT TIMINGS: %s" % transmit_timings);
        print("SAMPLE TIMINGS: %s" % sample_timings);

if __name__ == "__main__":
    if len(sys.argv) == 5:
        master_period = float(sys.argv[1])
        slave_period = float(sys.argv[2])
        m2s_pulse_jitter = float(sys.argv[3])
        s2m_pulse_jitter = float(sys.argv[4])

        print()
        print("** TIMING SPECIFICATION SUMMARY **")
        print("    Master clock: %.3f ns (%.2f MHz)" % (master_period, 1000 / master_period))
        print("    Slave clock: %.3f ns (%.2f MHz)" % (slave_period, 1000 / slave_period))
        print("    Master->Slave pulse jitter: %.3f ns" % (m2s_pulse_jitter))
        print("    Slave->Master pulse jitter: %.3f ns" % (s2m_pulse_jitter))

        solver = TimingSolver()
        solver.find_config(0, master_period, slave_period, m2s_pulse_jitter);
        solver.find_config(1, slave_period, master_period, s2m_pulse_jitter);

        print()
        print("** CORE CONFIGURATION **")
        print(".MASTER_TIMINGS(80'h%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x)," % (
                solver.results["M2S_TT"][4], solver.results["M2S_TT"][3], solver.results["M2S_TT"][2], solver.results["M2S_TT"][1], solver.results["M2S_TT"][0],
                solver.results["S2M_ST"][4], solver.results["S2M_ST"][3], solver.results["S2M_ST"][2], solver.results["S2M_ST"][1], solver.results["S2M_ST"][0]))
        print(".SLAVE_TIMINGS(80'h%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x)" % (
                solver.results["S2M_TT"][4], solver.results["S2M_TT"][3], solver.results["S2M_TT"][2], solver.results["S2M_TT"][1], solver.results["S2M_TT"][0],
                solver.results["M2S_ST"][4], solver.results["M2S_ST"][3], solver.results["M2S_ST"][2], solver.results["M2S_ST"][1], solver.results["M2S_ST"][0]))
        print()

    else:
        sys.exit(
            ('Usage: %s <master-period-ns> <slave-period-ns> \\\n' % sys.argv[0]) +
            ('    <master-to-slave-max-pulse-jitter-ns> <slave-to-master-max-pulse-jitter-ns>'))

