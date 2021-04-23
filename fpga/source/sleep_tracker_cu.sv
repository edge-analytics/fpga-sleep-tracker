/* verilator lint_off WIDTH */

module sleep_tracker_cu
import nn_pkg::*;
(
    input logic clk,
    input logic reset,
    
    // UART signals
    output logic write_strobe_o,
    output logic read_strobe_o,
    output logic[7:0] write_data_o,
    input logic [7:0] read_data_i,
    input logic read_valid_i,
    input logic tx_ready_i,
    input logic rx_ready_i,

    // System signals
    output logic start_acquisition,

    // NN signals
    output logic[$clog2(MAX_LAYER_DEPTH)-1:0] o_nn_addr,
    output logic signed[INPUT_DATA_WIDTH-1:0] o_nn_data,
    output logic o_nn_we,
    output logic o_nn_valid,
    output logic o_nn_start,
    input logic i_nn_done,
    input logic signed[OUTPUT_DATA_WIDTH-1:0] i_nn_data,
    input logic [7:0] i_nn_predicted_class,
    input logic i_nn_valid,

    // Actigraphy Feature
    input logic [7:0] i_count_feature,
    input logic i_count_valid,

    // Target to Host fifo: counts and predictions
    output logic o_fifo_input_valid,
    output logic[15:0] o_fifo_input_data,
    input logic i_fifo_ready_for_input,
    input logic i_fifo_empty,
    input logic i_fifo_output_valid,
    input logic[15:0] i_fifo_output_data,
    output logic o_fifo_ready_for_output
);
localparam REG_MAP_BYTES = 256;
localparam STATUS_REG_ADDR = 129;
localparam CMD_REG_ADDR = 128;
localparam CMD_REG_WRITE_REQ_BIT = 7;
localparam CMD_REG_FIFO_READ_BIT = 6;
localparam OUTPUT_BASE_ADDR = 64;
localparam INPUT_BASE_ADDR = 0;
localparam START_BIT = 7;

// UART comm signals
byte rx_byte_capture, tx_send_byte, fifo_current_byte;
logic [15:0] reg_base_address, current_byte, num_bytes;
logic write_request, fifo_read_request, start_cmd;

// Regmap memory
logic reg_map_we;
logic[$clog2(REG_MAP_BYTES)-1:0] reg_map_addr;
logic[7:0] reg_map_din, reg_map_dout, count_feature_capture;

// NN signals
logic [$clog2(NN_INPUTS)-1:0] nn_input_idx;
logic signed[OUTPUT_DATA_WIDTH-1:0] i_nn_data_capture;
logic handshake_empty;

// State variables and associated typedefs
typedef enum logic[1:0]{
    WAIT_FOR_RX = 2'd0,
    SET_READ_STROBE = 2'd1,
    WAIT_READ_VALID = 2'd2,
    PROCESS_RX_BYTE = 2'd3
}rx_state_t;

rx_state_t rx_state, rx_next_state;

typedef enum logic[3:0]{
    WAIT_RX_PACKET = 4'd0,
    WAIT_RX_PACKET_HEADER = 4'd1,
    WAIT_RX_PACKET_ADDR_LSB = 4'd2,
    WAIT_RX_PACKET_ADDR_MSB = 4'd3, 
    WAIT_RX_PACKET_DATA = 4'd4,
    WRITE_RX_PACKET_DATA = 4'd5,
    WAIT_TX_READY = 4'd6,
    LOAD_TX_PACKET_BYTE = 4'd7,
    LOAD_FIFO_PACKET_BYTE = 4'd8,
    SEND_TX_BYTE = 4'd9
}packet_state_t;

packet_state_t packet_state, packet_next_state;

typedef enum logic[1:0]{
    IDLE_NN = 2'd0,
    STORE_NN_INPUT_IP = 2'd1,
    START_NN = 2'd2,
    WAIT_NN_DONE = 2'd3
}nn_state_t;

nn_state_t nn_state, nn_next_state;

// Component instantiations
sp_ram #(.DATA_WIDTH(8), .MEM_SIZE(REG_MAP_BYTES)) register_map
(
    .clk(clk),
    .write_en(reg_map_we),
    .address(reg_map_addr),
    .data_in(reg_map_din),
    .data_out(reg_map_dout)
);

