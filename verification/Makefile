# Single runner entry point for the cocotb + Icarus harness.
#
#   make -C verification smoke      run the placeholder DUT test
#
# A new test directory under tests/<name>/ adds a target by setting the three
# variables below; nothing here needs restructuring when the SoC top lands.
# Needs cocotb (pinned in ../scripts/setup-env.sh) and iverilog on PATH.
# Fails, rather than skips, when cocotb is missing.

SIM ?= icarus
export PYTHON_BIN ?= python3
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

.PHONY: smoke
smoke:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/smoke TOPLEVEL=dut MODULE=test_smoke \
	    VERILOG_SOURCES=$(ROOT)/tests/smoke/dut.v SIM_BUILD=$(ROOT)/sim_build/smoke
