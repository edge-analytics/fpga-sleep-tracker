module nn_weights
import nn_pkg::*;
(
    input logic clk,
    input logic[$clog2(NUM_WEIGHTS)-1:0] i_index,
    output logic[PARAM_WIDTH-1:0] o_weight
);

logic [PARAM_WIDTH-1:0] weights [NUM_WEIGHTS];

initial begin
    $readmemb("weights.mif", weights);
end

always_ff @ (posedge clk) begin
    o_weight <= weights[i_index];
end

endmodule: nn_weights