module accel_sampler
import dsoxp_pkg::*;
(
    input logic clk,
    input logic reset,
    inout tri i2c2_scl_io, 
    inout tri i2c2_sda_io,
    output accel_data_t accel_data_o,
    output logic accel_data_valid_o
);

parameter logic unsigned[16:0] SAMPLE_COUNT_50HZ = 17'd120_000; // Assumes 6MHz clk
// LIS2D Address
localparam logic [6:0] LIS2D = 7'b0011101;
localparam logic [7:0] WHO_AM_I = 8'h0F;
localparam logic [7:0] ACCEL_OUT_BASE = 8'h28;
localparam logic [7:0] CTRL_1_ADDR = 8'h20;
localparam logic [7:0] CTRL_2_ADDR = 8'h21;
// LIS2D Default Values
localparam logic [7:0] CTRL_1_VAL = 8'b1011_1001; // 50Hz, 10bit, LP, cont
localparam logic [7:0] CTRL_2_VAL = 8'b0000_0100; // auto inc
// SB I2C Key Register Addresses
localparam logic [7:0] TXDR = 8'b0001_1101;
localparam logic [7:0] RXDR = 8'b0001_1110;
localparam logic [7:0] CMDR = 8'b0001_1001;
localparam logic [7:0] CSR  = 8'b0001_1100;
localparam logic [7:0] DONT_CARE = 8'b0000_0000;
// SB I2C related commands and subfields
localparam logic [7:0] SB_I2C_START = 8'b1001_0100;
localparam logic [7:0] SB_I2C_WRITE = 8'b0001_0100;
localparam logic [7:0] SB_I2C_STOP = 8'h44;
localparam logic [7:0] SB_I2C_READ_SLAVE_NO_STRETCH = 8'h24;
localparam logic [7:0] SB_I2C_NACK_STOP = 8'h6C;
localparam logic WRITE = 1'b0;
localparam logic READ = 1'b1;
localparam int TRRDY_BIT = 2; // FIXME this should be a smaller value
localparam byte BUS_BUSY_BIT = 6;
localparam int SRW_BIT = 4;
localparam byte WAIT_LONG_CYCLES = 8'd250; // Assumes 6MHz top clk and 50KHz scl
// SB variables
logic ipload_i, ipdone_o, sb_wr_i, sb_stb_i, sb_ack_o;
logic [7:0] sb_adr_i, sb_dat_i, sb_dat_o, reset_counter = 0;    
logic [1:0] i2c_pirq_o, i2c_pwkup_o;
// SB enums
typedef enum logic[1:0] {SB_READ_REQ, SB_WRITE_REQ, SB_NOP} sb_request_t;
typedef enum logic[1:0] {
    SB_IDLE, 
    SB_ASSERT, 
    SB_WAIT_ACK
}sb_state_t;
sb_request_t sb_request;
sb_state_t sb_state, sb_next_state;

// SB I2C LIS2D Read Register States 
typedef enum logic [4:0] {
    POR_INIT, 
    IDLE, 
    // SET CTRL 1 & CTRL 2 VALUES
    CFG_START_WRITE_CTRL_X_ADDR,
    CFG_START_WRITE_CTRL_X_CMD,
    CFG_WAIT_TRRDY_CTRL_X_ADDR, 
    CFG_WRITE_CTRL_X_ADDR,
    CFG_WRITE_CTRL_X_ADDR_CMD,
    CFG_WAIT_TRRDY_CTRL_X_VAL, 
    CFG_WRITE_CTRL_X_VAL,
    CFG_WRITE_CTRL_X_VAL_CMD,
    CFG_WAIT_TRRDY_CTRL_X_STOP,
    CFG_WRITE_CTRL_X_STOP_CMD, // CMDR = 0x44
    CFG_CHECK_BUSY,
    // SAMPLE ACCELEROMETER REGISTERS
    START_WRITE_ADDR,
    START_WRITE_CMD, 
    WAIT_TRRDY_SUB, 
    WRITE_SUB_ADDR,
    WRITE_SUB_CMD,
    WAIT_TRRDY_REPEAT,
    REPEAT_START_READ_ADDR,
    REPEAT_START_READ_CMD,
    WAIT_SRW,
    INDICATE_SLAVE_READ,
    WAIT_TRRDY_READ_PRIME,
    READ_DATA_PRIME,
    WAIT_LONG,
    NACK_STOP,
    WAIT_TRRDY_READ,
    READ_DATA
} i2c_cmd;

