SLAVE_ONLY_MAKEFILE := Makefile.slave_only.cocotb
SLAVE_ONLY_RESULTS := results_slave_only.xml
OSS_CAD_BINDIR := $(dir $(shell which verilator))
OSS_CAD_LIBDIR := $(abspath $(OSS_CAD_BINDIR)/../lib)
.DEFAULT_GOAL := sim

.PHONY: sim test regress lint clean clean-all setup-lib

sim test regress: setup-lib
sim test regress:
	$(MAKE) -f $(SLAVE_ONLY_MAKEFILE)

setup-lib:
	ln -sfn $(OSS_CAD_LIBDIR) lib

lint:
	verilator --lint-only axi4_lite_slave.sv

clean:
	rm -rf sim_build_slave_only $(SLAVE_ONLY_RESULTS) dump.vcd __pycache__ lib

clean-all: clean
	rm -rf sim_build results.xml obj_dir waveform.vcd
