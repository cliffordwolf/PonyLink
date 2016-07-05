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
// `define DEBUG

module ponylink_txrx #(
	parameter RECVRESET = 0,
	parameter PARBITS = 4,
	parameter RECV_DELAY = 0,
	parameter SEND_DELAY = 0,
	parameter SEND_PKTLEN = 64,
	parameter TIMINGS = 80'h4a3423120717120d0803
) (
	input clk,
	input resetn,
	output resetn_out,
	output linkerror,
	output linkready,
	output mode_recv,
	output mode_send,

	input      [7:0] gpio_i,
	output reg [7:0] gpio_o,

	input  [8:0] in_ser_tdata,
	input        in_ser_tvalid,
	output       in_ser_tready,

	output [8:0] out_ser_tdata,
	output       out_ser_tvalid,
	input        out_ser_tready,

	input  [PARBITS-1:0] serdes_in,
	output [PARBITS-1:0] serdes_out,
	output [PARBITS-1:0] serdes_en
);
	// Minimum length of recv pulses in samples
	localparam TIMING_R1 = TIMINGS[ 0 +: 8];  // 1 bit
	localparam TIMING_R2 = TIMINGS[ 8 +: 8];  // 2 bits
	localparam TIMING_R3 = TIMINGS[16 +: 8];  // 3 bits
	localparam TIMING_R4 = TIMINGS[24 +: 8];  // 4 bits
	localparam TIMING_R5 = TIMINGS[32 +: 8];  // 5 bits

	// Length of transmit pulses in samples
	localparam TIMING_T1 = TIMINGS[40 +: 8];  // 1 bit
	localparam TIMING_T2 = TIMINGS[48 +: 8];  // 2 bits
	localparam TIMING_T3 = TIMINGS[56 +: 8];  // 3 bits
	localparam TIMING_T4 = TIMINGS[64 +: 8];  // 4 bits
	localparam TIMING_T5 = TIMINGS[72 +: 8];  // 5 bits

	function integer my_clog2;
		input integer in_v;
		integer v;
		begin
			v = in_v;
			if (v > 0)
				v = v - 1;
			my_clog2 = 0;
			while (v) begin
				v = v >> 1;
				my_clog2 = my_clog2 + 1;
			end
		end
	endfunction

	localparam RECV_TIMEOUT = 200 * TIMING_R5 - 1;
	localparam RECV_TIMEOUT_BITS = my_clog2(RECV_TIMEOUT);
	localparam RECV_WAIT_BITS = my_clog2(RECV_DELAY);
	localparam SEND_WAIT_BITS = my_clog2(SEND_DELAY);

	localparam [8:0] MAGIC_RECV = RECVRESET ? 9'h9e : 9'h74;
	localparam [8:0] MAGIC_SEND = RECVRESET ? 9'h74 : 9'h9e;


	// --------------
	// Serdes encoder

	reg [8:0] send_word;
	reg send_valid = 0;
	wire send_ready;

	generate if (PARBITS == 1) begin:encode_1
		ponylink_txrx_encode_1 #(
			.TIMING_T1(TIMING_T1),
			.TIMING_T2(TIMING_T2),
			.TIMING_T3(TIMING_T3),
			.TIMING_T4(TIMING_T4),
			.TIMING_T5(TIMING_T5),
			.TIMING_BITS(my_clog2(TIMING_T1+TIMING_T5))
		) encoder (
			.clk(clk),
			.reset(!resetn_out),
			.send_word(send_word),
			.send_valid(send_valid),
			.send_ready(send_ready),
			.serdes_out(serdes_out),
			.serdes_en(serdes_en)
		);
	end else if (PARBITS == 2) begin:encode_2
		ponylink_txrx_encode_2 #(
			.TIMING_T1(TIMING_T1),
			.TIMING_T2(TIMING_T2),
			.TIMING_T3(TIMING_T3),
			.TIMING_T4(TIMING_T4),
			.TIMING_T5(TIMING_T5),
			.TIMING_BITS(my_clog2(TIMING_T1+TIMING_T5))
		) encoder (
			.clk(clk),
			.reset(!resetn_out),
			.send_word(send_word),
			.send_valid(send_valid),
			.send_ready(send_ready),
			.serdes_out(serdes_out),
			.serdes_en(serdes_en)
		);
	end else if (PARBITS == 4) begin:encode_4
		ponylink_txrx_encode_4 #(
			.TIMING_T1(TIMING_T1),
			.TIMING_T2(TIMING_T2),
			.TIMING_T3(TIMING_T3),
			.TIMING_T4(TIMING_T4),
			.TIMING_T5(TIMING_T5),
			.TIMING_BITS(my_clog2(TIMING_T1+TIMING_T5))
		) encoder (
			.clk(clk),
			.reset(!resetn_out),
			.send_word(send_word),
			.send_valid(send_valid),
			.send_ready(send_ready),
			.serdes_out(serdes_out),
			.serdes_en(serdes_en)
		);
	end endgenerate


	// --------------
	// Serdes decoder

	wire [8:0] recv_word;
	wire recv_word_en;
	wire recv_error;
	wire rstdetect;

	reg [3:0] reset_counter;
	assign resetn_out = !reset_counter;

	always @(posedge clk) begin
		if ((!RECVRESET && !resetn) || (RECVRESET && rstdetect))
			reset_counter <= ~0;
		else if (reset_counter)
			reset_counter <= reset_counter - 1'b1;
	end

	generate if (PARBITS == 1) begin:decode_1
		ponylink_txrx_decode_1 #(
			.RECVRESET(RECVRESET),
			.TIMING_R1(TIMING_R1),
			.TIMING_R2(TIMING_R2),
			.TIMING_R3(TIMING_R3),
			.TIMING_R4(TIMING_R4),
			.TIMING_R5(TIMING_R5),
			.TIMING_BITS(my_clog2(TIMING_R1+TIMING_R5))
		) decoder (
			.clk(clk),
			.reset(|serdes_en),
			.rstdetect(rstdetect),
			.recv_word(recv_word),
			.recv_word_en(recv_word_en),
			.recv_error(recv_error),
			.serdes_in(serdes_in)
		);
	end else if (PARBITS == 2) begin:decode_2
		ponylink_txrx_decode_2 #(
			.RECVRESET(RECVRESET),
			.TIMING_R1(TIMING_R1),
			.TIMING_R2(TIMING_R2),
			.TIMING_R3(TIMING_R3),
			.TIMING_R4(TIMING_R4),
			.TIMING_R5(TIMING_R5),
			.TIMING_BITS(my_clog2(TIMING_R1+TIMING_R5))
		) decoder (
			.clk(clk),
			.reset(|serdes_en),
			.rstdetect(rstdetect),
			.recv_word(recv_word),
			.recv_word_en(recv_word_en),
			.recv_error(recv_error),
			.serdes_in(serdes_in)
		);
	end else if (PARBITS == 4) begin:decode_4
		ponylink_txrx_decode_4 #(
			.RECVRESET(RECVRESET),
			.TIMING_R1(TIMING_R1),
			.TIMING_R2(TIMING_R2),
			.TIMING_R3(TIMING_R3),
			.TIMING_R4(TIMING_R4),
			.TIMING_R5(TIMING_R5),
			.TIMING_BITS(my_clog2(TIMING_R1+TIMING_R5))
		) decoder (
			.clk(clk),
			.reset(|serdes_en),
			.rstdetect(rstdetect),
			.recv_word(recv_word),
			.recv_word_en(recv_word_en),
			.recv_error(recv_error),
			.serdes_in(serdes_in)
		);
	end endgenerate


	// ------------------------------------------------
	// AXIS IN/OUT fifos

	reg [8:0] in_fifo_buffer [0:255];
	reg [7:0] in_fifo_iptr, in_fifo_optr;
	wire [7:0] in_fifo_iptr_nxt = in_fifo_iptr + 1'b1;
	wire [7:0] in_fifo_optr_nxt = in_fifo_optr + 1'b1;

	reg [8:0] out_fifo_buffer [0:255];
	reg [7:0] out_fifo_iptr, out_fifo_optr;
	wire [7:0] out_fifo_iptr_nxt = out_fifo_iptr + 1'b1;
	wire [7:0] out_fifo_optr_nxt = out_fifo_optr + 1'b1;

	wire [7:0] in_fifo_oblock;
	assign in_ser_tready = (in_fifo_iptr_nxt != in_fifo_oblock) && resetn_out;

	assign out_ser_tdata = out_fifo_buffer[out_fifo_optr];
	assign out_ser_tvalid = (out_fifo_iptr != out_fifo_optr) && resetn_out;

	always @(posedge clk) begin
		if (!resetn_out) begin
			in_fifo_iptr <= 0;
			out_fifo_optr <= 0;
		end else begin
			if (in_ser_tvalid && in_ser_tready) begin
				in_fifo_buffer[in_fifo_iptr] <= in_ser_tdata;
				in_fifo_iptr <= in_fifo_iptr_nxt;
			end

			if (out_ser_tvalid && out_ser_tready) begin
				out_fifo_optr <= out_fifo_optr_nxt;
			end
		end
	end


	// ------------------------------------------------
	// Half-duplex control

	reg hd_send_mode;
	reg hd_switch_to_send;
	reg hd_switch_to_recv;
	reg [RECV_TIMEOUT_BITS-1:0] hd_timeout;
	reg [RECV_WAIT_BITS-1:0] hd_recv_wait;
	reg [SEND_WAIT_BITS-1:0] hd_send_wait;
	reg hd_linkerror;
	wire hd_reset;

	always @(posedge clk) begin
		hd_linkerror <= 0;
		hd_timeout <= hd_send_mode && !hd_reset ? 0 : hd_timeout + 1;
		if (hd_recv_wait)
			hd_recv_wait <= hd_recv_wait-1;
		if (hd_send_wait)
			hd_send_wait <= hd_send_wait-1;
		if (!resetn_out) begin
			hd_timeout <= 0;
			hd_send_mode <= !RECVRESET;
			hd_recv_wait <= RECV_DELAY-1;
			hd_send_wait <= SEND_DELAY-1;
		end else
		if (hd_switch_to_send || (!RECVRESET && hd_timeout == RECV_TIMEOUT)) begin
			hd_timeout <= 0;
			hd_send_mode <= 1;
			hd_linkerror <= (!RECVRESET && hd_timeout == RECV_TIMEOUT);
			hd_send_wait <= SEND_DELAY-1;
		end else
		if (hd_switch_to_recv) begin
			hd_timeout <= 0;
			hd_send_mode <= 0;
			hd_recv_wait <= RECV_DELAY-1;
		end
	end

