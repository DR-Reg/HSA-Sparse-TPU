`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/02/2025 04:25:39 PM
// Design Name: 
// Module Name: MpuHsa_tb
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


module MpuHsa_tb;

	localparam BIT_WIDTH = 4;
	localparam SIZE = 2;

	reg [BIT_WIDTH-1:0] weights_sram [SIZE-1:0][SIZE-1:0];
	reg [BIT_WIDTH-1:0] acts_sram [SIZE-1:0][SIZE-1:0];

	reg [31:0] cycle_ctr;
	reg clk;

	initial begin
		cycle_ctr = 0;
		$readmemb("2x2_weights_4b.mem", weights_sram); 		// read in row-major order, so make sure data is transposed inside the file!
									// this is not the same as the transpose we do in cpp_impl, since there
									// it must be transposed inside of VpuHsa, whereas here we transpose
									// so we can access columns easily (since that is what we broadcast)
		$readmemb("2x2_acts_4b.mem",  acts_sram);
		clk = 0;
		en = 1;   // initially enabled device
	end
	
	always
		#20 clk = ~clk;

	reg [BIT_WIDTH-1:0] curr_weight;
	reg [$clog2(SIZE)-1:0] weight_col_ix;
	reg [$clog2(SIZE)-1:0] weight_row_ix;
	reg wEn, en;
	reg [BIT_WIDTH-1:0] act_row [SIZE-1:0];
	reg [$clog2(SIZE)-1:0] act_col_left_edge;
	reg [$clog2(SIZE)-1:0] act_col_right_edge;

	reg [BIT_WIDTH-1:0] result [SIZE-1:0];

	/* Init the MpuHsa module */
	MpuHsa #(.SIZE(SIZE), .BIT_WIDTH(BIT_WIDTH)) mpu_hsa(
        .weight(curr_weight),       // buses for loading a weight value
        .weight_col_ix(weight_col_ix),		    // holds the weight col write to when wEn = 1 
        .weight_row_ix(weight_row_ix),		    // holds the weight row write to when wEn = 1 
        .wEn(wEn),
        .en(en),
        .reset(1'b0),					// TODO: not like cpp_impl reset, this sets everything to 0
        .clk(clk),
        .activation(act_row),    // row of acts coming in from top
//        .act_col_left_edge(act_col_left_edge),             
//        .act_col_right_edge(act_col_right_edge),             
        .cycle_ctr(cycle_ctr),

        .result(result)       // buses for outputting result
	);

    reg opmode; // simpler opmode, only 0 = loading weights, 1 = computing
    initial begin
        opmode = 0;
        act_col_left_edge = 0;
        act_col_right_edge = 0;
        weight_col_ix <= 0;
        weight_row_ix <= 0;
    end

    wire [31:0] delta_cycle, redge, ledge;
    assign delta_cycle = cycle_ctr - (SIZE+1);  // cycles from when first result reaches bottom
                                                // right edge = delta cycle if delta cycle < N else N
                                                // left edge = 0 if delta cycle < N else deltacycle - N
                                                // up to when left edge = N i.e deltacycle = 2N -> cyclectr = 3N + 2
                                                // result column is just column it came from, row is deltacycle-j ?
    assign redge = delta_cycle < SIZE ? delta_cycle : SIZE - 1;
    assign ledge = delta_cycle < SIZE ? 0 : delta_cycle - (SIZE - 1); 
    genvar i,j;

	always @(posedge clk) begin
        if (opmode == 0) begin
            wEn <= 1;
            // In real module, this would be implemented using
            // the 
            weight_col_ix <= weight_col_ix + 1;
            if (weight_col_ix == SIZE - 1) begin
                weight_row_ix <= weight_row_ix + 1;
                if (weight_row_ix == SIZE - 1) begin
                    opmode <= 1; // finished loading all weights
                end
            end
            curr_weight <= weights_sram[weight_row_ix][weight_col_ix];
        end else if (opmode == 1) begin
            cycle_ctr <= cycle_ctr + 1;
            wEn <= 0;
        end
	end

    // transmit act rows in corr order
    for (j = 0; j < SIZE; j = j + 1) begin
        always @(posedge clk) begin
            if (opmode == 1) begin
                // only pass in an act row if ledge <= j <= right edge
                if (act_col_left_edge <= j && j <= act_col_right_edge) begin
                    act_row[j] <= acts_sram[SIZE-1+j-act_col_right_edge-act_col_left_edge][j];
                end else begin
                    act_row[j] <= 0;
                end
                
                if (act_col_right_edge < SIZE - 1) begin
                    act_col_right_edge <= act_col_right_edge + 1;
                end else if (act_col_left_edge < SIZE - 1) begin  // right edge now static, move left
                    act_col_left_edge <= act_col_left_edge + 1;
                end 
            end
        end
    end

    // get results
    for (i = 0; i < SIZE; i = i + 1) begin
        always @(posedge clk) begin
            if (cycle_ctr == 3*SIZE + 2) begin
                $finish;
            end else if (cycle_ctr >= SIZE + 1) begin
                if (ledge <= i && i <= redge) begin
                    $display("(cc:%d; i:%d) result[%d][%d] = %d", cycle_ctr, delta_cycle-i, i, i, result[i]);
                end
            end
        end
    end
endmodule

