`timescale 1 ns / 1 ps

module icedemo (
	input clk_pin,

	inout  master_io,
	output master_en,
	output master_in,
	output master_out,
	output master_rst,
	output master_clk,

	inout  slave_io,
	output slave_en,
	output slave_in,
	output slave_out,
	output slave_rst,
	output slave_clk,

	output led_0,
	output led_1,
	output led_2,
	output led_3,
	output led_4,
	output led_5,
	output led_6,
	output led_7
);
	localparam MASTER_TIMINGS = 80'h0e0b0805020d0a070401;
	localparam SLAVE_TIMINGS = 80'h0e0b0805020d0a070401;

	// ---------------------------
	// PonyLink Master

	wire        master_clk;
	wire        master_resetn;

	wire        master_linkerror;
	wire        master_linkready;

	wire        master_mode_recv;
	wire        master_mode_send;

	wire  [7:0] master_gpio_i;
	wire  [7:0] master_gpio_o;

	wire [15:0] master_in_tdata;
	wire        master_in_tvalid;
	wire        master_in_tlast;
	wire        master_in_tready;

	wire [15:0] master_out_tdata;
	wire        master_out_tvalid;
	wire        master_out_tlast;
	wire        master_out_tready;

	wire        master_serdes_in;
	wire        master_serdes_out;
	wire        master_serdes_en;

	ponylink_master #(
		.MASTER_PARBITS(1),
		.SLAVE_PARBITS(1),
		.M2S_TDATA_WIDTH(16),
		.S2M_TDATA_WIDTH(16),
		.MASTER_TIMINGS(MASTER_TIMINGS),
		.SLAVE_TIMINGS(SLAVE_TIMINGS)
	) master_core (
		.clk       (master_clk       ),
		.resetn    (master_resetn    ),
		.linkerror (master_linkerror ),
		.linkready (master_linkready ),
		.mode_recv (master_mode_recv ),
		.mode_send (master_mode_send ),
		.gpio_i    (master_gpio_i    ),
		.gpio_o    (master_gpio_o    ),
		.in_tdata  (master_in_tdata  ),
		.in_tvalid (master_in_tvalid ),
		.in_tlast  (master_in_tlast  ),
		.in_tready (master_in_tready ),
		.out_tdata (master_out_tdata ),
		.out_tvalid(master_out_tvalid),
		.out_tlast (master_out_tlast ),
		.out_tready(master_out_tready),
		.serdes_in (master_serdes_in ),
		.serdes_out(master_serdes_out),
		.serdes_en (master_serdes_en )
	);


	// ---------------------------
	// PonyLink Slave

	wire        slave_clk;
	wire        slave_resetn;

	wire        slave_linkerror;
	wire        slave_linkready;

	wire        slave_mode_recv;
	wire        slave_mode_send;

	wire  [7:0] slave_gpio_i;
	wire  [7:0] slave_gpio_o;

	wire [15:0] slave_in_tdata;
	wire        slave_in_tvalid;
	wire        slave_in_tlast;
	wire        slave_in_tready;

	wire [15:0] slave_out_tdata;
	wire        slave_out_tvalid;
	wire        slave_out_tlast;
	wire        slave_out_tready;

	wire        slave_serdes_in;
	wire        slave_serdes_out;
	wire        slave_serdes_en;

	ponylink_slave #(
		.MASTER_PARBITS(1),
		.SLAVE_PARBITS(1),
		.M2S_TDATA_WIDTH(16),
		.S2M_TDATA_WIDTH(16),
		.MASTER_TIMINGS(MASTER_TIMINGS),
		.SLAVE_TIMINGS(SLAVE_TIMINGS)
	) slave_core (
		.clk       (slave_clk       ),
		.resetn_out(slave_resetn    ),
		.linkerror (slave_linkerror ),
		.linkready (slave_linkready ),
		.mode_recv (slave_mode_recv ),
		.mode_send (slave_mode_send ),
		.gpio_i    (slave_gpio_i    ),
		.gpio_o    (slave_gpio_o    ),
		.in_tdata  (slave_in_tdata  ),
		.in_tvalid (slave_in_tvalid ),
		.in_tlast  (slave_in_tlast  ),
		.in_tready (slave_in_tready ),
		.out_tdata (slave_out_tdata ),
		.out_tvalid(slave_out_tvalid),
		.out_tlast (slave_out_tlast ),
		.out_tready(slave_out_tready),
		.serdes_in (slave_serdes_in ),
		.serdes_out(slave_serdes_out),
		.serdes_en (slave_serdes_en )
	);


	// ---------------------------
	// Master Reset Generator

	reg [19:0] m_reset_counter = 0;
	reg m_resetn = 0;

	always @(posedge master_clk) begin
		if (&m_reset_counter) begin
			m_resetn <= 1;
		end else begin
			m_reset_counter <= m_reset_counter + 1;
			m_resetn <= 0;
		end
	end


	// ---------------------------
	// Master Sender

	reg [15:0] m_send_tdata = 0;
	wire m_send_tready;
	wire m_send_mode;

	always @(posedge master_clk) begin
		if (m_send_tready) begin
`ifndef SIM
			if (m_send_mode)
				m_send_tdata <= m_send_tdata - 5;
			else
				m_send_tdata <= m_send_tdata + 2;