typedef enum logic[2:0] {
    X_LSB = 3'd0,
    X_MSB = 3'd1,
    Y_LSB = 3'd2,
    Y_MSB = 3'd3,
    Z_LSB = 3'd4,
    Z_MSB = 3'd5
} accel_byte_label_t;

accel_byte_label_t accel_byte_label;

i2c_cmd i2c_state, i2c_next_state;

// Counter variables
logic unsigned [16:0] sample_counter = 0;
logic capture_new_sample;
byte i2c_wait_counter = 8'd0;

// Module instantiation
i2c sb_i2c(
    .*,
    .rst_i(reset), 
    .sb_clk_i(clk)
);

typedef enum logic[1:0] {
    CFG_CTRL_1 = 2'd0,
    CFG_CTRL_2 = 2'd1
}cfg_label_t;

typedef struct packed{
    logic [7:0] addr;
    logic [7:0] val;
}reg_t;

reg_t cfg_regmap [2];

// Hopefully Radiant supports arrays of structs with an init block!
initial begin
    cfg_regmap[CFG_CTRL_1] = '{addr: CTRL_1_ADDR, val: CTRL_1_VAL};
    cfg_regmap[CFG_CTRL_2] = '{addr: CTRL_2_ADDR, val: CTRL_2_VAL};
end

// Control of startup control register write events
cfg_label_t cfg_label;
always_ff @ (posedge clk) begin
    if (reset) begin
        cfg_label <= CFG_CTRL_1;
    end
    else begin
        if (i2c_state == START_WRITE_ADDR) begin
            cfg_label <= cfg_label.last;  // Latch this state to prevent updates
        end
        else if (i2c_state == CFG_CHECK_BUSY 
            && sb_ack_o && ~sb_dat_o[BUS_BUSY_BIT]) begin
            cfg_label <= cfg_label.next;
        end
        else begin
            cfg_label <= cfg_label;
        end
    end
end

// Incrementing logic for what byte to serialize the acceleration data struct
always_ff @ (posedge clk) begin
    if (reset) begin
        accel_byte_label <= X_LSB;
    end
    else begin
        if (i2c_state == READ_DATA_PRIME && sb_ack_o) begin
            accel_byte_label <= accel_byte_label.next;
        end
        else begin
            accel_byte_label <= accel_byte_label;
        end
    end
end

//======================== Sample Strobe Generation ============================
always_ff @ (posedge clk) begin
    if (reset || ~ipdone_o) begin
        sample_counter <= 'd0;
        capture_new_sample <= 1'b0;
    end
    else begin
        if (sample_counter < SAMPLE_COUNT_50HZ) begin
            sample_counter <= sample_counter + 'd1;
            capture_new_sample <= 1'b0;
        end
        else begin
            sample_counter <= 0;
            capture_new_sample <= 1'b1;
        end
    end
end

//====================== System Bus I2C Control Block ==========================

// ipload_i: Soft IP input to start configuration of the IP at POR
// ipload_o: Soft IP output indicating when configuration is complete
// rst_i: System active high reset 
// sb_clk_i: System Bus (SB) clock source
// sb_wr_i: Read/write control signal. Low is read, High is write for SB 
// sb_stb_i: Active high strobe indicating slave is target for SB transaction
// sb_ack_o: Active high transfer ack asserted by IP indicating request received
// sb_adr_i: SB control registers address 
// sb_dat_i: SB data input
// sb_dat_o: SB data output
// i2c_pirq_o: Interrupt request output, intended to be connected to Master 
// i2c_pwkup_o: Wake up signal if the feature is set

