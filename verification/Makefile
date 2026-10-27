# Single runner entry point for the cocotb + Icarus harness.
#
#   make -C verification xbar       OBI crossbar/decode + reset synchroniser tests
#   make -C verification periph    GPIO, timer and peripheral-window decode tests
#   make -C verification boot       SoC top boots firmware/boot (needs build/cve2/cve2_top.v:
#                                   scripts/fetch-cve2.sh && scripts/convert-cve2.sh)
#
# A new test directory under tests/<name>/ adds a target by setting the three
# variables below.
# Needs cocotb (pinned in ../scripts/setup-env.sh) and iverilog on PATH.
# Fails, rather than skips, when cocotb is missing.

SIM ?= icarus
export PYTHON_BIN ?= python3
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

RTL := $(abspath $(ROOT)/../rtl)

.PHONY: xbar xbar-fabric xbar-rst
xbar: xbar-fabric xbar-rst

xbar-fabric:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/xbar TOPLEVEL=soc_fabric MODULE=test_xbar \
	    VERILOG_SOURCES="$(RTL)/obi_err_resp.sv $(RTL)/obi_xbar.sv $(RTL)/boot_rom.sv $(RTL)/soc_sram_i.sv $(RTL)/soc_sram_d.sv $(RTL)/gpio.sv $(RTL)/timer.sv $(RTL)/soc_fabric.sv" \
	    PLUSARGS=+rom_hex=$(RTL)/boot_rom.hex \
	    SIM_BUILD=$(ROOT)/sim_build/xbar

xbar-rst:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/xbar TOPLEVEL=rst_sync MODULE=test_rst_sync \
	    VERILOG_SOURCES=$(RTL)/rst_sync.sv \
	    SIM_BUILD=$(ROOT)/sim_build/rst_sync

PERIPH_SRCS := $(RTL)/gpio.sv $(RTL)/timer.sv
FABRIC_SRCS := $(RTL)/obi_err_resp.sv $(RTL)/obi_xbar.sv $(RTL)/boot_rom.sv $(RTL)/soc_sram_i.sv $(RTL)/soc_sram_d.sv $(PERIPH_SRCS) $(RTL)/soc_fabric.sv

.PHONY: periph periph-gpio periph-timer periph-decode
periph: periph-gpio periph-timer periph-decode

periph-gpio:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/periph TOPLEVEL=gpio MODULE=test_gpio \
	    VERILOG_SOURCES=$(RTL)/gpio.sv \
	    SIM_BUILD=$(ROOT)/sim_build/periph_gpio

periph-timer:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/periph TOPLEVEL=timer MODULE=test_timer \
	    VERILOG_SOURCES=$(RTL)/timer.sv \
	    SIM_BUILD=$(ROOT)/sim_build/periph_timer

periph-decode:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/periph TOPLEVEL=soc_fabric MODULE=test_decode \
	    VERILOG_SOURCES="$(FABRIC_SRCS)" \
	    PLUSARGS=+rom_hex=$(RTL)/boot_rom.hex \
	    SIM_BUILD=$(ROOT)/sim_build/periph_decode

CVE2_V := $(abspath $(ROOT)/../$(or $(CVE2_BUILD_REL),build/cve2))/cve2_top.v
BOOT_HEX := $(abspath $(ROOT)/../firmware/boot/boot_rom.hex)

.PHONY: boot
boot:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	@test -r $(CVE2_V) || { echo "$(CVE2_V) missing: run scripts/fetch-cve2.sh && scripts/convert-cve2.sh" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/boot TOPLEVEL=soc_top MODULE=test_boot \
	    VERILOG_SOURCES="$(RTL)/obi_err_resp.sv $(RTL)/obi_xbar.sv $(RTL)/boot_rom.sv $(RTL)/soc_sram_i.sv $(RTL)/soc_sram_d.sv $(RTL)/gpio.sv $(RTL)/timer.sv $(RTL)/soc_fabric.sv $(RTL)/rst_sync.sv $(CVE2_V) $(RTL)/soc_top.sv" \
	    PLUSARGS=+rom_hex=$(BOOT_HEX) \
	    SIM_BUILD=$(ROOT)/sim_build/boot
