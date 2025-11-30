`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/29/2025 01:24:21 PM
// Design Name: 
// Module Name: Wrapper
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


module Wrapper(
    input UART_TXD_IN,
    input clk_100mhz,
    input reset,                            // NOTE: C12 is active-low!

    output UART_RXD_OUT,
    output reg [15:0] LED
);
    localparam BIT_WIDTH = 4;
	localparam SIZE = 2;

    wire sys_reset = ~reset;

    ila_0 debug_ila (
        .clk(clk_100mhz),
        .probe0(UART_RXD_OUT),
        .probe1(clk_uart),
        .probe2(cycle_ctr),
        .probe3({result[1], result[0]})
    );


    wire locked;
    wire clk100;
    clk_wiz_0 pll(
        .clk100(clk100),
        .reset(sys_reset),
        .locked(locked),
        .clk_in1(clk_100mhz)
	); 

    reg clk_uart;
    reg [31:0] clk_uart_counter;
    always @(posedge clk100) begin
        if (sys_reset) begin
            clk_uart_counter <= 0;
            clk_uart <= 0;
        end else begin
            clk_uart_counter <= clk_uart_counter + 1;
            if (clk_uart_counter == 325) begin
                clk_uart <= ~clk_uart;
                clk_uart_counter <= 0;
            end
        end
    end

    /* Operating modes:
     * - Idle
     * - Receiving data
     * - Performing computation
     * - Transmitting
    */
    reg [1:0] operating_mode;

	reg [BIT_WIDTH-1:0] weights_sram [SIZE-1:0][SIZE-1:0];
	reg [BIT_WIDTH-1:0] acts_sram [SIZE-1:0];
     
	reg [31:0] cycle_ctr;

    // TODO: parametrise data frames and result index
    // for now: 4 bit result, 4 bit position (by up to 16-by-16)
	reg [3:0] result_index;
    reg [31:0] transmission_ctr;
    
    reg [7:0] uart_data_frame;
    reg uart_send_signal;

    initial begin
        cycle_ctr = 0;
    
        /* TEST TRANSMISSION ONLY */
        operating_mode = 2'b10;
        $readmemb("2x2_weights_4b.mem", weights_sram); 	// read in row-major order, so make sure data is transposed inside the file!
                                                        // this is not the same as the transpose we do in cpp_impl, since there
                                                        // it must be transposed inside of VpuHsa, whereas here we transpose
                                                        // so we can access columns easily (since that is what we broadcast)
		$readmemb("2x1_acts_4b.mem",  acts_sram); 
        /**************************/
    end

    

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
		.clk(clk100),
		.activation(act_value),
		.act_col_ix(act_col_ix),
		.result(result)
	);

	always @(posedge clk100) begin
        /* 2'b10 = Computing, the only case at system clock */
        if (operating_mode == 2'b10) begin
            wEn = cycle_ctr < SIZE;                             // only write enable for first N cycles
            en =  0 < cycle_ctr && cycle_ctr <= SIZE; 			// activation counter, the broadcast column lags a cycle behind the weight writing col
            weight_col_ix =  cycle_ctr[$clog2(SIZE)-1:0];
            weight_col_bus = weights_sram[weight_col_ix];

            act_col_ix =  cycle_ctr > 0 ? cycle_ctr[$clog2(SIZE)-1:0] - 1 : 'bz;
            act_value = acts_sram[act_col_ix];
            
            if (cycle_ctr == SIZE + 2) begin                    // 1 cycle more by acts follower, another to allow result to be latched
                operating_mode = 2'b11;
            end
            cycle_ctr = cycle_ctr + 1;
            // /* 2'b11 : Transmitting */
            // 2'b11 : begin
            //     
            //     // for (integer i = 0; i < SIZE; i = i + 1)
            //     //         $display("%d", result[i]); 
            // end
        end
	end 

    /* Clock UART should be 16 times the baudrate
     * To allow accurate sampling
     */

    
    /* 2'b00 defaults, does nothing */
    /* 2'b01 Receiving: TODO */
    /* 2'b11 Transmitting*/ 
    always @(posedge clk_uart) begin
        if (sys_reset) begin
            transmission_ctr <= 0;
            uart_data_frame <= 0;
            uart_send_signal <= 0;
            result_index <= 0;
        end else begin
            transmission_ctr <= transmission_ctr + 1;
            if (transmission_ctr == 1000) begin
                if (operating_mode == 2'b11) begin
                    uart_data_frame[7:4] <= result_index;
                    uart_data_frame[3:0] <= result[result_index];
                    // uart_data_frame <= result[0];
                end else begin
                    uart_data_frame <= 2'hDE;
                end
        
                uart_send_signal <= 1;
            end else if (transmission_ctr >= 1002) begin
                result_index <= result_index == SIZE - 1 ? 0 : result_index + 1;
                uart_send_signal <= 0;
                transmission_ctr <= 0;  // overrides increment
            end else begin
                uart_send_signal <= uart_send_signal;
            end
        end
    end

    // always @(posedge clk_uart) begin
    //     if (operating_mode == 2'b11) begin
    //         uart_data_frame = result[0];
    //         uart_send_signal = (transmission_ctr % 1000) == 0;
    //         transmission_ctr = transmission_ctr + 1;
    //     end
    //     LED <= {1'b1, operating_mode, transmission_ctr[12:0]};
    // end
    SerialTransmitter UART_TRANSMITTER(
            .data_frame(uart_data_frame),
            .send(uart_send_signal),
            .clk_uart(clk_uart),
            
            .tx(UART_RXD_OUT)
    );
    
endmodule
