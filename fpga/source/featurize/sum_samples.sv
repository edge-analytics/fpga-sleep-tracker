module sum_samples
#(parameter SAMPLES=15)
(
    input logic clk,
    input logic reset,
    input logic [7:0] i_data,
    input logic i_valid,
    output logic [7:0] o_data,
    output logic o_valid
);

logic [$clog2(SAMPLES)-1:0] count;
logic samples_end;
// Overflow is possible, but unlikely given the actigraphy data source
logic [7:0] sum; 

// input data counter relative to num sampless
always_ff @ (posedge clk) begin
     if (reset) begin
        count <= 'd0;
    end
    else begin
        if (samples_end) begin
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

// Sum 
always_ff @ (posedge clk) begin
    if (reset) begin
        sum <= 'd0;
    end
    else begin
        if (i_valid) begin
            if (samples_end) begin
                sum <= i_data;
            end
            else begin
                sum <= sum + i_data;
            end
        end
        else begin
            if (samples_end) begin
                sum <= 'd0;
            end
            else begin
                sum <= sum;
            end
        end
    end
end

assign samples_end = count == SAMPLES - 1;
assign o_valid = samples_end;
assign o_data = o_valid ? sum : 'd0;

endmodule: sum_samples