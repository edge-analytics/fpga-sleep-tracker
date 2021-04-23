module sp_ram
#(parameter DATA_WIDTH=8, MEM_SIZE=64)
(
    input logic clk,
    input logic write_en,
    input logic [$clog2(MEM_SIZE)-1:0] address,
    input logic [DATA_WIDTH-1:0] data_in,
    output logic [DATA_WIDTH-1:0] data_out
);

logic[DATA_WIDTH-1:0] mem [MEM_SIZE-1:0];

initial begin
    for(int i=0; i<MEM_SIZE;i++) begin
        mem[i] = 'd0;
    end
end

always_ff @(posedge clk) begin
    if (write_en) begin
        mem[address] <= data_in;
    end
    else begin 
        data_out <= mem[address];
    end
end

endmodule: sp_ram