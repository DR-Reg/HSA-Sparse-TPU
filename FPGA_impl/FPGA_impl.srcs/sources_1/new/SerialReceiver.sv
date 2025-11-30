`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/29/2025 11:05:23 PM
// Design Name: 
// Module Name: SerialReceiver
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


module SerialReceiver #(parameter FRAME_WIDTH = 8) (
    input clk_uart,             // clock at 16x baudrate
    input rx,
    input sys_reset,
    
    output reg frame_ready,     // has a frame been received,
                            // high for one cycle after frame received
    output reg [FRAME_WIDTH-1:0] data_frame   // the frame received
);

    reg [$clog2(FRAME_WIDTH/8):0] byte_counter;

    wire byte_ready;    // wires since registered
    wire [7:0] data_byte;     // in byte receiver
    SerialByteReceiver UART_BYTE_RECEIVER(
        .clk_uart(clk_uart),
        .rx(rx),
        .sys_reset(sys_reset),
        .byte_ready(byte_ready),
        .data_byte(data_byte)
    );

    always @(posedge clk_uart) begin
        if (sys_reset) begin
            byte_counter <= 0;
            frame_ready <= 0;
            data_frame <= '0;           // sysv shorthand for all zeroes
        end else begin
            frame_ready <= 0;
            if (byte_ready) begin
                byte_counter <= byte_counter + 1;
                data_frame[8*byte_counter +: 8] <= data_byte;
                if (byte_counter == FRAME_WIDTH/8 - 1) begin
                    frame_ready <= 1;
                    byte_counter <= 0;
                end
            end 
        end
    end
endmodule
