module biquad
(
    input logic clk,
    input logic reset,
    input logic signed[7:0] i_data,
    input logic i_valid,
    output logic signed[7:0] o_data,
    output logic o_valid
);

logic signed[7:0] b[3] = '{
    8'b00101101, // 0.3516
    8'b00000000, // 0.0
    8'b11010011  // -0.3516
};

// a0 is 1 and is not included, sign inverted to allow for acc additions only
logic signed[7:0] a[2] = '{
    8'b01111000, // 0.9375
    8'b11011011  // -0.2890
};

logic signed[7:0] x_n [2] = '{
    8'd0,
    8'd0
};

logic signed[7:0] y_n [2] = '{
    8'd0,
    8'd0
};

typedef enum logic[2:0]{
    IDLE = 3'd0,
    CALC_B0 = 3'd1,
    CALC_B1 = 3'd2,
    CALC_B2 = 3'd3,
    CALC_A1 = 3'd4,
    CALC_A2 = 3'd5,
    CALC_DONE = 3'd6
}biquad_states_t;

biquad_states_t biquad_state, biquad_next_state;

logic signed[15:0] acc;
logic signed[7:0] x_captured, z, coeff, y;

// FSM Current State
always_ff @ (posedge clk) begin
    if (reset) begin
        biquad_state <= IDLE;
    end
    else begin
        biquad_state <= biquad_next_state;
    end
end

// FSM Next State
always_comb begin
    case (biquad_state)
        IDLE: begin
            if (i_valid) begin
                biquad_next_state = CALC_B0;
            end
            else begin
                biquad_next_state = IDLE;
            end
        end
        CALC_B0: begin
            biquad_next_state = CALC_B1;
        end
        CALC_B1: begin
            biquad_next_state = CALC_B2;
        end
        CALC_B2: begin
            biquad_next_state = CALC_A1;
        end
        CALC_A1: begin
            biquad_next_state = CALC_A2;
        end
        CALC_A2: begin
            biquad_next_state = CALC_DONE;
        end
        CALC_DONE: begin
            biquad_next_state = IDLE;
        end
        default: begin
            biquad_next_state = IDLE;
        end
    endcase
end

// FSM Output
always_comb begin
    case (biquad_state)
        IDLE: begin
            o_valid = 1'b0;
            o_data = 'd0;
            z = 'd0;
            coeff = 'd0;
        end
        CALC_B0: begin
            o_valid = 1'b0;
            o_data = 'd0;
            z = x_captured;
            coeff = b[0];
        end
        CALC_B1: begin
            o_valid = 1'b0;
            o_data = 'd0;
            z = x_n[0];
            coeff = b[1];
        end
        CALC_B2: begin
            o_valid = 1'b0;
            o_data = 'd0;
            z = x_n[1];
            coeff = b[2];
        end
        CALC_A1: begin
            o_valid = 1'b0;
            o_data = 'd0;
            z = y_n[0];
            coeff = a[0];
        end
        CALC_A2: begin
            o_valid = 1'b0;
            o_data = 'd0;
            z = y_n[1];
            coeff = a[1];
        end
        CALC_DONE: begin
            o_valid = 1'b1;
            o_data = y;
            z = 'd0;
            coeff = 'd0;
        end
        default: begin
            o_valid = 1'b0;
            o_data = 'd0;
            z = 'd0;
            coeff = 'd0;
        end
    endcase
end

always_ff @ (posedge clk) begin
    if (reset | biquad_state == IDLE) begin
        acc <= 'd0;
    end
    else begin
        acc <= acc + z * coeff;
    end
end

// Capture x input
always_ff @ (posedge clk) begin
    if (reset) begin
        x_captured <= 'd0;
    end
    else begin
        if (i_valid) begin
            x_captured <= i_data;
        end
        else begin
            x_captured <= x_captured;
        end
    end
end

assign y = acc[14:7];

// Shift chain for biquad delay register state
always_ff @ (posedge clk) begin
    if (biquad_state == CALC_DONE) begin
        x_n[0] <= x_captured;
        x_n[1] <= x_n[0];
        y_n[0] <= y;
        y_n[1] <= y_n[0];
    end
    else begin
        y_n <= y_n;
        x_n <= x_n;
    end
end

endmodule: biquad
