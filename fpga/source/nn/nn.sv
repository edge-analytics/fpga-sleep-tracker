/* verilator lint_off WIDTH */
// Module: nn
// Description: The Edge Neural Net (nn) core theoretically supports MLP models of arbitrary size, 
// however in practice care will need to be taken to ensure that a given FPGA has sufficient on chip
// memory. 
// The nn core assumes a simple interface: the parent module will write new input data into the
// i_data port with an associated i_addr while asserting i_we and i_valid. When the new data is 
// written i_start can be asserted. The parent module must then wait for the o_done to assert before
// reading the results via o_data. The outputs must be read before new inputs are provided! To read
// the results one must provide the i_addr, leave i_we deasserted, and assert i_valid.
// Author: Blayne Kettlewell
// Date: 03/29/21
// Copyright 2021 - Edge Analytics 

module nn
import nn_pkg::*;
(
    input logic clk,
    input logic reset,
    input logic[$clog2(MAX_LAYER_DEPTH)-1:0] i_addr,
    input logic signed[INPUT_DATA_WIDTH-1:0] i_data,
    input logic i_we,
    input logic i_valid,
    input logic i_start,
    output logic o_done,
    output logic signed[OUTPUT_DATA_WIDTH-1:0] o_data,
    output logic [7:0] o_predicted_class,
    output logic o_valid
);

typedef enum logic[2:0]{
    // Wait for parent module to assert i_start
    WAIT_FOR_START = 3'd0,
    // ============ Weight Calcs and Sums ==============
    // Outer loop: Foreach neuron n_i in current layer
    // TODO can join loads below for optimization
    // n_i = curr_layer[i]
    LOOP_N_I_LOAD = 3'd1,                 
    // Inner loop: Foreach n_j in next layer... n_j += n_i * n_ji
    // n_j = next_layer[j] 
    // weight_ji = weights[weight_offset + i*len(next_layer) + j] 
    LOOP_N_J_AND_W_JI_LOAD = 3'd2,       
    // next_layer[j] = nj + n_i * w_ji; 
    // j++ 
    // conditional i++
    STORE_N_J_WITH_N_I_MULT_W_JI = 3'd3, 
    // ============ Bias and Relu Calcs ================
    // Loop: Foreach neuron n_b in next_layer add bias
    // n_b = next_layer[b]
    // bias_b = biases[bias_offset + b]
    LOOP_N_B_AND_B_B_LOAD = 3'd4,
    // curr_layer[b] = relu(bias_b + n_b)
    // next_layer[b] = 0
    // j++       
    STORE_N_J_WITH_RELU_N_J_ADD_BIAS_J = 3'd5,
    // Notify parent module calculation is complete
    ASSERT_DONE = 3'd6

}nn_state_t;

nn_state_t nn_state, nn_next_state;

logic[$clog2(NUM_WEIGHTS)-1:0] weight_idx;
logic signed [PARAM_WIDTH-1:0] weight_ji;
logic signed [OUTPUT_DATA_WIDTH+PARAM_WIDTH-1:0] n_i_mult_w_ji;
logic[$clog2(NUM_BIASES)-1:0] bias_idx;
logic signed [PARAM_WIDTH-1:0] bias_b;
logic [7:0] max_arg_index;

byte unsigned curr_layer_num_neurons, next_layer_num_neurons, layer, b, i, j;
shortint unsigned layer_offset, bias_offset, weight_offset, weight_sub_offset;

logic o_valid_sync;

// EBR signals
logic curr_layer_we, next_layer_we;
logic[$clog2(MAX_LAYER_DEPTH)-1:0] curr_layer_addr, next_layer_addr;
logic signed [OUTPUT_DATA_WIDTH-1:0] curr_layer_din, curr_layer_dout, 
next_layer_din, next_layer_dout, neuron_output, max_output;

// Component instantiations
nn_weights nn_weights_inst(
    .clk(clk),
    .i_index(weight_idx),
    .o_weight(weight_ji)
);
nn_biases nn_biases_inst(
    .clk(clk),
    .i_index(bias_idx),
    .o_bias(bias_b)
);
sp_ram #(.DATA_WIDTH(OUTPUT_DATA_WIDTH), .MEM_SIZE(MAX_LAYER_DEPTH)) current_layer_mem
(
    .clk(clk),
    .write_en(curr_layer_we),
    .address(curr_layer_addr),
    .data_in(curr_layer_din),
    .data_out(curr_layer_dout)
);
sp_ram #(.DATA_WIDTH(OUTPUT_DATA_WIDTH), .MEM_SIZE(MAX_LAYER_DEPTH)) next_layer_mem(
    .clk(clk),
    .write_en(next_layer_we),
    .address(next_layer_addr),
    .data_in(next_layer_din),
    .data_out(next_layer_dout)
);

