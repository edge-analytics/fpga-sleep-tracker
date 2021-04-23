module uart
// Parameters below will create a 115384Hz baud rate with a 6MHz input clock 
// This will incure ~0.16% baud rate error relative to the expected 115200Hz
#(
    parameter BAUD_DIV=52,
    parameter RX_SAMPLE_OFFSET=26
)
(
    input logic clk,
    input logic reset,
    // UART Signals
    input logic rx,
    output logic tx,
    // Full duplex no buffer interface
    input logic write_strobe_i,
    input logic read_strobe_i,
    input logic [7:0] write_data_i,
    output logic [7:0] read_data_o,
    output logic read_valid_o,
    output logic tx_ready_o,
    output logic rx_ready_o
);

logic tx_uclk_strobe, rx_uclk_strobe;
logic [5:0] tx_uclk_count, rx_uclk_count;

typedef enum logic [2:0] {
    RX_IDLE,
    RX_WAIT_START_DONE,
    RX_DATA,
    RX_WAIT_STOP,
    RX_WAIT_READ,
    RX_READ_STROBE
} uart_rx_t;

uart_rx_t rx_uart_state, rx_uart_next_state;

typedef enum logic [1:0] {
    TX_IDLE,
    TX_WAIT_START_DONE,
    TX_DATA,
    TX_WAIT_STOP
} uart_tx_t;

uart_tx_t tx_uart_state, tx_uart_next_state;

logic [2:0] rx_sample_count, tx_sample_count;

// RX bit sample counter
always_ff @(posedge clk) begin
    if (reset) begin
        rx_sample_count <= '0;
    end
    else begin
        if (rx_uart_state == RX_DATA) begin
            if (rx_uclk_strobe) begin
                rx_sample_count <= rx_sample_count + 1;
            end
            else begin
                rx_sample_count <= rx_sample_count;
            end
        end
        else begin
            rx_sample_count <= '0;
        end
    end
end

// TX bit sample counter
always_ff @(posedge clk) begin
    if (reset) begin
        tx_sample_count <= '0;
    end
    else begin
        if (tx_uart_state == TX_DATA) begin
            if (tx_uclk_strobe) begin
                tx_sample_count <= tx_sample_count + 1;
            end
            else begin
                tx_sample_count <= tx_sample_count;
            end
        end
        else begin
            tx_sample_count <= '0;
        end
    end
end

// TX UART clock generation
always_ff @(posedge clk) begin
    if (reset) begin
        tx_uclk_count <= '0;
        tx_uclk_strobe <= 1'b0;
    end
    else begin
        if (tx_uart_state != TX_IDLE) begin
            if (tx_uclk_count < BAUD_DIV - 1) begin
                tx_uclk_count <= tx_uclk_count + 1;
                tx_uclk_strobe <= 1'b0;
            end
            else begin
                tx_uclk_count <= '0;
                tx_uclk_strobe <= 1'b1;
            end
        end
        else begin
            tx_uclk_count <= '0;
            tx_uclk_strobe <= 1'b0;
        end
    end
end

// RX UART clock generation
always_ff @(posedge clk) begin
    if (reset) begin
        rx_uclk_count <= '0;
        rx_uclk_strobe <= 1'b0;
    end
    else begin
        if (rx_uart_state != RX_IDLE) begin
            if (rx_uclk_count < BAUD_DIV - 1) begin
                rx_uclk_count <= rx_uclk_count + 1;
                if (rx_uclk_count == RX_SAMPLE_OFFSET) begin
                    rx_uclk_strobe <= 1'b1;
                end
                else begin
                    rx_uclk_strobe <= 1'b0;
                end
            end
            else begin
                rx_uclk_count <= '0;
                rx_uclk_strobe <= 1'b0;
            end
        end
        else begin
            rx_uclk_count <= '0;
            rx_uclk_strobe <= 1'b0;
        end
    end
end

// Current state logic
always_ff @(posedge clk) begin
    if (reset) begin
        rx_uart_state <= RX_IDLE;
    end
    else begin
        rx_uart_state <= rx_uart_next_state;
    end
end

// Next state logic
always_comb begin
    case (rx_uart_state)
        RX_IDLE: begin
            if (~rx) begin
                rx_uart_next_state = RX_WAIT_START_DONE;
            end
            else begin
                rx_uart_next_state = RX_IDLE;
            end
        end
        RX_WAIT_START_DONE: begin
            if (rx_uclk_strobe) begin
                rx_uart_next_state = RX_DATA;
            end
            else begin
                rx_uart_next_state = RX_WAIT_START_DONE;
            end
        end
        RX_DATA: begin
            if (rx_sample_count == 7 && rx_uclk_strobe) begin
                rx_uart_next_state = RX_WAIT_STOP;
            end
            else begin
                rx_uart_next_state = RX_DATA;
            end
        end
        RX_WAIT_STOP: begin
            if (rx) begin
                rx_uart_next_state = RX_WAIT_READ;
            end
            else begin
                rx_uart_next_state = RX_WAIT_STOP;
            end
        end
        RX_WAIT_READ: begin
            if (read_strobe_i) begin
                rx_uart_next_state = RX_READ_STROBE;
            end
            else if (~rx) begin
                rx_uart_next_state = RX_IDLE;
            end
            else begin
                rx_uart_next_state = RX_WAIT_READ;
            end
        end
        RX_READ_STROBE: begin
            rx_uart_next_state = RX_IDLE;
        end
        default: begin
            rx_uart_next_state = RX_IDLE;
        end
    endcase
