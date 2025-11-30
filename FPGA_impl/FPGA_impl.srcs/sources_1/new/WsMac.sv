`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/11/2025 12:23:55 AM
// Design Name: 
// Module Name: WsMac
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


// computes a*w+cin, but w and a need not be passed
// during the same cycle
module WsMac #(parameter BIT_WIDTH = 4) (
	input [BIT_WIDTH-1:0] a,		// activation value to be passed in when en=1
	input [BIT_WIDTH-1:0] w, 		// weight value to be passed in when wEn=1 (will be written to inner mem)
	input wEn,
	input en,
	input clk,
	input [BIT_WIDTH-1:0] cin,		// partial sum to be passed in
	output [BIT_WIDTH-1:0] cout		// a*w+cin
    );
	reg [BIT_WIDTH-1:0] weight;

	/* falling edge to avoid collision from incoming weight */
	always @(negedge clk) begin
		if (wEn) begin
			weight <= w;
		end
	end

	/* en signal acts as a clock gate for MAC ops ? */
	// always @(posedge clk & en)
	assign cout = a*weight + cin;
endmodule
