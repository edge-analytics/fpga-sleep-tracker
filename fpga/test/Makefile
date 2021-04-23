VERILOG_SOURCES = $(PWD)/../source/nn/nn_pkg.sv \
$(PWD)/../source/nn/nn_biases.sv \
$(PWD)/../source/nn/nn_weights.sv \
$(PWD)/../source/mem/sp_ram.sv \
$(PWD)/../source/nn/nn.sv \
$(PWD)/../source/comm/uart/uart.sv \
$(PWD)/../source/util/handshake/handshake.sv \
$(PWD)/../source/fifo/fifo_256k.sv \
$(PWD)/../source/sleep_tracker_cu.sv \
$(PWD)/../source/math/math_pkg.sv \
$(PWD)/../source/dsp/biquad/biquad.sv \
$(PWD)/../source/featurize/peak_detect.sv \
$(PWD)/../source/featurize/sum_samples.sv \
$(PWD)/../source/featurize/actigraphy_counts.sv \
$(PWD)/../source/top.sv

TOPLEVEL_LANG=verilog
TOPLEVEL=top
MODULE=top_tb
SIM=modelsim
#EXTRA_ARGS += --trace --trace-structs
SIM_ARGS=-L /home/rbk/ice40up 
GUI=1
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

