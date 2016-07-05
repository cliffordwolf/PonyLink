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

module ponylink_slave #(
	parameter SERDES_REG_IN = 1,
	parameter SERDES_REG_OUT = 1,
	parameter M2S_TDATA_WIDTH = 8,
	parameter M2S_TUSER_WIDTH = 0,
	parameter S2M_TDATA_WIDTH = 8,
	parameter S2M_TUSER_WIDTH = 0,
	parameter MASTER_RECV_DELAY = 4,
	parameter SLAVE_RECV_DELAY = 4,
	parameter MASTER_SEND_DELAY = 32,
	parameter SLAVE_SEND_DELAY = 32,
	parameter MASTER_PARBITS = 1,
	parameter SLAVE_PARBITS = 1,
	parameter MASTER_PKTLEN = 64,
	parameter SLAVE_PKTLEN = 64,
	// python timings.py 6 19 0.25 1.5
	parameter MASTER_TIMINGS = 80'h1d17100a040f0c090602,
	parameter SLAVE_TIMINGS  = 80'h05040302010907050301
) (
	input clk,
	output resetn_out,
	output linkerror,
	output linkready,
	output mode_recv,
	output mode_send,

	input  [7:0] gpio_i,
	output [7:0] gpio_o,

	input  [S2M_TDATA_WIDTH-1:0] in_tdata,
	input  [S2M_TUSER_WIDTH-1:0] in_tuser,
	input                        in_tvalid,
	input                        in_tlast,
	output                       in_tready,

	output [M2S_TDATA_WIDTH-1:0] out_tdata,
	output [M2S_TUSER_WIDTH-1:0] out_tuser,
	output                       out_tvalid,
	output                       out_tlast,
	input                        out_tready,

	input  [SLAVE_PARBITS-1:0] serdes_in,
	output [SLAVE_PARBITS-1:0] serdes_out,
	output [SLAVE_PARBITS-1:0] serdes_en
);
	wire [8:0] in_ser_tdata;
	wire in_ser_tvalid, in_ser_tready;

	wire [8:0] out_ser_tdata;
	wire out_ser_tvalid, out_ser_tready;

	generate if (S2M_TDATA_WIDTH <= 8 && S2M_TUSER_WIDTH <= 8) begin:pack_8bits
		ponylink_pack_8bits #(
			.TDATA_WIDTH(S2M_TDATA_WIDTH),
			.TUSER_WIDTH(S2M_TUSER_WIDTH)
		) packer (
			.clk(clk),
			.resetn(resetn_out),
			.tdata(in_tdata),
			.tuser(in_tuser),
			.tvalid(in_tvalid),
			.tlast(in_tlast),
			.tready(in_tready),
			.ser_tdata(in_ser_tdata),
			.ser_tvalid(in_ser_tvalid),
			.ser_tready(in_ser_tready)
		);
	end else begin:pack_generic
		ponylink_pack_generic #(
			.TDATA_WIDTH(S2M_TDATA_WIDTH),
			.TUSER_WIDTH(S2M_TUSER_WIDTH)
		) packer (
			.clk(clk),
			.resetn(resetn_out),
			.tdata(in_tdata),
			.tuser(in_tuser),
			.tvalid(in_tvalid),
			.tlast(in_tlast),
			.tready(in_tready),
			.ser_tdata(in_ser_tdata),
			.ser_tvalid(in_ser_tvalid),
			.ser_tready(in_ser_tready)
		);
	end endgenerate

	generate if (M2S_TDATA_WIDTH <= 8 && M2S_TUSER_WIDTH <= 8) begin:unpack_8bits
		ponylink_unpack_8bits #(
			.TDATA_WIDTH(M2S_TDATA_WIDTH),
			.TUSER_WIDTH(M2S_TUSER_WIDTH)
		) unpacker (
			.clk(clk),
			.resetn(resetn_out),
			.tdata(out_tdata),
			.tuser(out_tuser),
			.tvalid(out_tvalid),
			.tlast(out_tlast),
			.tready(out_tready),
			.ser_tdata(out_ser_tdata),
			.ser_tvalid(out_ser_tvalid),
			.ser_tready(out_ser_tready)
		);
	end else begin:unpack_generic
		ponylink_unpack_generic #(
			.TDATA_WIDTH(M2S_TDATA_WIDTH),
			.TUSER_WIDTH(M2S_TUSER_WIDTH)
		) unpacker (
			.clk(clk),
			.resetn(resetn_out),
			.tdata(out_tdata),
			.tuser(out_tuser),
			.tvalid(out_tvalid),
			.tlast(out_tlast),
			.tready(out_tready),
			.ser_tdata(out_ser_tdata),
			.ser_tvalid(out_ser_tvalid),
			.ser_tready(out_ser_tready)
		);
	end endgenerate

	wire [SLAVE_PARBITS-1:0] serdes_in_t;
	wire [SLAVE_PARBITS-1:0] serdes_out_t;
	wire [SLAVE_PARBITS-1:0] serdes_en_t;

	reg [SLAVE_PARBITS-1:0] serdes_in_r;
	reg [SLAVE_PARBITS-1:0] serdes_out_r;
	reg [SLAVE_PARBITS-1:0] serdes_en_r;

	ponylink_txrx #(
		.RECVRESET(1),
		.RECV_DELAY(SLAVE_RECV_DELAY),
		.SEND_DELAY(SLAVE_SEND_DELAY),
		.SEND_PKTLEN(SLAVE_PKTLEN),
		.PARBITS(SLAVE_PARBITS),
		.TIMINGS(SLAVE_TIMINGS)
	) txrx (
		.clk(clk),
		.resetn(1'b1),
		.resetn_out(resetn_out),
		.linkerror(linkerror),
		.linkready(linkready),
		.mode_recv(mode_recv),
		.mode_send(mode_send),

		.gpio_i(gpio_i),
		.gpio_o(gpio_o),

		.in_ser_tdata(in_ser_tdata),
		.in_ser_tvalid(in_ser_tvalid),
		.in_ser_tready(in_ser_tready),

		.out_ser_tdata(out_ser_tdata),
		.out_ser_tvalid(out_ser_tvalid),
		.out_ser_tready(out_ser_tready),

		.serdes_in(serdes_in_t),
		.serdes_out(serdes_out_t),
		.serdes_en(serdes_en_t)
	);
 
	generate if (SERDES_REG_IN) begin
		always @(posedge clk) serdes_in_r <= serdes_in;
		assign serdes_in_t = serdes_in_r;
	end else begin
		assign serdes_in_t = serdes_in;
	end endgenerate

	generate if (SERDES_REG_OUT) begin
		always @(posedge clk) serdes_out_r <= serdes_out_t;
		always @(posedge clk) serdes_en_r <= serdes_en_t;
		assign serdes_out = serdes_out_r, serdes_en = serdes_en_r;
	end else begin
		assign serdes_out = serdes_out_t, serdes_en = serdes_en_t;
	end endgenerate
endmodule