//============================= SB Write Cycle ================================
// Clock Edge    0         1         2
//                ____      ____      ____
// sb_clk_i  ____|    |____|    |____|    |____
//                ________________________
// sb_stb_i  ____|                        |____
//                ________________________
// sb_wr_i   ____|                        |____
//           ____ ________________________ ____
// sb_adr_i  ____/________________________\____
//           ____ ________________________ ____
// sb_dat_i  ____/________________________\____
//           _____________________________ ____
// sb_dat_o  ___________don't care_____________
//                                 _____
// sb_ack_o  _____________________|     |______
//
// Summary: On clock edge 0, master updates the address, data, and asserts
// control signals sb_stb_i and sb_wr_i=1 to indicate a write. On edge 1, the
// master maintains these values and the slave decodes the address. On edge 2,
// or greater the slave latches sb_dat_i and then the master needs to deassert 
// sb_stb_i and sb_wr_i

//============================= SB Read Cycle ================================
// Clock Edge    0         1         2
//                ____      ____      ____
// sb_clk_i  ____|    |____|    |____|    |____
//                ________________________
// sb_stb_i  ____|                        |____
//                
// sb_wr_i   __________________________________
//           ____ ________________________ ____
// sb_adr_i  ____/________________________\____
//           ____ ________________________ ____
// sb_dat_i  ___________don't care_____________
//           _____________________ _____ ______
// sb_dat_o  _____________________/_____\_______
//                                 _____
// sb_ack_o  _____________________|     |______
//
// Summary: On clock edge 0, master updates the address asserts
// control signals sb_stb_i and sb_wr_i=0 to indicate a read. On edge 1, the
// master maintains these values and the slave decodes the address. On edge 2,
// or greater the slave outputs sb_dat_o and then the master needs to deassert 
// sb_stb_i. The slave will deassert sb_ack_o once the sb_stb_i is deasserted.

//=========================== SB I2C Key Registers =============================
// Name         |  Address  |     Function   
//------------------------------------------------------------------------------          
// I2CCMDR      |  0001     | I2C command register
//  ___________________________________________________________
// | Bit7 | Bit6 | Bit5 | Bit4 | Bit 3 | Bit2 | Bit1  | Bit 0  |
//  -----------------------------------------------------------
// | STA  | STO  | RD   | WR   | ACK   |CKSDIS|RBUFDIS|RESERVED|
//  -----------------------------------------------------------
// STA:     Generate Start or repeated start condition, default 0
// STO:     Generate Stop condition 
// RD:      Indicate read from slave
// WR:      Indicate write to slave
// ACK:     Acknowledge - when receiving 0: send ACK, 1: send NACK
// CKSDIS:  Clock stretching disable: 0: enable clock stretching, 1: disable
// RBUFDIS: Read command with buffer disable, 0: read with buffer, 1: no buffer
// _____________________________________________________________________________
// I2CCSR      |  1011     | I2C status register
//  ___________________________________________________________
// | Bit7 | Bit6 | Bit5 | Bit4 | Bit 3 | Bit2 | Bit1  | Bit 0  |
//  -----------------------------------------------------------
// | TIP  | BUSY | RARC | SRW  | ARBL  |TRRDY | TROE  | HGC    |
//  -----------------------------------------------------------
// TIP:     Transmit byte in progress - 0: completed transfer, 1: in progress
// BUSY:    Bus busy - 1: after start command, 0: after stop
// RARC:    Receive acknowledged - 0: no acknowledge, 1: acknowledge received
// SRW:     Slave RW - 0: Master transmitting slave receiving, 1: opposite
// ARBL:    Arbitration lost - 0: normal, 1 arbitration lost
// TRRDY:   Transmit or recv ready - 0 Transmitter or recv not ready, 1 ready
// TROE:    Transmitter or recv overrun or nack - 0 normal, 1- overrun or nack
// HGC:     Hardware general call (only relevant for slave mode)
// _____________________________________________________________________________
// I2CTXDR      |  1000     | I2C transmit data register
//  ___________________________________________________________
// | Bit7 | Bit6 | Bit5 | Bit4 | Bit 3 | Bit2 | Bit1  | Bit 0  |
//  -----------------------------------------------------------
// |                    Transmit Data[7:0]                     |
//  -----------------------------------------------------------
// Transmit Data[7:0]: When transmitting slave address Bit 0 is the R/W bit
// _____________________________________________________________________________
// I2CRXDR      |  1001     | I2C receive data register
//  ___________________________________________________________
// | Bit7 | Bit6 | Bit5 | Bit4 | Bit 3 | Bit2 | Bit1  | Bit 0  |
//  -----------------------------------------------------------
// |                    Receive Data[7:0]                     |
//  -----------------------------------------------------------
// Receive Data[7:0]: Received data from slave. Bit 0 is the last bit received

