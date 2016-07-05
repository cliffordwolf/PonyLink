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
// `define NO_PONYLINK_SCRAMBLE

module ponylink_pack_8bits #(
	parameter TDATA_WIDTH = 10,
	parameter TUSER_WIDTH = 0
)(
	input clk,
	input resetn,

	input  [TDATA_WIDTH-1:0] tdata,
	input  [TUSER_WIDTH-1:0] tuser,
	input                    tvalid,
	input                    tlast,
	output                   tready,

	output reg [8:0] ser_tdata,
	output reg       ser_tvalid,
	input            ser_tready
);
	reg [31:0] rng;
	reg [11:0] rng_counter;
	reg [4:0] rng_cursor;

	reg [7:0] queue_tuser, queue_tdata;
	reg queue_tvalid, queue_tlast, queue_send_tuser, queue_send_tuser2;
	assign tready = !queue_tvalid && resetn;

	always @(posedge clk) begin
		if (tready && tvalid) begin
			queue_tuser <= tuser;
			queue_tdata <= tdata;
			queue_tlast <= tlast;
			queue_send_tuser <= (queue_tuser !== tuser) && (TUSER_WIDTH > 0);
			queue_send_tuser2 <= 0;
			queue_tvalid <= 1;
		end
		if (!resetn) begin
`ifdef NO_PONYLINK_SCRAMBLE
			rng = 0;
`else
			rng = 123456789;
`endif
			rng_cursor <= 1;
			queue_tuser <= 0;
			queue_tlast <= 0;
			queue_send_tuser <= 0;
			queue_send_tuser2 <= 0;
			queue_tvalid <= 0;
			ser_tvalid <= 0;
		end else if (!ser_tvalid || ser_tready) begin
			if (rng_cursor) begin
				(* full_case, parallel_case *)
				case (1'b1)
					rng_cursor[0]: ser_tdata <= 9'h11c;
					rng_cursor[1]: ser_tdata <= rng[ 0 +: 8];
					rng_cursor[2]: ser_tdata <= rng[ 8 +: 8];
					rng_cursor[3]: ser_tdata <= rng[16 +: 8];
					rng_cursor[4]: ser_tdata <= rng[24 +: 8];
				endcase
				ser_tvalid <= 1;
				rng_counter <= 1;
				rng_cursor <= rng_cursor << 1;
			end else if (queue_tlast) begin
				ser_tvalid <= 1;
				ser_tdata <= 9'h17c;
				queue_tlast <= 0;
			end else if (queue_send_tuser) begin
				ser_tvalid <= 1;
				ser_tdata <= 9'h15c;
				queue_send_tuser <= 0;
				queue_send_tuser2 <= 1;
			end else if (queue_send_tuser2 || queue_tvalid) begin
				if (queue_send_tuser2) begin
					ser_tvalid <= 1;
					ser_tdata <= queue_tuser ^ rng[7:0];
					queue_send_tuser2 <= 0;
				end else if (queue_tvalid) begin
					ser_tvalid <= 1;
					ser_tdata <= queue_tdata ^ rng[7:0];
					queue_tvalid <= 0;
				end
				rng = rng ^ (rng << 13);
				rng = rng ^ (rng >> 17);
				rng = rng ^ (rng << 5);
				if (!rng_counter)
					rng_cursor <= 1;
				rng_counter <= rng_counter + 1'b1;
			end else
				ser_tvalid <= 0;
		end
	end
endmodule

module ponylink_unpack_8bits #(
	parameter TDATA_WIDTH = 8,
	parameter TUSER_WIDTH = 8
) (
	input clk,
	input resetn,

	output reg [TDATA_WIDTH-1:0] tdata,
	output reg [TUSER_WIDTH-1:0] tuser,
	output reg                   tvalid,
	output reg                   tlast,
	input                        tready,

	input  [8:0] ser_tdata,
	input        ser_tvalid,
	output reg   ser_tready
);
	reg store_tuser;

	reg [31:0] rng;
	reg [3:0] rng_cursor;
	reg rng_next;

	always @(posedge clk) begin
		rng_next <= 0;
		ser_tready <= 0;
		if (tready && tvalid) begin
			tlast <= 0;
			tvalid <= 0;
		end
		if (!resetn) begin
			rng = 123456789;
			rng_cursor <= 0;
			rng_next <= 0;
			tlast <= 0;
			tvalid <= 0;
			tuser <= 0;
		end else if (!ser_tready && ser_tvalid && (!tvalid || tready)) begin
			if (rng_cursor) begin
				(* full_case, parallel_case *)
				case (1'b1)
					rng_cursor[0]: rng[ 0 +: 8] = ser_tdata[7:0];
					rng_cursor[1]: rng[ 8 +: 8] = ser_tdata[7:0];
					rng_cursor[2]: rng[16 +: 8] = ser_tdata[7:0];
					rng_cursor[3]: rng[24 +: 8] = ser_tdata[7:0];
				endcase
				rng_cursor <= rng_cursor << 1;
				ser_tready <= 1;
			end else if (store_tuser) begin
				tuser <= ser_tdata[7:0] ^ rng[7:0];
				store_tuser <= 0;
				ser_tready <= 1;
				rng_next <= 1;
			end else if (ser_tdata == 9'h17c) begin
				tlast <= 1;
				ser_tready <= 1;
			end else if (ser_tdata == 9'h15c) begin
				store_tuser <= 1;
				ser_tready <= 1;
			end else if (ser_tdata == 9'h11c) begin
				rng_cursor <= 1;
				ser_tready <= 1;
			end else begin
				tdata <= ser_tdata[7:0] ^ rng[7:0];
				tvalid <= 1;
				ser_tready <= 1;
				rng_next <= 1;
			end
		end else if (rng_next) begin
			rng = rng ^ (rng << 13);
			rng = rng ^ (rng >> 17);
			rng = rng ^ (rng << 5);
		end
	end
endmodule

module ponylink_pack_generic #(
	parameter TDATA_WIDTH = 10,
	parameter TUSER_WIDTH = 0
) (
	input clk,
	input resetn,

	input  [TDATA_WIDTH-1:0] tdata,
	input  [TUSER_WIDTH-1:0] tuser,
	input                    tvalid,
	input                    tlast,
	output reg               tready,

	output reg [8:0] ser_tdata,
	output reg       ser_tvalid,
	input            ser_tready
);
	localparam TDATA_BYTES = (TDATA_WIDTH + 7) / 8;
	localparam TUSER_BYTES = (TUSER_WIDTH + 7) / 8;

	reg [TDATA_BYTES-1:0] cursor_td;
	reg [TUSER_BYTES-1:0] cursor_tu;
	reg [8*TDATA_BYTES-1:0] current_td;
	reg [8*TUSER_BYTES-1:0] current_tu;
	reg current_tl, mkseq_tu;

	integer i;
	reg [31:0] rng;
	reg [11:0] rng_counter;
	reg [4:0] rng_cursor;

	reg [TDATA_BYTES-1:0] nxt_cursor_td;
	reg [TUSER_BYTES-1:0] nxt_cursor_tu;
	reg nxt_current_tl, nxt_mkseq_tu;

	always @(posedge clk) begin
		ser_tdata <= 'bx;
		ser_tvalid <= 0;
		tready <= 0;
		if (!resetn) begin
			cursor_td = 0;
			cursor_tu = 0;
			current_tu = 0;
			current_tl = 0;
			mkseq_tu = 0;
			nxt_cursor_td = 0;
			nxt_cursor_tu = 0;
			nxt_current_tl = 0;
			nxt_mkseq_tu = 0;
`ifdef NO_PONYLINK_SCRAMBLE
			rng = 0;
