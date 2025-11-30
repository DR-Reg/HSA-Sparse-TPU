`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/14/2025 11:15:08 PM
// Design Name: 
// Module Name: SerialTransmitter
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


module SerialTransmitter #(parameter FRAME_WIDTH = 8) (
	input [FRAME_WIDTH - 1:0] data_frame,      
    input send,                             // this should pulse on for 1 clk_uart cycle to begin transmission
    input clk_uart,                         // expects this to be 16 times the clock rate

    output reg tx
);

    reg [FRAME_WIDTH + 2:0] send_frame;            // <start><frame><even parity><stop>
    reg [3:0] counter;                             // for baud division, 
    reg [$clog2(FRAME_WIDTH+3):0] bit_counter;     // what bit currently sending, need one more
                                                   // to avoid ovf in stop sending guard

    reg sending;

    always @(posedge clk_uart) begin
        if (sending) begin
            tx = send_frame[bit_counter];
            if (counter == 15) begin
                bit_counter = bit_counter + 1;
                if (bit_counter == FRAME_WIDTH+3) begin
                    sending = 0;
                end
                counter = 0;
            end
            counter += 1;                               // counter automatically wraps
        end else if (send) begin                        // Guard after so don't stop sending halfway
            send_frame[FRAME_WIDTH+2] = 1;              // stop bit
            send_frame[FRAME_WIDTH+1] = ^data_frame;    // parity
            send_frame[FRAME_WIDTH:1] = data_frame;     // LSB first per UART protocol
            send_frame[0]             = 0;              // start bit
            counter = 0;
            sending = 1;
            bit_counter = 0;
        end else begin
            tx = 1;                         // idle set to high
        end
    end
endmodule
