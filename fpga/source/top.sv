module top
import nn_pkg::*;
//import accel_pkg::*;
(
    input logic clk,
    input logic reset,
    // UART
    input logic rx,
    output logic tx,
    // I2C
    // inout tri i2c2_scl_io, 
    // inout tri i2c2_sda_io

    // Simulate accelerometer for testbench
    input logic signed[7:0] accel_z,
    input logic accel_valid
);

// Comm and Sleep tracker CU signals
logic [7:0] write_data, read_data;
logic write_strobe, read_strobe, read_valid, tx_ready, rx_ready;

// NN signals
logic nn_we, nn_start, nn_done, nn_in_valid, nn_out_valid;
logic[$clog2(MAX_LAYER_DEPTH)-1:0] nn_addr;
logic signed[INPUT_DATA_WIDTH-1:0] nn_din;
logic signed[OUTPUT_DATA_WIDTH-1:0] nn_dout;
logic [7:0] predicted_class;

// Accelerometer signals
//accel_data_t accel_data;
//logic signed [7:0] accel_z;
logic [7:0] count_feature;
//logic accel_valid, count_valid;
//assign accel_z = accel_data.z[11:4];

// Host to target Fifo signals
logic fifo_input_valid, fifo_output_valid, fifo_empty,
fifo_ready_for_input, fifo_ready_for_output;
logic[15:0] fifo_input_data, fifo_output_data;

// UART component instantiation
// Parameters below will create a 115384Hz baud rate with a 6MHz input clock 
// This will incure ~0.16% baud rate error relative to the expected 115200Hz
uart #(.BAUD_DIV(52), .RX_SAMPLE_OFFSET(26)) uart_rs232
(
    .*,
    .rx(rx),
    .tx(tx),
    .write_strobe_i(write_strobe),
    .read_strobe_i(read_strobe),
    .write_data_i(write_data),
    .read_data_o(read_data),
    .read_valid_o(read_valid),
    .tx_ready_o(tx_ready),
    .rx_ready_o(rx_ready)
);

// ~17 hours of recording time at 1 sample per 15 secs
fifo_256k #(.NUM_ELEMENTS(4096)) target_to_host_fifo
(
    .*,
    .input_valid(fifo_input_valid),
    .data_in(fifo_input_data),
    .ready_for_input(fifo_ready_for_input),
    .fifo_empty(fifo_empty),
    .output_valid(fifo_output_valid),
    .data_out(fifo_output_data),
    .ready_for_output(fifo_ready_for_output)
);

// accel_sampler accel_sampler_inst(
//     .*,
//     .accel_data_o(accel_data),
//     .accel_data_valid_o(accel_valid)
// );

actigraphy_counts actigraphy_counts_inst(
    .*,
    .i_z_accel(accel_z),
    .i_valid(accel_valid),
    .o_count(count_feature),
    .o_valid(count_valid)
);

sleep_tracker_cu sleep_tracker_cu_inst(
    .*,
    .write_strobe_o(write_strobe),
    .read_strobe_o(read_strobe),
    .write_data_o(write_data),
    .read_data_i(read_data),
    .read_valid_i(read_valid),
    .tx_ready_i(tx_ready),
    .rx_ready_i(rx_ready),
    .o_nn_addr(nn_addr),
    .o_nn_data(nn_din),
    .o_nn_we(nn_we),
    .o_nn_valid(nn_in_valid),
    .o_nn_start(nn_start),
    .i_nn_done(nn_done),
    .i_nn_data(nn_dout),
    .i_nn_predicted_class(predicted_class),
    .i_nn_valid(nn_out_valid),
    .i_count_feature(count_feature),
    .i_count_valid(count_valid),
    .o_fifo_input_valid(fifo_input_valid),
    .o_fifo_input_data(fifo_input_data),
    .i_fifo_ready_for_input(fifo_ready_for_input),
    .i_fifo_empty(fifo_empty),
    .i_fifo_output_valid(fifo_output_valid),
    .i_fifo_output_data(fifo_output_data),
    .o_fifo_ready_for_output(fifo_ready_for_output)
);

nn mlp(
    .*,
    .i_addr(nn_addr),
    .i_data(nn_din),
    .i_we(nn_we),
    .i_valid(nn_in_valid),
    .i_start(nn_start),
    .o_done(nn_done),
    .o_data(nn_dout),
    .o_predicted_class(predicted_class),
    .o_valid(nn_out_valid)
);

endmodule: top