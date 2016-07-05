
`timescale 1 ns / 1 ps

module top (
	// 125 MHz clock
	input iclk,
`ifdef SYNTHESIS
	inout master_pin,
	inout slave_pin
`else
	inout shared_pin
`endif
);
	wire pll_feedback;
	wire pll_locked;
	wire clk, clk4;

`ifdef SYNTHESIS
    wire clk125 = iclk;
`else
    reg clk125 = 0;
    always @* clk125 <= #4 !clk125;
`endif

	MMCME2_BASE #(
	    .CLKIN1_PERIOD(8.0),
		.CLKFBOUT_MULT_F(8.0),
		.CLKOUT1_DIVIDE(20),
		.CLKOUT1_DUTY_CYCLE(0.5),
		.CLKOUT1_PHASE(0.0),
		.CLKOUT2_DIVIDE(5),
		.CLKOUT2_DUTY_CYCLE(0.5),
		.CLKOUT2_PHASE(0.0)
	) pll (
		.CLKIN1(clk125),
		.CLKOUT1(clk),
		.CLKOUT2(clk4),
		.CLKFBOUT(pll_feedback),
		.CLKFBIN(pll_feedback),
		.PWRDWN(1'b0),
		.LOCKED(pll_locked),
		.RST(1'b0)
	);
	
	reg resetn;
	reg [3:0] locked_q;
	always @(posedge clk)
		{resetn, locked_q} <= {locked_q, pll_locked};

	parameter M2S_TDATA_WIDTH = 8;
	parameter M2S_TUSER_WIDTH = 1;
	parameter S2M_TDATA_WIDTH = 8;
	parameter S2M_TUSER_WIDTH = 1;
	parameter MASTER_PARBITS = 4;
	parameter MASTER_TIMINGS = 80'h110c0805020f0a070401;
	parameter SLAVE_PARBITS = 4;
	parameter SLAVE_TIMINGS = 80'h110c0805020f0a070401;

	wire [7:0] master_gpio_i = 0;
	wire [7:0] master_gpio_o = 0;

	wire [7:0] slave_gpio_i = 0;
	wire [7:0] slave_gpio_o = 0;

	wire [M2S_TDATA_WIDTH-1:0] master_in_tdata = 0;
	wire [M2S_TUSER_WIDTH-1:0] master_in_tuser = 0;
	wire                       master_in_tvalid = 1;
	wire                       master_in_tlast = 0;
	wire                       master_in_tready;

	wire [S2M_TDATA_WIDTH-1:0] master_out_tdata;
	wire [S2M_TUSER_WIDTH-1:0] master_out_tuser;
	wire                       master_out_tvalid;
	wire                       master_out_tlast;
	wire                       master_out_tready = 1;

	wire [S2M_TDATA_WIDTH-1:0] slave_in_tdata = 0;
	wire [S2M_TUSER_WIDTH-1:0] slave_in_tuser = 0;
	wire                       slave_in_tvalid = 1;
	wire                       slave_in_tlast = 0;
	wire                       slave_in_tready;

	wire [M2S_TDATA_WIDTH-1:0] slave_out_tdata;
	wire [M2S_TUSER_WIDTH-1:0] slave_out_tuser;
	wire                       slave_out_tvalid;
	wire                       slave_out_tlast;
	wire                       slave_out_tready = 1;

	wire master_linkerror;
	wire slave_linkerror;
	wire slave_resetn;

	wire [MASTER_PARBITS-1:0] master_serdes_in;
	wire [MASTER_PARBITS-1:0] master_serdes_out;
	wire [MASTER_PARBITS-1:0] master_serdes_en;

	wire [SLAVE_PARBITS-1:0] slave_serdes_in;
	wire [SLAVE_PARBITS-1:0] slave_serdes_out;
	wire [SLAVE_PARBITS-1:0] slave_serdes_en;

	integer i;

	reg master_oserdes_last = 0;
	reg [3:0] master_oserdes_d;
	wire [3:0] master_iserdes_q;
	reg [2:0] master_oserdes_t;

	reg slave_oserdes_last = 0;
	reg [3:0] slave_oserdes_d;
	wire [3:0] slave_iserdes_q;
	reg [2:0] slave_oserdes_t;
	
	always @(posedge clk) begin
		master_oserdes_t <= {master_oserdes_t, 1'b1};
		for (i = 0; i < 4; i = i+1) begin
			if (master_serdes_en[i]) begin
				master_oserdes_last = master_serdes_out[i];
				master_oserdes_t[0] <= 0;
			end
			master_oserdes_d[i] <= master_oserdes_last;
		end
	end

	always @(posedge clk) begin
		slave_oserdes_t <= {slave_oserdes_t, 1'b1};
		for (i = 0; i < 4; i = i+1) begin
			if (slave_serdes_en[i]) begin
				slave_oserdes_last = slave_serdes_out[i];
				slave_oserdes_t[0] <= 0;
			end
			slave_oserdes_d[i] <= slave_oserdes_last;
		end
	end

	// assign master_serdes_in = (master_serdes_out & master_serdes_en) | (slave_serdes_out & ~master_serdes_en);
	// assign slave_serdes_in = (slave_serdes_out & slave_serdes_en) | (master_serdes_out & ~slave_serdes_en);

`ifdef SYNTHESIS
	assign master_serdes_in = master_iserdes_q;
	assign slave_serdes_in = slave_iserdes_q;
