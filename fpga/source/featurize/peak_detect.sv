module peak_detect
#(parameter WINDOW_LEN=50)
(
    input logic clk,
    input logic reset,
    input logic [7:0] i_data,
    input logic i_valid,
    output logic [7:0] o_data,
    output logic o_valid
);

logic [$clog2(WINDOW_LEN)-1:0] count;
logic window_end;
logic [7:0] peak;

// input data counter relative to window length
always_ff @ (posedge clk) begin
     if (reset) begin
        count <= 'd0;
    end
    else begin
        if (window_end) begin
            count <= 'd0;
        end
        else begin
            if (i_valid) begin
                count <= count + 'd1;
            end
            else begin
                count <= count;
            end
        end
    end
end

// Peak detect update
always_ff @ (posedge clk) begin
    if (reset) begin
        peak <= 'd0;
    end
    else begin
        if (i_valid) begin
            if (i_data > peak || window_end) begin
                peak <= i_data;
            end
            else begin
                peak <= peak;
            end
        end
        else begin
            if (window_end) begin
                peak <= 'd0;
            end
            else begin
                peak <= peak;
            end
        end
    end
end

assign window_end = count == WINDOW_LEN - 1;
assign o_valid = window_end;
assign o_data = o_valid ? peak : 'd0;

endmodule: peak_detect