# Single runner entry point for the cocotb + Icarus harness.
#
#   make -C verification smoke      run the placeholder DUT test
#   make -C verification xbar       OBI crossbar/decode + reset synchroniser tests
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

RTL := $(abspath $(ROOT)/../rtl)

.PHONY: xbar xbar-fabric xbar-rst
xbar: xbar-fabric xbar-rst

xbar-fabric:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/xbar TOPLEVEL=soc_fabric MODULE=test_xbar \
	    VERILOG_SOURCES="$(RTL)/obi_err_resp.sv $(RTL)/obi_xbar.sv $(RTL)/boot_rom.sv $(RTL)/soc_sram_i.sv $(RTL)/soc_sram_d.sv $(RTL)/soc_fabric.sv" \
	    PLUSARGS=+rom_hex=$(RTL)/boot_rom.hex \
	    SIM_BUILD=$(ROOT)/sim_build/xbar

xbar-rst:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/xbar TOPLEVEL=rst_sync MODULE=test_rst_sync \
	    VERILOG_SOURCES=$(RTL)/rst_sync.sv \
	    SIM_BUILD=$(ROOT)/sim_build/rst_sync