handshake #(.DATA_WIDTH(16)) fifo_write_handshake
(
    .*,
    .i_data({i_nn_predicted_class, count_feature_capture}),
    .i_valid(i_nn_done),
    .ready_for_output(~handshake_empty & (packet_state == WAIT_RX_PACKET)),
    .o_data(o_fifo_input_data),
    .o_valid(o_fifo_input_valid),
    .ready_for_input(handshake_empty)
);

//==============================================================================
//                            UART Read Control FSM
//==============================================================================
// Current state
always_ff @ (posedge clk) begin
    if (reset) begin
        rx_state <= WAIT_FOR_RX;
    end
    else begin
        rx_state <= rx_next_state;
    end
end
// Next state
always_comb begin
    case (rx_state)
        WAIT_FOR_RX: begin
            if (rx_ready_i) begin
                rx_next_state = SET_READ_STROBE;
            end
            else begin
                rx_next_state = WAIT_FOR_RX;
            end
        end
        SET_READ_STROBE: begin
            rx_next_state = WAIT_READ_VALID;
        end
        WAIT_READ_VALID: begin
            if (read_valid_i) begin
                rx_next_state = PROCESS_RX_BYTE;
            end
            else begin
                rx_next_state = WAIT_READ_VALID;
            end
        end
        PROCESS_RX_BYTE: begin
            rx_next_state = WAIT_FOR_RX;
        end
        default: begin
            rx_next_state = WAIT_FOR_RX;
        end
    endcase
end
// Output
assign read_strobe_o = rx_state == SET_READ_STROBE;

//==============================================================================
//                              Packet Control FSM
//==============================================================================
//======================== Receive packet format ==========================/
// Byte 0 (Packet Header):
// |  bit7  |  bit6  |  bit5  |  bit4  |  bit3  |  bit2  |  bit1  |  bit0  |
// |  R/W   |  FIFO  |     Reserved    |    REG Num Bytes or FIFO ID       |
// Byte 1 (Register Address LSB):
// |  bit7  |  bit6  |  bit5  |  bit4  |  bit3  |  bit2  |  bit1  |  bit0  |
// |            REGISTER ADDRESS[7:0]  or  FIFO_NUM_ELEMENTS_R/W[7:0]      |
// Byte 2 (Register Address MSB):
// |  bit7  |  bit6  |  bit5  |  bit4  |  bit3  |  bit2  |  bit1  |  bit0  |
// |            REGISTER ADDRESS[15:0]  or  FIFO_NUM_ELEMENTS_R/W[13:0]    |
// Byte 3 (Write only - payload):
// |  bit7  |  bit6  |  bit5  |  bit4  |  bit3  |  bit2  |  bit1  |  bit0  |
// |                       WRITE VALUE BYTE 0                              |
// Byte 4.. (Write only - payload):
// |  bit7  |  bit6  |  bit5  |  bit4  |  bit3  |  bit2  |  bit1  |  bit0  |
// |                       WRITE VALUE BYTE 1..                            |

// FSM Current state
always_ff @ (posedge clk) begin
    if (reset) begin
        packet_state <= WAIT_RX_PACKET;
    end
    else begin
        packet_state <= packet_next_state;
    end