end

// FSM outputs TX UART
// Next state logic
always_comb begin
    case (rx_uart_state)
        RX_IDLE: begin
            rx_ready_o = 1'b0;
            read_valid_o = 1'b0;
        end
        RX_WAIT_START_DONE: begin
            rx_ready_o = 1'b0;
            read_valid_o = 1'b0;
        end
        RX_DATA: begin
            rx_ready_o = 1'b0;
            read_valid_o = 1'b0;
        end
        RX_WAIT_STOP: begin
            rx_ready_o = 1'b0;
            read_valid_o = 1'b0;
        end
        RX_WAIT_READ: begin
            rx_ready_o = 1'b1;
            read_valid_o = 1'b0;
        end
        RX_READ_STROBE: begin
            rx_ready_o = 1'b0;
            read_valid_o = 1'b1;
        end
        default: begin
            rx_ready_o = 1'b0;
            read_valid_o = 1'b0;
        end
    endcase
end

logic [7:0] rx_data_reg;
logic rx_sync_in;
// Input synchronizer
always_ff @ (posedge clk) begin
    rx_sync_in <= rx;
end

// RX shift register
genvar i;
generate
    for (i=7; i>=0; i--) begin: gen_shift_rx
        always_ff @ (posedge clk) begin
            if (reset) begin
                rx_data_reg[i] <= 1'b1;
            end
            else begin
                if (rx_uart_state == RX_DATA && rx_uclk_strobe) begin
                    if(i==7) begin
                        rx_data_reg[i] <= rx_sync_in;
                    end
                    else begin
                        rx_data_reg[i] <= rx_data_reg[i+1];
                    end
                end
                else begin
                    rx_data_reg[i] <= rx_data_reg[i];
                end
            end
        end
    end
endgenerate

assign read_data_o = read_valid_o ? rx_data_reg: '0;

// Current state logic
always_ff @(posedge clk) begin
    if (reset) begin
        tx_uart_state <= TX_IDLE;
    end
    else begin
        tx_uart_state <= tx_uart_next_state;
    end
end

// Next state logic
always_comb begin
    case (tx_uart_state)
        TX_IDLE: begin
            if (write_strobe_i) begin
                tx_uart_next_state = TX_WAIT_START_DONE;
            end
            else begin
                tx_uart_next_state = TX_IDLE;
            end
        end
        TX_WAIT_START_DONE: begin
            if (tx_uclk_strobe) begin
                tx_uart_next_state = TX_DATA;
            end
            else begin
                 tx_uart_next_state = TX_WAIT_START_DONE;
            end
        end
        TX_DATA: begin
            if (tx_sample_count == 7 && tx_uclk_strobe) begin
                tx_uart_next_state = TX_WAIT_STOP;
            end
            else begin
                 tx_uart_next_state = TX_DATA;
            end
        end
        TX_WAIT_STOP: begin
            if (tx_uclk_strobe) begin
                tx_uart_next_state = TX_IDLE;
            end
            else begin
                 tx_uart_next_state = TX_WAIT_STOP;
            end
        end
        default: begin
            tx_uart_next_state = TX_IDLE;
        end
    endcase
end

logic [7:0] tx_data_reg;
logic tx_comb;
// FSM outputs TX UART
always_comb begin
    case (tx_uart_state)
        TX_IDLE: begin
           tx_ready_o = 1'b1;
           tx_comb = 1'b1;
        end
        TX_WAIT_START_DONE: begin
            tx_ready_o = 1'b0;
            tx_comb = 1'b0;
        end
        TX_DATA: begin
            tx_ready_o = 1'b0;
            tx_comb = tx_data_reg[tx_sample_count];
        end
        TX_WAIT_STOP: begin
            tx_ready_o = 1'b0;
            tx_comb = 1'b1;
        end
        default: begin
            tx_ready_o = 1'b0;
            tx_comb = 1'b0;
        end
    endcase
end

// Register combinatorial output to tx line
always_ff @ (posedge clk) begin
    tx <= tx_comb;
end


// TX bus input data registering block
always_ff @(posedge clk) begin
    if (reset) begin
        tx_data_reg <= '0;
    end
    else begin
        if (write_strobe_i) begin
            tx_data_reg <= write_data_i;
        end
        else begin
            tx_data_reg <= tx_data_reg;
        end
    end
end

endmodule: uart