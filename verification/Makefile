# Single runner entry point for the cocotb + Icarus harness.
#
#   make -C verification xbar       OBI crossbar/decode + reset synchroniser tests
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
#   make -C verification archtest   ACT4 architecture tests on the SoC, one cocotb test per
#                                   selected image, through klt functional-verification (needs
#                                   the ACT4 toolchain; scripts/build-archtest.sh builds the images)
#   make -C verification archtest-negative  one corrupted reference result must fail its test
#
# A new test directory under tests/<name>/ adds a target by setting the three
# variables below.
# Needs cocotb (pinned in ../scripts/setup-env.sh) and iverilog on PATH.
# Fails, rather than skips, when cocotb is missing.

SIM ?= icarus
export PYTHON_BIN ?= python3
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

RTL := $(abspath $(ROOT)/../rtl)

# Guards, stated once and used as a recipe line: every cocotb target starts with
# $(CHECK_COCOTB), and one elaborating soc_top adds $(CHECK_CVE2). Fail, not skip.
define CHECK_COCOTB
@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
endef

define CHECK_CVE2
@test -r $(CVE2_V) || { echo "$(CVE2_V) missing: run scripts/fetch-cve2.sh && scripts/convert-cve2.sh" >&2; exit 1; }
endef

.PHONY: xbar xbar-fabric xbar-rst
xbar: xbar-fabric xbar-rst

FABRIC_SRC := $(RTL)/obi_xbar.sv $(RTL)/boot_rom.sv $(RTL)/soc_sram_i.sv $(RTL)/uart.sv $(RTL)/gpio.sv $(RTL)/timer.sv $(RTL)/soc_fabric.sv

# 16-word ROM image for the fabric test (0xB0070000 + i; test_xbar.py ROM_IMG), generated.
XBAR_ROM_HEX := $(ROOT)/sim_build/xbar_rom.hex

$(XBAR_ROM_HEX): Makefile
	@mkdir -p $(dir $@)
	@i=0; while [ $$i -lt 16 ]; do printf '%08x\n' $$((0xB0070000 + i)); i=$$((i + 1)); done > $@

xbar-fabric: $(XBAR_ROM_HEX)
	$(CHECK_COCOTB)
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/xbar TOPLEVEL=soc_fabric MODULE=test_xbar \
	    VERILOG_SOURCES="$(FABRIC_SRC)" \
	    PLUSARGS=+rom_hex=$(XBAR_ROM_HEX) \
	    SIM_BUILD=$(ROOT)/sim_build/xbar

xbar-rst:
	$(CHECK_COCOTB)
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/xbar TOPLEVEL=rst_sync MODULE=test_rst_sync \
	    VERILOG_SOURCES=$(RTL)/rst_sync.sv \
	    SIM_BUILD=$(ROOT)/sim_build/rst_sync

# uart, gpio and timer differ only in the name (tests/periph/test_<name>.py over
# rtl/<name>.sv). periph-decode stays separate: it elaborates the whole fabric.
PERIPH_TESTS := uart gpio timer

.PHONY: periph periph-decode $(addprefix periph-,$(PERIPH_TESTS))
periph: $(addprefix periph-,$(PERIPH_TESTS)) periph-decode

$(addprefix periph-,$(PERIPH_TESTS)): periph-%:
	$(CHECK_COCOTB)
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/periph TOPLEVEL=$* MODULE=test_$* \
	    VERILOG_SOURCES=$(RTL)/$*.sv \
	    SIM_BUILD=$(ROOT)/sim_build/periph_$*

periph-decode: $(XBAR_ROM_HEX)
	$(CHECK_COCOTB)
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/periph TOPLEVEL=soc_fabric MODULE=test_decode \
	    VERILOG_SOURCES="$(FABRIC_SRC)" \
	    PLUSARGS=+rom_hex=$(XBAR_ROM_HEX) \
	    SIM_BUILD=$(ROOT)/sim_build/periph_decode

CVE2_V := $(abspath $(ROOT)/../$(or $(CVE2_BUILD_REL),build/cve2))/cve2_top.v
BOOT_HEX := $(abspath $(ROOT)/../firmware/boot/boot_rom.hex)

.PHONY: boot
boot:
	$(CHECK_COCOTB)
	$(CHECK_CVE2)
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/boot TOPLEVEL=soc_top MODULE=test_boot \
	    VERILOG_SOURCES="$(SOC_SRC)" \
	    PLUSARGS=+rom_hex=$(BOOT_HEX) \
	    SIM_BUILD=$(ROOT)/sim_build/boot

# SoC firmware tests (issue #48): one simulation per ROM image firmware/soc/<name>.hex,
# because the image is fixed at elaboration (+rom_hex). The images are checked in;
# `firmware/soc/build.sh --check` (needs the pinned RISC-V GCC) verifies them locally.
SOC_SRC := $(FABRIC_SRC) $(RTL)/rst_sync.sv $(CVE2_V) $(RTL)/soc_top.sv
SOC_TESTS := banner echo gpio timer

.PHONY: soc soc-negative $(addprefix soc-,$(SOC_TESTS))
soc: $(addprefix soc-,$(SOC_TESTS))

