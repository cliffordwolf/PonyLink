#!/usr/bin/python
#
# timings.py is a script to calculate transmitter timing configurations between
# a master and a slave core, given their timing parameters.
#
# Example usage:
# python timings.py 6 19 0.25 1.5
#                   |  |  |    |
# Master clock period  |  |    Slave to Master pulse jitter
#                      |  |
#     Slave clock period  Master to slave pulse jitter
#
# All parameters are given in nanoseconds.
#
# Please refer to the "protocol.txt" file for a more detailed explanation of
# how to use this tool.

from __future__ import division
from __future__ import print_function

import sys
import numpy as np
import matplotlib.pyplot as plt

class TimingSolver:
    """
    Solves the constraints required for an asynchronously clocked receiver
    to unambiguously decode an asynchronously clocked transmitter's bit stream.

    What follows is a bit of theory behind why this class is so useful.

    In a synchronous circuit, we could arrange the transmitter and receiver to
    use the same clock.  This is what SPI does, for instance, and it eliminates
    the need for clock recovery in most cases.  It also offers the best
    possible performance.  However, many applications can get by with "fast
    enough" communications, and so do not need the additional overhead of a
    dedicated clock.  Clocks are particularly unwanted when using differential
    signalling, since they take up valuable I/O pins, already rapidly exhausted
    thanks to needing two per signal.

    With asynchronous transmission, however, the receiver and transmitter need
    not share a single clock.  Their clocks just need to be "close enough."
    This is how RS-232 communications work, for instance.  However, the
    disadvantage here is that your endpoints must somehow agree ahead of time
    on the transmission rate, and their sampling clocks must fall within some
    small percentage of each other for the link to communicate at all.

    PonyLink is an asynchronous transmission technology which allows the
    receiver and transmitter to have wildly different clocks.  It does this by
    allowing the transmitter to send pulses long enough to guarantee the
    receiver at least one opportunity to recognize different transmitted bit
    patterns.  The transmitter must know, a priori, some timing details about
    the receiver for this to happen.  Knowing what information to encode for
    this to happen is the reason for this class.
    
    Let's suppose we want to transmit the bits 01000001.  We can break this
    down into four pieces: a 0-vector of length 1, a 1-vector of length 1, a
    0-vector of length 5, and a 1-vector of length 1.  Notice how we always
    alternate between 0s and 1s.  If we plot this on a timing diagram, we
    might see a pattern like:

             ___                           ___
        \___/   \_________________________/   \___
          |    |    |    |    |    |    |    |  -- RX sample points
          0    1    0    0    0    0    0    1

    The vertical bars indicate sampling points needed by the receiver or
    transmitter.  But, if the transmitter is 2x faster than the receiver, it
    follows that the transmitter will need to send twice as many bits as the
    receiver will sample to see the desired bit pattern:

             ___                           ___
        \___/   \_________________________/   \___
          |    |    |    |    |    |    |    |  -- RX sample points
          0    1    0    0    0    0    0    1

         | | | |  | |  | |  | |  | |  | |  | | -- TX sample points
         0 0 1 1  0 0  0 0  0 0  0 0  0 0  1 1

    As long as the ratio of transmitter to receiver clocking is a convenient
    power of two, you can get by with making circuits yourself, by hand, that
    meet these requirements.  But when you have circuits with inconvenient
    clocking ratios, what happens then?  You end up needing to send pulses with
    slightly different durations to represent the same actual pulse stream on
    the receiver; indeed, PonyLink's key innovation is the recognition of
    bounded ranges of pulse trains representing symbols.

    For example, you might have noticed the not-quite-even spacing used in the
    TX sample points row in the above diagram.  That's because my math was
    slightly off; I was going to fix it, but it actually illustrates the value
    of this class perfectly.  Let's redraw the graph, as-is, but with a more
    realistic TX sample spacing:
             ___                           ___
        \___/   \_________________________/   \___
          |    |    |    |    |    |    |    |  -- RX sample points
          0    1    0    0    0    0    0    1

         | | | | | | | | | | | | | | | | | | | -- TX sample points
         0 0 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1
    
    From this diagram, can you tell how many zeros are minimally or maximally
    needed to decode a stream of five contiguous data 0 bits?  Depending on
    phase relationships, exact timing of the transmitter, and that of the
    receiver, it can vary between 10 and 14 zeros.  In the above example, I
    draw 13 0s.

    Reliably computing these bounded ranges is the purpose of this class.
    """

    def __init__(self):
        # the values for self.lendist come from bitdist.py
        self.lendist = [ 0.32735297, 0.36519647, 0.21898804, 0.07264801, 0.0158145 ]
        self.results = { }

    def test_recv_timings(self, transmit_period, sample_period, pulse_jitter, transmit_timings, verbose):
        """
        Answers with an array of receiver sample timings.  Each timing
        parameter determines the number of identical samples the receiver must
        receive to correspond to a bit vector of a given length.  The 0th
        element determines the number of samples for a single bit, 1st element
        corresponds to the number of samples for two bits, etc.

        The transmit_period determines the transmitter's NOMINAL serializer
        clock rate.  For example, if your transmitter operates at 100MHz, this
        value is 10.  It's assumed to be in nanoseconds.  The sample_period
        determines the receiver's NOMINAL sampling rate, in exactly the same
        way.  It, too, is assumed to be nanoseconds.

        pulse_jitter (also in nanoseconds) specifies worst-case boundaries for
        timing.  For example, if given a value of 0.5 and a transmit_period of
        10, then we expect the transmitter to send with a period between 9.5
        and 10.5ns, with an AVERAGE period of 10ns.

        The transmit_timings parameter is a list of numbers.  The 0th element
        determines the number transmit_periods required for the receiver to
        identify a single bit's worth of encoded data.  The 1st element
        determines the number of transmit_periods required for the receiver to
        identify a span of two bits worth of data.  Etc.  If you can guarantee
        your transmitter will never produce a continuous stream of 1s or 0s
        longer than N, then the length of this list must be N as well.  E.g.,
        for PonyLink, this len(transmit_timings)=5.

        If verbose is truthy, stdout will receive a diagnostic report of the
        samples calculated.
        """
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
        """
        Compute and report the timing configuration needed by a master and/or slave to its peer.
        """
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

    elif len(sys.argv) == 2 and sys.argv[1] == "-plot":
        x_slave_period = list()
        y_m2s_bitrate = list()
        y_s2m_bitrate = list()

        for k in range(50, 200):
            master_period = 100.0
            slave_period = k
            m2s_pulse_jitter = 0.5
            s2m_pulse_jitter = 0.5

            solver = TimingSolver()
            solver.find_config(0, master_period, slave_period, m2s_pulse_jitter);
            solver.find_config(1, slave_period, master_period, s2m_pulse_jitter);

            x_slave_period.append(slave_period)
            y_m2s_bitrate.append(solver.results["M2S_BW"])
            y_s2m_bitrate.append(solver.results["S2M_BW"])

        from matplotlib import pyplot as plt

        x_slave_period = np.array(x_slave_period)
        y_m2s_bitrate = np.array(y_m2s_bitrate)
        y_s2m_bitrate = np.array(y_s2m_bitrate)

        plt.figure(figsize=(10, 5))
        plt.title("Bandwidth, normalized using master clock frequency")
        plt.plot(x_slave_period / 100, y_m2s_bitrate / 10, label="master -> slave")
        plt.plot(x_slave_period / 100, y_s2m_bitrate / 10, label="slave -> master")
        plt.ylabel("Bandwidth (MBit/s / MHz master clock)")
        plt.xlabel("Ratio of slave clock period to master clock period " +
                   "(<1.0 = slave clock is faster than master clock)")
        plt.semilogx()
        xticks = [0.5, 0.7, 1.0, 1.5, 2.0]
        plt.xticks(xticks, xticks)
        plt.xlim(0.5, 2.0)
        plt.ylim(0, 1.2)
        plt.legend()
        plt.show()

    else:
        sys.exit(
            ('Usage: %s <master-period-ns> <slave-period-ns> \\\n' % sys.argv[0]) +
            ('    <master-to-slave-max-pulse-jitter-ns> <slave-to-master-max-pulse-jitter-ns>'))