end
// FSM Next state
always_comb begin
    case (packet_state)
        WAIT_RX_PACKET: begin
            if (rx_state != WAIT_FOR_RX) begin
                packet_next_state = WAIT_RX_PACKET_HEADER;
            end
            else begin
                packet_next_state = WAIT_RX_PACKET;
            end
        end
        WAIT_RX_PACKET_HEADER: begin
            if (rx_state == PROCESS_RX_BYTE) begin
                packet_next_state = WAIT_RX_PACKET_ADDR_LSB;
            end
            else begin
                packet_next_state = WAIT_RX_PACKET_HEADER;
            end
        end
        WAIT_RX_PACKET_ADDR_LSB: begin
            if (rx_state == PROCESS_RX_BYTE) begin
                packet_next_state = WAIT_RX_PACKET_ADDR_MSB;
            end
            else begin
                packet_next_state = WAIT_RX_PACKET_ADDR_LSB;
            end
        end
        WAIT_RX_PACKET_ADDR_MSB: begin
            if (rx_state == PROCESS_RX_BYTE) begin
                if (write_request) begin
                    packet_next_state = WAIT_RX_PACKET_DATA;
                end
                else begin
                    packet_next_state = WAIT_TX_READY;
                end
            end
            else begin
                packet_next_state = WAIT_RX_PACKET_ADDR_MSB;
            end
        end
        WAIT_RX_PACKET_DATA: begin
            if (rx_state == PROCESS_RX_BYTE) begin
                packet_next_state = WRITE_RX_PACKET_DATA;
            end
            else begin
                packet_next_state = WAIT_RX_PACKET_DATA;
            end
        end
        WRITE_RX_PACKET_DATA: begin
            if (current_byte < num_bytes - 'd1) begin
                packet_next_state = WAIT_RX_PACKET_DATA;
            end
            else begin
                packet_next_state = WAIT_RX_PACKET;
            end
        end
        WAIT_TX_READY: begin
            if (tx_ready_i) begin
                if (fifo_read_request) begin
                    if (i_fifo_empty) begin
                        packet_next_state = WAIT_RX_PACKET;
                    end
                    else begin
                        packet_next_state = LOAD_FIFO_PACKET_BYTE;
                    end
                end
                else begin
                    packet_next_state = LOAD_TX_PACKET_BYTE;
                end
            end
            else begin
                packet_next_state = WAIT_TX_READY;
            end
        end
        LOAD_TX_PACKET_BYTE: begin
            packet_next_state = SEND_TX_BYTE;
        end
        LOAD_FIFO_PACKET_BYTE: begin
            packet_next_state = SEND_TX_BYTE; 
        end
        SEND_TX_BYTE: begin
            if (current_byte < num_bytes - 'd1) begin
                packet_next_state = WAIT_TX_READY;
            end
            else begin
                packet_next_state = WAIT_RX_PACKET;
            end
        end
        default: begin
            packet_next_state = WAIT_RX_PACKET;
        end
    endcase
end
// FSM Output
always_comb begin
    case (packet_state)
        WAIT_RX_PACKET: begin
            reg_map_we = 1'b0;
            reg_map_addr = 'd0;
            reg_map_din = 'd0;
            write_strobe_o = 1'b0;
            write_data_o = 'd0;
            o_fifo_ready_for_output = 1'b0;
        end
        WAIT_RX_PACKET_HEADER: begin
            reg_map_we = 1'b0;
            reg_map_addr = 'd0;
            reg_map_din = 'd0;
            write_strobe_o = 1'b0;
            write_data_o = 'd0;
            o_fifo_ready_for_output = 1'b0;
        end
        WAIT_RX_PACKET_ADDR_LSB: begin
            reg_map_we = 1'b0;
            reg_map_addr = 'd0;
            reg_map_din = 'd0;
            write_strobe_o = 1'b0;
            write_data_o = 'd0;
            o_fifo_ready_for_output = 1'b0;
        end
        WAIT_RX_PACKET_ADDR_MSB: begin
            reg_map_we = 1'b0;
            reg_map_addr = 'd0;
            reg_map_din = 'd0;
            write_strobe_o = 1'b0;
            write_data_o = 'd0;
            o_fifo_ready_for_output = 1'b0;
        end
        WAIT_RX_PACKET_DATA: begin
            reg_map_we = 1'b0;
            reg_map_addr = 'd0;
            reg_map_din = 'd0;
            write_strobe_o = 1'b0;
            write_data_o = 'd0;
            o_fifo_ready_for_output = 1'b0;
        end
        WRITE_RX_PACKET_DATA: begin
            reg_map_we = 1'b1;
            reg_map_addr = reg_base_address[$clog2(REG_MAP_BYTES)-1:0] + current_byte;
            reg_map_din = rx_byte_capture;
            write_strobe_o = 1'b0;
            write_data_o = 'd0;
            o_fifo_ready_for_output = 1'b0;
        end
        WAIT_TX_READY: begin
            reg_map_we = 1'b0;
            reg_map_addr = 'd0;
            reg_map_din = 'd0;
            write_strobe_o = 1'b0;
            write_data_o = 'd0;
            o_fifo_ready_for_output = 1'b0;
        end
        LOAD_TX_PACKET_BYTE: begin
            reg_map_we = 1'b0;
            reg_map_addr = reg_base_address[$clog2(REG_MAP_BYTES)-1:0] + current_byte;
            reg_map_din = 'd0;
            write_strobe_o = 1'b0;
            write_data_o = 'd0;
            o_fifo_ready_for_output = 1'b0;
        end
        LOAD_FIFO_PACKET_BYTE: begin
            reg_map_we = 1'b0;
            reg_map_addr = 'd0;
            reg_map_din = 'd0;
            write_strobe_o = 1'b0;
            write_data_o = 'd0;
            o_fifo_ready_for_output = current_byte[0] == 1'b0; // Only pull from fifo every other byte
        end
        SEND_TX_BYTE: begin
            reg_map_we = 1'b0;
            reg_map_addr = 'd0;
            reg_map_din = 'd0;
            write_strobe_o = 1'b1;
            write_data_o = tx_send_byte;
            o_fifo_ready_for_output = 1'b0;
        end
        default: begin
            reg_map_we = 1'b0;
            reg_map_addr = 'd0;
            reg_map_din = 'd0;
            write_strobe_o = 1'b0;
            write_data_o = 'd0;
            o_fifo_ready_for_output = 1'b0;
        end
    endcase
end

// NOTE this fifo byte selection method is only relevant for the 16 bit packed words in this
// specific application. A more general target-host fifo protocol should be developed
assign fifo_current_byte = (current_byte[0] == 1'b0) ? i_fifo_output_data[7:0] : i_fifo_output_data[15:8];
assign tx_send_byte = fifo_read_request ? fifo_current_byte : reg_map_dout;

// Capture the RX byte
always_ff @ (posedge clk) begin
    if (reset) begin
        rx_byte_capture <= 'd0;
    end
    else begin
        if (read_valid_i) begin
            rx_byte_capture <= read_data_i;
        end
        else begin
            rx_byte_capture <= rx_byte_capture;
        end
    end
end

// Capture the packet bytes
always_ff @ (posedge clk) begin
    if (reset) begin
        write_request <= 1'b0;
        fifo_read_request <= 1'b0;
        num_bytes <= 'd0;
        current_byte <= 'd0;
        reg_base_address <= 'd0;
    end
    else begin
        if (packet_state == WAIT_RX_PACKET_HEADER) begin
            write_request <= rx_byte_capture[CMD_REG_WRITE_REQ_BIT];
            fifo_read_request <= rx_byte_capture[CMD_REG_FIFO_READ_BIT];
            num_bytes <= {{12{1'b0}}, rx_byte_capture[3:0]};
            current_byte <= 'd0;
            reg_base_address <= 'd0;
        end
        else if (packet_state == WAIT_RX_PACKET_ADDR_LSB) begin
            write_request <= write_request;
            fifo_read_request <= fifo_read_request;
            num_bytes <= num_bytes;
            current_byte <= current_byte;
            if (fifo_read_request) begin
                num_bytes[7:0] <= rx_byte_capture;
                reg_base_address[7:0] <= 'd0;
            end
            else begin
                num_bytes <= num_bytes;
                reg_base_address[7:0] <= rx_byte_capture;
            end
        end
        else if (packet_state == WAIT_RX_PACKET_ADDR_MSB) begin
            write_request <= write_request;
            fifo_read_request <= fifo_read_request;
            num_bytes <= num_bytes;
            current_byte <= current_byte;
            if (fifo_read_request) begin
                num_bytes[15:8] <= rx_byte_capture;
                reg_base_address[15:8] <= 'd0;
            end
            else begin
                num_bytes <= num_bytes;
                reg_base_address[15:8] <= rx_byte_capture;
            end
        end 
        else if (packet_state == WRITE_RX_PACKET_DATA) begin
            write_request <= write_request;
            fifo_read_request <= fifo_read_request;
            num_bytes <= num_bytes;
            current_byte <= current_byte + 'd1;
            reg_base_address <= reg_base_address;
        end
        else if (packet_state == SEND_TX_BYTE) begin
            write_request <= write_request;
            fifo_read_request <= fifo_read_request;
            num_bytes <= num_bytes;
            current_byte <= current_byte + 'd1;
            reg_base_address <= reg_base_address;
        end
        else begin
            write_request <= write_request;
            fifo_read_request <= fifo_read_request;
            num_bytes <= num_bytes;
            current_byte <= current_byte;
            reg_base_address <= reg_base_address;
        end
    end
end

// Capture start bit
always_ff @ (posedge clk) begin
    if (reset) begin
        start_cmd <= 1'b0;
    end
    else begin
        if (reg_map_addr == CMD_REG_ADDR & reg_map_we) begin
            start_cmd <= reg_map_din[START_BIT];
        end
        else begin
            start_cmd <= start_cmd;
        end
    end
end

// Capture the count feature 
always_ff @ (posedge clk) begin
    if (reset) begin
        count_feature_capture <= 'd0;
    end
    else begin
        if (i_count_valid) begin
            count_feature_capture <= i_count_feature;
        end
        else begin
            count_feature_capture <= count_feature_capture;
        end
    end
end

//==============================================================================
//                              NN IP CONTROL FSM
//==============================================================================a

// FSM Current State
always_ff @(posedge clk) begin
    if (reset) begin
        nn_state <= IDLE_NN;
    end
    else begin
        nn_state <= nn_next_state;
    end
end

// FSM Next State
always_comb begin
    case (nn_state)
        IDLE_NN: begin
            if (start_cmd & i_count_valid) begin
                nn_next_state = STORE_NN_INPUT_IP;
            end
            else begin
                nn_next_state = IDLE_NN;
            end
        end
        STORE_NN_INPUT_IP: begin
            if (nn_input_idx < NN_INPUTS - 'd1) begin
                nn_next_state = STORE_NN_INPUT_IP;
            end
            else begin
                nn_next_state = START_NN;
            end
        end
        START_NN: begin
            nn_next_state = WAIT_NN_DONE;
        end
        WAIT_NN_DONE: begin
            if (i_nn_done) begin
                nn_next_state = IDLE_NN;
            end
        end
        default: begin
            nn_next_state = IDLE_NN;
        end
    endcase
end

// FSM Output
always_comb begin
    case (nn_state)
        IDLE_NN: begin
            o_nn_addr = 'd0;
            o_nn_data = 'd0;
            o_nn_we = 1'b0;
            o_nn_valid = 1'b0;
            o_nn_start = 1'b0;
        end
        STORE_NN_INPUT_IP: begin
            o_nn_addr = nn_input_idx; // FIXME address non-sequential loading
            o_nn_data = {8'd0, count_feature_capture, 16'd0}; // Unsigned input
            o_nn_we = 1'b1;
            o_nn_valid = 1'b1;
            o_nn_start = 1'b0;
        end
        START_NN: begin
            o_nn_addr = 'd0;
            o_nn_data = 'd0;
            o_nn_we = 1'b0;
            o_nn_valid = 1'b0;
            o_nn_start = 1'b1;
        end
        WAIT_NN_DONE: begin
            o_nn_addr = 'd0;
            o_nn_data = 'd0;
            o_nn_we = 1'b0;
            o_nn_valid = 1'b0;
            o_nn_start = 1'b0;
        end
        default: begin
            o_nn_addr = 'd0;
            o_nn_data = 'd0;
            o_nn_we = 1'b0;
            o_nn_valid = 1'b0;
            o_nn_start = 1'b0;
        end
    endcase
end

// NN variable update section

always_ff @ (posedge clk) begin
    if (reset) begin
        i_nn_data_capture <= 'd0;
    end
    else begin
        if (i_nn_valid) begin
            i_nn_data_capture <= i_nn_data;
        end
        else begin
            i_nn_data_capture <= i_nn_data_capture;
        end
    end
end

always_ff @ (posedge clk) begin
    if (reset) begin
        nn_input_idx <= 'd0;
    end
    else begin
        if (nn_state == STORE_NN_INPUT_IP) begin
            nn_input_idx <= nn_input_idx + 'd1;
        end
        else begin
            nn_input_idx <= 'd0;
        end
    end
end

endmodule: sleep_tracker_cu