//
// PonyLink Chip-to-Chip Interconnect
//
// Copyright (C) 2014  Clifford Wolf <clifford@clifford.at>
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//

`timescale 1 ns / 1 ps

module ponylink_test #(
	parameter M2S_TDATA_WIDTH = 8,
	parameter M2S_TUSER_WIDTH = 0,
	parameter S2M_TDATA_WIDTH = 8,
	parameter S2M_TUSER_WIDTH = 0,
	parameter MASTER_PARBITS = 2,
	parameter SLAVE_PARBITS = 2,
	parameter MASTER_TIMINGS = 80'h0e0b0805020d0a070401,
	parameter SLAVE_TIMINGS = 80'h0e0b0805020d0a070401,

	parameter real MASTER_BIT_PERIOD_NS = 10.0,
	parameter real MASTER_PULSE_JITTER_NS = 0.0,
	parameter real SLAVE_BIT_PERIOD_NS = 10.0,
	parameter real SLAVE_PULSE_JITTER_NS = 0.0
) (
	input  master_clk,
	input  master_resetn,
	output master_linkerror,
	output master_linkready,

	input  slave_clk,
	output slave_resetn,
	output slave_linkerror,
	output slave_linkready,

	input  [7:0] master_gpio_i,
	output [7:0] master_gpio_o,

	input  [7:0] slave_gpio_i,
	output [7:0] slave_gpio_o,

	input  [M2S_TDATA_WIDTH-1:0] master_in_tdata,
	input  [M2S_TUSER_WIDTH-1:0] master_in_tuser,
	input                        master_in_tvalid,
	input                        master_in_tlast,
	output                       master_in_tready,

	output [S2M_TDATA_WIDTH-1:0] master_out_tdata,
	output [S2M_TUSER_WIDTH-1:0] master_out_tuser,
	output                       master_out_tvalid,
	output                       master_out_tlast,
	input                        master_out_tready,

	input  [S2M_TDATA_WIDTH-1:0] slave_in_tdata,
	input  [S2M_TUSER_WIDTH-1:0] slave_in_tuser,
	input                        slave_in_tvalid,
	input                        slave_in_tlast,
	output                       slave_in_tready,

	output [M2S_TDATA_WIDTH-1:0] slave_out_tdata,
	output [M2S_TUSER_WIDTH-1:0] slave_out_tuser,
	output                       slave_out_tvalid,
	output                       slave_out_tlast,
	input                        slave_out_tready,

	input  link_scramble,
	input  link_scramble_idle,
	output link_collision,

	output master_recv,
	output master_send,
	output slave_recv,
	output slave_send
);
	reg link_collision;
	reg link_master, link_slave, link_signal;
	reg [31:0] link_rng = 1;

	always @(link_master, link_slave, master_clk, slave_clk) begin
		link_collision = 0;
		if (link_scramble || (link_master === 1'bz && link_slave === 1'bz)) begin
			if (link_scramble || link_scramble_idle) begin
				link_signal = link_rng;
				link_rng = link_rng ^ (link_rng << 13);
				link_rng = link_rng ^ (link_rng >> 7);
				link_rng = link_rng ^ (link_rng << 17);
			end
		end else if (link_master === 1'bz && link_slave !== 1'bz)
			link_signal = link_slave;
		else if (link_master !== 1'bz && link_slave === 1'bz)
			link_signal = link_master;
		else begin
			link_signal = link_master === link_slave ? link_master : 1'bx;
			link_collision = 1;
		end
	end

	event send_master, send_slave;
	event sample_master, sample_slave;

	integer master_bitcnt, slave_bitcnt;
	real master_jitter, slave_jitter;

	reg  [MASTER_PARBITS-1:0] master_serdes_in;
	wire [MASTER_PARBITS-1:0] master_serdes_out;
	wire [MASTER_PARBITS-1:0] master_serdes_en;

	always @(posedge master_clk) begin:master_ser
		reg [MASTER_PARBITS-1:0] bits, en;
		real bit_time, delta_bit_time;
		reg last_bit;
		integer i;

		bits = master_serdes_out;
		en = master_serdes_en;

		bit_time = MASTER_BIT_PERIOD_NS * 0.5;

		for (i = 0; i < MASTER_PARBITS; i = i+1) begin
			delta_bit_time = 0;
			if (en[i]) begin
				if (last_bit !== bits[i]) begin
					master_jitter = (MASTER_PULSE_JITTER_NS * 0.01) * ($random % 45);
					bit_time = bit_time + master_jitter;
					delta_bit_time = -master_jitter;
				end
				last_bit = bits[i];
			end else
				last_bit = 'bx;
			if (bit_time <= 0 || bit_time >= 1.5 * MASTER_BIT_PERIOD_NS) begin
				$display("Out-of-bounds master bit time: %.3f (valid range = 0 .. %.3f)", bit_time, 1.5 * MASTER_BIT_PERIOD_NS);
				#(10 * MASTER_BIT_PERIOD_NS);
				$stop;
			end
			#(bit_time);

			-> send_master;
			link_master = en[i] ? bits[i] : 1'bz;
			bit_time = MASTER_BIT_PERIOD_NS + delta_bit_time;
		end
	end

	always @(posedge master_clk) begin:master_des
		reg [MASTER_PARBITS-1:0] bits;
		reg last_bit;
		integer i;

		master_serdes_in <= bits;
		for (i = 0; i < MASTER_PARBITS; i = i+1) begin
			if (i > 0)
				#(MASTER_BIT_PERIOD_NS);
			if (link_signal == last_bit)
				master_bitcnt = master_bitcnt + 1;
			else
				master_bitcnt = 1;
			bits[i] = link_signal;
			last_bit = link_signal;
			-> sample_master;
		end
	end

	reg  [SLAVE_PARBITS-1:0] slave_serdes_in;
	wire [SLAVE_PARBITS-1:0] slave_serdes_out;
	wire [SLAVE_PARBITS-1:0] slave_serdes_en;

	always @(posedge slave_clk) begin:slave_ser
		reg [SLAVE_PARBITS-1:0] bits, en;
		real bit_time, delta_bit_time;
		reg last_bit;
		integer i;

		bits = slave_serdes_out;
		en = slave_serdes_en;

		bit_time = SLAVE_BIT_PERIOD_NS * 0.5;

		for (i = 0; i < SLAVE_PARBITS; i = i+1) begin
			delta_bit_time = 0;
			if (en[i]) begin
				if (last_bit !== bits[i]) begin
					slave_jitter = (SLAVE_PULSE_JITTER_NS * 0.01) * ($random % 45);
					bit_time = bit_time + slave_jitter;
					delta_bit_time = -slave_jitter;
				end
				last_bit = bits[i];
			end else
				last_bit = 'bx;
			if (bit_time <= 0 || bit_time >= 1.5 * SLAVE_BIT_PERIOD_NS) begin
				$display("Out-of-bounds slave bit time: %.3f (valid range = 0 .. %.3f)", bit_time, 1.5 * SLAVE_BIT_PERIOD_NS);
				#(10 * SLAVE_BIT_PERIOD_NS);
				$stop;
			end
			#(bit_time);

			-> send_slave;
			link_slave = en[i] ? bits[i] : 1'bz;
			bit_time = SLAVE_BIT_PERIOD_NS + delta_bit_time;
		end
	end

	always @(posedge slave_clk) begin:slave_des
		reg [SLAVE_PARBITS-1:0] bits;
		reg last_bit;
		integer i;

		slave_serdes_in <= bits;
		for (i = 0; i < SLAVE_PARBITS; i = i+1) begin
			if (i > 0)
				#(SLAVE_BIT_PERIOD_NS);
			if (link_signal == last_bit)
				slave_bitcnt = slave_bitcnt + 1;
			else
				slave_bitcnt = 1;
			bits[i] = link_signal;
			last_bit = link_signal;
			-> sample_slave;
		end
	end

	ponylink_master #(
		.M2S_TDATA_WIDTH(M2S_TDATA_WIDTH),
		.M2S_TUSER_WIDTH(M2S_TUSER_WIDTH),
		.S2M_TDATA_WIDTH(S2M_TDATA_WIDTH),
		.S2M_TUSER_WIDTH(S2M_TUSER_WIDTH),
		.MASTER_PARBITS(MASTER_PARBITS),
		.MASTER_TIMINGS(MASTER_TIMINGS),
		.SLAVE_PARBITS(SLAVE_PARBITS),
		.SLAVE_TIMINGS(SLAVE_TIMINGS)
	) test_master (
		.clk(master_clk),
		.resetn(master_resetn),
		.linkerror(master_linkerror),
		.linkready(master_linkready),
		.mode_recv(master_recv),
		.mode_send(master_send),

		.gpio_i(master_gpio_i),
		.gpio_o(master_gpio_o),

		.in_tdata(master_in_tdata),
		.in_tuser(master_in_tuser),
		.in_tlast(master_in_tlast),
		.in_tvalid(master_in_tvalid),
		.in_tready(master_in_tready),

		.out_tdata(master_out_tdata),
		.out_tuser(master_out_tuser),
		.out_tlast(master_out_tlast),
		.out_tvalid(master_out_tvalid),
		.out_tready(master_out_tready),

		.serdes_in(master_serdes_in),
		.serdes_out(master_serdes_out),
		.serdes_en(master_serdes_en)
	);

	ponylink_slave #(
		.M2S_TDATA_WIDTH(M2S_TDATA_WIDTH),
		.M2S_TUSER_WIDTH(M2S_TUSER_WIDTH),
		.S2M_TDATA_WIDTH(S2M_TDATA_WIDTH),
		.S2M_TUSER_WIDTH(S2M_TUSER_WIDTH),
		.MASTER_PARBITS(MASTER_PARBITS),
		.MASTER_TIMINGS(MASTER_TIMINGS),
		.SLAVE_PARBITS(SLAVE_PARBITS),
		.SLAVE_TIMINGS(SLAVE_TIMINGS)
	) test_slave (
		.clk(slave_clk),
		.resetn_out(slave_resetn),
		.linkerror(slave_linkerror),
		.linkready(slave_linkready),
		.mode_recv(slave_recv),
		.mode_send(slave_send),

		.gpio_i(slave_gpio_i),
		.gpio_o(slave_gpio_o),

		.in_tdata(slave_in_tdata),
		.in_tuser(slave_in_tuser),
		.in_tlast(slave_in_tlast),
		.in_tvalid(slave_in_tvalid),
		.in_tready(slave_in_tready),

		.out_tdata(slave_out_tdata),
		.out_tuser(slave_out_tuser),
		.out_tlast(slave_out_tlast),
		.out_tvalid(slave_out_tvalid),
		.out_tready(slave_out_tready),

		.serdes_in(slave_serdes_in),
		.serdes_out(slave_serdes_out),
		.serdes_en(slave_serdes_en)
	);
endmodule

