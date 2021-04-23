module fifo_ebr
#(parameter DATA_WIDTH = 16, parameter NUM_ELEMENTS=32)
(
    input logic clk,
    input logic reset,
    input logic input_valid,
    input logic[DATA_WIDTH-1:0] data_in,
    output logic ready_for_input,
    output logic output_valid,
    output logic[DATA_WIDTH-1:0] data_out,
    input logic ready_for_output
);

localparam ADDRESS_WIDTH = $clog2(NUM_ELEMENTS);

logic[DATA_WIDTH-1:0] mem[NUM_ELEMENTS];

initial begin 
    for(int i=0; i<NUM_ELEMENTS; i++) begin
        mem[i] = 'd0;
    end
end

logic [ADDRESS_WIDTH:0] element_count;
logic [ADDRESS_WIDTH-1:0] write_idx, read_idx;
logic empty, full, qualified_write, qualified_read;

assign qualified_read = ready_for_output & ~empty;
assign qualified_write = input_valid & ~full;
assign ready_for_input = ~full;

always_ff @ (posedge clk) begin
    if (reset) begin
        empty <= 1'b1;
        full <= 1'b0;
        write_idx <= 'd0;
        read_idx <= 'd0;
        element_count <= 'd0;
    end
    else begin
        if (qualified_read & qualified_write) begin
            empty <= empty;
            full <= full;
            element_count <= element_count;
            write_idx <= write_idx + 'd1;
            read_idx <= read_idx + 'd1;
        end
        else if (qualified_read) begin
            empty <= element_count == 'd1;
            full <= 1'b0;
            element_count <= element_count - 'd1;
            write_idx <= write_idx;
            read_idx <= read_idx + 'd1;
        end
        else if (qualified_write) begin
            empty <= 1'b0;
            full <= element_count == NUM_ELEMENTS[ADDRESS_WIDTH:0] - 'd1;
            element_count <= element_count + 'd1;
            write_idx <= write_idx + 'd1;
            read_idx <= read_idx;
        end
        else begin
            empty <= empty;
            full <= full;
            element_count <= element_count;
            write_idx <= write_idx;
            read_idx <= read_idx;
        end
    end
end

// Psuedo Dual Port RAM should be inferred
always_ff @ (posedge clk) begin
    if (qualified_read) begin
        data_out <= mem[read_idx];
        output_valid <= 1'b1;
    end
    else begin
        data_out <= data_out;
        output_valid <= 1'b0;
    end
end
always_ff @ (posedge clk) begin
    if (qualified_write) begin
        mem[write_idx] <= data_in;
    end
    else begin
        mem[write_idx] <= mem[write_idx];
    end
end

endmodule: fifo_ebr