`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/11/2025 01:09:20 AM
// Design Name: 
// Module Name: DeMux
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


module DeMux #(parameter BIT_WIDTH = 4, SIZE = 2) (
	input [BIT_WIDTH-1:0] in,
	input [$clog2(SIZE)-1:0] sel,
	output reg [BIT_WIDTH-1:0] out [SIZE-1:0]		// need the reg for demux behaviour
    );

	// essentially always_comb
	always @(*) begin
		integer i;
		for (i = 0; i < SIZE; i = i + 1) begin
			out[i] = 0;
		end
		out[sel] = in;
	end
endmodule
