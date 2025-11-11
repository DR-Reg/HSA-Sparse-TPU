`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/10/2025 11:29:15 PM
// Design Name: 
// Module Name: VpuHsa
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: WsMac
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


/*
 * NOTE: changed top-down flow from cpp_impl to left-right to avoid the transposition of weights
 * SIZE is N in cpp_impl
 * To init:
 *  - call reset to set counter and latches to 0
 *  - during next N (SIZE) clock cycles, pass in the cols of weights matrix through the weights input
 *  - when passing a col of matrix weight, wEn should be high, and the col index to write passed in too
 *  - this way we reuse the broadcast channels created for the activations for the weights too
 * To run:
 *  - simply clock the Vpu and pass in the correct activation (which will be broadcast to appropriate
 *    columns) and pass in the correct counter value (so the adequate MAC units can be gated) 
 *  - outputs will be put on 'result' buses (? can I combine this with weights in buses?)
 *    and ready signal will be on (though external should know when)
 *  Note that first run through the Vpu should 'pipeline' the weight writing and computation
 *   i.e. 
*/
module VpuHsa #(parameter SIZE = 2, BIT_WIDTH = 4) (
	input [BIT_WIDTH-1:0] weights [SIZE-1:0],       // buses for loading a weight column
	input [$clog2(SIZE)-1:0] weight_col_ix,		// holds the weight col write to when wEn = 1 
	input wEn,
	input en,
	input reset,					// TODO: not like cpp_impl reset, this sets everything to 0
	input clk,
	input [BIT_WIDTH-1:0] activation,
	input [$clog2(SIZE)-1:0] act_col_ix,		// holds the activation col broadcast to
	output [BIT_WIDTH-1:0] result [SIZE-1:0]       // buses for outputting result
    );

	/* Create and wire the MAC units and corresponding latches */
	genvar i,j;
	reg [BIT_WIDTH-1:0] left_latches [SIZE-1:0][SIZE-1:0]; 			// store downwards flow of partial sums
	wire [BIT_WIDTH-1:0] broadcast_channels [SIZE-1:0];     		// to broadcast on a per-column basis (i.e. not all at all times)

	generate
		for (i = 0; i < SIZE; i = i + 1) begin
			for (j = 0; j < SIZE; j = j + 1) begin
				wire [BIT_WIDTH-1:0] psum;
				wire enable, wEnable;
				assign enable = en & act_col_ix == j;           // only mult and acc when we are being broadcast an actiavion to this col
				assign wEnable = wEn & (weight_col_ix == j);    // when wEn is 1 (and we are broadcasting weights for this column), 
                                                                                // the internal reg holding the weight is written to               

				WsMac #(.BIT_WIDTH(BIT_WIDTH)) mac(
					.a(broadcast_channels[j]),
					.w(weights[i]),				// not used in computation, but when the weight col is passed in,
					.wEn(wEnable),       			
					.en(enable),				
					.clk(clk),
					.cin(j==0 ? 0 : left_latches[i][j-1]),     // pass in psum from left latch, unless we are first MAC, in which
										// case no previous sum to use
					.cout(psum)				// the partial sum being output to be latched to the next latch
				);
				always @(posedge clk & enable)
					left_latches[i][j] <= psum;
			end 
			/* result just grabs from the last layer of latches */
			assign result[i] = left_latches[i][SIZE-1];
		end
	endgenerate
	
	/* DeMux the input activations to go down the correct broadcast_channels */
        DeMux #(.BIT_WIDTH(BIT_WIDTH), .SIZE(SIZE)) demux(
			.in(activation),
			.sel(act_col_ix),
			.out(broadcast_channels)
	);
endmodule 
