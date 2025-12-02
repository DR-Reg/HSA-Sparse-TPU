`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/30/2025 01:09:19 AM
// Design Name: 
// Module Name: SerialByteTransmitter
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


module SerialByteTransmitter (
	input [7:0] data_frame,      
    input send,                             // this should pulse on for 1 clk_uart cycle to begin transmission
    input clk_uart,                         // expects this to be 16 times the clock rate
    input sys_reset,

    output reg tx,
    output reg finished_sending 
);
    reg [10:0] send_frame;                         // <start><frame><even parity><stop>
    reg [3:0] counter;                             // for baud division, 
    reg [3:0] bit_counter;                         // what bit currently sending, need one more
                                                   // to avoid ovf in stop sending guard

    reg sending;

    always @(posedge clk_uart) begin
        if (sys_reset) begin
            tx <= 1;
            finished_sending <= 0;
            send_frame <= 11'b0;
            counter <= 4'b0;
            bit_counter <= 4'b0;
        end else if (sending) begin
            tx <= send_frame[bit_counter];
            if (counter == 15) begin
                bit_counter <= bit_counter + 1;
                if (bit_counter == 10) begin
                    sending <= 0;
                    finished_sending <= 1;          // pulse for 1 clock cycle
                end
                counter <= 0;
            end else begin
                counter <= counter + 1;          // counter automatically wraps
            end
        end else if (send) begin                        // Guard after so don't stop sending halfway
            send_frame[10]  <= 1;            // stop bit
            send_frame[9]   <= ^data_frame;  // parity
            send_frame[8:1] <= data_frame;   // LSB first per UART protocol
            send_frame[0]   <= 0;            // start bit
            counter <= 0;
            sending <= 1;
            bit_counter <= 0;
            finished_sending <= 0;
        end else begin
            tx <= 1;                         // idle set to high
            finished_sending <= 0;           
        end
    end
endmodule 

