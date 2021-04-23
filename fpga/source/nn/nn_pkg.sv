
package nn_pkg;
// NN package for parameters that define a given mlp model
// The model is restricted to less than 256 inputs, 256 outputs and 256 layers 

// NN general parameters dependent on model
localparam NUM_WEIGHTS = 495;
localparam NUM_BIASES = 47;
localparam INPUT_DATA_WIDTH = 32;
localparam OUTPUT_DATA_WIDTH = 32;
localparam OUTPUT_Q_INT = 16;
localparam OUTPUT_Q_FRAC = OUTPUT_DATA_WIDTH - OUTPUT_Q_INT;
localparam PARAM_WIDTH = 16;
localparam PARAM_Q_INT = 2;
localparam PARAM_Q_FRAC = PARAM_WIDTH - PARAM_Q_INT;
localparam PARAM_MIF_PATH = "/Users/rbk/consulting/edge-analytics/fpga-sleep-tracker/fpga/source/nn/";
localparam NUM_LAYERS = 5;
localparam MAX_LAYER_DEPTH = 15;
localparam NN_INPUTS = 1;
localparam NN_OUTPUTS = 2;

localparam logic [7:0] NEURONS_PER_LAYER [NUM_LAYERS] = '{
	8'd1,
	8'd15,
	8'd15,
	8'd15,
	8'd2
};

// TODO add function for relu
function automatic logic signed[OUTPUT_DATA_WIDTH-1:0] relu(input logic signed[OUTPUT_DATA_WIDTH-1:0] x);
    return x < 0 ? '0: x;
endfunction

endpackage: nn_pkg
    