$(addprefix soc-,$(SOC_TESTS)): soc-%:
	$(CHECK_COCOTB)
	$(CHECK_CVE2)
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
	$(CHECK_COCOTB)
	@test -r $(PDK_VERILOG)/sky130_fd_sc_hd.v || { echo "sky130_fd_sc_hd verilog models not found (set PDK_VERILOG)" >&2; exit 1; }
	@test -r $(abspath $(ROOT)/../netlist/soc_top_synth.v) || { echo "netlist missing: run scripts/synth-soc.sh" >&2; exit 1; }
	SOC_GATE=1 $(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/soc TOPLEVEL=soc_top MODULE=test_banner \
	    VERILOG_SOURCES="$(GATE_SRC)" \
	    COMPILE_ARGS="-DFUNCTIONAL -DUNIT_DELAY=#0" \
	    SIM_BUILD=$(ROOT)/sim_build/soc_gate

# ACT4 architecture tests (issue #49): one cocotb test per self-checking image
# riscv-arch-test selects for the SoC, each ending in ACT4's own pass/fail
# halt. scripts/build-archtest.sh (needs the ACT4 toolchain,
# ../scripts/setup-env.sh --check-act4) fetches, generates and builds the
# images; nothing is checked in. The run goes through `klt
# functional-verification` at PIN_KLT rather than cocotb.mk because its report
# is the evidence: klt prints its report (ARCHTEST_FORMAT, text or json), or
# writes the JSON report to ARCHTEST_REPORT when that is set (a record's
# report.json). The recipe is not echoed, so stdout is klt's own. Exit status
# is klt's: 3 once a test fails.
# The request names its boot ROM image relative to klt's output directory, so
# ARCHTEST_SIM has to stay exactly this deep inside verification/.
PIN_KLT := $(shell sed -n 's/^PIN_KLT="\([^"]*\)".*/\1/p' $(ROOT)/../scripts/setup-env.sh)
KLT ?= klt
ARCHTEST_DIR := $(ROOT)/tests/archtest
ARCHTEST_SIM ?= $(ROOT)/sim_build/archtest
ARCHTEST_FORMAT ?= text
ARCHTEST_REPORT ?=

.PHONY: archtest archtest-build archtest-negative
archtest-build:
	@$(KLT) --version 2>/dev/null | grep -qx "klt $(PIN_KLT)" || { echo "$(KLT) is not klt $(PIN_KLT) (PIN_KLT in ../scripts/setup-env.sh): put the pinned klt first on PATH, or set KLT=" >&2; exit 1; }
	$(ROOT)/../scripts/build-archtest.sh

archtest: archtest-build
ifneq ($(ARCHTEST_REPORT),)
	@$(KLT) functional-verification $(ARCHTEST_DIR)/fv_request.json -o $(ARCHTEST_SIM) --format json > $(ARCHTEST_REPORT) && echo "report: $(ARCHTEST_REPORT)"
else
	@$(KLT) functional-verification $(ARCHTEST_DIR)/fv_request.json -o $(ARCHTEST_SIM) --format $(ARCHTEST_FORMAT)
endif

# The self-check must be able to fail: with one reference result of I-add-00
# corrupted (ARCHTEST_PERTURB, read by the bench), that test alone is run and
# has to fail with ACT4's fail code. (cocotb 2.0 lists the tests a testcase
# filter leaves out as skipped, so the check counts the non-skipped ones. It
# runs in its own output directory and leaves the suite's in place.)
archtest-negative: archtest-build
	@rm -rf $(ARCHTEST_SIM)-negative
	@python3 -I -c 'import json, sys; r = json.load(open(sys.argv[1])); r["testbench"]["testcase"] = "rv32i/I/I-add-00"; json.dump(r, sys.stdout)' \
	    $(ARCHTEST_DIR)/fv_request.json > $(ARCHTEST_SIM)-negative.request.json
	@cd $(ARCHTEST_DIR) && ARCHTEST_PERTURB=rv32i/I/I-add-00 $(KLT) functional-verification - -o $(ARCHTEST_SIM)-negative --format json \
	    < $(ARCHTEST_SIM)-negative.request.json > $(ARCHTEST_SIM)-negative.json; rc=$$?; \
	if [ $$rc -ne 3 ]; then echo "archtest-negative: klt exited $$rc (3 = tests ran, one failed): $$(head -c 300 $(ARCHTEST_SIM)-negative.json)" >&2; exit 1; fi; \
	python3 -I -c 'import json, sys; r = json.load(open(sys.argv[1])); f = [t for t in r["tests"] if t["status"] == "failed"]; \
	    ok = len(f) == 1 and f[0]["name"] == "rv32i/I/I-add-00" and "ACT4 self-check FAILED" in f[0]["error_message"]; \
	    print("archtest-negative: corrupted reference result rejected:", f[0]["error_message"].splitlines()[0]) if ok else sys.exit("archtest-negative: the corrupted reference result was not rejected: " + json.dumps(f))' \
	    $(ARCHTEST_SIM)-negative.json
