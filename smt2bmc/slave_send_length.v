module main (
	input        clk,
	input        serdes_in,
	output       serdes_out,
	output       serdes_en
);
	wire clk;
	wire resetn_out;
	wire linkerror;
	wire linkready;
	wire mode_recv;
	wire mode_send;
	wire [7:0] gpio_i = 0;
	wire [7:0] gpio_o;
	wire [4:0] in_tdata = 0;
	wire [3:0] in_tuser = 0;
	wire in_tvalid = 1;
	wire in_tlast = 0;
	wire in_tready;
	wire [4:0] out_tdata;
	wire [3:0] out_tuser;
	wire out_tvalid;
	wire out_tlast;
	wire out_tready = 1;
	wire serdes_in;
	wire serdes_out;
	wire serdes_en;

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
		.MASTER_PARBITS(1),
		.SLAVE_PARBITS(1),
		.MASTER_PKTLEN(8),
		.SLAVE_PKTLEN(8),
		.MASTER_TIMINGS(80'h2e241a100618130e0904),
		.SLAVE_TIMINGS (80'h05040302010907050301)
	) uut (
		.clk       (clk       ),
		.resetn_out(resetn_out),
		.linkerror (linkerror ),
		.linkready (linkready ),
		.mode_recv (mode_recv ),
		.mode_send (mode_send ),
		.gpio_i    (gpio_i    ),
		.gpio_o    (gpio_o    ),
		.in_tdata  (in_tdata  ),
		.in_tuser  (in_tuser  ),
		.in_tvalid (in_tvalid ),
		.in_tlast  (in_tlast  ),
		.in_tready (in_tready ),
		.out_tdata (out_tdata ),
		.out_tuser (out_tuser ),
		.out_tvalid(out_tvalid),
		.out_tlast (out_tlast ),
		.out_tready(out_tready),
		.serdes_in (serdes_in ),
		.serdes_out(serdes_out),
		.serdes_en (serdes_en )
	);
endmodule