//========================= LIS2DS I2C Information =============================
// SAD: Slave address is 0011101 since SA0 DSO pin is connected to VCC
//      SAD + R/W Patterns => I2C read: 00111011, I2C write 00111010
// ST: Start condition
// SR: Repeated start
// SP: Stop condition
// SUB: Sub register address
// SAK: Slave acknowledge
// MAK: Master acknowledge
// NMAK: No Master acknowledge

//====================== LIS2DS I2C Read Single Byte ===========================
// _____________________________________________________________________________
// Master | ST | SAD + W |     | SUB |     | SR | SAD + R |   |    | NMAK | SP |
// -----------------------------------------------------------------------------
// Slave  |    |         | SAK |     | SAK |    |         |SAK|DATA|      |    |
// ----------------------------------------------------------------------------- 
//=============== SM BUS Transactions for LIS2DS Single Read ===================
//
// START 
// TXDR <= I2C ADDR + "W"
// CMDR <= 0x94 (STA + WR)
// 0x94 = 0b1001_0100 = Generate Start, Write, and disable clock stretching
//
// Wait for TRRDY, could check for ack (not mvp)
// 
// TXDR <= SUB
// CMDR <= 0x14
//
// Wait for TRRDY, could check for ack (not mvp)
//
// TXDR <= I2C ADDR + "R"
// CMDR <= 0x94 (STA + WR)
//
// Wait for SRW - Master receiving slave transmitting
// 
// CMDR <= 0x24 - indicate read from slave, no clock stretching
//
// Wait for TRRDY
// 
// READ_DATA <= RXDR, first read data to push data into the double register
//
// Wait 2-7 cycles
// 
// CMDR <= 0x6C - (RD NACK STOP)
//
// Wait for TRRDY
//
// READ_DATA <= RXDR
// 
// Wait for next sample strobe, then repeat

//====================== LIS2DS I2C Write Single Byte ==========================
// _____________________________________________________________________________
// Master | ST | SAD + W |     | SUB |     | DATA |     | SP |
// -----------------------------------------------------------------------------
// Slave  |    |         | SAK |     | SAK |      | SAK |    |
// ----------------------------------------------------------------------------- 

//====================== LIS2DS I2C Read Multiple Bytes ========================
// _____________________________________________________________________________
// Master | ST | SAD + W |   |SUB|     |SR|SAD + R|   |    |MAK|    |...|MAK|SP|
// -----------------------------------------------------------------------------
// Slave  |    |         |SAK|   | SAK |  |       |SAK|DATA|   |DATA|...|   |  |
// ----------------------------------------------------------------------------- 

assign ipload_i = 1'b0; // Do not change the sb i2c module after boot

// Current state logic
always_ff @ (posedge clk) begin
    if (reset) begin 
        i2c_state <= POR_INIT;
    end
    else begin
        i2c_state <= i2c_next_state;
    end
end