`else
			if (m_send_mode)
				m_send_tdata <= m_send_tdata - 50;
			else
				m_send_tdata <= m_send_tdata + 20;
`endif
		end
	end


	// ---------------------------
	// Slave Sender

	reg [15:0] s_send_tdata = 0;
	wire s_send_tready;
	wire s_send_mode;

	always @(posedge master_clk) begin
		if (s_send_tready) begin
`ifndef SIM
			if (s_send_mode)
				s_send_tdata <= s_send_tdata - 7;
			else
				s_send_tdata <= s_send_tdata + 3;
`else
			if (s_send_mode)
				s_send_tdata <= s_send_tdata - 70;
			else
				s_send_tdata <= s_send_tdata + 30;
`endif
		end
	end


	// ---------------------------
	// Master Receiver

	wire [15:0] m_recv_tdata;
	wire m_recv_tvalid;
	reg m_recv_mode = 0;

	always @(posedge master_clk) begin
		if (m_recv_tvalid) begin
			if (m_recv_tdata <  16'h4000) m_recv_mode <= 0;
			if (m_recv_tdata >= 16'hc000) m_recv_mode <= 1;
		end
	end


	// ---------------------------
	// Slave Receiver

	wire [15:0] s_recv_tdata;
	wire s_recv_tvalid;
	reg s_recv_mode = 0;

	always @(posedge slave_clk) begin
		if (s_recv_tvalid) begin
			if (s_recv_tdata <  16'h4000) s_recv_mode <= 0;
			if (s_recv_tdata >= 16'hc000) s_recv_mode <= 1;
		end
	end


	// ---------------------------
	// Master Clock Generator

	// SB_GB_IO #(
	// 	.PIN_TYPE(6'b 0000_01)
	// ) clk_gb (
	// 	.PACKAGE_PIN(clk_pin),
	// 	.GLOBAL_BUFFER_OUTPUT(master_clk)
	// );
	assign master_clk = clk_pin;


	// ---------------------------
	// Slave Clock Generator

	assign slave_clk = master_clk;


	// ---------------------------
	// Master IO Pin

`ifndef SIM
	SB_IO #(
		.PIN_TYPE(6'b 1010_01),
		.PULLUP(1'b 0)
	) master_io_buffer (
		.PACKAGE_PIN(master_io),
		.OUTPUT_ENABLE(master_serdes_en),
		.D_OUT_0(master_serdes_out),
		.D_IN_0(master_serdes_in)
	);
`else
	assign master_io = master_serdes_en ? master_serdes_out : 1'bz;
	assign master_serdes_in = master_io === 1'b1;
`endif

	assign master_en = master_serdes_en;
	assign master_out = master_serdes_out;
	assign master_in = master_serdes_in;
	assign master_rst = !master_resetn;


	// ---------------------------
	// Slave IO Pin

`ifndef SIM
	SB_IO #(
		.PIN_TYPE(6'b 1010_01),
		.PULLUP(1'b 0)
	) slave_io_buffer (
		.PACKAGE_PIN(slave_io),
		.OUTPUT_ENABLE(slave_serdes_en),
		.D_OUT_0(slave_serdes_out),
		.D_IN_0(slave_serdes_in)
	);
`else
	assign slave_io = slave_serdes_en ? slave_serdes_out : 1'bz;
	assign slave_serdes_in = slave_io === 1'b1;
`endif

	assign slave_en = slave_serdes_en;
	assign slave_out = slave_serdes_out;
	assign slave_in = slave_serdes_in;
	assign slave_rst = !slave_resetn;


	// ---------------------------
	// Status LEDs

	assign led_0 = master_linkready;
	assign led_1 = slave_linkready;
	assign led_2 = m_recv_mode;
	assign led_3 = s_recv_mode;
	assign led_4 = 0;
	assign led_5 = 0;
	assign led_6 = master_linkerror;
	assign led_7 = slave_linkerror;


	// ---------------------------
	// Master Wiring

	assign master_resetn = m_resetn;

	assign master_gpio_i = {7'b0, m_recv_mode};
	assign m_send_mode = master_gpio_o[0];

	assign master_in_tdata = m_send_tdata;
	assign master_in_tvalid = 1'b1;
	assign master_in_tlast = 1'b0;
	assign m_send_tready = master_in_tready;

	assign m_recv_tdata = master_out_tdata;
	assign m_recv_tvalid = master_out_tvalid;
	assign master_out_tready = 1'b1;


	// ---------------------------
	// Slave Wiring

	assign slave_gpio_i = {7'b0, s_recv_mode};
	assign s_send_mode = slave_gpio_o[0];

	assign slave_in_tdata = s_send_tdata;
	assign slave_in_tvalid = 1'b1;
	assign slave_in_tlast = 1'b0;
	assign s_send_tready = slave_in_tready;

	assign s_recv_tdata = slave_out_tdata;
	assign s_recv_tvalid = slave_out_tvalid;
	assign slave_out_tready = 1'b1;
endmodule