// Current State Logic
always_ff@(posedge clk) begin
    if (reset) begin
        nn_state <= WAIT_FOR_START;
    end
    else begin
        nn_state <= nn_next_state;
    end
end

// Next State logic
always_comb begin
    case (nn_state)
        WAIT_FOR_START: begin
            if (i_start) begin
                nn_next_state = LOOP_N_I_LOAD;
            end
            else begin
                nn_next_state = WAIT_FOR_START;
            end
        end
        LOOP_N_I_LOAD: begin
            nn_next_state = LOOP_N_J_AND_W_JI_LOAD;
        end                 
        LOOP_N_J_AND_W_JI_LOAD: begin
            nn_next_state = STORE_N_J_WITH_N_I_MULT_W_JI; 
        end    
        STORE_N_J_WITH_N_I_MULT_W_JI: begin
            if (j == next_layer_num_neurons - 'd1) begin
                if (i == curr_layer_num_neurons - 'd1) begin
                    nn_next_state = LOOP_N_B_AND_B_B_LOAD;
                end
                else begin
                    nn_next_state = LOOP_N_I_LOAD;
                end
            end
            else begin
                nn_next_state = LOOP_N_J_AND_W_JI_LOAD;
            end
        end
        LOOP_N_B_AND_B_B_LOAD: begin
            nn_next_state = STORE_N_J_WITH_RELU_N_J_ADD_BIAS_J;
        end
        STORE_N_J_WITH_RELU_N_J_ADD_BIAS_J: begin
            if (b == next_layer_num_neurons - 'd1) begin
                if (layer == NUM_LAYERS - 'd2) begin
                    nn_next_state = ASSERT_DONE;
                end
                else begin
                    nn_next_state = LOOP_N_I_LOAD;
                end
            end
            else begin
                nn_next_state = LOOP_N_B_AND_B_B_LOAD;
            end
        end
        ASSERT_DONE: begin
            nn_next_state = WAIT_FOR_START;
        end
        default: begin
            nn_next_state = WAIT_FOR_START;
        end
    endcase
end

localparam MULT_MSB = OUTPUT_DATA_WIDTH + PARAM_WIDTH - PARAM_Q_INT;
localparam MULT_LSB = MULT_MSB - OUTPUT_DATA_WIDTH;
localparam BIAS_SIGN_EXT_LEN = OUTPUT_DATA_WIDTH - PARAM_WIDTH - PARAM_Q_INT;

// FSM Outputs
always_comb begin
    case (nn_state)
        WAIT_FOR_START: begin
            curr_layer_addr = i_addr;
            curr_layer_din = i_data;
            curr_layer_we = i_we;
            next_layer_addr = 'd0;
            next_layer_din = 'd0;
            next_layer_we = 1'b0;
            o_done = 1'b0;
            o_valid = o_valid_sync;
            o_predicted_class = 'd0;
        end
        LOOP_N_I_LOAD: begin
            curr_layer_addr = i;
            curr_layer_din = 'd0;
            curr_layer_we = 1'b0;
            next_layer_addr = 'd0;
            next_layer_din = 'd0;
            next_layer_we = 1'b0;
            o_done = 1'b0;
            o_valid = 1'b0;
            o_predicted_class = 'd0;
        end                 
        LOOP_N_J_AND_W_JI_LOAD: begin
            curr_layer_addr = i;
            curr_layer_din = 'd0;
            curr_layer_we = 1'b0;
            next_layer_addr = j;
            next_layer_din = 'd0;
            next_layer_we = 1'b0;
            o_done = 1'b0;
            o_valid = 1'b0;
            o_predicted_class = 'd0;
        end    
        STORE_N_J_WITH_N_I_MULT_W_JI: begin
            curr_layer_addr = i;
            curr_layer_din = 'd0;
            curr_layer_we = 1'b0;
            next_layer_addr = j;
            next_layer_din = n_i_mult_w_ji[MULT_MSB-1:MULT_LSB] + next_layer_dout;
            next_layer_we = 1'b1;
            o_done = 1'b0;
            o_valid = 1'b0;
            o_predicted_class = 'd0;
        end
        LOOP_N_B_AND_B_B_LOAD: begin
            curr_layer_addr = 'd0;
            curr_layer_din = 'd0;
            curr_layer_we = 1'b0;
            next_layer_addr = b;
            next_layer_din = 'd0;
            next_layer_we = 1'b0;
            o_done = 1'b0;
            o_valid = 1'b0;
            o_predicted_class = 'd0;
        end
        STORE_N_J_WITH_RELU_N_J_ADD_BIAS_J: begin
            curr_layer_addr = b;
            curr_layer_din = neuron_output;
            curr_layer_we = 1'b1;
            next_layer_addr = b;
            next_layer_din = 'd0;
            next_layer_we = 1'b1;
            o_done = 1'b0;
            o_valid = 1'b0;
            o_predicted_class = 'd0;
        end
        ASSERT_DONE:begin
            curr_layer_addr = 'd0;
            curr_layer_din = 'd0;
            curr_layer_we = 1'b0;
            next_layer_addr = 'd0;
            next_layer_din = 'd0;
            next_layer_we = 1'b0;
            o_done = 1'b1;
            o_valid = 1'b0;
            o_predicted_class = max_arg_index;
        end
        default: begin
            curr_layer_addr = 'd0;
            curr_layer_din = 'd0;
            curr_layer_we = 1'b0;
            next_layer_addr = 'd0;
            next_layer_din = 'd0;
            next_layer_we = 1'b0;
            o_done = 1'b0;
            o_valid = 1'b0;
            o_predicted_class = 'd0;
        end
    endcase
end

assign o_data = o_valid_sync ? curr_layer_dout : 'd0;
assign neuron_output = relu(next_layer_dout + {{BIAS_SIGN_EXT_LEN{bias_b[PARAM_WIDTH-1]}}, bias_b, {PARAM_Q_INT{1'b0}}});

// Loop indices and variable updates: Weight Calcs and Sums
always_ff @ (posedge clk) begin
    if (reset | (nn_state == WAIT_FOR_START)) begin
        i <= 'd0;
        j <= 'd0;
        weight_offset <= 'd0;
        weight_sub_offset <= 'd0;
    end
    else begin
        if (i < curr_layer_num_neurons) begin
            weight_offset <= weight_offset;
            weight_sub_offset <= i * next_layer_num_neurons;
            if (nn_state == STORE_N_J_WITH_N_I_MULT_W_JI) begin
                if (j < next_layer_num_neurons - 'd1) begin
                    j <= j + 'd1;
                    i <= i;
                end
                else begin
                    j <= 'd0;
                    i <= i + 'd1;
                end
            end
            else begin
                i <= i;
                j <= j;
            end
        end
        else begin
            // Update loop variables
            weight_offset <= weight_offset + curr_layer_num_neurons * next_layer_num_neurons;
            weight_sub_offset <= 'd0;
            i <= 'd0;
            j <= 'd0;
        end
    end
end

// Weight ROM offset
assign weight_idx = weight_offset + weight_sub_offset + {8'd0, j};

// Loop indices and variable updates: Biases and Relu Calcs
always_ff @ (posedge clk) begin
    if (reset | (nn_state == WAIT_FOR_START)) begin
        b <= 'd0;
        bias_offset <= 'd0;
        layer <= 'd0;
        curr_layer_num_neurons <= NEURONS_PER_LAYER['d0];
        next_layer_num_neurons <= NEURONS_PER_LAYER['d1];
    end
    else begin
        if (b < next_layer_num_neurons) begin
            curr_layer_num_neurons <= curr_layer_num_neurons;
            next_layer_num_neurons <= next_layer_num_neurons;
            layer <= layer;
            bias_offset <= bias_offset;
            if (nn_state == STORE_N_J_WITH_RELU_N_J_ADD_BIAS_J) begin
                b <= b + 'd1;
            end
            else begin
                b <= b;
            end
        end
        else begin
            // Update loop variables
            bias_offset <= bias_offset + next_layer_num_neurons;
            curr_layer_num_neurons <= next_layer_num_neurons;
            next_layer_num_neurons <= NEURONS_PER_LAYER[layer + 'd2];
            layer <= layer + 'd1;
            b <= 'd0;
        end
    end
end

// Argmax calculation
always_ff @ (posedge clk) begin
    if (reset | (nn_state == WAIT_FOR_START)) begin
        max_output <= 'd0;
        max_arg_index <= 'd0;
    end
    else begin
        if (nn_state == STORE_N_J_WITH_RELU_N_J_ADD_BIAS_J) begin
            if (layer == NUM_LAYERS - 'd2) begin
               if (neuron_output > max_output) begin
                   max_output <= neuron_output;
                   max_arg_index <= b;
               end
               else begin
                   max_output <= max_output;
                   max_arg_index <= max_arg_index;
               end
            end
            else begin
                max_output <= max_output;
                max_arg_index <= max_arg_index;
            end
        end
    end
end



// Bias ROM offset
assign bias_idx = bias_offset + b;

// Calc for STORE_N_J_WITH_N_I_MULT_W_JI
assign n_i_mult_w_ji = curr_layer_dout * weight_ji;

// Sync delay for reading results from EBR
always_ff @ (posedge clk) begin
    o_valid_sync <= ~i_we & i_valid;
end

endmodule: nn