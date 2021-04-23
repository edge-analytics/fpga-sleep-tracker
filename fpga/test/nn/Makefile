VERILOG_SOURCES = $(PWD)/../../source/nn/nn_pkg.sv \
$(PWD)/../../source/nn/nn_biases.sv \
$(PWD)/../../source/nn/nn_weights.sv \
$(PWD)/../../source/mem/sp_ram.sv \
$(PWD)/../../source/nn/nn.sv
TOPLEVEL_LANG=verilog
TOPLEVEL=nn
MODULE=nn_tb
SIM=modelsim
#EXTRA_ARGS += --trace --trace-structs
#SIM_ARGS=-L /home/rbk/ice40up 
GUI=0
WAVES=1
ARCH=i686
include $(shell cocotb-config --makefiles)/Makefile.sim

clean::
	-find . -type d \( -name __pycache__ -o -name sim_build \) | xargs rm -rf
	-find . -type f -name dump.vcd | xargs rm -r
	-find . -type f -name vsim.wlf | xargs rm -r
	-find . -type f -name transcript | xargs rm -r
	-find . -type f -name modelsim.ini | xargs rm -r
	-find . -type f -name results.xml | xargs rm -r

