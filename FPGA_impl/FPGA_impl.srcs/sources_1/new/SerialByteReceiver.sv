`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/30/2025 01:07:14 PM
// Design Name: 
// Module Name: SerialByteReceiver
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


module SerialByteReceiver (
    input clk_uart,             // clock at 16x baudrate
    input rx,
    input sys_reset,
    
    output reg byte_ready,     // has a byte been received,
                            // high for one cycle after byte received
    output reg [7:0] data_byte   // the byte received
);

    reg [1:0] state;      // idle, assert low rx, receiving byte 
    reg [3:0] cycle_ctr; // used throughout transmission
    reg [3:0] bit_ctr;
    reg last_rx;   // holds the value of rx last clock cycle (edge detection)
    
    always @(posedge clk_uart) begin
        if (sys_reset) begin
            byte_ready <= 0;
            data_byte <= 0;
            state <= 0;
            cycle_ctr <= 0;
            bit_ctr <= 0;
        end else begin
            last_rx <= rx;
            case (state)
                2'b00: begin
                    // Idle, poll for a start bit (low)
                    state[0] <= last_rx & ~rx; // if last_rx=1, rx=0, falling edge -> start
                    cycle_ctr <= 0;            // restart our cycle counter for this byte
                    bit_ctr <= 0;              // need this too.
                    byte_ready <= 0;
                end
                2'b01: begin
                    // Assert we are low after 8 clk_uart_cycles
                    // which will be middle of start bit
                    cycle_ctr <= cycle_ctr + 1;
                    if (cycle_ctr == 7) begin
                        state[0] <= 0;
                        state[1] <= ~rx;        // rx high => go back to idle
                                                // else go through to receiving data byte
                        cycle_ctr <= 0;         // reset for counting in the next state
                    end
                end
                2'b10: begin
                    // receiving byte, get the
                    // value every 16 clk_uart cycles into
                    // data_byte (LSB first). Since we already offset
                    // by 8 clk_uart cycles in the previous state
                    // this will be the middle of the bit.
                    cycle_ctr <= cycle_ctr + 1;
                    if (cycle_ctr == 15) begin
                        bit_ctr <= bit_ctr + 1;
                        if (bit_ctr == 8) begin
                            // assert that parity bit is correct
                            // if not (i.e. rx <> ^data_byte)
                            // go back to idle!
                            if (rx != ^data_byte) begin
                                state <= 2'b00;
                            end else begin
                                state <= 2'b11; // otherwise move to stop bit detection
                            end
                        end else begin
                            data_byte[bit_ctr] <= rx;
                        end

                        cycle_ctr <= 0;
                    end
                end
                2'b11: begin
                    // Detect the stop bit, and set the ready signal
                    // Only if we detect the stop bit
                    cycle_ctr <= cycle_ctr + 1;
                    if (cycle_ctr == 15) begin
                        if (rx) begin
                            byte_ready <= 1'b1;
                        end
                        state <= 2'b00;
                    end
                end
            endcase
        end
    end
endmodule

