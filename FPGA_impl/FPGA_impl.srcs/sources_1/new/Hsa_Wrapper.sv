`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/03/2025 09:46:35 PM
// Design Name: 
// Module Name: Hsa_Wrapper
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


module Hsa_Wrapper(
    input UART_TXD_IN,
    input clk_100mhz,

    output UART_RXD_OUT,
    output reg [15:0] LED
);
    localparam BIT_WIDTH = 16;
    localparam SIZE = 8;

    // ila_0 debug_ila (
    //     .clk(clk_100mhz),
    //     .probe0(got_magic),
    //     .probe1(rx_frame_ready),
    //     .probe2(rx_data_frame),
    //     .probe3({weights_sram[0][0], weights_sram[0][1], weights_sram[1][0], weights_sram[1][1]})
    // );
     

    /* Reset signals */
    reg rst;                    // sync internal reset

    /* Clocks */
    wire locked, clk100;
    clk_wiz_0 pll(           
        .clk100(clk100),     
        .reset(rst),   
        .locked(locked),     
        .clk_in1(clk_100mhz) 
    );                          

    /* 921600 baud tick */
    reg baud_tick;
    reg [9:0] baud_tick_counter;
    always @(posedge clk100) begin
        baud_tick_counter <= baud_tick_counter + 1;
        baud_tick <= 0;
        if (baud_tick_counter == 6) begin
            baud_tick <= 1;
            baud_tick_counter <= 0;
        end
    end

    /* Main FSM register */
    reg [1:0] operating_mode;

    /* Transmission and reception signals */
    wire rx_frame_ready_signal;
    reg rx_frame_consumed;
    wire [31:0] rx_data_frame_signal;
    reg rx_frame_ready, tx_frame_ready;
    reg [31:0] rx_data_frame, tx_data_frame;

    /* Signal reset detection and pulse */
    wire signal_reset_detected;
    assign signal_reset_detected = rx_frame_ready & (rx_data_frame == 32'hFFFFFFFF);

    /* Mode switching */
    reg hsa_mode;
    wire tom_mode_switch_detected;      // to matrix mode
    wire tov_mode_switch_detected;      // to vector mode
    assign tom_mode_switch_detected = rx_frame_ready & (rx_data_frame == 32'hFEFEFEFE);
    assign tov_mode_switch_detected = rx_frame_ready & (rx_data_frame == 32'hFDFDFDFD);
    
    /* Operating mode 00 registers */
    reg send_aligner;
    reg misalignment_state;   // FSM substate of opmode=00
    reg recv_drop_byte;

    /* Operating mode 01 registers */
    reg got_magic;
    reg [(SIZE*SIZE)-1:0] weights_filled;
    reg [(SIZE*SIZE)-1:0] acts_filled;

    /* Operating mode 10 registers */
	reg wEn, en;
    reg mm_opmode;  // matrix multiply, 0 = loading weights, 1 = computing 
    reg [BIT_WIDTH-1:0] curr_weight;
	reg [BIT_WIDTH-1:0] weight_col_bus [SIZE-1:0];
	reg [$clog2(SIZE)-1:0] weight_col_ix;
	reg [$clog2(SIZE)-1:0] weight_row_ix;
	reg [BIT_WIDTH-1:0] act_row [SIZE-1:0];
	reg [BIT_WIDTH-1:0] activation_inp [SIZE-1:0];
	reg [$clog2(SIZE)-1:0] act_col_left_edge;
	reg [$clog2(SIZE)-1:0] act_col_right_edge;
	reg [$clog2(SIZE)-1:0] act_col_ix;
	reg [BIT_WIDTH-1:0] act_value;
	reg [BIT_WIDTH-1:0] result [SIZE-1:0];
    reg [31:0] cycle_ctr;

	/* Init the MpuHsa module */
    wire [BIT_WIDTH-1:0] weights [SIZE-1:0];
    genvar i;
    integer j;  // see below
    generate
        for (i = 0; i < SIZE; i=i+1) begin
            if (i == 0) begin
                assign weights[0] = hsa_mode ? curr_weight : weight_col_bus[0];
                assign activation_inp[0] = hsa_mode ? act_row[0] : act_value;
            end else begin
                assign weights[i] = hsa_mode ? '0 : weight_col_bus[i];
                assign activation_inp[i] = hsa_mode ? act_row[i] : '0;
            end
        end
    endgenerate
	Hsa #(.SIZE(SIZE), .BIT_WIDTH(BIT_WIDTH)) mpu_hsa(
        .weights(weights),       // buses for loading a weight value
        .weight_col_ix(weight_col_ix),		    // holds the weight col write to when wEn = 1 
        .weight_row_ix(weight_row_ix),		    // holds the weight row write to when wEn = 1 
        .wEn(wEn),
        .en(en),
        .reset(1'b0),					// TODO: not like cpp_impl reset, this sets everything to 0
        .clk(clk100),
        .hsa_mode(hsa_mode),
        .activation(activation_inp),    // row of acts coming in from top
//        .act_col_left_edge(act_col_left_edge),             
//        .act_col_right_edge(act_col_right_edge),             
        .cycle_ctr(cycle_ctr),
        
        .act_col_ix(act_col_ix),        // Only used in MVM mode, fixme

        .result(result)       // buses for outputting result
	); 
    

    /* Parent storage for weight/activation */
    reg [BIT_WIDTH-1:0] weights_sram [SIZE-1:0][SIZE-1:0];
    reg [BIT_WIDTH-1:0] acts_sram [SIZE-1:0][SIZE-1:0];

    always @(posedge clk100) begin
        if (rst) begin
            /* Reset block */
            rst <= 0;
            /* Misc */
            operating_mode <= 2'b00;
            tx_frame_ready <=  0;
            tx_data_frame  <= '0;
            rx_frame_ready <=  0;
            rx_data_frame  <= '0;
            rx_frame_consumed <= 0;
             
            /* Op mode 00 */
            send_aligner <= 1;
            misalignment_state <= 2'b00;
            recv_drop_byte <= 1;

            /* Op mode 01*/
            got_magic <= 0;
            weights_filled <= '0;
            acts_filled    <= '0;

            /* Op mode 10 registers */
            wEn <= 0;
            en <= 0;
            mm_opmode <= 0;
            act_col_left_edge <= 0;
            act_col_right_edge <= 0;
            weight_col_ix <= 0;
            weight_row_ix <= 0; 
            cycle_ctr <= 0;
        end else if (signal_reset_detected) begin
            /* Signal reset */
            rst <= 1;
        end else if (tom_mode_switch_detected) begin
            hsa_mode <= 1;
            rst <= 1;
        end else if (tov_mode_switch_detected) begin
            hsa_mode <= 0;
            rst <= 1; 
        end else begin
            if (rx_frame_ready_signal) begin
                rx_frame_ready <= 1;
                rx_data_frame <= rx_data_frame_signal;
            end else if (rx_frame_consumed) begin
                rx_frame_ready <= 0;
                rx_frame_consumed <= 0;
            end 
            /* Functional block*/
            case (operating_mode)
                /* 00: Alignment, prepare for data stream */
                2'b00: begin
                    if (rx_frame_ready) begin
                        rx_frame_consumed <= 1;
                        case (misalignment_state)
                            1'b0 : begin
                                LED[15:0] <= 16'h1;
                                if (rx_data_frame == 32'hBEEFDEAD) begin
                                    recv_drop_byte <= 0;
                                    misalignment_state <= 1'b1;
                                end else begin
                                    recv_drop_byte <= 1;
                                end
                            end
                            1'b1 : begin
                                LED[15:0] <= 16'h2;
                                if (rx_data_frame == 32'hADBEEFDE) begin
                                    tx_data_frame <= 32'h0C0C0C0C;
                                    tx_frame_ready <= 1;
                                    operating_mode <= 2'b01;
                                end else begin
                                    misalignment_state <= 1'b0;
                                end
                            end
                        endcase
                    end
                end
                
                /* 01: Receive datastream into parent sram */
                2'b01: begin
                    tx_frame_ready <= 0;            // reset the transmission signal, set below
                    if (rx_frame_ready) begin
                        rx_frame_consumed <= 1;
                        if (~got_magic) begin
                            if (rx_data_frame == 32'hDA221D06) begin
                                got_magic <= 1;
                            end
                        end else begin
                            LED[15:0] <= 16'h4;
                            if (rx_data_frame[31] == 0) begin
                                if (rx_data_frame[30]) begin
                                    weights_sram[rx_data_frame[22:16]][rx_data_frame[29:23]] <= rx_data_frame[BIT_WIDTH-1:0];
                                    weights_filled[rx_data_frame[22:16]*SIZE + rx_data_frame[29:23]] <= 1;
                                end else begin
                                    acts_sram[rx_data_frame[22:16]][rx_data_frame[29:23]] <= rx_data_frame[BIT_WIDTH-1:0];
                                    acts_filled[rx_data_frame[22:16]*SIZE + rx_data_frame[29:23]] <= 1;
                                end

                                if (&acts_filled & &weights_filled) begin
                                    tx_data_frame <= 32'h1C1C1C1C;
                                    tx_frame_ready <= 1;
                                    operating_mode <= 2'b10;
                                end
                            end
                        end
                    end
                end
                
                /* 10: Compute */
                2'b10 : begin
                    if (hsa_mode) begin
                        LED[15:0] <= 16'h8;
                        if (mm_opmode == 0) begin
                            wEn <= 1;
                            weight_col_ix <= weight_col_ix + 1;
                            if (weight_col_ix == SIZE - 1) begin
                                weight_row_ix <= weight_row_ix + 1;
                                if (weight_row_ix == SIZE - 1) begin
                                    mm_opmode <= 1;
                                end
                            end
                            curr_weight <= weights_sram[weight_row_ix][weight_col_ix];
                        end else if (mm_opmode == 1) begin
                            cycle_ctr <= cycle_ctr + 1;
                            wEn <= 0;
                            for (j = 0; j < SIZE; j = j + 1) begin
                                if (act_col_left_edge <= j && j <= act_col_right_edge) begin
                                    act_row[j] <= acts_sram[SIZE-1+j-act_col_right_edge-act_col_left_edge][j];
                                end else begin
                                    act_row[j] <= 0;
                                end
                            end

                            if (act_col_right_edge < SIZE - 1) begin
                                act_col_right_edge <= act_col_right_edge + 1;
                            end else if (act_col_left_edge < SIZE - 1) begin  // right edge now static, move left
                                act_col_left_edge <= act_col_left_edge + 1;
                            end   
                        end
                    end else begin
                        LED[15:0] <= 16'h10;
                        wEn = cycle_ctr < SIZE; 					// only write enable for first N cycles
                        en =  0 <= cycle_ctr && cycle_ctr < SIZE; 			// activation counter, the broadcast column lags a cycle behind the weight writing col
                        weight_col_ix =  cycle_ctr[$clog2(SIZE)-1:0];
                        weight_col_bus = weights_sram[weight_col_ix];

                        // act_col_ix =  cycle_ctr > 0 ? cycle_ctr[$clog2(SIZE)-1:0] - 1 : 'bz;
                        act_col_ix = cycle_ctr >= 0 ? cycle_ctr[$clog2(SIZE)-1:0] : 'bz;
                        act_value = acts_sram[act_col_ix][0];
                        
                        if (cycle_ctr == SIZE + 2) begin				// 1 cycle more by acts follower, another to allow result to be latched
                            operating_mode <= 2'b11;
                        end
                        cycle_ctr = cycle_ctr + 1; 
                    end 
                end

                /* 11: Transmit */
                2'b11: LED[15:0] <= 16'h20;
            endcase
        end
    end

    SerialTransmitter #(.FRAME_WIDTH(32)) UART_TRANSMITTER(
            .data_frame(tx_data_frame),
            .send(tx_frame_ready),
            .clk_uart(baud_tick),
            .sys_reset(rst),
            
            .tx(UART_RXD_OUT)
    );

    SerialReceiver #(.FRAME_WIDTH(32)) UART_RECEIVER(
            .clk_uart(baud_tick),
            .rx(UART_TXD_IN),
            .sys_reset(rst),
            .drop_byte(recv_drop_byte),
            
            .frame_ready(rx_frame_ready_signal),
            .data_frame(rx_data_frame_signal)
    );
endmodule
