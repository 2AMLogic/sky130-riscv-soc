# Shared cocotb/Icarus rules, driven by verification/Makefile (not run directly).
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
COCOTB_RESULTS_FILE ?= $(SIM_BUILD)/results.xml
export PYTHONPATH := $(TESTDIR):$(PYTHONPATH)
include $(shell cocotb-config --makefiles)/Makefile.sim
