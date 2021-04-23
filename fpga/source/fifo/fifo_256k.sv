module fifo_256k
#(parameter NUM_ELEMENTS=32)
(
    input logic clk,
    input logic reset,
    input logic input_valid,
    input logic[15:0] data_in,
    output logic ready_for_input,
    output logic fifo_empty,
    output logic output_valid,
    output logic[15:0] data_out,
    input logic ready_for_output
);

localparam ADDRESS_WIDTH = $clog2(NUM_ELEMENTS);
localparam ADDR_PAD = 14 - ADDRESS_WIDTH;
logic [ADDRESS_WIDTH:0] element_count;
logic [ADDRESS_WIDTH-1:0] write_idx, read_idx, addr;
logic empty, full, qualified_write, qualified_read;
logic [15:0] mem_out;

assign qualified_read = ready_for_output & ~empty;
assign qualified_write = input_valid & ~full;
assign ready_for_input = ~full;
assign fifo_empty = empty;

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

//
SP256K fifo_256k_inst (
  .AD       ({{ADDR_PAD{1'b0}}, addr}),     // I, 14-bit address
  .DI       (data_in),  // I, 16-bit write data
  .MASKWE   (4'b1111),  // I, 4-bit nibble mask control
  .WE       (qualified_write), // I, write(H)/read(L) mode select
  .CS       (1'b1),     // I, memory enable
  .CK       (clk),      // I, clock
  .STDBY    (1'b0),     // I, low leakage standby mode
  .SLEEP    (1'b0),     // I, periphery shutdown sleep mode
  .PWROFF_N (1'b1),     // I, no memory retention turn off
  .DO       (mem_out)  // O, 16-bit read data
);

assign addr = qualified_write ? write_idx : read_idx;

// Register output
always_ff @ (posedge clk) begin
    if (qualified_read) begin
        output_valid <= 1'b1;
        data_out <= mem_out;
    end
    else begin
        output_valid <= 1'b0;
        data_out <= data_out;
    end
end

endmodule: fifo_256k