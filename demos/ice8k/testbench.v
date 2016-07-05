`timescale 1 ns / 1 ps

module testbench;
	reg clk_pin = 1;
	always #500 clk_pin = ~clk_pin;

	wire master_io;
	wire master_en;

	wire slave_io;
	wire slave_en;

	wire led_0;
	wire led_1;
	wire led_2;
	wire led_3;
	wire led_4;
	wire led_5;
	wire led_6;
	wire led_7;

	icedemo uut (
		.clk_pin  (clk_pin  ),
		.master_io(master_io),
		.master_en(master_en),
		.slave_io (slave_io ),
		.slave_en (slave_en ),
		.led_0    (led_0    ),
		.led_1    (led_1    ),
		.led_2    (led_2    ),
		.led_3    (led_3    ),
		.led_4    (led_4    ),
		.led_5    (led_5    ),
		.led_6    (led_6    ),
		.led_7    (led_7    )
	);

	tran (master_io, slave_io);

	wire [15:0] master_counter = uut.m_send_tdata;
	wire [15:0] slave_counter = uut.s_send_tdata;

	initial begin
		$dumpfile("testbench.vcd");
		$dumpvars(1, testbench);
		@(negedge clk_pin);
		uut.m_reset_counter = -20;
		repeat (1000000) @(posedge clk_pin);
		$finish;
	end
endmodule