// Next state logic
always_comb begin
    case (i2c_state)
        POR_INIT: begin
            if (ipdone_o) begin
                i2c_next_state = IDLE;
            end
            else begin
                i2c_next_state = POR_INIT;
            end
        end
        IDLE: begin
            if (capture_new_sample) begin
                // Only perform configuration once
                if (cfg_label == cfg_label.last) begin
                    i2c_next_state = START_WRITE_ADDR;
                end
                else begin
                    i2c_next_state = CFG_START_WRITE_CTRL_X_ADDR;
                end
            end
            else begin
                i2c_next_state = IDLE;
            end
        end
        // Set CTRL 1
        CFG_START_WRITE_CTRL_X_ADDR: begin
            if (sb_ack_o) begin
                i2c_next_state = CFG_START_WRITE_CTRL_X_CMD;
            end
            else begin
                i2c_next_state = CFG_START_WRITE_CTRL_X_ADDR;
            end
        end
        CFG_START_WRITE_CTRL_X_CMD: begin
            if (sb_ack_o) begin
                i2c_next_state = CFG_WAIT_TRRDY_CTRL_X_ADDR;
            end
            else begin
                i2c_next_state = CFG_START_WRITE_CTRL_X_CMD;
            end
        end
        CFG_WAIT_TRRDY_CTRL_X_ADDR: begin
            if (sb_ack_o && sb_dat_o[TRRDY_BIT]) begin
                i2c_next_state = CFG_WRITE_CTRL_X_ADDR;
            end
            else begin
                i2c_next_state = CFG_WAIT_TRRDY_CTRL_X_ADDR;
            end
        end
        CFG_WRITE_CTRL_X_ADDR: begin
            if (sb_ack_o) begin
                i2c_next_state = CFG_WRITE_CTRL_X_ADDR_CMD;
            end
            else begin
                i2c_next_state = CFG_WRITE_CTRL_X_ADDR;
            end
        end
        CFG_WRITE_CTRL_X_ADDR_CMD: begin
            if (sb_ack_o) begin
                i2c_next_state = CFG_WAIT_TRRDY_CTRL_X_VAL;
            end
            else begin
                i2c_next_state = CFG_WRITE_CTRL_X_ADDR_CMD;
            end
        end
        CFG_WAIT_TRRDY_CTRL_X_VAL: begin
            if (sb_ack_o && sb_dat_o[TRRDY_BIT]) begin
                i2c_next_state = CFG_WRITE_CTRL_X_VAL;
            end
            else begin
                i2c_next_state = CFG_WAIT_TRRDY_CTRL_X_VAL;
            end
        end
        CFG_WRITE_CTRL_X_VAL: begin
            if (sb_ack_o) begin
                i2c_next_state = CFG_WRITE_CTRL_X_VAL_CMD;
            end
            else begin
                i2c_next_state = CFG_WRITE_CTRL_X_VAL;
            end
        end
        CFG_WRITE_CTRL_X_VAL_CMD: begin
            if (sb_ack_o) begin
                i2c_next_state = CFG_WAIT_TRRDY_CTRL_X_STOP;
            end
            else begin
                i2c_next_state = CFG_WRITE_CTRL_X_VAL_CMD;
            end
        end
        CFG_WAIT_TRRDY_CTRL_X_STOP: begin
            if (sb_ack_o && sb_dat_o[TRRDY_BIT]) begin  
                i2c_next_state = CFG_WRITE_CTRL_X_STOP_CMD;
            end
            else begin
                i2c_next_state = CFG_WAIT_TRRDY_CTRL_X_STOP;
            end
        end
        CFG_WRITE_CTRL_X_STOP_CMD: begin
            if (sb_ack_o) begin
                i2c_next_state = CFG_CHECK_BUSY;
            end
            else begin
                i2c_next_state = CFG_WRITE_CTRL_X_STOP_CMD;
            end
        end
        CFG_CHECK_BUSY: begin
            if (sb_ack_o && ~sb_dat_o[BUS_BUSY_BIT]) begin
                if (cfg_label == cfg_label.last) begin
                    i2c_next_state = START_WRITE_ADDR;
                end
                else begin
                    i2c_next_state = CFG_START_WRITE_CTRL_X_ADDR;
                end
            end
            else begin
                i2c_next_state = CFG_CHECK_BUSY;
            end
        end
        START_WRITE_ADDR: begin
            if (sb_ack_o) begin
                i2c_next_state = START_WRITE_CMD;
            end
            else begin
                i2c_next_state = START_WRITE_ADDR;
            end
        end
        START_WRITE_CMD: begin
            if (sb_ack_o) begin
                i2c_next_state = WAIT_TRRDY_SUB;
            end
            else begin
                i2c_next_state = START_WRITE_CMD;
            end
        end
        WAIT_TRRDY_SUB: begin
            if (sb_ack_o && sb_dat_o[TRRDY_BIT]) begin
                i2c_next_state = WRITE_SUB_ADDR;
            end
            else begin
                i2c_next_state = WAIT_TRRDY_SUB;
            end
        end
        WRITE_SUB_ADDR: begin
            if (sb_ack_o) begin
                i2c_next_state = WRITE_SUB_CMD;
            end
            else begin
                i2c_next_state = WRITE_SUB_ADDR;
            end
        end
        WRITE_SUB_CMD: begin
            if (sb_ack_o) begin
                i2c_next_state = WAIT_TRRDY_REPEAT;
            end
            else begin
                i2c_next_state = WRITE_SUB_CMD;
            end
        end
        WAIT_TRRDY_REPEAT: begin
            if (sb_ack_o && sb_dat_o[TRRDY_BIT]) begin
                i2c_next_state = REPEAT_START_READ_ADDR;
            end
            else begin
                i2c_next_state = WAIT_TRRDY_REPEAT;
            end
        end
        REPEAT_START_READ_ADDR: begin
            if (sb_ack_o) begin
                i2c_next_state = REPEAT_START_READ_CMD;
            end
            else begin
                i2c_next_state = REPEAT_START_READ_ADDR;
            end
        end
        REPEAT_START_READ_CMD: begin
            if (sb_ack_o) begin
                i2c_next_state = WAIT_SRW;
            end
            else begin
                i2c_next_state = REPEAT_START_READ_CMD;
            end
        end
        WAIT_SRW: begin
            if (sb_ack_o && sb_dat_o[SRW_BIT]) begin
                i2c_next_state = INDICATE_SLAVE_READ;
            end
            else begin
                i2c_next_state = WAIT_SRW;
            end
        end
        INDICATE_SLAVE_READ: begin
            if (sb_ack_o) begin
                i2c_next_state = WAIT_TRRDY_READ_PRIME;
            end
            else begin
                i2c_next_state = INDICATE_SLAVE_READ;
            end
        end
        WAIT_TRRDY_READ_PRIME: begin
            if (sb_ack_o && sb_dat_o[TRRDY_BIT]) begin
                i2c_next_state = READ_DATA_PRIME;
            end
            else begin
                i2c_next_state = WAIT_TRRDY_READ_PRIME;
            end
        end
        READ_DATA_PRIME:begin
            if (sb_ack_o) begin
                if (accel_byte_label == accel_byte_label.last) begin
                    i2c_next_state = WAIT_LONG;
                end
                else begin
                    i2c_next_state = WAIT_TRRDY_READ_PRIME;
                end
            end
            else begin
                i2c_next_state = READ_DATA_PRIME;
            end
        end
        WAIT_LONG: begin
            if (i2c_wait_counter == WAIT_LONG_CYCLES) begin
                i2c_next_state = NACK_STOP;
            end
            else begin
                i2c_next_state = WAIT_LONG;
            end
        end
        NACK_STOP: begin
            if (sb_ack_o) begin
                i2c_next_state = WAIT_TRRDY_READ;
            end
            else begin
                i2c_next_state = NACK_STOP;
            end
        end
        WAIT_TRRDY_READ: begin
            if (sb_ack_o && sb_dat_o[TRRDY_BIT]) begin
                i2c_next_state = READ_DATA;
            end
            else begin
                i2c_next_state = WAIT_TRRDY_READ;
            end
        end
        READ_DATA: begin
            if (sb_ack_o) begin
                i2c_next_state = IDLE;
            end
            else begin
                i2c_next_state = READ_DATA; 
            end
        end
        default: begin
            i2c_next_state = IDLE;
        end
    endcase
