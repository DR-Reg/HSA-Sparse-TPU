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
    input sys_reset,

    output tx,
    output reg ready
);
    localparam N_BYTES = FRAME_WIDTH / 8;
    reg [$clog2(N_BYTES):0] byte_counter;             // for current_byte, 
    reg sending;
    reg send_signal;
    reg [7:0] current_byte;
    reg bt_finished;                                       // did finish sending last byte sent

    SerialByteTransmitter UART_BYTE_TRANSMITTER(
        .data_frame(current_byte),
        .send(send_signal),
        .clk_uart(clk_uart),
        .sys_reset(sys_reset),
        .tx(tx),
        .finished_sending(bt_finished)
    );

    always @(posedge clk_uart) begin
        if (sys_reset) begin
            ready <= 0;
            sending <= 0;
            send_signal <= 0;
            current_byte <= 8'b0;
        end else if (sending) begin
            send_signal <= 0;
            if (bt_finished) begin
                byte_counter <= byte_counter + 1;
                if (byte_counter == N_BYTES) begin
                    // Sent all bytes, go back to idle state
                    sending <= 0;
                end else begin
                    send_signal <= 1;                   // pulse on
                    current_byte <= data_frame[((N_BYTES-byte_counter)*8 - 1) -: 8];
                end
            end
        end else if (send) begin                        
            sending <= 1;
            current_byte <= data_frame[FRAME_WIDTH - 1:FRAME_WIDTH - 8];
            byte_counter <= 1;                      // by non-blocking!
            send_signal <= 1;
            ready <= 0;
        end else begin
            ready <= 1;
        end
    end
endmodule
