`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/03/2025 06:05:17 PM
// Design Name: 
// Module Name: SpVpu
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

module SpVpu #(parameter SIZE = 2, BIT_WIDTH = 4) (
	input [BIT_WIDTH-1:0] weights [SIZE-1:0],       // buses for loading a weight column
    input weight_parity_tags [SIZE-1:0],
    input [$clog2(SIZE)-1:0] weight_col_ix,		// holds the even weight col write to when wEn = 1 
	input wEn,
	input en,
	input reset,					// TODO: not like cpp_impl reset, this sets everything to 0
	input clk,
	input [BIT_WIDTH-1:0] activation_even,
	input [BIT_WIDTH-1:0] activation_odd,
	input [$clog2(SIZE)-1:0] act_col_ix,		// holds the col broadcast to (remember div by 2)
	output [BIT_WIDTH-1:0] result [SIZE-1:0]       // buses for outputting result
);

	/* Create and wire the MAC units and corresponding latches */
	genvar i,j;
	reg [BIT_WIDTH-1:0] left_latches [SIZE-1:0][SIZE/2-1:0]; 			// store downwards flow of partial sums
	wire [BIT_WIDTH-1:0] broadcast_channels_even [SIZE/2-1:0];     		// to broadcast on a per-column basis (i.e. not all at all times)
	wire [BIT_WIDTH-1:0] broadcast_channels_odd [SIZE/2-1:0];     		// to broadcast on a per-column basis (i.e. not all at all times)

	generate
		for (i = 0; i < SIZE; i = i + 1) begin : row
			for (j = 0; j < SIZE/2; j = j + 1) begin : col
				wire [BIT_WIDTH-1:0] psum;
				wire enable, wEnable;
				assign enable = en & act_col_ix == j;           // only mult and acc when we are being broadcast an actiavion to this col
				assign wEnable = wEn & (weight_col_ix == j);    // when wEn is 1 (and we are broadcasting weights for this column), 
                                                                                // the internal reg holding the weight is written to               

				SpMac #(.BIT_WIDTH(BIT_WIDTH)) mac(
					// .a(weight_parity_tags[i] ? broadcast_channels_odd[j] : broadcast_channels_even[j]),
                    .a0(broadcast_channels_even[j]),
                    .a1(broadcast_channels_odd[j]),
					.w(weights[i]),				// not used in computation, but when the weight col is passed in,
                    .wix(weight_parity_tags[i]),
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
    DeMux #(.BIT_WIDTH(BIT_WIDTH), .SIZE(SIZE/2)) demux_even(
        .in(activation_even),
        .sel(act_col_ix),
        .out(broadcast_channels_even)
	);

    /* DeMux the input activations to go down the correct broadcast_channels */
    DeMux #(.BIT_WIDTH(BIT_WIDTH), .SIZE(SIZE/2)) demux_odd(
        .in(activation_odd),
        .sel(act_col_ix),
        .out(broadcast_channels_odd)
	);
endmodule  
