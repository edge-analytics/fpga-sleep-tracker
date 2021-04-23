module handshake
#(parameter DATA_WIDTH = 16)
(
    input logic clk,
    input logic reset,
    input logic[DATA_WIDTH-1:0] i_data,
    input logic i_valid,
    input logic ready_for_output,
    output logic[DATA_WIDTH-1:0] o_data,
    output logic o_valid,
    output logic ready_for_input
);

logic[DATA_WIDTH-1:0] data_captured;

typedef enum logic[1:0]{
    EMPTY = 2'd0,
    FILLED = 2'd1,
    SEND_OUTPUT = 2'd2
}handshake_state_t;

handshake_state_t handshake_state, handshake_next_state;

// FSM current state
always_ff @ (posedge clk) begin
    if (reset) begin
        handshake_state <= EMPTY;
    end
    else begin
        handshake_state <= handshake_next_state;
    end
end

// FSM next state
always_comb begin
    case (handshake_state)
        EMPTY: begin
            if (i_valid) begin
                handshake_next_state = FILLED;
            end
            else begin
                handshake_next_state = EMPTY;
            end
        end
        FILLED: begin
            if (ready_for_output) begin
                handshake_next_state = SEND_OUTPUT;
            end
            else begin
                handshake_next_state = FILLED;
            end
        end
        SEND_OUTPUT: begin
            handshake_next_state = EMPTY;
        end
        default: begin
            handshake_next_state = EMPTY;
        end
    endcase
end

// FSM output
always_comb begin
    case (handshake_state)
        EMPTY: begin
            o_data = 'd0;
            o_valid = 1'b0;
            ready_for_input = 1'b1;
        end
        FILLED: begin
            o_data = 'd0;
            o_valid = 1'b0;
            ready_for_input = 1'b0;
        end
        SEND_OUTPUT: begin
            o_data = data_captured;
            o_valid = 1'b1;
            ready_for_input = 1'b0;
        end
        default: begin
            o_data = 'd0;
            o_valid = 1'b0;
            ready_for_input = 1'b1;
        end
    endcase
end

// Capture data register
always_ff @ (posedge clk) begin
    if (reset) begin
       data_captured <= 'd0; 
    end
    else begin
        if (i_valid & handshake_state == EMPTY) begin
            data_captured <= i_data;
        end
        else begin
            data_captured <= data_captured;
        end
    end
end

endmodule: handshake