`ifdef DEBUG
	reg last_hd_send_mode;
	always @(posedge clk) begin
		if (hd_send_mode) begin
			if (send_valid && send_ready)
				$display("%s send: %03x", RECVRESET ? "S" : "M", send_word);
		end else begin
			if (recv_word_en)
				$display("%s recv: %03x%s", RECVRESET ? "S" : "M", recv_word, recv_error ? " *" : "");
		end
		if (last_hd_send_mode != hd_send_mode && !last_hd_send_mode)
			$display("%s ---------", RECVRESET ? "S" : "M");
		last_hd_send_mode <= hd_send_mode;
	end
`endif


	// ------------------------------------------------
	// Checksum generator

	wire [31:0] checksum;
	reg [8:0] checksum_word;
	reg checksum_enable;
	reg checksum_lock;

	ponylink_crc32 crc32 (
		.clk(clk),
		.crc_en(checksum_enable),
		.rst(checksum_word == 9'h1fc && checksum_enable),
		.data_in(checksum_word [8] ? ~checksum_word[7:0] : checksum_word[7:0]),
		.crc_out(checksum)
	);

	always @* begin
		checksum_word = 'bx;
		checksum_enable = 0;
		if (send_valid && send_ready) begin
			checksum_word = send_word;
			checksum_enable = !checksum_lock;
		end
		if (!hd_send_mode && recv_word_en) begin
			checksum_word = recv_word;
			checksum_enable = 1;
		end
	end


	// ------------------------------------------------
	// IN pkt engine

	localparam istate_preamble1 = 0;
	localparam istate_preamble2 = 1;
	localparam istate_seq_your  = 2;
	localparam istate_seq_mine  = 3;
	localparam istate_payload   = 4;
	localparam istate_gpio_ctrl = 5;
	localparam istate_gpio_data = 6;
	localparam istate_end_ctrl  = 7;
	localparam istate_checksum0 = 8;
	localparam istate_checksum1 = 9;
	localparam istate_checksum2 = 10;
	localparam istate_checksum3 = 11;

	reg [3:0] istate;
	reg [31:0] ichecksum;
	reg [7:0] igpiobuf;
	reg ilinkerror;

	reg [3:0] ilinkready = 0;
	reg linkerror = 0;
	reg linkready = 0;

	reg [7:0] next_sent_gpio;
	reg [7:0] next_sent_gpio_at;
	reg [8:0] sent_gpio;

	reg work_out_fifo_iptr_apply;
	reg [7:0] work_out_fifo_iptr;
	wire [7:0] work_out_fifo_iptr_nxt = work_out_fifo_iptr + 1;

	reg [7:0] peer_out_fifo_iptr;
	reg [7:0] peer_out_fifo_iptr_next;

	assign in_fifo_oblock = peer_out_fifo_iptr;

	always @(posedge clk) begin
		ilinkerror <= 0;
		linkready <= &ilinkready;
		hd_switch_to_send <= rstdetect;
		if (ilinkerror && !linkready)
			ilinkready <= 0;
		if (hd_linkerror || ilinkerror)
			linkerror <= 1;
		if (!resetn_out) begin
			out_fifo_iptr <= 0;
			peer_out_fifo_iptr <= 0;
			istate <= istate_preamble1;
			ilinkready <= 0;
			linkready <= 0;
			linkerror <= 0;
			sent_gpio <= 'h100;
			gpio_o <= 0;
		end else if (hd_send_mode) begin
			istate <= istate_preamble1;
		end else if (recv_word_en && !hd_recv_wait && !serdes_en) begin
			if (recv_error) begin
				istate <= istate_preamble1;
				ilinkerror <= istate != istate_preamble1 && istate != istate_preamble2;
			end else
			if (recv_word == 9'h1fc) begin
				istate <= istate_preamble2;
			end else begin
				(* full_case *)
				case (istate)
					istate_preamble1: begin
					end
					istate_preamble2: begin
						if (recv_word != 9'h1fc)
							istate <= istate_preamble1;
						if (recv_word == MAGIC_RECV) begin
							istate <= istate_seq_your;
							igpiobuf <= gpio_o;
							work_out_fifo_iptr <= out_fifo_iptr;
						end
					end
					istate_seq_your: begin
						peer_out_fifo_iptr_next <= recv_word;
						istate <= recv_word[8] ? istate_preamble1 : istate_seq_mine;
						ilinkerror <= recv_word[8] && recv_word != (RECVRESET ? 9'h1fd : 9'h1fe);
					end
					istate_seq_mine: begin
						work_out_fifo_iptr_apply <= recv_word == work_out_fifo_iptr;
						istate <= recv_word[8] ? istate_preamble1 : istate_payload;
						ilinkerror <= recv_word[8];
					end
					istate_payload: begin
						if (recv_word == 9'h19c) begin
							istate <= istate_gpio_data;
						end else if (recv_word == 9'h1bc) begin
							ichecksum <= checksum;
							istate <= istate_checksum0;
						end else if (recv_word[8] && recv_word != 9'h11c && recv_word != 9'h15c && recv_word != 9'h17c) begin
							istate <= istate_preamble1;
							ilinkerror <= 1;
						end else if (work_out_fifo_iptr_nxt == out_fifo_optr || !work_out_fifo_iptr_apply) begin
							work_out_fifo_iptr_apply <= 0;
						end else begin
							out_fifo_buffer[work_out_fifo_iptr] <= recv_word;
							work_out_fifo_iptr <= work_out_fifo_iptr_nxt;
						end
					end
					istate_gpio_data: begin
						if (recv_word == 9'h1bc) begin
							ichecksum <= checksum;
							istate <= istate_checksum0;
						end else if (recv_word[8]) begin
							istate <= istate_preamble1;
							ilinkerror <= 1;
						end else
							igpiobuf <= recv_word;
					end
					istate_checksum0: begin
						if (recv_word == ichecksum[7:0]) begin
							istate <= istate_checksum1;
						end else begin
							istate <= istate_preamble1;
							ilinkerror <= 1;
						end
					end
					istate_checksum1: begin
						if (recv_word == ichecksum[15:8]) begin
							istate <= istate_checksum2;
						end else begin
							istate <= istate_preamble1;
							ilinkerror <= 1;
						end
					end
					istate_checksum2: begin
						if (recv_word == ichecksum[23:16]) begin
							istate <= istate_checksum3;
						end else begin
							istate <= istate_preamble1;
							ilinkerror <= 1;
						end
					end
					istate_checksum3: begin
						if (recv_word == ichecksum[31:24]) begin
							gpio_o <= igpiobuf;
							peer_out_fifo_iptr <= peer_out_fifo_iptr_next;
							if (work_out_fifo_iptr_apply)
								out_fifo_iptr <= work_out_fifo_iptr;
							if (sent_gpio != next_sent_gpio)
								sent_gpio <= peer_out_fifo_iptr_next == next_sent_gpio_at &&
									peer_out_fifo_iptr_next != peer_out_fifo_iptr ? next_sent_gpio : 'h100;
							if (&linkready == 0)
								ilinkready <= ilinkready + 1;
							linkerror <= 0;
						end else
							ilinkerror <= 1;
						hd_switch_to_send <= 1;
						istate <= istate_preamble1;
					end
				endcase
			end
		end
	end


	// ------------------------------------------------
	// OUT pkt engine

	localparam ostate_preamble1 = 0;
	localparam ostate_preamble2 = 1;
	localparam ostate_preamble3 = 2;
	localparam ostate_seq_your  = 3;
	localparam ostate_seq_mine  = 4;
	localparam ostate_payload   = 5;
	localparam ostate_gpio_ctrl = 6;
	localparam ostate_gpio_data = 7;
	localparam ostate_end_ctrl  = 8;
	localparam ostate_checksum0 = 9;
	localparam ostate_checksum1 = 10;
	localparam ostate_checksum2 = 11;
	localparam ostate_checksum3 = 12;
	localparam ostate_tail      = 13;
	localparam ostate_wait      = 14;

	reg [3:0] ostate;
	reg [6:0] ostate_counter;
	reg       ostate_reset;

	assign hd_reset = ostate_reset && ostate_counter == 16 && !RECVRESET;

	always @(posedge clk) begin
		hd_switch_to_recv <= 0;
		if (!resetn_out) begin
			send_valid <= 0;
			ostate_reset <= 1;
			ostate_counter <= 0;
			ostate <= ostate_preamble1;
			in_fifo_optr <= 0;
			next_sent_gpio <= 0;
			next_sent_gpio_at <= 0;
		end else if (ostate_reset) begin
			ostate <= ostate_preamble1;
			if ((!send_valid || send_ready) && !hd_send_wait) begin
				if (ostate_counter < 16) begin
					ostate_counter <= ostate_counter + 1;
					case (ostate_counter)
						0:
							send_word <= 9'hb5;
						1:
							send_word <= 9'h1fc;
						2, 3, 4, 5:
							send_word <= RECVRESET ? 9'h1fe : 9'h1fd;
						15:
							send_word <= 9'h100;
						default:
							send_word <= ostate_counter;
					endcase
					send_valid <= 1;
				end else if (RECVRESET) begin
					ostate_reset <= 0;
					send_valid <= 0;
					hd_switch_to_recv <= 1;
				end else begin
					if (hd_timeout != RECV_TIMEOUT) begin
						if (rstdetect) begin
							send_valid <= 0;
							ostate_reset <= 0;
							hd_switch_to_recv <= 1;
						end
					end else begin
						ostate_counter <= 0;
					end
					send_valid <= 0;
				end
			end
		end else if (!hd_send_mode) begin
			ostate <= ostate_preamble1;
			send_valid <= 0;
		end else if (!hd_switch_to_recv && !hd_send_wait) begin
			(* full_case *)
			case (ostate)
				ostate_preamble1: begin
					if (!send_valid || send_ready) begin
						ostate <= ostate_preamble2;
						checksum_lock <= 0;
						send_word <= 9'hb5;
						send_valid <= 1;
					end
				end
				ostate_preamble2: begin
					if (!send_valid || send_ready) begin
						ostate <= ostate_preamble3;
						send_word <= 9'h1fc;
						send_valid <= 1;
					end
				end
				ostate_preamble3: begin
					if (!send_valid || send_ready) begin
						ostate <= ostate_seq_your;
						send_word <= MAGIC_SEND;
						send_valid <= 1;
					end
				end
				ostate_seq_your: begin
					if (!send_valid || send_ready) begin
						ostate <= ostate_seq_mine;
						send_word <= out_fifo_iptr;
						send_valid <= 1;
					end
				end
				ostate_seq_mine: begin
					if (!send_valid || send_ready) begin
						in_fifo_optr <= peer_out_fifo_iptr;
						ostate <= in_fifo_iptr != peer_out_fifo_iptr ? ostate_payload :
								gpio_i !== sent_gpio ? ostate_gpio_ctrl : ostate_end_ctrl;
						ostate_counter <= 0;
						send_word <= peer_out_fifo_iptr;
						send_valid <= 1;
					end
				end
				ostate_payload: begin
					if (send_valid && send_ready) begin
						if (in_fifo_iptr != in_fifo_optr && ostate_counter < SEND_PKTLEN)
							in_fifo_optr <= in_fifo_optr_nxt;
					end
					if (!send_valid || send_ready) begin
						if (in_fifo_iptr != in_fifo_optr && ostate_counter < SEND_PKTLEN) begin
							ostate_counter <= ostate_counter + 1;
							send_word <= in_fifo_buffer[in_fifo_optr];
							send_valid <= 1;
						end else begin
							ostate <= gpio_i !== sent_gpio ? ostate_gpio_data : ostate_checksum0;
							checksum_lock <= gpio_i === sent_gpio;
							send_word <= gpio_i !== sent_gpio ? 9'h19c : 9'h1bc;
							send_valid <= 1;
						end
					end
				end
				ostate_gpio_ctrl: begin
					if (!send_valid || send_ready) begin
						ostate <= ostate_gpio_data;
						send_word <= 9'h19c;
						send_valid <= 1;
					end
				end
				ostate_gpio_data: begin
					if (!send_valid || send_ready) begin
						ostate <= ostate_end_ctrl;
						send_word <= gpio_i;
						next_sent_gpio <= gpio_i;
						next_sent_gpio_at <= in_fifo_optr;
						send_valid <= 1;
					end
				end
				ostate_end_ctrl: begin
					if (!send_valid || send_ready) begin
						ostate <= ostate_checksum0;
						checksum_lock <= 1;
						send_word <= 9'h1bc;
						send_valid <= 1;
					end
				end
				ostate_checksum0: begin
					if (!send_valid || send_ready) begin
						ostate <= ostate_checksum1;
						checksum_lock <= 1;
						send_word <= checksum[7:0];
						send_valid <= 1;
					end
				end
				ostate_checksum1: begin
					if (!send_valid || send_ready) begin
						ostate <= ostate_checksum2;
						checksum_lock <= 1;
						send_word <= checksum[15:8];
						send_valid <= 1;
					end
				end
				ostate_checksum2: begin
					if (!send_valid || send_ready) begin
						ostate <= ostate_checksum3;
						checksum_lock <= 1;
						send_word <= checksum[23:16];
						send_valid <= 1;
					end
				end
				ostate_checksum3: begin
					if (!send_valid || send_ready) begin
						ostate <= ostate_tail;
						send_word <= checksum[31:24];
						send_valid <= 1;
					end
				end
				ostate_tail: begin
					if (!send_valid || send_ready) begin
						ostate <= ostate_wait;
						send_word <= 9'h100;
						send_valid <= 1;
					end
				end
				ostate_wait: begin
					if (!send_valid || send_ready) begin
						if (!serdes_en) begin
							hd_switch_to_recv <= 1;
							ostate <= ostate_preamble1;
						end
						send_valid <= 0;
					end
				end
			endcase
		end else begin
			if (send_ready)
				send_valid <= 0;
		end
	end

	assign mode_recv = !hd_send_mode && !hd_recv_wait && !serdes_en;
	assign mode_send = hd_send_mode && !hd_switch_to_recv && !hd_send_wait;
endmodule

// =======================================================================

module ponylink_txrx_encode_1 #(
	parameter TIMING_T1 = 1,  // 1 bit
	parameter TIMING_T2 = 2,  // 2 bits
	parameter TIMING_T3 = 3,  // 3 bits
	parameter TIMING_T4 = 4,  // 4 bits
	parameter TIMING_T5 = 5,  // 5 bits
	parameter TIMING_BITS = 8
) (
	input clk,
	input reset,

	input [8:0] send_word,
	input send_valid,
	output reg send_ready,

	output reg serdes_out,
	output reg serdes_en
);
	reg send_disp;
	wire [9:0] send_bits;
	wire next_send_disp;

	reg [14:0] buffer;
	reg [14:0] buffer_en;

	reg [14:0] next_buffer;
	reg [14:0] next_buffer_en;

	reg stage2_bits;
	reg stage2_enable;
	reg stage2_shift;

	ponylink_encode_8b10b_xtra en8b10b (
		.clk(clk),
		.datain(send_word),
		.dispin(send_disp && send_word !== 'h1fc),
		.dataout(send_bits),
		.dispout(next_send_disp)
	);

	always @(posedge clk) begin
		send_ready <= 0;
		if (reset) begin
			buffer_en <= 0;
			stage2_enable <= 0;
			send_disp <= 0;
		end else begin
			next_buffer = buffer;
			next_buffer_en = buffer_en;

			if (next_buffer_en[14:5] == 0 && send_valid) begin
				next_buffer[14:5] = send_bits;
				next_buffer_en[14:5] = {10{send_valid}};
				send_disp <= next_send_disp;
				send_ready <= send_valid;
			end

			if (stage2_shift) begin
				next_buffer = next_buffer >> 1;
				next_buffer_en = next_buffer_en >> 1;
			end

			buffer <= next_buffer;
			buffer_en <= next_buffer_en;

			stage2_bits <= next_buffer[0];
			stage2_enable <= next_buffer_en[0];
		end
	end

	reg [TIMING_BITS-1:0] max_counter = TIMING_T1;
	reg [TIMING_BITS-1:0] counter = 0;
	reg lastbit = 0;

	always @(posedge clk) begin
		stage2_shift <= 0;
		if (reset) begin
			serdes_en <= 0;
			max_counter = TIMING_T1;
			counter = 0;
			lastbit = 0;
		end else begin
			if (stage2_shift) begin
				serdes_en <= stage2_enable;
				serdes_out <= stage2_bits;
				if (!stage2_enable || lastbit != stage2_bits || max_counter == TIMING_T5) begin
					max_counter = TIMING_T1;
					counter = 0;
				end else begin
					case (max_counter)
						TIMING_T1: max_counter = TIMING_T2;
						TIMING_T2: max_counter = TIMING_T3;
						TIMING_T3: max_counter = TIMING_T4;
						TIMING_T4: max_counter = TIMING_T5;
						default: begin
							max_counter = TIMING_T1;
							counter = 0;
						end
					endcase
				end
				lastbit = stage2_bits;
			end
			counter = counter + 1'b1;
			if (max_counter == counter) begin
				stage2_shift <= 1;
			end
		end
	end
endmodule

// =======================================================================

module ponylink_txrx_encode_2 #(
	parameter TIMING_T1 = 1,  // 1 bit
	parameter TIMING_T2 = 2,  // 2 bits
	parameter TIMING_T3 = 3,  // 3 bits
	parameter TIMING_T4 = 4,  // 4 bits
	parameter TIMING_T5 = 5,  // 5 bits
	parameter TIMING_BITS = 8
) (
	input clk,
	input reset,

	input [8:0] send_word,
	input send_valid,
	output reg send_ready,

	output reg [1:0] serdes_out,
	output reg [1:0] serdes_en
);
	function integer get_max;
		input integer a, b;
		begin
			get_max = a > b ? a : b;
		end
	endfunction

	function integer get_mb2;
		input integer T1, T2, T3, T4, T5;
		begin
			get_mb2 = 2 * T1;
			get_mb2 = get_max(get_mb2, T3 - T1);
			get_mb2 = get_max(get_mb2, T4 - T2);
			get_mb2 = get_max(get_mb2, T5 - T3);
			get_mb2 = get_max(get_mb2, T1 + T2 - T1);
			get_mb2 = get_max(get_mb2, T1 + T3 - T2);
			get_mb2 = get_max(get_mb2, T1 + T4 - T3);
			get_mb2 = get_max(get_mb2, T1 + T5 - T4);
		end
	endfunction

	// maximum number of encoded samples for two consecutive data bits
	localparam TIMING_MB2 = get_mb2(TIMING_T1, TIMING_T2, TIMING_T3, TIMING_T4, TIMING_T5);

	reg send_disp;
	wire [9:0] send_bits;
	wire next_send_disp;

	reg [14:0] buffer;
	reg [14:0] buffer_en;

	reg buffer_lastbit = 0;
	reg [1:0] buffer_lastlen = 0;
	reg [1:0] buffer_thislen = 0;

	reg [14:0] next_buffer;
	reg [14:0] next_buffer_en;

	reg [TIMING_MB2-1:0] stage2_bits;
	reg [TIMING_MB2-1:0] stage2_enable;
	reg stage2_shift;

	ponylink_encode_8b10b_xtra en8b10b (
		.clk(clk),
		.datain(send_word),
		.dispin(send_disp && send_word !== 'h1fc),
		.dataout(send_bits),
		.dispout(next_send_disp)
	);

	always @(posedge clk) begin
		send_ready <= 0;
		if (reset) begin
			buffer <= 0;
			buffer_en <= 0;
			buffer_lastbit = 0;
			buffer_lastlen = 0;
			buffer_thislen = 0;
			stage2_enable <= 0;
			send_disp <= 0;
		end else begin
			next_buffer = buffer;
			next_buffer_en = buffer_en;

			if (next_buffer_en[14:5] == 0 && send_valid) begin
				next_buffer[14:5] = send_bits;
				next_buffer_en[14:5] = {10{send_valid}};
				send_disp <= next_send_disp;
				send_ready <= send_valid;
			end

			if (stage2_shift) begin
				buffer_lastbit = next_buffer[1];
				buffer_lastlen = buffer_thislen;
				next_buffer = next_buffer >> 2;
				next_buffer_en = next_buffer_en >> 2;
			end

			case (next_buffer[1:0])
				2'b00: begin
					stage2_bits <= 0;
					if (buffer_lastbit == 0) begin
						case (buffer_lastlen)
							0: stage2_enable <= {TIMING_T3-TIMING_T1{|next_buffer_en[1:0]}};
							1: stage2_enable <= {TIMING_T4-TIMING_T2{|next_buffer_en[1:0]}};
							default: stage2_enable <= {TIMING_T5-TIMING_T3{|next_buffer_en[1:0]}};
						endcase
						buffer_thislen = buffer_lastlen + 2;
					end else begin
						stage2_enable <= {TIMING_T2{1'b1}};
						buffer_thislen = 1;
					end
				end
				2'b01: begin
					if (buffer_lastbit == 1) begin
						case (buffer_lastlen)
							0: stage2_bits <= {TIMING_T2-TIMING_T1{1'b1}};
							1: stage2_bits <= {TIMING_T3-TIMING_T2{1'b1}};
							2: stage2_bits <= {TIMING_T4-TIMING_T3{1'b1}};
							3: stage2_bits <= {TIMING_T5-TIMING_T4{1'b1}};
						endcase
						case (buffer_lastlen)
							0: stage2_enable <= {TIMING_T1+TIMING_T2-TIMING_T1{|next_buffer_en[1:0]}};
							1: stage2_enable <= {TIMING_T1+TIMING_T3-TIMING_T2{|next_buffer_en[1:0]}};
							2: stage2_enable <= {TIMING_T1+TIMING_T4-TIMING_T3{|next_buffer_en[1:0]}};
							3: stage2_enable <= {TIMING_T1+TIMING_T5-TIMING_T4{|next_buffer_en[1:0]}};
						endcase
						buffer_thislen = 0;
					end else begin
						stage2_bits <= {TIMING_T1{1'b1}};
						stage2_enable <= {2*TIMING_T1{1'b1}};
						buffer_thislen = 0;
					end
				end
				2'b10: begin
					if (buffer_lastbit == 0) begin
						case (buffer_lastlen)
							0: stage2_bits <= ~{TIMING_T2-TIMING_T1{1'b1}};
							1: stage2_bits <= ~{TIMING_T3-TIMING_T2{1'b1}};
							2: stage2_bits <= ~{TIMING_T4-TIMING_T3{1'b1}};
							3: stage2_bits <= ~{TIMING_T5-TIMING_T4{1'b1}};
						endcase
						case (buffer_lastlen)
							0: stage2_enable <= {TIMING_T1+TIMING_T2-TIMING_T1{|next_buffer_en[1:0]}};
							1: stage2_enable <= {TIMING_T1+TIMING_T3-TIMING_T2{|next_buffer_en[1:0]}};
							2: stage2_enable <= {TIMING_T1+TIMING_T4-TIMING_T3{|next_buffer_en[1:0]}};
							3: stage2_enable <= {TIMING_T1+TIMING_T5-TIMING_T4{|next_buffer_en[1:0]}};
						endcase
						buffer_thislen = 0;
					end else begin
						stage2_bits <= ~{TIMING_T1{1'b1}};
						stage2_enable <= {2*TIMING_T1{1'b1}};
						buffer_thislen = 0;
					end
				end
				2'b11: begin
					stage2_bits <= ~0;
					if (buffer_lastbit == 1) begin
						case (buffer_lastlen)
							0: stage2_enable <= {TIMING_T3-TIMING_T1{|next_buffer_en[1:0]}};
							1: stage2_enable <= {TIMING_T4-TIMING_T2{|next_buffer_en[1:0]}};
							default: stage2_enable <= {TIMING_T5-TIMING_T3{|next_buffer_en[1:0]}};
						endcase
						buffer_thislen = buffer_lastlen + 2;
					end else begin
						stage2_enable <= {TIMING_T2{1'b1}};
						buffer_thislen = 1;
					end
				end
			endcase

			buffer <= next_buffer;
			buffer_en <= next_buffer_en;
		end
	end

	reg [TIMING_MB2:0] queue_bits;
	reg [TIMING_MB2:0] queue_enable = 0;

	always @(posedge clk) begin
		stage2_shift <= 0;
		if (reset) begin
			serdes_en <= 0;
			queue_enable = 0;
		end else begin
			if (stage2_shift) begin
				if (queue_enable[0]) begin
					queue_bits = {stage2_bits, queue_bits[0]};
					queue_enable = {stage2_enable, queue_enable[0]};
				end else begin
					queue_bits = stage2_bits;
					queue_enable = stage2_enable;
				end
			end

			serdes_out <= queue_bits;
			serdes_en <= queue_enable;

			queue_bits = queue_bits >> 2;
			queue_enable = queue_enable >> 2;

			stage2_shift <= !queue_enable[1];
		end
	end
endmodule

// =======================================================================

module ponylink_txrx_encode_4 #(
	parameter TIMING_T1 = 1,  // 1 bit
	parameter TIMING_T2 = 2,  // 2 bits
	parameter TIMING_T3 = 3,  // 3 bits
	parameter TIMING_T4 = 4,  // 4 bits
	parameter TIMING_T5 = 5,  // 5 bits
	parameter TIMING_BITS = 8
) (
	input clk,
	input reset,

	input [8:0] send_word,
	input send_valid,
	output reg send_ready,

	output reg [3:0] serdes_out,
	output reg [3:0] serdes_en
);
	function integer get_max;
		input integer a, b;
		begin
			get_max = a > b ? a : b;
		end
	endfunction

	function integer get_mb2;
		input integer T1, T2, T3, T4, T5;
		begin
			get_mb2 = 2 * T1;
			get_mb2 = get_max(get_mb2, T3 - T1);
			get_mb2 = get_max(get_mb2, T4 - T2);
			get_mb2 = get_max(get_mb2, T5 - T3);
			get_mb2 = get_max(get_mb2, T1 + T2 - T1);
			get_mb2 = get_max(get_mb2, T1 + T3 - T2);
			get_mb2 = get_max(get_mb2, T1 + T4 - T3);
			get_mb2 = get_max(get_mb2, T1 + T5 - T4);
		end
	endfunction

	function integer get_mb4;
		input integer T1, T2, T3, T4, T5;
		begin
			get_mb4 = 2 * get_mb2(T1, T2, T3, T4, T5);
		end
	endfunction

	// maximum number of encoded samples for four consecutive data bits
	localparam TIMING_MB4 = get_mb4(TIMING_T1, TIMING_T2, TIMING_T3, TIMING_T4, TIMING_T5);

	reg send_disp;
	wire [9:0] send_bits;
	wire next_send_disp;

	reg [20:0] buffer;
	reg [20:0] buffer_en;

	reg buffer_lastbit = 0;
	reg [1:0] buffer_lastlen = 0;
	reg [1:0] buffer_thislen = 0;

	reg [20:0] next_buffer;
	reg [20:0] next_buffer_en;

	reg [TIMING_MB4-1:0] stage2_bits;
	reg [TIMING_MB4-1:0] stage2_enable;
	reg stage2_shift;

	ponylink_encode_8b10b_xtra en8b10b (
		.clk(clk),
		.datain(send_word),
		.dispin(send_disp && send_word !== 'h1fc),
		.dataout(send_bits),
		.dispout(next_send_disp)
	);

	always @(posedge clk) begin
		send_ready <= 0;
		if (reset) begin
			buffer <= 0;
			buffer_en <= 0;
			buffer_lastbit = 0;
			buffer_lastlen = 0;
			buffer_thislen = 0;
			stage2_enable <= 0;
			send_disp <= 0;
		end else begin
			next_buffer = buffer;
			next_buffer_en = buffer_en;

			if (next_buffer_en[20:11] == 0 && send_valid) begin
				if (next_buffer_en[10:9] == 0) begin
					next_buffer[20:9] = send_bits;
					next_buffer_en[20:9] = {10{send_valid}};
				end else begin
					next_buffer[20:11] = send_bits;
					next_buffer_en[20:11] = {10{send_valid}};
				end
				send_disp <= next_send_disp;
				send_ready <= send_valid;
			end

			if (stage2_shift) begin
				buffer_lastbit = next_buffer[3];
				buffer_lastlen = buffer_thislen;
				next_buffer = next_buffer >> 4;
				next_buffer_en = next_buffer_en >> 4;
			end

			case (next_buffer[3:0])
				4'b0000, 4'b1111: begin
					stage2_bits <= next_buffer[0] ? ~0 : 0;
					if (buffer_lastbit == next_buffer[0]) begin
						stage2_enable <= {TIMING_T5-TIMING_T1{|next_buffer_en[3:0]}};
						buffer_thislen = 0;
					end else begin
						stage2_enable <= {TIMING_T4{1'b1}};
						buffer_thislen = 3;
					end
				end
				4'b0001, 4'b1110: begin
					if (buffer_lastbit == next_buffer[0]) begin
						case (buffer_lastlen)
							0: stage2_bits <= {{TIMING_T3{~next_buffer[0]}}, {TIMING_T2-TIMING_T1{next_buffer[0]}}};
							1: stage2_bits <= {{TIMING_T3{~next_buffer[0]}}, {TIMING_T3-TIMING_T2{next_buffer[0]}}};
							2: stage2_bits <= {{TIMING_T3{~next_buffer[0]}}, {TIMING_T4-TIMING_T3{next_buffer[0]}}};
							3: stage2_bits <= {{TIMING_T3{~next_buffer[0]}}, {TIMING_T5-TIMING_T4{next_buffer[0]}}};
						endcase
						case (buffer_lastlen)
							0: stage2_enable <= {TIMING_T3+TIMING_T2-TIMING_T1{|next_buffer_en[3:0]}};
							1: stage2_enable <= {TIMING_T3+TIMING_T3-TIMING_T2{|next_buffer_en[3:0]}};
							2: stage2_enable <= {TIMING_T3+TIMING_T4-TIMING_T3{|next_buffer_en[3:0]}};
							3: stage2_enable <= {TIMING_T3+TIMING_T5-TIMING_T4{|next_buffer_en[3:0]}};
						endcase
					end else begin
						stage2_bits <= {{TIMING_T3{~next_buffer[0]}}, {TIMING_T1{next_buffer[0]}}};
						stage2_enable <= {TIMING_T3+TIMING_T1{1'b1}};
					end
					buffer_thislen = 2;
				end
				4'b0010, 4'b1101: begin
					if (buffer_lastbit == next_buffer[0]) begin
						case (buffer_lastlen)
							0: stage2_bits <= {{TIMING_T2{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T2-TIMING_T1{next_buffer[0]}}};
							1: stage2_bits <= {{TIMING_T2{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T3-TIMING_T2{next_buffer[0]}}};
							2: stage2_bits <= {{TIMING_T2{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T4-TIMING_T3{next_buffer[0]}}};
							3: stage2_bits <= {{TIMING_T2{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T5-TIMING_T4{next_buffer[0]}}};
						endcase
						case (buffer_lastlen)
							0: stage2_enable <= {TIMING_T2+TIMING_T1+TIMING_T2-TIMING_T1{|next_buffer_en[3:0]}};
							1: stage2_enable <= {TIMING_T2+TIMING_T1+TIMING_T3-TIMING_T2{|next_buffer_en[3:0]}};
							2: stage2_enable <= {TIMING_T2+TIMING_T1+TIMING_T4-TIMING_T3{|next_buffer_en[3:0]}};
							3: stage2_enable <= {TIMING_T2+TIMING_T1+TIMING_T5-TIMING_T4{|next_buffer_en[3:0]}};
						endcase
					end else begin
						stage2_bits <= {{TIMING_T2{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T1{next_buffer[0]}}};
						stage2_enable <= {TIMING_T2+2*TIMING_T1{1'b1}};
					end
					buffer_thislen = 1;
				end
				4'b0011, 4'b1100: begin
					if (buffer_lastbit == next_buffer[0]) begin
						case (buffer_lastlen)
							0: stage2_bits <= {{TIMING_T2{~next_buffer[0]}}, {TIMING_T3-TIMING_T1{next_buffer[0]}}};
							1: stage2_bits <= {{TIMING_T2{~next_buffer[0]}}, {TIMING_T4-TIMING_T2{next_buffer[0]}}};
							default: stage2_bits <= {{TIMING_T2{~next_buffer[0]}}, {TIMING_T5-TIMING_T3{next_buffer[0]}}};
						endcase
						case (buffer_lastlen)
							0: stage2_enable <= {TIMING_T2+TIMING_T3-TIMING_T1{|next_buffer_en[3:0]}};
							1: stage2_enable <= {TIMING_T2+TIMING_T4-TIMING_T2{|next_buffer_en[3:0]}};
							default: stage2_enable <= {TIMING_T2+TIMING_T5-TIMING_T3{|next_buffer_en[3:0]}};
						endcase
					end else begin
						stage2_bits <= {{TIMING_T2{~next_buffer[0]}}, {TIMING_T2{next_buffer[0]}}};
						stage2_enable <= {2*TIMING_T2{1'b1}};
					end
					buffer_thislen = 1;
				end
				4'b0100, 4'b1011: begin
					if (buffer_lastbit == next_buffer[0]) begin
						case (buffer_lastlen)
							0: stage2_bits <= {{TIMING_T1{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T3-TIMING_T1{next_buffer[0]}}};
							1: stage2_bits <= {{TIMING_T1{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T4-TIMING_T2{next_buffer[0]}}};
							default: stage2_bits <= {{TIMING_T1{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T5-TIMING_T3{next_buffer[0]}}};
						endcase
						case (buffer_lastlen)
							0: stage2_enable <= {TIMING_T1+TIMING_T1+TIMING_T3-TIMING_T1{|next_buffer_en[3:0]}};
							1: stage2_enable <= {TIMING_T1+TIMING_T1+TIMING_T4-TIMING_T2{|next_buffer_en[3:0]}};
							default: stage2_enable <= {TIMING_T1+TIMING_T1+TIMING_T5-TIMING_T3{|next_buffer_en[3:0]}};
						endcase
					end else begin
						stage2_bits <= {{TIMING_T1{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T2{next_buffer[0]}}};
						stage2_enable <= {2*TIMING_T1+TIMING_T2{1'b1}};
					end
					buffer_thislen = 0;
				end
				4'b0101, 4'b1010: begin
					if (buffer_lastbit == next_buffer[0]) begin
						case (buffer_lastlen)
							0: stage2_bits <= {{TIMING_T1{~next_buffer[0]}}, {TIMING_T1{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T2-TIMING_T1{next_buffer[0]}}};
							1: stage2_bits <= {{TIMING_T1{~next_buffer[0]}}, {TIMING_T1{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T3-TIMING_T2{next_buffer[0]}}};
							2: stage2_bits <= {{TIMING_T1{~next_buffer[0]}}, {TIMING_T1{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T4-TIMING_T3{next_buffer[0]}}};
							3: stage2_bits <= {{TIMING_T1{~next_buffer[0]}}, {TIMING_T1{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T5-TIMING_T4{next_buffer[0]}}};
						endcase
						case (buffer_lastlen)
							0: stage2_enable <= {3*TIMING_T1+TIMING_T2-TIMING_T1{|next_buffer_en[3:0]}};
							1: stage2_enable <= {3*TIMING_T1+TIMING_T3-TIMING_T2{|next_buffer_en[3:0]}};
							2: stage2_enable <= {3*TIMING_T1+TIMING_T4-TIMING_T3{|next_buffer_en[3:0]}};
							3: stage2_enable <= {3*TIMING_T1+TIMING_T5-TIMING_T4{|next_buffer_en[3:0]}};
						endcase
					end else begin
						stage2_bits <= {{TIMING_T1{~next_buffer[0]}}, {TIMING_T1{next_buffer[0]}}, {TIMING_T1{~next_buffer[0]}}, {TIMING_T1{next_buffer[0]}}};
						stage2_enable <= {4*TIMING_T1{1'b1}};
					end
					buffer_thislen = 0;
				end
				4'b0110, 4'b1001: begin
					if (buffer_lastbit == next_buffer[0]) begin
						case (buffer_lastlen)
							0: stage2_bits <= {{TIMING_T1{next_buffer[0]}}, {TIMING_T2{~next_buffer[0]}}, {TIMING_T2-TIMING_T1{next_buffer[0]}}};
							1: stage2_bits <= {{TIMING_T1{next_buffer[0]}}, {TIMING_T2{~next_buffer[0]}}, {TIMING_T3-TIMING_T2{next_buffer[0]}}};
							2: stage2_bits <= {{TIMING_T1{next_buffer[0]}}, {TIMING_T2{~next_buffer[0]}}, {TIMING_T4-TIMING_T3{next_buffer[0]}}};
							3: stage2_bits <= {{TIMING_T1{next_buffer[0]}}, {TIMING_T2{~next_buffer[0]}}, {TIMING_T5-TIMING_T4{next_buffer[0]}}};
						endcase
						case (buffer_lastlen)
							0: stage2_enable <= {TIMING_T1+TIMING_T2+TIMING_T2-TIMING_T1{|next_buffer_en[3:0]}};
							1: stage2_enable <= {TIMING_T1+TIMING_T2+TIMING_T3-TIMING_T2{|next_buffer_en[3:0]}};
							2: stage2_enable <= {TIMING_T1+TIMING_T2+TIMING_T4-TIMING_T3{|next_buffer_en[3:0]}};
							3: stage2_enable <= {TIMING_T1+TIMING_T2+TIMING_T5-TIMING_T4{|next_buffer_en[3:0]}};
						endcase
					end else begin
						stage2_bits <= {{TIMING_T1{next_buffer[0]}}, {TIMING_T2{~next_buffer[0]}}, {TIMING_T1{next_buffer[0]}}};
						stage2_enable <= {TIMING_T1+TIMING_T2+TIMING_T1{1'b1}};
					end
					buffer_thislen = 0;
				end
				4'b0111, 4'b1000: begin
					if (buffer_lastbit == next_buffer[0]) begin
						case (buffer_lastlen)
							0: stage2_bits <= {{TIMING_T1{~next_buffer[0]}}, {TIMING_T4-TIMING_T1{next_buffer[0]}}};
							default: stage2_bits <= {{TIMING_T1{~next_buffer[0]}}, {TIMING_T5-TIMING_T2{next_buffer[0]}}};
						endcase
						case (buffer_lastlen)
							0: stage2_enable <= {TIMING_T1+TIMING_T4-TIMING_T1{|next_buffer_en[3:0]}};
							default: stage2_enable <= {TIMING_T1+TIMING_T5-TIMING_T2{|next_buffer_en[3:0]}};
						endcase
					end else begin
						stage2_bits <= {{TIMING_T1{~next_buffer[0]}}, {TIMING_T3{next_buffer[0]}}};
						stage2_enable <= {TIMING_T1+TIMING_T3{1'b1}};
					end
					buffer_thislen = 0;
				end
			endcase

			buffer <= next_buffer;
			buffer_en <= next_buffer_en;
		end
	end

	reg [TIMING_MB4+3:0] queue_bits;
	reg [TIMING_MB4+3:0] queue_enable = 0;

	always @(posedge clk) begin
		stage2_shift <= 0;
		if (reset) begin
			serdes_en <= 0;
			queue_enable = 0;
		end else begin
			if (stage2_shift) begin
				if (queue_enable[2]) begin
					queue_bits = {stage2_bits, queue_bits[2:0]};
					queue_enable = {stage2_enable, queue_enable[2:0]};
				end else if (queue_enable[1]) begin
					queue_bits = {stage2_bits, queue_bits[1:0]};
					queue_enable = {stage2_enable, queue_enable[1:0]};
				end else if (queue_enable[0]) begin
					queue_bits = {stage2_bits, queue_bits[0]};
					queue_enable = {stage2_enable, queue_enable[0]};
				end else begin
					queue_bits = stage2_bits;
					queue_enable = stage2_enable;
				end
			end

			serdes_out <= queue_bits;
			serdes_en <= queue_enable;

			queue_bits = queue_bits >> 4;
			queue_enable = queue_enable >> 4;

			stage2_shift <= !queue_enable[3];
		end
	end
endmodule

// =======================================================================

module ponylink_txrx_decode_1 #(
	parameter RECVRESET = 0,
	parameter TIMING_R1 = 0,  // 1 bit
	parameter TIMING_R2 = 0,  // 2 bits
	parameter TIMING_R3 = 0,  // 3 bits
	parameter TIMING_R4 = 0,  // 4 bits
	parameter TIMING_R5 = 0,  // 5 bits
	parameter TIMING_BITS = 8
) (
	input clk,
	input reset,
	output rstdetect,

	output [8:0] recv_word,
	output reg recv_word_en,
	output recv_error,

	input [0:0] serdes_in
);
	reg [9:0] recv_wbits;
	reg [9:0] next_recv_wbits;

	ponylink_decode_8b10b_xtra #(RECVRESET) de8b10b (
		.clk(clk),
		.reset(reset),
		.enable(recv_word_en),
		.rstdetect(rstdetect),
		.datain(recv_wbits),
		.dataout(recv_word),
		.recv_error(recv_error)
	);

	reg last_bit = 0;
	reg [TIMING_BITS-1:0] cnt = 0;
	reg [3:0] cnt2 = 0;
	reg [3:0] next_cnt2;

	always @(posedge clk) begin
		recv_word_en <= 0;
		next_cnt2 = cnt2;
		next_recv_wbits = recv_wbits;
		if (serdes_in == last_bit) begin
			if (cnt == TIMING_R2-2) begin next_recv_wbits = {serdes_in, next_recv_wbits[9:1]}; next_cnt2 = next_cnt2 + 1'b1; end
			if (cnt == TIMING_R3-2) begin next_recv_wbits = {serdes_in, next_recv_wbits[9:1]}; next_cnt2 = next_cnt2 + 1'b1; end
			if (cnt == TIMING_R4-2) begin next_recv_wbits = {serdes_in, next_recv_wbits[9:1]}; next_cnt2 = next_cnt2 + 1'b1; end
			if (cnt == TIMING_R5-2) begin next_recv_wbits = {serdes_in, next_recv_wbits[9:1]}; next_cnt2 = next_cnt2 + 1'b1; end
			cnt <= cnt + 1'b1;
		end else begin
			next_recv_wbits = {serdes_in, next_recv_wbits[9:1]};
			next_cnt2 = next_cnt2 + 1'b1;
			cnt <= 0;
		end
		if (next_recv_wbits == 10'b0001111100 || next_cnt2 == 10) begin
			next_cnt2 = 0;
			recv_word_en <= !reset;
		end
		cnt2 <= next_cnt2;
		recv_wbits <= next_recv_wbits;
		last_bit <= serdes_in;
	end
endmodule

// =======================================================================

module ponylink_txrx_decode_2 #(
	parameter RECVRESET = 0,
	parameter TIMING_R1 = 0,  // 1 bit
	parameter TIMING_R2 = 0,  // 2 bits
	parameter TIMING_R3 = 0,  // 3 bits
	parameter TIMING_R4 = 0,  // 4 bits
	parameter TIMING_R5 = 0,  // 5 bits
	parameter TIMING_BITS = 8
) (
	input clk,
	input reset,
	output rstdetect,

	output [8:0] recv_word,
	output reg recv_word_en,
	output recv_error,

	input [1:0] serdes_in
);
	reg [9:0] recv_wbits;

	ponylink_decode_8b10b_xtra #(RECVRESET) de8b10b (
		.clk(clk),
		.reset(reset),
		.enable(recv_word_en),
		.rstdetect(rstdetect),
		.datain(recv_wbits),
		.dataout(recv_word),
		.recv_error(recv_error)
	);

	reg deser_last = 0;
	reg [1:0] deser_bits, deser_en;
	reg [TIMING_BITS-1:0] deser_cnt;

	wire deser_cnt_1 = deser_cnt == TIMING_R2-1 || deser_cnt == TIMING_R3-1 || deser_cnt == TIMING_R4-1 || deser_cnt == TIMING_R5-1;
	wire deser_cnt_2 = deser_cnt == TIMING_R2-2 || deser_cnt == TIMING_R3-2 || deser_cnt == TIMING_R4-2 || deser_cnt == TIMING_R5-2;

	always @(posedge clk) begin
		case (serdes_in)
			2'b00, 2'b11: begin
				if (deser_last == serdes_in[0]) begin
					deser_bits <= serdes_in;
					deser_en[0] <= deser_cnt_1 || deser_cnt_2;
					deser_en[1] <= deser_cnt_1 && deser_cnt_2;
					deser_cnt <= deser_cnt + 2;
				end else begin
					deser_bits <= serdes_in;
					deser_en[0] <= 1;
					deser_en[1] <= TIMING_R2 == 2;
					deser_cnt <= 2;
				end
			end
			2'b01, 2'b10: begin
				if (deser_last == serdes_in[0]) begin
					if (deser_cnt_1) begin
						deser_bits <= serdes_in;
						deser_en <= 2'b11;
					end else begin
						deser_bits <= serdes_in[1];
						deser_en <= 1'b1;
					end
				end else begin
					deser_bits <= serdes_in;
					deser_en <= 2'b11;
				end
				deser_cnt <= 1;
			end
		endcase
		deser_last <= serdes_in[1];
	end

	integer i;
	reg [9:0] bitbuffer;
	reg [3:0] bitcount = 0;

	always @(posedge clk) begin
		recv_word_en <= 0;
		for (i = 0; i < 2; i = i+1) begin
			if (deser_en[i]) begin
				bitcount = bitcount + 1;
				bitbuffer = {deser_bits[i], bitbuffer[9:1]};
				if (bitcount == 10 || bitbuffer == 10'b0001111100) begin
					recv_wbits <= bitbuffer;
					recv_word_en <= !reset;
					bitcount = 0;
				end
			end
		end
	end
endmodule


// =======================================================================

module ponylink_txrx_decode_4 #(
	parameter RECVRESET = 0,
	parameter TIMING_R1 = 0,  // 1 bit
	parameter TIMING_R2 = 0,  // 2 bits
	parameter TIMING_R3 = 0,  // 3 bits
	parameter TIMING_R4 = 0,  // 4 bits
	parameter TIMING_R5 = 0,  // 5 bits
	parameter TIMING_BITS = 8
) (
	input clk,
	input reset,
	output rstdetect,

	output [8:0] recv_word,
	output reg recv_word_en,
	output recv_error,

	input [3:0] serdes_in
);
	reg [9:0] recv_wbits;

	ponylink_decode_8b10b_xtra #(RECVRESET) de8b10b (
		.clk(clk),
		.reset(reset),
		.enable(recv_word_en),
		.rstdetect(rstdetect),
		.datain(recv_wbits),
		.dataout(recv_word),
		.recv_error(recv_error)
	);

	reg deser_last = 0;
	reg [3:0] deser_bits, deser_en;
	reg [TIMING_BITS-1:0] deser_cnt;

	wire deser_cnt_1 = deser_cnt == TIMING_R2-1 || deser_cnt == TIMING_R3-1 || deser_cnt == TIMING_R4-1 || deser_cnt == TIMING_R5-1;
	wire deser_cnt_2 = deser_cnt == TIMING_R2-2 || deser_cnt == TIMING_R3-2 || deser_cnt == TIMING_R4-2 || deser_cnt == TIMING_R5-2;
	wire deser_cnt_3 = deser_cnt == TIMING_R2-3 || deser_cnt == TIMING_R3-3 || deser_cnt == TIMING_R4-3 || deser_cnt == TIMING_R5-3;
	wire deser_cnt_4 = deser_cnt == TIMING_R2-4 || deser_cnt == TIMING_R3-4 || deser_cnt == TIMING_R4-4 || deser_cnt == TIMING_R5-4;

	always @(posedge clk) begin
		case (serdes_in)
			4'b0000, 4'b1111: begin
				if (deser_last == serdes_in[0]) begin
					deser_bits <= serdes_in;
					deser_en[0] <= deser_cnt_1 + deser_cnt_2 + deser_cnt_3 + deser_cnt_4 >= 3'd1;
					deser_en[1] <= deser_cnt_1 + deser_cnt_2 + deser_cnt_3 + deser_cnt_4 >= 3'd2;
					deser_en[2] <= deser_cnt_1 + deser_cnt_2 + deser_cnt_3 + deser_cnt_4 >= 3'd3;
					deser_en[3] <= deser_cnt_1 + deser_cnt_2 + deser_cnt_3 + deser_cnt_4 >= 3'd4;
					deser_cnt <= deser_cnt + 4;
				end else begin
					deser_bits <= serdes_in;
					deser_en[0] <= 1;
					deser_en[1] <= TIMING_R2 <= 4;
					deser_en[2] <= TIMING_R3 <= 4;
					deser_en[3] <= TIMING_R4 <= 4;
					deser_cnt <= 4;
				end
			end
			4'b0001, 4'b1110: begin
				if (deser_last == serdes_in[0]) begin
					if (deser_cnt_1) begin
						deser_bits <= serdes_in;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= TIMING_R2 <= 3;
						deser_en[3] <= TIMING_R3 <= 3;
					end else begin
						deser_bits <= serdes_in >> 1;
						deser_en[0] <= 1;
						deser_en[1] <= TIMING_R2 <= 3;
						deser_en[2] <= TIMING_R3 <= 3;
						deser_en[3] <= 0;
					end
				end else begin
					deser_bits <= serdes_in;
					deser_en[0] <= 1;
					deser_en[1] <= 1;
					deser_en[2] <= TIMING_R2 <= 3;
					deser_en[3] <= TIMING_R3 <= 3;
				end
				deser_cnt <= 3;
			end
			4'b0011, 4'b1100: begin
				if (deser_last == serdes_in[0]) begin
					if (deser_cnt_1 && deser_cnt_2) begin
						deser_bits <= serdes_in;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= TIMING_R2 <= 2;
					end else
					if (deser_cnt_1 || deser_cnt_2) begin
						deser_bits <= serdes_in >> 1;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= TIMING_R2 <= 2;
						deser_en[3] <= 0;
					end else begin
						deser_bits <= serdes_in >> 2;
						deser_en[0] <= 1;
						deser_en[1] <= TIMING_R2 <= 2;
						deser_en[2] <= 0;
						deser_en[3] <= 0;
					end
				end else begin
					if (TIMING_R2 <= 2) begin
						deser_bits <= serdes_in;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 1;
					end else begin
						deser_bits <= serdes_in >> 1;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 0;
						deser_en[3] <= 0;
					end
				end
				deser_cnt <= 2;
			end
			4'b0111, 4'b1000: begin
				if (deser_last == serdes_in[0]) begin
					if (deser_cnt_1 + deser_cnt_2 + deser_cnt_3 >= 3'd3) begin
						deser_bits <= serdes_in;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 1;
					end else
					if (deser_cnt_1 + deser_cnt_2 + deser_cnt_3 >= 3'd2) begin
						deser_bits <= serdes_in >> 1;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 0;
					end else
					if (deser_cnt_1 + deser_cnt_2 + deser_cnt_3 >= 3'd1) begin
						deser_bits <= serdes_in >> 2;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 0;
						deser_en[3] <= 0;
					end else begin
						deser_bits <= serdes_in >> 3;
						deser_en[0] <= 1;
						deser_en[1] <= 0;
						deser_en[2] <= 0;
						deser_en[3] <= 0;
					end
				end else begin
					if (TIMING_R3 <= 3) begin
						deser_bits <= serdes_in;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 1;
					end else
					if (TIMING_R2 <= 3) begin
						deser_bits <= serdes_in >> 1;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 0;
					end else begin
						deser_bits <= serdes_in >> 2;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 0;
						deser_en[3] <= 0;
					end
				end
				deser_cnt <= 1;
			end
			4'b0110, 4'b1001: begin
				if (deser_last == serdes_in[0]) begin
					if (deser_cnt_1) begin
						if (TIMING_R2 <= 2) begin
							deser_bits <= serdes_in;
							deser_en[0] <= 1;
							deser_en[1] <= 1;
							deser_en[2] <= 1;
							deser_en[3] <= 1;
						end else begin
							deser_bits <= {serdes_in[3], serdes_in[2], serdes_in[0]};
							deser_en[0] <= 1;
							deser_en[1] <= 1;
							deser_en[2] <= 1;
							deser_en[3] <= 0;
						end
					end else begin
						if (TIMING_R2 <= 2) begin
							deser_bits <= serdes_in >> 1;
							deser_en[0] <= 1;
							deser_en[1] <= 1;
							deser_en[2] <= 1;
							deser_en[3] <= 0;
						end else begin
							deser_bits <= serdes_in >> 2;
							deser_en[0] <= 1;
							deser_en[1] <= 1;
							deser_en[2] <= 0;
							deser_en[3] <= 0;
						end
					end
				end else begin
					if (TIMING_R2 <= 2) begin
						deser_bits <= serdes_in;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 1;
					end else begin
						deser_bits <= {serdes_in[3], serdes_in[2], serdes_in[0]};
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 0;
					end
				end
				deser_cnt <= 1;
			end
			4'b0010, 4'b1101: begin
				if (deser_last == serdes_in[0]) begin
					if (deser_cnt_1) begin
						deser_bits <= serdes_in;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= TIMING_R2 <= 2;
					end else begin
						deser_bits <= serdes_in >> 1;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= TIMING_R2 <= 2;
						deser_en[3] <= 0;
					end
				end else begin
					deser_bits <= serdes_in;
					deser_en[0] <= 1;
					deser_en[1] <= 1;
					deser_en[2] <= 1;
					deser_en[3] <= TIMING_R2 <= 2;
				end
				deser_cnt <= 2;
			end
			4'b0100, 4'b1011: begin
				if (deser_last == serdes_in[0]) begin
					if (deser_cnt_1 && deser_cnt_2) begin
						deser_bits <= serdes_in;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 1;
					end else
					if (deser_cnt_1 || deser_cnt_2) begin
						deser_bits <= serdes_in >> 1;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 0;
					end else begin
						deser_bits <= serdes_in >> 2;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 0;
						deser_en[3] <= 0;
					end
				end else begin
					if (TIMING_R2 <= 2) begin
						deser_bits <= serdes_in;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 1;
					end else begin
						deser_bits <= serdes_in >> 1;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 0;
					end
				end
				deser_cnt <= 1;
			end
			4'b0101, 4'b1010: begin
				if (deser_last == serdes_in[0]) begin
					if (deser_cnt_1) begin
						deser_bits <= serdes_in;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 1;
					end else begin
						deser_bits <= serdes_in >> 1;
						deser_en[0] <= 1;
						deser_en[1] <= 1;
						deser_en[2] <= 1;
						deser_en[3] <= 0;
					end
				end else begin
					deser_bits <= serdes_in;
					deser_en[0] <= 1;
					deser_en[1] <= 1;
					deser_en[2] <= 1;
					deser_en[3] <= 1;
				end
				deser_cnt <= 1;
			end
		endcase
		deser_last <= serdes_in[3];
	end

	reg [3:0] bitcount = 0;
	reg [9:0] bitbuffer = 0;

	// wire [2:0] deser_en_sum = deser_en[0] + deser_en[1] + deser_en[2] + deser_en[3];
	wire [2:0] deser_en_sum = deser_en[3] ? 4 : deser_en[2] ? 3 : deser_en[1] ? 2 : deser_en[0] ? 1 : 0;

	always @(posedge clk) begin
		recv_word_en <= 0;
		bitbuffer <= {deser_bits, bitbuffer} >> deser_en_sum;
		if (deser_en[0] && {deser_bits[0], bitbuffer[9:1]} == 10'b0001111100) begin
			bitcount <= deser_en_sum - 1;
			recv_word_en <= !reset;
			recv_wbits <= 10'b0001111100;

		end else
		if (&deser_en[1:0] && {deser_bits[1:0], bitbuffer[9:2]} == 10'b0001111100) begin
			bitcount <= deser_en_sum - 2;
			recv_word_en <= !reset;
			recv_wbits <= 10'b0001111100;
		end else
		if (&deser_en[2:0] && {deser_bits[2:0], bitbuffer[9:3]} == 10'b0001111100) begin
			bitcount <= deser_en_sum - 3;
			recv_word_en <= !reset;
			recv_wbits <= 10'b0001111100;
		end else
		if (&deser_en[3:0] && {deser_bits[3:0], bitbuffer[9:4]} == 10'b0001111100) begin
			bitcount <= 0;
			recv_word_en <= !reset;
			recv_wbits <= 10'b0001111100;
		end else begin
			if (bitcount + deser_en_sum >= 10) begin
				recv_word_en <= !reset;
				recv_wbits <= {deser_bits, bitbuffer} >> (10 - bitcount);
				bitcount <= bitcount + deser_en_sum - 10;
			end else
				bitcount <= bitcount + deser_en_sum;
			bitbuffer <= {deser_bits, bitbuffer} >> deser_en_sum;
		end
	end
endmodule