end

// FSM outputs
always_comb begin
    case (i2c_state)
        POR_INIT: begin
            sb_adr_i = DONT_CARE;
            sb_dat_i = DONT_CARE;
            sb_request = SB_NOP;
        end
        IDLE: begin
            sb_adr_i = DONT_CARE;
            sb_dat_i = DONT_CARE;
            sb_request = SB_NOP;
        end
        CFG_START_WRITE_CTRL_X_ADDR: begin
            sb_adr_i = TXDR;
            sb_dat_i = {LIS2D, WRITE};
            sb_request = SB_WRITE_REQ;
        end
        CFG_START_WRITE_CTRL_X_CMD: begin
            sb_adr_i = CMDR;
            sb_dat_i = SB_I2C_START;
            sb_request = SB_WRITE_REQ;
        end
        CFG_WAIT_TRRDY_CTRL_X_ADDR: begin
            sb_adr_i = CSR;
            sb_dat_i = DONT_CARE;
            sb_request = SB_READ_REQ;
        end
        CFG_WRITE_CTRL_X_ADDR: begin
            sb_adr_i = TXDR;
            sb_dat_i = cfg_regmap[cfg_label].addr;
            sb_request = SB_WRITE_REQ;
        end
        CFG_WRITE_CTRL_X_ADDR_CMD: begin
            sb_adr_i = CMDR;
            sb_dat_i = SB_I2C_WRITE;
            sb_request = SB_WRITE_REQ;
        end
        CFG_WAIT_TRRDY_CTRL_X_VAL: begin
            sb_adr_i = CSR;
            sb_dat_i = DONT_CARE;
            sb_request = SB_READ_REQ;
        end
        CFG_WRITE_CTRL_X_VAL: begin
            sb_adr_i = TXDR;
            sb_dat_i = cfg_regmap[cfg_label].val;
            sb_request = SB_WRITE_REQ;
        end
        CFG_WRITE_CTRL_X_VAL_CMD: begin
            sb_adr_i = CMDR;
            sb_dat_i = SB_I2C_WRITE;
            sb_request = SB_WRITE_REQ;
        end
        CFG_WAIT_TRRDY_CTRL_X_STOP: begin
            sb_adr_i = CSR;
            sb_dat_i = DONT_CARE;
            sb_request = SB_READ_REQ;
        end
        CFG_WRITE_CTRL_X_STOP_CMD: begin
            sb_adr_i = CMDR;
            sb_dat_i = SB_I2C_STOP;
            sb_request = SB_WRITE_REQ;
        end
        CFG_CHECK_BUSY: begin
            sb_adr_i = CSR;
            sb_dat_i = DONT_CARE;
            sb_request = SB_READ_REQ;
        end
        START_WRITE_ADDR: begin
            sb_adr_i = TXDR;
            sb_dat_i = {LIS2D, WRITE};
            sb_request = SB_WRITE_REQ;
        end
        START_WRITE_CMD: begin
            sb_adr_i = CMDR;
            sb_dat_i = SB_I2C_START;
            sb_request = SB_WRITE_REQ;
        end
        WAIT_TRRDY_SUB: begin
            sb_adr_i = CSR;
            sb_dat_i = DONT_CARE;
            sb_request = SB_READ_REQ;
        end
        WRITE_SUB_ADDR: begin
            sb_adr_i = TXDR;
            sb_dat_i = ACCEL_OUT_BASE;
            sb_request = SB_WRITE_REQ;
        end
        WRITE_SUB_CMD: begin
            sb_adr_i = CMDR;
            sb_dat_i = SB_I2C_WRITE;
            sb_request = SB_WRITE_REQ;
        end
        WAIT_TRRDY_REPEAT: begin
            sb_adr_i = CSR;
            sb_dat_i = DONT_CARE;
            sb_request = SB_READ_REQ;
        end
        REPEAT_START_READ_ADDR: begin
            sb_adr_i = TXDR;
            sb_dat_i = {LIS2D, READ};  
            sb_request = SB_WRITE_REQ;   
        end     
        REPEAT_START_READ_CMD: begin
            sb_adr_i = CMDR;
            sb_dat_i = SB_I2C_START;
            sb_request = SB_WRITE_REQ;
        end        
        WAIT_SRW: begin
            sb_adr_i = CSR;
            sb_dat_i = DONT_CARE;
            sb_request = SB_READ_REQ;
        end           
        INDICATE_SLAVE_READ: begin
            sb_adr_i = CMDR;
            sb_dat_i = SB_I2C_READ_SLAVE_NO_STRETCH;
            sb_request = SB_WRITE_REQ;
        end
        WAIT_TRRDY_READ_PRIME: begin
            sb_adr_i = CSR;
            sb_dat_i = DONT_CARE;
            sb_request = SB_READ_REQ;
        end
        READ_DATA_PRIME:begin
            sb_adr_i = RXDR;
            sb_dat_i = DONT_CARE;
            sb_request = SB_READ_REQ;
        end
        WAIT_LONG: begin
            sb_adr_i = DONT_CARE;
            sb_dat_i = DONT_CARE;
            sb_request = SB_NOP;
        end
        NACK_STOP: begin
            sb_adr_i = CMDR;
            sb_dat_i = SB_I2C_NACK_STOP;
            sb_request = SB_WRITE_REQ;
        end
        WAIT_TRRDY_READ: begin
            sb_adr_i = CSR;
            sb_dat_i = DONT_CARE;
            sb_request = SB_READ_REQ;
        end
        READ_DATA: begin
            sb_adr_i = RXDR;
            sb_dat_i = DONT_CARE;
            sb_request = SB_READ_REQ;
        end
        default: begin
            sb_adr_i = DONT_CARE;
            sb_dat_i = DONT_CARE;
            sb_request = SB_NOP;
        end    
    endcase