`else
	assign master_serdes_in = {
		master_iserdes_q[3] === 1'b1,
		master_iserdes_q[2] === 1'b1,
		master_iserdes_q[1] === 1'b1,
		master_iserdes_q[0] === 1'b1
	};
	assign slave_serdes_in = {
		slave_iserdes_q[3] === 1'b1,
		slave_iserdes_q[2] === 1'b1,
		slave_iserdes_q[1] === 1'b1,
		slave_iserdes_q[0] === 1'b1
	};
`endif

	ponylink_master #(
		.M2S_TDATA_WIDTH(M2S_TDATA_WIDTH),
		.M2S_TUSER_WIDTH(M2S_TUSER_WIDTH),
		.S2M_TDATA_WIDTH(S2M_TDATA_WIDTH),
		.S2M_TUSER_WIDTH(S2M_TUSER_WIDTH),
		.MASTER_PARBITS(MASTER_PARBITS),
		.MASTER_TIMINGS(MASTER_TIMINGS),
		.SLAVE_PARBITS(SLAVE_PARBITS),
		.SLAVE_TIMINGS(SLAVE_TIMINGS)
	) ponylink_master_core (
		.clk(clk),
		.resetn(resetn),
		.linkerror(master_linkerror),

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
	) ponylink_slave_core (
		.clk(clk),
		.resetn_out(slave_resetn),
		.linkerror(slave_linkerror),

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

	wire master_oq, master_tq, master_d;
	wire slave_oq, slave_tq, slave_d;
	
	IOBUF master_buf (
		.I(master_oq),
		.T(master_tq),
		.O(master_d),
`ifdef SYNTHESIS
		.IO(master_pin)
`else
		.IO(shared_pin)
`endif
	);
	
	IOBUF slave_buf (
		.I(slave_oq),
		.T(slave_tq),
		.O(slave_d),
`ifdef SYNTHESIS
		.IO(slave_pin)
`else
		.IO(shared_pin)
`endif
	);

	OSERDESE2 #(
		.DATA_RATE_OQ("SDR"),
		.DATA_RATE_TQ("SDR"),
		.DATA_WIDTH(4),
		.INIT_OQ(1'b0),
		.INIT_TQ(1'b1),
		.SERDES_MODE("MASTER"),
		.SRVAL_OQ(1'b0),
		.SRVAL_TQ(1'b1),
		.TBYTE_CTL("FALSE"),
		.TBYTE_SRC("FALSE"),
		.TRISTATE_WIDTH(1)
	) master_oserdes (
		.OFB(),
		.OQ(master_oq),
		.SHIFTOUT1(),
		.SHIFTOUT2(),
		.TBYTEOUT(),
		.TFB(),
		.TQ(master_tq),
		.CLK(clk4),
		.CLKDIV(clk),
		.D1(master_oserdes_d[0]),
		.D2(master_oserdes_d[1]),
		.D3(master_oserdes_d[2]),
		.D4(master_oserdes_d[3]),
		.D5(),
		.D6(),
		.D7(),
		.D8(),
		.OCE(1'b1),
		.RST(~resetn),
		.SHIFTIN1(1'b0),
		.SHIFTIN2(1'b0),
		.T1(&master_oserdes_t),
		.T2(1'b0),
		.T3(1'b0),
		.T4(1'b0),
		.TBYTEIN(1'b0),
		.TCE(1'b1)
	);

	OSERDESE2 #(
		.DATA_RATE_OQ("SDR"),
		.DATA_RATE_TQ("SDR"),
		.DATA_WIDTH(4),
		.INIT_OQ(1'b0),
		.INIT_TQ(1'b1),
		.SERDES_MODE("MASTER"),
		.SRVAL_OQ(1'b0),
		.SRVAL_TQ(1'b1),
		.TBYTE_CTL("FALSE"),
		.TBYTE_SRC("FALSE"),
		.TRISTATE_WIDTH(1)
	) slave_oserdes (
		.OFB(),
		.OQ(slave_oq),
		.SHIFTOUT1(),
		.SHIFTOUT2(),
		.TBYTEOUT(),
		.TFB(),
		.TQ(slave_tq),
		.CLK(clk4),
		.CLKDIV(clk),
		.D1(slave_oserdes_d[0]),
		.D2(slave_oserdes_d[1]),
		.D3(slave_oserdes_d[2]),
		.D4(slave_oserdes_d[3]),
		.D5(),
		.D6(),
		.D7(),
		.D8(),
		.OCE(1'b1),
		.RST(~resetn),
		.SHIFTIN1(1'b0),
		.SHIFTIN2(1'b0),
		.T1(&slave_oserdes_t),
		.T2(1'b0),
		.T3(1'b0),
		.T4(1'b0),
		.TBYTEIN(1'b0),
		.TCE(1'b1)
	);

	ISERDESE2 #(
		.DATA_RATE("SDR"),
		.DATA_WIDTH(4),
		.DYN_CLKDIV_INV_EN("FALSE"),
		.DYN_CLK_INV_EN("FALSE"),
		.INIT_Q1(1'b0),
		.INIT_Q2(1'b0),
		.INIT_Q3(1'b0),
		.INIT_Q4(1'b0),
		.INTERFACE_TYPE("NETWORKING"),   // MEMORY, MEMORY_DDR3, MEMORY_QDR, NETWORKING, OVERSAMPLE
		.IOBDELAY("NONE"),
		.NUM_CE(2),
		.OFB_USED("FALSE"),
		.SERDES_MODE("MASTER"),
		.SRVAL_Q1(1'b0),
		.SRVAL_Q2(1'b0),
		.SRVAL_Q3(1'b0),
		.SRVAL_Q4(1'b0) 
	) master_iserdes (
		.O(),
		.Q1(master_iserdes_q[3]),
		.Q2(master_iserdes_q[2]),
		.Q3(master_iserdes_q[1]),
		.Q4(master_iserdes_q[0]),
		.Q5(),
		.Q6(),
		.Q7(),
		.Q8(),
		.SHIFTOUT1(),
		.SHIFTOUT2(),
		.BITSLIP(1'b0),
		.CE1(1'b1),
		.CE2(1'b1),
		.CLKDIVP(1'b0),
		.CLK(clk4),
		.CLKB(~clk4),
		.CLKDIV(clk),
		.OCLK(1'b0), 
		.DYNCLKDIVSEL(1'b0),
		.DYNCLKSEL(1'b0),
		.D(master_d),
		.DDLY(1'b0),
		.OFB(1'b0),
		.OCLKB(1'b0),
		.RST(~resetn),
		.SHIFTIN1(1'b0),
		.SHIFTIN2(1'b0) 
	);

	ISERDESE2 #(
		.DATA_RATE("SDR"),
		.DATA_WIDTH(4),
		.DYN_CLKDIV_INV_EN("FALSE"),
		.DYN_CLK_INV_EN("FALSE"),
		.INIT_Q1(1'b0),
		.INIT_Q2(1'b0),
		.INIT_Q3(1'b0),
		.INIT_Q4(1'b0),
		.INTERFACE_TYPE("NETWORKING"),   // MEMORY, MEMORY_DDR3, MEMORY_QDR, NETWORKING, OVERSAMPLE
		.IOBDELAY("NONE"),
		.NUM_CE(2),
		.OFB_USED("FALSE"),
		.SERDES_MODE("MASTER"),
		.SRVAL_Q1(1'b0),
		.SRVAL_Q2(1'b0),
		.SRVAL_Q3(1'b0),
		.SRVAL_Q4(1'b0) 
	) slave_iserdes (
		.O(),
		.Q1(slave_iserdes_q[3]),
		.Q2(slave_iserdes_q[2]),
		.Q3(slave_iserdes_q[1]),
		.Q4(slave_iserdes_q[0]),
		.Q5(),
		.Q6(),
		.Q7(),
		.Q8(),
		.SHIFTOUT1(),
		.SHIFTOUT2(),
		.BITSLIP(1'b0),
		.CE1(1'b1),
		.CE2(1'b1),
		.CLKDIVP(1'b0),
		.CLK(clk4),
		.CLKB(~clk4),
		.CLKDIV(clk),
		.OCLK(1'b0), 
		.DYNCLKDIVSEL(1'b0),
		.DYNCLKSEL(1'b0),
		.D(slave_d),
		.DDLY(1'b0),
		.OFB(1'b0),
		.OCLKB(1'b0),
		.RST(~resetn),
		.SHIFTIN1(1'b0),
		.SHIFTIN2(1'b0) 
	);
endmodule
