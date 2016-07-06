
PonyLink -- A single-wire bi-directional chip-to-chip interface for FPGAs
=========================================================================

PonyLink is a bi-directional chip-to-chip interface that is using only a single
signal wire between the two chips. Naturally this wire is used in a half-duplex
fashion. For faster link speeds the use of a LVDS pair is recommended. The
cores are tested on Xilinx Series 7 and Lattice iCE40 FPGAs.

On the chip-facing side PonyLink provides a transmit and receive AXI Stream as
well as 8 GPIO inputs and 8 GPIO outputs. PonyLink handles all the low-level
tasks, including flow control and detection of failed transfers and automatic
resend.

The main features of the core are that it only requires one single data line
between the chips and that it can operate on resonable data rates (compared to
the clock rates of the clocks driving the cores, usually over 0.5 MBit/s per
MHz). This comes at a high resource cost, e.g. on iCE40 FPGAs (4-input LUTs)
an instance of PonyLink uses about 1700 LUTs.

Features:
---------

- typical net data rates of over 100 MBit/s at 166 MHz
- can utilize up to 4x serdes hardware for higher link speed
- support for any AXIS TDATA and TUSER width and TLAST signal
- bi-directional communication over a single data line (usually LVDS)
- works without a dedicated hardware block for clock recovery
- dc-free signaling, allowing for caps or magnetics in the link
- embedded clock and control signals (using 8b10b encoding)
- support for different data rates for each direction
- 8 asynchonous GPIO pins in each direction
- spread EMI spectrum via data scrambling

Master and Slave Roles and Link Reset:
--------------------------------------

- One of the two PonyLink IPs must run in MASTER and one in SLAVE mode
- The MASTER IP has a reset input signal
- Resetting the MASTER will reset the SLAVE over the link
- The SLAVE IP has a reset output that is pulsed by a reset event

Block Diagram:
--------------

      +--------------------------------------------------+
      |           Application Logic on Chip A            |
      +--------------------------------------------------+
          ^                |                     ^
          |                |                     |
          v                v                     |               \
      +------+    +----------------+    +----------------+       |
      | GPIO |    |   AXIS Input   |    |   AXIS Output  |       |
      +------+    +----------------+    +----------------+       |
          ^                |                     ^               |
          |                v                     |               |
          |       +----------------+    +----------------+       |
          |       |      Pack      |    |      Unpack    |       |
          |       +----------------+    +----------------+       |
          |                |                     ^               |  PonyLink
          |                v                     |               |  Master
          |       +----------------+    +----------------+       |  on Chip A
          |       |    Scramble    |    |   Unscramble   |       |
          |       +----------------+    +----------------+       |
          |                |                     ^               |
          |                v                     |               |
          |       +--------------------------------------+       |
          +------>|              TX/RX Engine            |       |
                  +--------------------------------------+       |
                                      ^                          /
                                      |
                                      |
                                      |
                                      v                          \
                  +--------------------------------------+       |
          +------>|              TX/RX Engine            |       |
          |       +--------------------------------------+       |
          |                |                     ^               |
          |                v                     |               |
          |       +----------------+    +----------------+       |
          |       |   Unscramble   |    |    Scramble    |       |
          |       +----------------+    +----------------+       |
          |                |                     ^               |  PonyLink
          |                v                     |               |  Slave
          |       +----------------+    +----------------+       |  on Chip B
          |       |      Unpack    |    |      Pack      |       |
          |       +----------------+    +----------------+       |
          |                |                     ^               |
          v                v                     |               |
      +------+    +----------------+    +----------------+       |
      | GPIO |    |   AXIS Output  |    |    AXIS Input  |       |
      +------+    +----------------+    +----------------+       |
          ^                |                     ^               /
          |                |                     |
          v                v                     |
      +--------------------------------------------------+
      |           Application Logic on Chip B            |
      +--------------------------------------------------+

See [plinksrc/protocol.txt](plinksrc/protocol.txt) for more details.


Files in this repository
========================

[plinksrc/](plinksrc/):
-----------------------

The actual PonyLink source. In most use cases you simply want to copy this
directory into your project.

[demos/ice8k/](demos/ice8k/):
-----------------------------

A simple demo for PonyLink running on the Lattice iCE40 HX8K Breakout Board.
This example is built using the FOSS Lattice iCE40 toolchain from [Project
IceStorm](http://www.clifford.at/icestorm/).

[demos/zybo/](demos/zybo/):
---------------------------

A simple demo for PonyLink running on the Digilent Zybo Board (featuring a Zynq
FPGA). This example is built using Xilinx Vivado.

[testbench/](testbench/):
-------------------------

A testbench (or rather testbench generator) for PonyLink. Running `make` in
this directory will create 100 test benches and run them.

[analyzer/](analyzer/):
-----------------------

A low-level analyzer for PonyLink traffic. Reads a text file with one floating
point number (representing a sample) per line. Can be used to analyze PonyLink
traffic recorded with an oszilloscope.

[smt2bmc/](smt2bmc/):
---------------------

Some formal proofs regarding PonyLink, based on elements from the Yosys-SMTBMC
flow.


Howto use PonyLink in your designs
==================================

PonyLink uses a master/slave architecture. Note that the slave core is reset
via the link and has a `resetn_out` output port that can be used to trigger
a reset of other circuits implemented on the slave side of the link.

Instantiate `ponylink_master` in the FPGA design that sits on the master side
of the link, and instantiate `ponylink_slave` on the slave side.

Make sure that the parameters `M2S_TDATA_WIDTH`, `M2S_TUSER_WIDTH`,
`S2M_TDATA_WIDTH`, and `S2M_TUSER_WIDTH` have the same values on both sides.

When a serdes core is used, set `MASTER_PARBITS` and `SLAVE_PARBITS` to the
correct serdes width.

Use the `timings.py` script to generate the values for the `MASTER_TIMINGS` and
`SLAVE_TIMINGS` parameter. The 1st and 2nd parameters to the script specify the
clock period on the slave and master side in ns. When a serdes core is used, this
is the period for the fast side of the serdes. The 3rd and 4th parameter specify
the maximum expected edge-to-edge jitter for pulses transmitted from the master
to the slave and vice versa respectively. Increase the values for the 3rd and 4th
parameters if transmission errors are detected.

Note that PonyLink performs best if the master and slave clock rates are *not*
integer multiples of each other.


Why the obscure name?
=====================

All other "YadaYada-Link" names seem to be already taken.

