module actigraphy_counts
import math_pkg::abs_i8;
(
    input logic clk,
    input logic reset,
    input logic signed[7:0] i_z_accel,
    input logic i_valid,
    output logic[7:0] o_count,
    output logic o_valid
);

logic signed[7:0] filtered_data;
logic [7:0] filtered_data_abs, peak, sum, relu_biased_sum;
logic filtered_valid, peak_valid, sum_valid;
logic [15:0] converted_count_data;

// Component instantiations
biquad biquad_x (
    .*,
    .i_data(i_z_accel),
    .i_valid(i_valid),
    .o_data(filtered_data),
    .o_valid(filtered_valid)
);

assign filtered_data_abs = abs_i8(filtered_data);

peak_detect #(.WINDOW_LEN(50)) peak_detect_one_sec(
    .*,
    .i_data(filtered_data_abs),
    .i_valid(filtered_valid),
    .o_data(peak),
    .o_valid(peak_valid)
);

// Output of peak detect occurs once per 50 samples, hence 1Hz output
sum_samples #(.SAMPLES(15)) sum_fifteen_seconds(
    .*,
    .i_data(peak),
    .i_valid(peak_valid),
    .o_data(sum),
    .o_valid(sum_valid)
);

localparam logic[7:0] BIAS = 8'b00010010; // Unsigned 1.7 = 18 counts, 0.141
// The scaling factor is left at 1 currently 
localparam logic[7:0] M = 8'b01000000;    // From paper it should be 3.03 -> 2.424 since +-4g accel range

// Ensure bias application will not result in invalid sum
assign relu_biased_sum = sum > BIAS ? sum - BIAS : 'd0;

// Apply corrections to match Actiwatch counts
always_ff @ (posedge clk) begin
    if (reset) begin
        converted_count_data <= 'd0;
        o_valid <= 1'b0;
    end
    else begin
        if (sum_valid) begin
            converted_count_data <= M * (relu_biased_sum);
            o_valid <= 1'b1;
        end
        else begin
            converted_count_data <= 'd0;
            o_valid <= 1'b0;
        end
    end
end

assign o_count = converted_count_data[13:6]; // I1.7 Output 

endmodule: actigraphy_counts