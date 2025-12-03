`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/02/2025 04:25:10 PM
// Design Name: 
// Module Name: MpuHsa
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

/*
Loading stage (opmode 01):
When we receive dataframe in wrapper,
-> put into weight bus
-> x and y on weight col ix and row ix
-> wEn set high

Compute stage (opmode 10):
-> Acts passed in, as well as
-> act column mask to gate!
*/

module MpuHsa #(parameter SIZE = 2, BIT_WIDTH = 4) (
    input [BIT_WIDTH-1:0] weight,       // buses for loading a weight value
	input [$clog2(SIZE)-1:0] weight_col_ix,		    // holds the weight col write to when wEn = 1 
	input [$clog2(SIZE)-1:0] weight_row_ix,		    // holds the weight row write to when wEn = 1 
	input wEn,
	input en,
	input reset,					// TODO: not like cpp_impl reset, this sets everything to 0
	input clk,
	input [BIT_WIDTH-1:0] activation [SIZE-1:0],    // row of acts coming in from top
    // imagine mask of which ones actually getting values (e.g. cycle 1: 1000.., cycle 2: 1100... cycle N-1: 0001 etc)
    // num of zeros to left is 'left edge', (N-zeros to right) is 'right edge'
//	input [$clog2(SIZE)-1:0] act_col_left_edge,             
//	input [$clog2(SIZE)-1:0] act_col_right_edge,   
    input [31:0] cycle_ctr,          

	output [BIT_WIDTH-1:0] result [SIZE-1:0]       // buses for outputting result
);

	/* Create and wire the MAC units and corresponding latches */
	genvar i,j;
	reg [BIT_WIDTH-1:0] left_latches [SIZE-1:0][SIZE-1:0]; 			// store rightwards flow of partial sums
    reg [BIT_WIDTH-1:0] top_latches  [SIZE-1:0][SIZE-1:0];

	generate
		for (i = 0; i < SIZE; i = i + 1) begin : row
			for (j = 0; j < SIZE; j = j + 1) begin : col
				wire [BIT_WIDTH-1:0] psum;
				wire enable, wEnable;
				wire [BIT_WIDTH-1:0] act;

                // Want to enable in diagonal wavefront
                // Such that we only enable if the activation is there for us
                // I.e. the top-most (i = 0) row has from leftedge to rightedge enabled
                // the next one will have it shifted to the left by 1 (leftedge-1 to rightedge-1)
                // So enabled if whole unit enabled and column ix leftedge-i <= j <= rightedge-1
                // Left edge - 1: parche?
//                assign enable = en && $signed(act_col_left_edge-1+i) <= j && j <= $signed(act_col_right_edge+i);    
                // RHS <= : patch latch latency       
                assign enable = en && (i+j) <= cycle_ctr && cycle_ctr <= (i+j+SIZE);
				assign wEnable = wEn & (weight_col_ix == j) & (weight_row_ix == i);    // when wEn is 1 (and the col and row index of weight on bus match this MAC), 
                                                                                // the internal reg holding the weight is written to               

                assign act = i == 0 ? activation[j] : top_latches[i-1][j];
				WsMac #(.BIT_WIDTH(BIT_WIDTH)) mac(
					.a(act),   // get act from top latch or if first from activation

					.w(weight),                                // not used in computation, but when the weight is passed in,
					.wEn(wEnable),       			
					.en(enable),				               // this signal is actually unused, we clock gate the latches below
					.clk(clk),
					.cin(j==0 ? 0 : left_latches[i][j-1]),     // pass in psum from left latch, unless we are first MAC, in which
                                                               // case no previous sum to use
                    .cout(psum)                                // the partial sum being output to be latched to the next latch
				);

				always @(posedge clk & enable) begin
					left_latches[i][j] <= psum;
					top_latches[i][j] <= act;
                end           
			end 
			/* result just grabs from the last layer of psum latches
             * wrapper module must use its cycle counter to synch when
             * it should grab the results
             */
			assign result[i] = left_latches[i][SIZE-1];
		end
	endgenerate
endmodule  
