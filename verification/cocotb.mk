# Shared cocotb/Icarus rules, driven by verification/Makefile (not run directly).
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
COCOTB_RESULTS_FILE ?= $(SIM_BUILD)/results.xml
# Imports: the testbench's own directory, then tests/lib -- the shared bench core
# (obi_bench.py: one definition of the reset sequence and the request/accept/
# response contract). Per-testbench isolation is otherwise unchanged: a testbench
# still cannot import another testbench's modules.
TESTLIB := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))tests/lib)
export PYTHONPATH := $(TESTDIR):$(TESTLIB):$(PYTHONPATH)
include $(shell cocotb-config --makefiles)/Makefile.sim