`else
			rng = 123456789;
`endif
			rng_counter = 1;
			rng_cursor = 1;
		end else begin
			if (ser_tvalid && ser_tready) begin
				if (!current_tl && !mkseq_tu && !rng_cursor) begin
					rng = rng ^ (rng << 13);
					rng = rng ^ (rng >> 17);
					rng = rng ^ (rng << 5);
					if (!rng_counter)
						rng_cursor = 1;
					rng_counter = rng_counter+1;
				end else
					rng_cursor = rng_cursor << 1;
				cursor_td = nxt_cursor_td;
				cursor_tu = nxt_cursor_tu;
				current_tl = nxt_current_tl;
				mkseq_tu = nxt_mkseq_tu;
			end
			if (tvalid && tready) begin
				cursor_td = 1;
				cursor_tu = (current_tu === tuser || TUSER_WIDTH == 0) ? 0 : 1;
				mkseq_tu = (current_tu === tuser || TUSER_WIDTH == 0) ? 0 : 1;
				current_td = tdata;
				current_tu = tuser;
				current_tl = tlast;

				nxt_cursor_td = cursor_td;
				nxt_cursor_tu = cursor_tu;
				nxt_current_tl = current_tl;
				nxt_mkseq_tu = mkseq_tu;
			end
			if (rng_cursor) begin
				if (rng_cursor[0]) ser_tdata <= 9'h11c;
				if (rng_cursor[1]) ser_tdata <= rng[ 0 +: 8];
				if (rng_cursor[2]) ser_tdata <= rng[ 8 +: 8];
				if (rng_cursor[3]) ser_tdata <= rng[16 +: 8];
				if (rng_cursor[4]) ser_tdata <= rng[24 +: 8];
				ser_tvalid <= 1;
			end else
			if (current_tl) begin
				ser_tdata <= 9'h17c;
				ser_tvalid <= 1;
				nxt_current_tl = 0;
			end else
			if (mkseq_tu) begin
				ser_tdata <= 9'h15c;
				ser_tvalid <= 1;
				nxt_mkseq_tu = 0;
			end else
			if (cursor_tu) begin
				for (i = 0; i < TUSER_BYTES; i = i+1)
					if (cursor_tu[i]) begin ser_tdata <= current_tu[8*i +: 8] ^ rng[7:0]; ser_tvalid <= 1; end
				nxt_cursor_tu = cursor_tu << 1;
			end else
			if (cursor_td) begin
				for (i = 0; i < TDATA_BYTES; i = i+1)
					if (cursor_td[i]) begin ser_tdata <= current_td[8*i +: 8] ^ rng[7:0]; ser_tvalid <= 1; end
				nxt_cursor_td = cursor_td << 1;
			end else
				tready <= 1;
		end
	end