end

// I2C long wait counter
always_ff @ (posedge clk) begin
    if (reset || i2c_state != WAIT_LONG) begin
        i2c_wait_counter <= '0;
    end
    else begin
        i2c_wait_counter <= i2c_wait_counter + 1;
    end
end

// Current state logic for system bus controller
always_ff @ (posedge clk) begin
    if (reset) begin
        sb_state <= SB_IDLE;
    end
    else begin
        sb_state <= sb_next_state;
    end
end

// Next state logic for system bus
always_comb begin
    case (sb_state)
        SB_IDLE: begin
            if (~sb_ack_o && (sb_request != SB_NOP)) begin
                sb_next_state = SB_ASSERT;
            end
            else begin
                sb_next_state = SB_IDLE;
            end
        end
        SB_ASSERT: begin
            sb_next_state = SB_WAIT_ACK;
        end
        SB_WAIT_ACK: begin
            if(sb_ack_o) begin
                sb_next_state = SB_IDLE;
            end
            else begin // TODO consider adding a timeout check for sb_ack_o
                sb_next_state = SB_WAIT_ACK;
            end
        end
        default: begin
            sb_next_state = SB_IDLE;
        end
    endcase
end

// FSM outputs system bus
always_comb begin
    case (sb_state)
        SB_IDLE: begin
            sb_stb_i = 1'b0;
            sb_wr_i = 1'b0;
        end
        SB_ASSERT: begin
            if (sb_request == SB_WRITE_REQ) begin
                sb_wr_i = 1'b1;
            end
            else begin
                sb_wr_i = 1'b0;
            end
            sb_stb_i = 1'b1;
        end
        SB_WAIT_ACK: begin
            sb_wr_i = sb_wr_i;
            sb_stb_i = 1'b1;
        end
        default: begin
            sb_stb_i = 1'b0;
            sb_wr_i = 1'b0;
        end
    endcase
