# Sleep Tracker FPGA implementation
TBD

## Sleep Tracker FPGA Block Diagram
TBD

### NN Block Diagram
TBD

![NN Memory Organization](doc/img/memory_org.png)



### Verilator Cocotb Requirements
Verilator can typically be installed on macosx with the following command

```brew install verilator```

Currently cocotb version v1.5.1 was hanging with verilator versions > v4.106

### Modelsim Cocotb Requirements

Modelsim must use a 32bit arch with cocotb.

Ubuntu conda 32 bit env creation steps: 
```
conda create -n py3_32
conda activate py3_32
conda config --env --set subdir linux-32
conda install python=3 gxx_linux-32
pip install cocotb
```

## Pinouts
### HW-USBN-2B Pinout
![HW-USBN-2B Pinout](doc/img/usbn_pinout.png)

### iCE40 UltraPlus Mobile Development Pinout - FPGA C
![iCE40 MDP Pinout](doc/img/ice40_mobile_fpga_c.png)  
&nbsp;

### Suggested JTAG Pin Mapping
| USBN  | MDP J32       | ICE40 PIN  | ICE40 Net  | Wire Color |
| ----- | ------------- | ---------- | ---------- | ---------- |
| VCC   | 2: VCC        | NA         | NA         | Red        |
| TDO   | 15: SPARE_C4  | E4         | TDO        | Brown      |
| TDI   | 14: SPARE_C0  | C3         | TDI        | Orange     |
| TMS   | 16: SPARE_C1  | B1         | TMS        | Purple     |
| TCK   | 22: SPARE_C3  | F4         | TCLK       | White      |
| GND   | 24: GND       | NA         | NA         | Black      |  
&nbsp;

## JTAG FPGA Clock
6MHz clock will work with appropriate JTAG clock constraints as below  
&nbsp;
## Contraints File Additions
Need to constrain the JTAG clock and set false paths as such: 
&nbsp;
```
create_clock -name {mytck} -period 366.3003663 [get_ports JTAG_TCK]
create_clock -name {clk} -period 166.6666667 [get_pins OSCInst0/CLKHF] 
set_false_path -from {mytck} -to {clk}
set_false_path -from {clk} -to {mytck}
```

## Reveal Module Insertion
TODO

## Running Reveal Session
1. Compile and export bin file in radiant
2. Open Reveal Analyzer Startup Wizard
- Create a new file
- Detect USB Port
  - Select LATTICE HW-USBN-2B CH A Location 2
- Select RVL source 


## UART Pin Constraints

The mobile development platform has a FT223H USB to uart chip. Based on the mapping
on the PCB the UART_RX_C next should be used to connect into the FPGA uart receive rx signal;
This is Pin A2 for FPGA_C. Pin A1 should be connected to the uart tx output from the FPGA
toplevel module. The constraints to do this is shown below.


```
ldc_set_port -iobuf {PULLMODE=100K} [get_ports rx]
ldc_set_location -site {A1} [get_ports tx]
ldc_set_location -site {A2} [get_ports rx]
```

## Host FPGA protocol example
```
import serial
ser = serial.Serial("/dev/tty.usbserial-14601", 115200, timeout=1)
# Write to regmap at offset 4, 4 bytes [1,2,3,4]
write_packet = bytearray(b'\x84\x04\x00\x01\x02\x03\x04')
ser.write(write_packet)
# Read back 4 bytes from offset 4
read_packet = bytearray(b'\x04\x04\x00')
ser.write(read_packet)
ser.read(4) =>
b'\x01\x02\x03\x04'
```

In [2]: import serial
   ...: ser = serial.Serial("/dev/cu.usbserial-145201", 115200, timeout=1)

In [3]: def start():
   ...:     ser.write(bytes([129,128,0,128]))
   ...:

In [4]: def stop():
   ...:     ser.write(bytes([129,128,0,0]))
   ...:

In [5]: def read_fifo(num_elem):
   ...:     nb = bytes(num_elem)
   ...:     print(int(nb[0]))
   ...:     #ser.write(bytes([64,num_elem,0]))
   ...:

In [21]: def read_fifo(num_elem):
    ...:     # only supports < 256
    ...:     ser.write(bytes([64,num_elem,0]))
    ...:     sleep(0.25)
    ...:     return ser.read(num_elem)