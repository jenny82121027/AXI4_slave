TOPLEVEL_LANG = verilog
.DEFAULT_GOAL := sim

SIM ?= icarus

VERILOG_SOURCES = \
	$(PWD)/tb.v \
	$(PWD)/../src/axi4_lite_slave.sv

COMPILE_ARGS += -g2012

TOPLEVEL = tb
MODULE = test
COCOTB_RESULTS_FILE = results.xml

export COCOTB_REDUCED_LOG_FMT = 1

include $(shell cocotb-config --makefiles)/Makefile.sim
