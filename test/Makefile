TOPLEVEL_LANG = verilog
.DEFAULT_GOAL := sim

VERILOG_SOURCES = \
	$(PWD)/tb.v \
	$(PWD)/../src/axi4_lite_slave.sv

OSS_CAD_BINDIR := $(dir $(shell which verilator))
OSS_CAD_LIBDIR := $(abspath $(OSS_CAD_BINDIR)/../lib)

TOPLEVEL = tb
MODULE = test
SIM = verilator
COCOTB_RESULTS_FILE = results.xml
EXTRA_ARGS = --timing --assert

export COCOTB_REDUCED_LOG_FMT = 1
export COCOTB_RESOLVE_X = zeros
export DYLD_LIBRARY_PATH := $(OSS_CAD_LIBDIR):$(DYLD_LIBRARY_PATH)
export LD_LIBRARY_PATH := $(OSS_CAD_LIBDIR):$(LD_LIBRARY_PATH)

setup-lib:
	ln -sfn $(OSS_CAD_LIBDIR) lib

sim test regress: setup-lib

include $(shell cocotb-config --makefiles)/Makefile.sim
