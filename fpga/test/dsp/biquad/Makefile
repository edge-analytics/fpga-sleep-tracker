VERILOG_SOURCES = $(PWD)/../../../source/dsp/biquad/biquad.sv
TOPLEVEL_LANG=verilog
TOPLEVEL=biquad
MODULE=biquad_tb
SIM=verilator
EXTRA_ARGS += --trace --trace-structs
GUI=1
WAVES=1
include $(shell cocotb-config --makefiles)/Makefile.sim

clean::
	-find . -type d \( -name __pycache__ -o -name sim_build \) | xargs rm -rf
	-find . -type f -name dump.vcd | xargs rm -r
	-find . -type f -name vsim.wlf | xargs rm -r
	-find . -type f -name transcript | xargs rm -r
	-find . -type f -name modelsim.ini | xargs rm -r
	-find . -type f -name results.xml | xargs rm -r