# Single runner entry point for the cocotb + Icarus harness.
#
#   make -C verification xbar       OBI crossbar/decode + reset synchroniser tests, fabric
#                                   at default parameters and at ISRAM_1RW=1 / 1024-word SRAMs
#   make -C verification xbar-1rw   just the alternate-parameter fabric run
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

.PHONY: xbar xbar-fabric xbar-1rw xbar-rst
xbar: xbar-fabric xbar-1rw xbar-rst

FABRIC_SRC := $(RTL)/obi_err_resp.sv $(RTL)/obi_xbar.sv $(RTL)/boot_rom.sv $(RTL)/soc_sram_i.sv $(RTL)/soc_sram_i_1rw.sv $(RTL)/soc_sram_d.sv $(RTL)/soc_fabric.sv

xbar-fabric:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/xbar TOPLEVEL=soc_fabric MODULE=test_xbar \
	    VERILOG_SOURCES="$(FABRIC_SRC)" \
	    PLUSARGS=+rom_hex=$(RTL)/boot_rom.hex \
	    SIM_BUILD=$(ROOT)/sim_build/xbar

# Single-port I-SRAM, 4 KB per SRAM (the test reads FABRIC_* to know the build).
# COMPILE_ARGS goes in the environment so cocotb's own iverilog flags still append.
xbar-1rw:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	COMPILE_ARGS="-Psoc_fabric.ISRAM_1RW=1 -Psoc_fabric.ISRAM_AW=10 -Psoc_fabric.DSRAM_AW=10" \
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/xbar TOPLEVEL=soc_fabric MODULE=test_xbar \
	    VERILOG_SOURCES="$(FABRIC_SRC)" \
	    FABRIC_ISRAM_1RW=1 FABRIC_SRAM_AW=10 \
	    PLUSARGS=+rom_hex=$(RTL)/boot_rom.hex \
	    SIM_BUILD=$(ROOT)/sim_build/xbar_1rw \
	    COCOTB_RESULTS_FILE=$(ROOT)/sim_build/xbar_1rw/results.xml

xbar-rst:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/xbar TOPLEVEL=rst_sync MODULE=test_rst_sync \
	    VERILOG_SOURCES=$(RTL)/rst_sync.sv \
	    SIM_BUILD=$(ROOT)/sim_build/rst_sync

CVE2_V := $(abspath $(ROOT)/../$(or $(CVE2_BUILD_REL),build/cve2))/cve2_top.v
BOOT_HEX := $(abspath $(ROOT)/../firmware/boot/boot_rom.hex)

.PHONY: boot
boot:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	@test -r $(CVE2_V) || { echo "$(CVE2_V) missing: run scripts/fetch-cve2.sh && scripts/convert-cve2.sh" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/boot TOPLEVEL=soc_top MODULE=test_boot \
	    VERILOG_SOURCES="$(RTL)/obi_err_resp.sv $(RTL)/obi_xbar.sv $(RTL)/boot_rom.sv $(RTL)/soc_sram_i.sv $(RTL)/soc_sram_i_1rw.sv $(RTL)/soc_sram_d.sv $(RTL)/soc_fabric.sv $(RTL)/rst_sync.sv $(CVE2_V) $(RTL)/soc_top.sv" \
	    PLUSARGS=+rom_hex=$(BOOT_HEX) \
	    SIM_BUILD=$(ROOT)/sim_build/boot

# Same firmware and test as `boot`, with the single-port I-SRAM and 4 KB SRAMs
# (1024 words). The -P flags show in the iverilog command line of the sim log.
.PHONY: boot-1rw
boot-1rw:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	@test -r $(CVE2_V) || { echo "$(CVE2_V) missing: run scripts/fetch-cve2.sh && scripts/convert-cve2.sh" >&2; exit 1; }
	COMPILE_ARGS="-Psoc_top.ISRAM_1RW=1 -Psoc_top.ISRAM_AW=10 -Psoc_top.DSRAM_AW=10" \
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/boot TOPLEVEL=soc_top MODULE=test_boot \
	    VERILOG_SOURCES="$(RTL)/obi_err_resp.sv $(RTL)/obi_xbar.sv $(RTL)/boot_rom.sv $(RTL)/soc_sram_i.sv $(RTL)/soc_sram_i_1rw.sv $(RTL)/soc_sram_d.sv $(RTL)/soc_fabric.sv $(RTL)/rst_sync.sv $(CVE2_V) $(RTL)/soc_top.sv" \
	    PLUSARGS=+rom_hex=$(BOOT_HEX) \
	    SIM_BUILD=$(ROOT)/sim_build/boot_1rw \
	    COCOTB_RESULTS_FILE=$(ROOT)/sim_build/boot_1rw/results.xml