endmodule

module ponylink_unpack_generic #(
	parameter TDATA_WIDTH = 10,
	parameter TUSER_WIDTH = 0
) (
	input clk,
	input resetn,

	output [TDATA_WIDTH-1:0] tdata,
	output [TUSER_WIDTH-1:0] tuser,
	output                   tvalid,
	output                   tlast,
	input                    tready,

	input  [8:0] ser_tdata,
	input        ser_tvalid,
	output reg   ser_tready
);
	reg [TDATA_WIDTH-1:0] buffer_td [0:7];
	reg [TUSER_WIDTH-1:0] buffer_tu [0:7];
	reg                   buffer_tl [0:7];
	reg [2:0] buffer_in, buffer_out;

	localparam TDATA_BYTES = (TDATA_WIDTH + 7) / 8;
	localparam TUSER_BYTES = (TUSER_WIDTH + 7) / 8;

	reg [TDATA_BYTES-1:0] cursor_td;
	reg [TUSER_BYTES-1:0] cursor_tu;
	reg [8*TDATA_BYTES-1:0] next_td;
	reg [8*TUSER_BYTES-1:0] next_tu;
	reg next_tl;

	integer i;
	reg [31:0] rng;
	reg [3:0] rng_cursor;
	reg reset_q;

	assign tdata = buffer_td[buffer_out];
	assign tuser = buffer_tu[buffer_out];
	assign tlast = buffer_tl[buffer_out];
	assign tvalid = buffer_in != buffer_out && resetn;

	always @(posedge clk) begin
		reset_q <= !resetn;
		if (!resetn) begin
			buffer_in <= 0;
			buffer_out <= 0;
			ser_tready <= 0;

			cursor_td = 1;
			cursor_tu = 0;
			next_tl = 0;
			next_tu = 0;
			rng = 0;
			rng_cursor = 0;
		end else begin
			if (!cursor_td && !cursor_tu) begin
				buffer_td[buffer_in] <= next_td;
				buffer_tu[buffer_in] <= next_tu;
				buffer_tl[buffer_in] <= next_tl;
				buffer_in <= buffer_in + 1;
				ser_tready <= (buffer_out - buffer_in) > 3'd3;

				cursor_td = 1;
				next_tl = 0;
			end
			if (ser_tvalid && ser_tready) begin
				if (ser_tdata == 9'h11c) begin
					rng_cursor = 1;
				end else
				if (ser_tdata == 9'h15c && TUSER_BYTES) begin
					cursor_tu = 1;
				end else
				if (ser_tdata == 9'h17c) begin
					next_tl = 1;
				end else
				if (rng_cursor) begin
					if (rng_cursor[0]) rng[ 0 +: 8] = ser_tdata;
					if (rng_cursor[1]) rng[ 8 +: 8] = ser_tdata;
					if (rng_cursor[2]) rng[16 +: 8] = ser_tdata;
					if (rng_cursor[3]) rng[24 +: 8] = ser_tdata;
					rng_cursor = rng_cursor << 1;
				end else begin
					for (i = 0; i < TUSER_BYTES; i = i+1)
						if (cursor_tu[i]) next_tu[8*i +: 8] = ser_tdata ^ rng[7:0];
					for (i = 0; i < TDATA_BYTES; i = i+1)
						if (cursor_td[i]) next_td[8*i +: 8] = ser_tdata ^ rng[7:0];
					if (cursor_tu && TUSER_BYTES)
						cursor_tu = cursor_tu << 1;
					else
						cursor_td = cursor_td << 1;
					rng = rng ^ (rng << 13);
					rng = rng ^ (rng >> 17);
					rng = rng ^ (rng << 5);
				end
			end
			if (tvalid && tready) begin
				buffer_out <= buffer_out + 1;
				ser_tready <= 1;
			end
			if (reset_q)
				ser_tready <= 1;
		end
	end
endmodule

