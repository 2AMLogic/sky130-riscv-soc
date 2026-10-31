# Single runner entry point for the cocotb + Icarus harness.
#
#   make -C verification xbar       OBI crossbar/decode + reset synchroniser tests, fabric
#                                   at default parameters and at ISRAM_1RW=1 / 1024-word SRAMs
#   make -C verification xbar-1rw   just the alternate-parameter fabric run
#   make -C verification periph    UART, GPIO, timer and peripheral-window decode tests
#   make -C verification soc        firmware tests on the SoC: banner, echo, GPIO, timer
#                                   interrupt (checked-in firmware/soc/*.hex; needs the
#                                   same converted CVE2 as boot, no RISC-V compiler)
#   make -C verification soc-negative  the banner test with one expected byte perturbed must fail
#   make -C verification soc-gate   the banner test on the synthesized netlist
#                                   (netlist/soc_top_synth.v) with sky130_fd_sc_hd cell models and
#                                   the macro stand-in; transcript must equal the RTL one
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

FABRIC_SRC := $(RTL)/obi_err_resp.sv $(RTL)/obi_xbar.sv $(RTL)/boot_rom.sv $(RTL)/soc_sram_i.sv $(RTL)/soc_sram_d.sv $(RTL)/uart.sv $(RTL)/gpio.sv $(RTL)/timer.sv $(RTL)/soc_fabric.sv

# 16-word ROM image for the fabric test (0xB0070000 + i; test_xbar.py ROM_IMG), generated.
XBAR_ROM_HEX := $(ROOT)/sim_build/xbar_rom.hex

$(XBAR_ROM_HEX): Makefile
	@mkdir -p $(dir $@)
	@i=0; while [ $$i -lt 16 ]; do printf '%08x\n' $$((0xB0070000 + i)); i=$$((i + 1)); done > $@

xbar-fabric: $(XBAR_ROM_HEX)
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/xbar TOPLEVEL=soc_fabric MODULE=test_xbar \
	    VERILOG_SOURCES="$(FABRIC_SRC)" \
	    PLUSARGS=+rom_hex=$(XBAR_ROM_HEX) \
	    SIM_BUILD=$(ROOT)/sim_build/xbar

# Single-port I-SRAM, 4 KB per SRAM (the test reads FABRIC_* to know the build).
# COMPILE_ARGS goes in the environment so cocotb's own iverilog flags still append.
xbar-1rw: $(XBAR_ROM_HEX)
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	COMPILE_ARGS="-Psoc_fabric.ISRAM_1RW=1 -Psoc_fabric.ISRAM_AW=10 -Psoc_fabric.DSRAM_AW=10" \
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/xbar TOPLEVEL=soc_fabric MODULE=test_xbar \
	    VERILOG_SOURCES="$(FABRIC_SRC)" \
	    FABRIC_ISRAM_1RW=1 FABRIC_SRAM_AW=10 \
	    PLUSARGS=+rom_hex=$(XBAR_ROM_HEX) \
	    SIM_BUILD=$(ROOT)/sim_build/xbar_1rw \
	    COCOTB_RESULTS_FILE=$(ROOT)/sim_build/xbar_1rw/results.xml

xbar-rst:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/xbar TOPLEVEL=rst_sync MODULE=test_rst_sync \
	    VERILOG_SOURCES=$(RTL)/rst_sync.sv \
	    SIM_BUILD=$(ROOT)/sim_build/rst_sync

.PHONY: periph periph-uart periph-gpio periph-timer periph-decode
periph: periph-uart periph-gpio periph-timer periph-decode

periph-uart:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/periph TOPLEVEL=uart MODULE=test_uart \
	    VERILOG_SOURCES=$(RTL)/uart.sv \
	    SIM_BUILD=$(ROOT)/sim_build/periph_uart

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

periph-decode: $(XBAR_ROM_HEX)
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/periph TOPLEVEL=soc_fabric MODULE=test_decode \
	    VERILOG_SOURCES="$(FABRIC_SRC)" \
	    PLUSARGS=+rom_hex=$(XBAR_ROM_HEX) \
	    SIM_BUILD=$(ROOT)/sim_build/periph_decode

CVE2_V := $(abspath $(ROOT)/../$(or $(CVE2_BUILD_REL),build/cve2))/cve2_top.v
BOOT_HEX := $(abspath $(ROOT)/../firmware/boot/boot_rom.hex)

