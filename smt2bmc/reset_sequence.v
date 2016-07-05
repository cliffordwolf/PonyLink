module main (
	input  slave_clk,
	input  master_clk,
	input  reset,
	output out_finish,
	output out_error
);
	wire       slave_clk;
	wire       slave_resetn_out;
	wire       slave_linkerror;
	wire       slave_linkready;
	wire       slave_mode_recv;
	wire       slave_mode_send;
	wire [7:0] slave_gpio_i = 0;
	wire [7:0] slave_gpio_o;
	wire [7:0] slave_in_tdata;
	wire [3:0] slave_in_tuser;
	wire       slave_in_tvalid;
	wire       slave_in_tlast;
	wire       slave_in_tready;
	wire [7:0] slave_out_tdata;
	wire [3:0] slave_out_tuser;
	wire       slave_out_tvalid;
	wire       slave_out_tlast;
	wire       slave_out_tready;
	wire [3:0] slave_serdes_in;
	wire [3:0] slave_serdes_out;
	wire [3:0] slave_serdes_en;

	assign slave_in_tdata = slave_out_tdata;
	assign slave_in_tuser = slave_out_tuser;
	assign slave_in_tvalid = slave_out_tvalid;
	assign slave_in_tlast = slave_out_tlast;
	assign slave_out_tready = slave_in_tready;

	wire       master_clk;
	wire       master_resetn;
	wire       master_linkerror;
	wire       master_linkready;
	wire       master_mode_recv;
	wire       master_mode_send;
	wire [7:0] master_gpio_i = 0;
	wire [7:0] master_gpio_o;
	wire [7:0] master_in_tdata = 23;
	wire [3:0] master_in_tuser = 13;
	wire       master_in_tvalid;
	wire       master_in_tlast = 0;
	wire       master_in_tready;
	wire [7:0] master_out_tdata;
	wire [3:0] master_out_tuser;
	wire       master_out_tvalid;
	wire       master_out_tlast;
	wire       master_out_tready = 0;
	wire [3:0] master_serdes_in;
	wire [3:0] master_serdes_out;
	wire [3:0] master_serdes_en;

	assign master_serdes_in = slave_serdes_in, slave_serdes_in =
			|master_serdes_en && !slave_serdes_en ? master_serdes_out :
			!master_serdes_en && |slave_serdes_en ? slave_serdes_out : 0;

    assign out_finish = !reset && master_resetn && master_out_tvalid;
	assign out_error = (master_out_tdata != 23 || master_out_tuser != 13);

	reg master_resetn, master_in_tvalid;
	reg [1:0] state;

	always @(posedge master_clk) begin
		if (reset) begin
			master_resetn <= 0;
			master_in_tvalid <= 1;
			state <= 0;
		end else
		case (state)
			0: begin
				master_resetn <= 1;
				state <= 1;
			end
			1: begin
				if (master_in_tready) begin
					master_in_tvalid <= 0;
					state <= 2;
				end
			end
		endcase
	end

	ponylink_slave #(
		.SERDES_REG_IN(1),
		.SERDES_REG_OUT(1),
		.M2S_TDATA_WIDTH(8),
		.M2S_TUSER_WIDTH(4),
		.S2M_TDATA_WIDTH(8),
		.S2M_TUSER_WIDTH(4),
		.MASTER_RECV_DELAY(8),
		.SLAVE_RECV_DELAY(8),
		.MASTER_SEND_DELAY(32),
		.SLAVE_SEND_DELAY(32),
		.MASTER_PARBITS(4),
		.SLAVE_PARBITS(4),
		.MASTER_PKTLEN(8),
		.SLAVE_PKTLEN(8),
		.MASTER_TIMINGS(80'h0e0b0805020d0a070401),
		.SLAVE_TIMINGS(80'h0e0b0805020d0a070401)
	) uut_slave (
		.clk       (slave_clk       ),
		.resetn_out(slave_resetn_out),
		.linkerror (slave_linkerror ),
		.linkready (slave_linkready ),
		.mode_recv (slave_mode_recv ),
		.mode_send (slave_mode_send ),
		.gpio_i    (slave_gpio_i    ),
		.gpio_o    (slave_gpio_o    ),
		.in_tdata  (slave_in_tdata  ),
		.in_tuser  (slave_in_tuser  ),
		.in_tvalid (slave_in_tvalid ),
		.in_tlast  (slave_in_tlast  ),
		.in_tready (slave_in_tready ),
		.out_tdata (slave_out_tdata ),
		.out_tuser (slave_out_tuser ),
		.out_tvalid(slave_out_tvalid),
		.out_tlast (slave_out_tlast ),
		.out_tready(slave_out_tready),
		.serdes_in (slave_serdes_in ),
		.serdes_out(slave_serdes_out),
		.serdes_en (slave_serdes_en )
	);

	ponylink_master #(
		.SERDES_REG_IN(1),
		.SERDES_REG_OUT(1),
		.M2S_TDATA_WIDTH(8),
		.M2S_TUSER_WIDTH(4),
		.S2M_TDATA_WIDTH(8),
		.S2M_TUSER_WIDTH(4),
		.MASTER_RECV_DELAY(8),
		.SLAVE_RECV_DELAY(8),
		.MASTER_SEND_DELAY(32),
		.SLAVE_SEND_DELAY(32),
		.MASTER_PARBITS(4),
		.SLAVE_PARBITS(4),
		.MASTER_PKTLEN(8),
		.SLAVE_PKTLEN(8),
		.MASTER_TIMINGS(80'h0e0b0805020d0a070401),
		.SLAVE_TIMINGS(80'h0e0b0805020d0a070401)
	) uut_master (
		.clk       (master_clk       ),
		.resetn    (master_resetn    ),
		.linkerror (master_linkerror ),
		.linkready (master_linkready ),
		.mode_recv (master_mode_recv ),
		.mode_send (master_mode_send ),
		.gpio_i    (master_gpio_i    ),
		.gpio_o    (master_gpio_o    ),
		.in_tdata  (master_in_tdata  ),
		.in_tuser  (master_in_tuser  ),
		.in_tvalid (master_in_tvalid ),
		.in_tlast  (master_in_tlast  ),
		.in_tready (master_in_tready ),
		.out_tdata (master_out_tdata ),
		.out_tuser (master_out_tuser ),
		.out_tvalid(master_out_tvalid),
		.out_tlast (master_out_tlast ),
		.out_tready(master_out_tready),
		.serdes_in (master_serdes_in ),
		.serdes_out(master_serdes_out),
		.serdes_en (master_serdes_en )
	);
endmodule
