module nn_biases
import nn_pkg::*;
(
    input logic clk,
    input logic[$clog2(NUM_BIASES)-1:0] i_index,
    output logic[PARAM_WIDTH-1:0] o_bias
);

logic [PARAM_WIDTH-1:0] biases [NUM_BIASES];

initial begin
    $readmemb("biases.mif", biases);
end

always_ff @ (posedge clk) begin
    o_bias <= biases[i_index];
end

endmodule: nn_biases