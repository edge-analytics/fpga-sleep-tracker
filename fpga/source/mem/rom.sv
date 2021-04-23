module rom
#(parameter NUM_ELEMENTS=64, DATA_WIDTH=16, MIF_PATH="")
(
    input logic clk,
    input logic[$clog2(NUM_ELEMENTS)-1:0] i_addr,
    output logic[DATA_WIDTH-1:0] o_data
);

logic [DATA_WIDTH-1:0] mem [NUM_ELEMENTS];

initial begin
    $readmemb(MIF_PATH, mem);
end

always_ff @ (posedge clk) begin
    o_data <= mem[i_addr];
end

endmodule: rom