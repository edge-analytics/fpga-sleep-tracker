module rising_edge(
    input logic clk,
    input logic reset,
    input logic i_a,
    output logic o_re_a
);

logic a_delayed;

always_ff @(posedge clk) begin
    if (reset) begin
        o_re_a <= 1'b0;
        a_delayed <= 1'b0;
    end
    else begin
        o_re_a <= i_a & ~a_delayed;
        a_delayed <= i_a;
    end
end

endmodule: rising_edge