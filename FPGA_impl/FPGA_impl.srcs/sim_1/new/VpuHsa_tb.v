`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/11/2025 12:31:54 AM
// Design Name: 
// Module Name: VpuHsa_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module VpuHsa_tb;

	localparam BIT_WIDTH = 4;
	localparam SIZE = 2;

	reg [BIT_WIDTH-1:0] weights_sram [SIZE-1:0][SIZE-1:0];
	reg [BIT_WIDTH-1:0] acts_sram [SIZE-1:0];

	reg [31:0] cycle_ctr;
	reg clk;

	initial begin
		cycle_ctr = 0;
		$readmemb("2x2_weights_4b.mem", weights_sram); 		// read in row-major order, so make sure data is transposed inside the file!
									// this is not the same as the transpose we do in cpp_impl, since there
									// it must be transposed inside of VpuHsa, whereas here we transpose
									// so we can access columns easily (since that is what we broadcast)
		$readmemb("2x1_acts_4b.mem",  acts_sram);
		clk = 0;
	end
	
	always
		#20 clk = ~clk;

	reg [BIT_WIDTH-1:0] weight_col_bus [SIZE-1:0];
	reg [$clog2(SIZE)-1:0] weight_col_ix;
	reg wEn, en;
	reg [BIT_WIDTH-1:0] act_value;
	reg [$clog2(SIZE)-1:0] act_col_ix;
	reg [BIT_WIDTH-1:0] result [SIZE-1:0];
	/* Init the VpuHsa module */
	VpuHsa #(.SIZE(SIZE), .BIT_WIDTH(BIT_WIDTH)) vpu_hsa(
		.weights(weight_col_bus),
		.weight_col_ix(weight_col_ix),
		.wEn(wEn),
		.en(en),
		.reset(1'b0),					// reset has not been impl yet
		.clk(clk),
		.activation(act_value),
		.act_col_ix(act_col_ix),
		.result(result)
	);

	always @(posedge clk) begin
		wEn = cycle_ctr < SIZE; 					// only write enable for first N cycles
		en =  0 < cycle_ctr && cycle_ctr <= SIZE; 			// activation counter, the broadcast column lags a cycle behind the weight writing col
		weight_col_ix =  cycle_ctr[$clog2(SIZE)-1:0];
		weight_col_bus = weights_sram[weight_col_ix];

		act_col_ix =  cycle_ctr > 0 ? cycle_ctr[$clog2(SIZE)-1:0] - 1 : 'bz;
		act_value = acts_sram[act_col_ix];
		
		if (cycle_ctr == SIZE + 2) begin				// 1 cycle more by acts follower, another to allow result to be latched
			for (integer i = 0; i < SIZE; i = i + 1)
				$display("%d", result[i]);
			$finish;
		end
		cycle_ctr = cycle_ctr + 1;
	end
endmodule
