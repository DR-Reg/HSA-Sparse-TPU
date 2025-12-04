`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/02/2025 07:47:28 PM
// Design Name: 
// Module Name: MpuHsa_Wrapper
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


module MpuHsa_Wrapper(
    input UART_TXD_IN,
    input clk_100mhz,
    input reset,                            // NOTE: C12 is active-low!

    output UART_RXD_OUT,
    output reg [15:0] LED
);
    localparam BIT_WIDTH = 8;
	localparam SIZE = 2;

    wire sys_reset = ~reset;
    reg internal_reset;

    initial begin
        internal_reset <= 0;
    end

    // ila_0 debug_ila (
    //     .clk(clk_100mhz),
    //     .probe0(wEn),
    //     .probe1(clk100),
    //     .probe2({operating_mode, weight_row_ix, weight_col_ix, curr_weight}),
    //     .probe3({weights_sram[0][0], weights_sram[0][1], weights_sram[1][0], weights_sram[1][1]})
    // );


    wire locked;
    wire clk100;
    //wire clk_uart_900k;
    reg clk_uart;
    clk_wiz_0 pll(
        .clk100(clk100),
        .clk_uart(clk_uart),
        .reset(sys_reset),
        .locked(locked),
        .clk_in1(clk_100mhz)
	); 
    /* Clock UART should be 16 times the baudrate
    * To allow accurate sampling
    * generate with pll at high baudrate
    */
    // reg [31:0] clk_uart_counter;
    // always @(posedge clk_uart_900k) begin
    //     if (sys_reset || internal_reset) begin
    //         clk_uart_counter <= 0;
    //         clk_uart <= 0;
    //     end else begin
    //         clk_uart_counter <= clk_uart_counter + 1;
    //         if (clk_uart_counter == 47) begin
    //             clk_uart_counter <= 0;
    //             clk_uart <= ~clk_uart;
    //         end
    //     end
    // end
        
    // reg clk_uart;
    // reg [31:0] clk_uart_counter;
    // always @(posedge clk450) begin
    //     if (sys_reset) begin
    //         clk_uart_counter <= 0;
    //         clk_uart <= 0;
    //     end else begin
    //         clk_uart_counter <= clk_uart_counter + 1;
    //         if (clk_uart_counter == 15) begin
    //             clk_uart <= ~clk_uart;
    //             clk_uart_counter <= 0;
    //         end
    //     end
    // end

    /* Operating modes:
     * - Idle
     * - Receiving data
     * - Performing computation
     * - Transmitting
    */
    reg [1:0] operating_mode;

    // not needed in this module, load straight into the MPU SRAM
	// reg [BIT_WIDTH-1:0] weights_sram [SIZE-1:0][SIZE-1:0];
	reg [BIT_WIDTH-1:0] acts_sram [SIZE-1:0][SIZE-1:0];
     
	reg [31:0] cycle_ctr;

	// reg [$clog2(SIZE)-1:0] result_index;
    // make 7 bits so fits nicely into transmission packet
    // reg [6:0] result_index;
    reg [6:0] result_row_ix, result_col_ix;
    reg [31:0] transmission_ctr;
    
    reg [31:0] uart_data_frame;
    reg uart_send_signal;

    initial begin
        cycle_ctr = 0;


        // start idle
        operating_mode = 2'b00;
    
        /* TEST TRANSMISSION ONLY */
        // operating_mode = 2'b10;
        // $readmemb("2x2_weights_4b.mem", weights_sram); 	// read in row-major order, so make sure data is transposed inside the file!
        //                                                 // this is not the same as the transpose we do in cpp_impl, since there
        //                                                 // it must be transposed inside of VpuHsa, whereas here we transpose
        //                                                 // so we can access columns easily (since that is what we broadcast)
		// $readmemb("2x1_acts_4b.mem",  acts_sram); 
        /**************************/
    end

    

	reg [$clog2(SIZE)-1:0] weight_col_ix;
	reg [$clog2(SIZE)-1:0] weight_row_ix;
	reg wEn, en;
	reg [BIT_WIDTH-1:0] act_row [SIZE-1:0];
	reg [$clog2(SIZE)-1:0] act_col_left_edge, act_col_right_edge;

	reg [BIT_WIDTH-1:0] result [SIZE-1:0][SIZE-1:0];
	reg [BIT_WIDTH-1:0] result_row [SIZE-1:0];


    wire [BIT_WIDTH-1:0] weights_sram [SIZE-1:0][SIZE-1:0];

    assign curr_weight = rx_data_frame[BIT_WIDTH-1:0];

	/* Init the MpuHsa module */
	MpuHsa #(.SIZE(SIZE), .BIT_WIDTH(BIT_WIDTH)) mpu_hsa(
		.weight(curr_weight),        // straight from reading
		.weight_col_ix(weight_col_ix),
		.weight_row_ix(weight_row_ix),
		.wEn(wEn),
		.en(en),
		.reset(1'b0),					// reset has not been impl yet
		.clk(clk100),
		.activation(act_row),
        .cycle_ctr(cycle_ctr),
        .my_weights(weights_sram),
		.result(result_row)
	);

    // TODO: in recv stage, just fill the weights sram as needed
    reg compute_done;       // flag for switching back to slow clock

    wire [31:0] delta_cycle, redge, ledge;
    assign delta_cycle = cycle_ctr - (SIZE+1);
    assign redge = delta_cycle < SIZE ? delta_cycle : SIZE - 1;
    assign ledge = delta_cycle < SIZE ? 0 : delta_cycle - (SIZE - 1);  

    genvar j;
    generate
        for (j = 0; j < SIZE; j = j + 1) begin
            always @(posedge clk100) begin
                if (sys_reset || internal_reset) begin
                    compute_done <= 0;
                    cycle_ctr <= 0;
                    act_col_left_edge <= 0;
                    act_col_right_edge <= 0;
                /* 2'b10 = Computing, the only case at system clock */
                end else if (operating_mode == 2'b10) begin
                    cycle_ctr <= cycle_ctr + 1;
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

                    if (cycle_ctr == 3*SIZE+2) begin
                        compute_done <= 1;
                    end else if(cycle_ctr >= SIZE + 1) begin
                        if (ledge <= j && j <= redge) begin
                            result[delta_cycle - j][j] <= result_row[j];
                        end
                    end
                end
            end 
        end
    endgenerate

    /* 2'b00 listening for DEADBEEF to perform alignment */
    
    /* Misalignment FSM has following 2 states:
     * 0 : Listen for DEADBEEF. If not, keep dropping individual bytes (recv_drop_byte = 1)
           until our frame ready == DEADBEEF
     * 1 : Assert we now receive a clean DEADBEEF, go back to state 0 if not
               Send an OK (0C) message to PC if we do and move to op mode 01

     * Then in operating mode 01:
     * PC will then send a 'magic' DA221D06 as it's commencement of data,
     * this data is asserted and not written to memory. If DA221D06 is missed,
     * fault, turn on the error LEDs and go back to idle. Otherwise, with the
     * next data frames:

     * Read the data into the appropriate memory units. Each frame:

           <-- 1 bit --><-- 1 bit --><-- 7 bits --><-- 7 bits --><-- 16 bits -->
            ^ handshake   ^ acts       ^ x coord    ^ y coord     ^ data payload
             vs data      or weights
            
            Once all frames are received (i.e. memory units all full), send back
            a second OK (1C), and move to operating mode 10
     */
    reg misal_fsm;
    reg recv_drop_byte; 
    reg got_magic;
    // Stores whether we have or have not filled
    // that weights/acts
    reg [(SIZE*SIZE)-1:0] weights_filled;
    reg [(SIZE*SIZE)-1:0] acts_filled;
    reg send_aligner;
    always @(posedge clk_uart) begin
        if (sys_reset || internal_reset) begin
            misal_fsm <= 0;
            recv_drop_byte <= 0;
            got_magic <= 0;
            weights_filled <= '0;
            acts_filled <= '0;
            transmission_ctr <= 0;
            uart_data_frame  <= 0;
            uart_send_signal <= 0;
            result_col_ix <= 0;
            result_row_ix <= 0;
            LED[15:0] <= 0;
            internal_reset <= 0;        // internal reset max 1 cycle
        end else if (frame_ready && rx_data_frame == 32'hFFFFFFFF) begin      // capture a reset signal
            internal_reset <= 1;
            operating_mode <= 2'b00;    // internal reset does not set op mode, do here manually
        end else if (operating_mode == 2'b00) begin
            send_aligner <= 1;  // want this to start at 1
            if (frame_ready) begin
                case (misal_fsm)
                    1'b0 : begin
                        // signal we are in idle with leds
                        LED[15:0] <= 16'hFFFF;
                        // because the drop signal will last one more cycle
                        // check for the frame needing 1 drop (remember little-endian)
                        if (rx_data_frame == 32'hADBEEFDE) begin
                            // aligned, so don't drop byte
                            recv_drop_byte <= 0;
                            misal_fsm <= 1'b1;
                        end else begin
                            // otherwise keep dropping, drop byte flag
                            // just means transmitter reads 5 and takes last 4
                            recv_drop_byte <= 1;
                        end
                    end
                    1'b1 : begin
                        LED[15:0] <= 16'h0000;
                        if (rx_data_frame == 32'hDEADBEEF) begin
                            // verified, send OK
                            uart_data_frame <= 32'h0C0C0C0C;
                            uart_send_signal <= 1;  // pulsed back down to 0 when in op mode 01
                            operating_mode <= 2'b01;
                            LED[15:0] <= 16'h0001;
                            got_magic <= 0;         // must be 0 for opmode 01
                        end else begin
                            // something bad happened, go back to alignment state
                            misal_fsm <= 1'b0;
                        end
                    end
                endcase
            end
        end else if (operating_mode == 2'b10) begin       // must take precedence over op mode 01
            uart_send_signal <= 0;
            if (compute_done) begin
                operating_mode <= 2'b11;
            end
        end else if (operating_mode == 2'b01) begin
            uart_send_signal <= 0;  // need this
            send_aligner <= 1;  // want this to start at 1
            wEn <= 0;
            if (frame_ready) begin
                // we keep checking for magic (sender should send e.g. 5 to allow for
                // adequate timem between until a non-magic number starts
                // in which case begin reading
                if (~got_magic) begin   
                    if (rx_data_frame == 32'hDA221D06) begin
                        // start reading into memory
                        got_magic <= 1;
                        LED[15:0] <= 16'h0003;
                    end
                // Once we got magic, wait for first non-1 msb.
                end else if (rx_data_frame[31] == 0) begin
                    // FIXME: make acts a matrix when it needs to be
                    // FIXME: should check x,y being in index...
                    // check if acts or weights (2nd msb)
                    if (rx_data_frame[30]) begin
                        // weights: row=y, col=x
                        // truncate data that doesn't fit in our bit width
                        // weights_sram[rx_data_frame[22:16]][rx_data_frame[29:23]] <= rx_data_frame[BIT_WIDTH-1:0];

                        // enable writing
                        wEn <= 1;
                        
                        // Should fit automatically
                        // assign the row and column to write to
                        weight_row_ix <= rx_data_frame[22:16];
                        weight_col_ix <= rx_data_frame[29:23];

                        // record that we have filled this one:
                        weights_filled[rx_data_frame[22:16]*SIZE + rx_data_frame[29:23]] <= 1;
                    end else begin
                        // record that we have filled this one:
                        acts_sram[rx_data_frame[22:16]][rx_data_frame[29:23]] <= rx_data_frame[BIT_WIDTH-1:0];
                        acts_filled[rx_data_frame[22:16]*SIZE + rx_data_frame[29:23]] <= 1;
                        LED[7:0] <= acts_filled;
                    end
                    // Have we filled all of them?
                    if (&acts_filled & &weights_filled) begin
                        // send an acknowledge (2nd OK, 1c) back to PC
                        uart_data_frame <= 32'h1C1C1C1C;
                        uart_send_signal <= 1;
                        // move to op mode
                        operating_mode <= 2'b10;
                        LED[15:0] <= 16'h0007;
                    end
                end
            end
        end else if (operating_mode == 2'b11) begin
            transmission_ctr <= transmission_ctr + 1;
            /* OK signals are made to be 4x same byte so no need
             * to correct for misalignment here
             **/
            if (frame_ready && rx_data_frame == 32'h0C0C0C0C) begin
                send_aligner <= 0;      // host is aligned
            end else if (frame_ready && rx_data_frame == 32'h1C1C1C1C) begin
                // reset all signals
                internal_reset <= 1;
                // go back to state 0
                operating_mode <= 2'b00;
            end
            if (transmission_ctr == 2000) begin
                if (send_aligner) begin
                    uart_data_frame <= 32'hDEADBEEF;
                    
                end else begin
                    uart_data_frame[31]    <= 0;                    // message -> msb = 0
                    uart_data_frame[30]    <= 0;                    // acts/sram flag does not matter as only results.
                    uart_data_frame[29:23] <= result_col_ix;        // x-index
                    uart_data_frame[22:16] <= result_row_ix;        // y-index
                    if (BIT_WIDTH < 16) begin
                        uart_data_frame[15:BIT_WIDTH]  <= 0;            // left-pad data with 0
                    end
                    uart_data_frame[BIT_WIDTH-1:0] <= result[result_row_ix][result_col_ix]; // data
                    // uart_data_frame <= 32'h00DA221D;
                end
                uart_send_signal <= 1;
            end else if (transmission_ctr >= 2002) begin
                // result_index <= result_index == SIZE - 1 ? 0 : result_index + 1;
                result_col_ix <= result_col_ix + 1;
                if (result_col_ix == SIZE - 1) begin
                    result_col_ix <= 0;
                    result_row_ix <= result_row_ix + 1;
                    if (result_row_ix == SIZE - 1) begin
                        result_row_ix <= 0;
                    end
                end

                uart_send_signal <= 0;
                transmission_ctr <= 0;  // overrides increment
            end else begin
                uart_send_signal <= uart_send_signal;
            end
        end                                                              
    end // always posedge clk_uart                                        
                                                                          
    SerialTransmitter #(.FRAME_WIDTH(32)) UART_TRANSMITTER(               
            .data_frame(uart_data_frame),                                 
            .send(uart_send_signal),                                      
            .clk_uart(clk_uart),                                          
            .sys_reset(sys_reset || internal_reset),                      
                                                                          
            .tx(UART_RXD_OUT)                                             
    );                                                                    

    wire frame_ready;
    wire [31:0] rx_data_frame;
    SerialReceiver #(.FRAME_WIDTH(32)) UART_RECEIVER(
            .clk_uart(clk_uart),
            .rx(UART_TXD_IN),
            .sys_reset(sys_reset || internal_reset),
            .drop_byte(recv_drop_byte),
            
            .frame_ready(frame_ready),
            .data_frame(rx_data_frame)
    );
endmodule 