end

// Accelerometer data packing and output management
accel_data_t accel_data;

always_ff @ (posedge clk) begin
    if (reset) begin
        accel_data <= '0;
    end
    else begin
        if (i2c_state == READ_DATA_PRIME && sb_ack_o) begin
            case (accel_byte_label)
                X_LSB: begin
                    accel_data.x <= {accel_data.x[15:8], sb_dat_o};
                    accel_data.y <= accel_data.y;
                    accel_data.z <= accel_data.z;
                end
                X_MSB: begin
                    accel_data.x <= {sb_dat_o, accel_data.x[7:0]};
                    accel_data.y <= accel_data.y;
                    accel_data.z <= accel_data.z;
                end
                Y_LSB: begin
                    accel_data.x <= accel_data.x;
                    accel_data.y <= {accel_data.y[15:8], sb_dat_o};
                    accel_data.z <= accel_data.z;
                end
                Y_MSB: begin
                    accel_data.x <= accel_data.x;
                    accel_data.y <= {sb_dat_o, accel_data.y[7:0]};
                    accel_data.z <= accel_data.z;
                end
                Z_LSB: begin
                    accel_data.x <= accel_data.x;
                    accel_data.y <= accel_data.y;
                    accel_data.z <= {accel_data.z[15:8], sb_dat_o};
                end
                Z_MSB: begin
                    accel_data.x <= accel_data.x;
                    accel_data.y <= accel_data.y;
                    accel_data.z <= {sb_dat_o, accel_data.z[7:0]};
                end
                default: begin
                    accel_data <= accel_data;
                end
            endcase
        end
        else begin
            accel_data <= accel_data;
        end
    end
end

// Make want to register these outputs
assign accel_data_valid_o = i2c_state == READ_DATA && sb_ack_o;
assign accel_data_o = accel_data_valid_o ? accel_data: '0;
        
endmodule: accel_sampler