.PHONY: boot
boot:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	@test -r $(CVE2_V) || { echo "$(CVE2_V) missing: run scripts/fetch-cve2.sh && scripts/convert-cve2.sh" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/boot TOPLEVEL=soc_top MODULE=test_boot \
	    VERILOG_SOURCES="$(SOC_SRC)" \
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
	    VERILOG_SOURCES="$(SOC_SRC)" \
	    PLUSARGS=+rom_hex=$(BOOT_HEX) \
	    SIM_BUILD=$(ROOT)/sim_build/boot_1rw \
	    COCOTB_RESULTS_FILE=$(ROOT)/sim_build/boot_1rw/results.xml

# SoC firmware tests (issue #48): one simulation per ROM image firmware/soc/<name>.hex,
# because the image is fixed at elaboration (+rom_hex). The images are checked in;
# `firmware/soc/build.sh --check` (needs the pinned RISC-V GCC) verifies them locally.
SOC_SRC := $(RTL)/obi_err_resp.sv $(RTL)/obi_xbar.sv $(RTL)/boot_rom.sv $(RTL)/soc_sram_i.sv $(RTL)/soc_sram_d.sv $(RTL)/uart.sv $(RTL)/gpio.sv $(RTL)/timer.sv $(RTL)/soc_fabric.sv $(RTL)/rst_sync.sv $(CVE2_V) $(RTL)/soc_top.sv
SOC_TESTS := banner echo gpio timer

.PHONY: soc soc-negative $(addprefix soc-,$(SOC_TESTS))
soc: $(addprefix soc-,$(SOC_TESTS))

$(addprefix soc-,$(SOC_TESTS)): soc-%:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	@test -r $(CVE2_V) || { echo "$(CVE2_V) missing: run scripts/fetch-cve2.sh && scripts/convert-cve2.sh" >&2; exit 1; }
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/soc TOPLEVEL=soc_top MODULE=test_$* \
	    VERILOG_SOURCES="$(SOC_SRC)" \
	    PLUSARGS=+rom_hex=$(abspath $(ROOT)/../firmware/soc/$*.hex) \
	    SIM_BUILD=$(ROOT)/sim_build/soc_$*

# The transcript comparison must be able to fail: perturb the expected banner's first byte.
soc-negative:
	@rm -rf $(ROOT)/sim_build/soc_banner
	@if SOC_PERTURB=1 $(MAKE) soc-banner >$(ROOT)/sim_build/soc-negative.log 2>&1; then \
	    echo "soc-negative: the perturbed transcript was accepted" >&2; exit 1; \
	else grep -m1 'AssertionError' $(ROOT)/sim_build/soc-negative.log; echo "soc-negative: perturbed transcript rejected, as required"; fi

# Post-synthesis regression (issue #35): the banner image is baked into the netlist at
# synthesis (flow/soc/synth_request.json), so one test. Cell models: the PDK's
# sky130_fd_sc_hd verilog (primitives.v + sky130_fd_sc_hd.v, FUNCTIONAL, zero delay);
# SRAM macros: models/..._standin.v (the pinned macro model does not elaborate in Icarus).
# PDK_VERILOG overrides the cell-model directory (default: the ciel/volare install).
PDK_VERILOG ?= $(or $(wildcard $(PDK_ROOT)/$(PDK)/libs.ref/sky130_fd_sc_hd/verilog),$(wildcard $(HOME)/.ciel/sky130A/libs.ref/sky130_fd_sc_hd/verilog))
GATE_SRC := $(abspath $(ROOT)/../netlist/soc_top_synth.v) $(PDK_VERILOG)/primitives.v $(PDK_VERILOG)/sky130_fd_sc_hd.v $(ROOT)/models/sky130_sram_2kbyte_1rw1r_32x512_8_standin.v

.PHONY: soc-gate
soc-gate:
	@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
	@test -r $(PDK_VERILOG)/sky130_fd_sc_hd.v || { echo "sky130_fd_sc_hd verilog models not found (set PDK_VERILOG)" >&2; exit 1; }
	@test -r $(abspath $(ROOT)/../netlist/soc_top_synth.v) || { echo "netlist missing: run scripts/synth-soc.sh" >&2; exit 1; }
	SOC_GATE=1 $(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/soc TOPLEVEL=soc_top MODULE=test_banner \
	    VERILOG_SOURCES="$(GATE_SRC)" \
	    COMPILE_ARGS="-DFUNCTIONAL -DUNIT_DELAY=#0" \
	    SIM_BUILD=$(ROOT)/sim_build/soc_gate
