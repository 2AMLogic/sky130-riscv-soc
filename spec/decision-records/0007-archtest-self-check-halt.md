# 0007 — riscv-arch-test on the SoC: the ACT4 self-check halt stands in for the signature compare, on a testbench-only RAM

- **Status**: proposed (2026-11-26), issue #49, written up per the operator
  ruling of 2026-10-28 (option a); awaiting the EE and market key reviews and
  the operator's ratification. Until it is ratified `spec/soc.md` §
  Verification plan row 1 reads as before.
- **Supersedes**: none (it restates the pass criterion of `spec/soc.md` §
  Verification plan row 1 for the suite the pinned commit actually is)
- **Superseded by**: none
- **Spec rows**: `spec/soc.md` § Verification plan row 1 (ISA conformance of the
  SoC); § Memory map unchanged

## Context

`spec/soc.md` § Verification plan row 1 asks for `riscv-arch-test` at commit
`9929db1c3a84f90f808f39f21678d9cd98776147`, run on the simulated SoC, with
"every selected test's signature matches the reference; skipped tests are
listed with a reason". Three facts about that commit, read on 2026-10-27 and
re-read for this record, do not fit that wording:

- It is the ACT4 framework, which is self-checking. There is no reference
  signature to compare: ACT4 runs each test on the Sail model configured for
  the DUT, compiles the results into the test's own image, and the test ends
  in `RVMODEL_HALT_PASS` or `RVMODEL_HALT_FAIL` after checking every result
  itself (`tests/env/rvtest_setup.h`, `RVTEST_SIGUPD`; `framework/src/act/
  build_plan.py`, the sig.elf → `.results` → self-check ELF pipeline).
- No image fits the shipped memory. The selected images link from one entry
  point and end 46 KB to 162 KB above it (`.text.rvmodel` and the stack
  follow the data, `tests/env/rvtest_setup.h`), against the ratified 8 KB
  instruction SRAM, 8 KB data SRAM and 4 KB ROM.
- It needs Sail 0.16, a GCC of 15 or later, and Ruby with the riscv-unified-db
  gems (`framework/src/act/config.py`, `REQUIRED_SAIL_VERSION` and
  `REQUIRED_GCC_MAJOR_VERSION`).

## Decision

1. **Pass criterion.** For this suite, ACT4's self-check halt stands in for
   "signature matches the reference": a selected test passes when the SoC,
   running the image ACT4 built for it, halts through `RVMODEL_HALT_PASS`. The
   reference is still Sail's; what changes is where it is compared — inside
   the test, against results compiled into it, rather than in a signature
   dump compared afterwards.
2. **Skipped tests.** "Selected" means selected by ACT4 for the SoC's own
   configuration (`verification/tests/archtest/dut/sky130-riscv-soc.yaml`,
   every value taken from `rtl/soc_top.sv` and the CVE2 sources at the pin).
   Every other candidate test is listed with the selection criterion it fails
   (`verification/tools/archtest_select.py`; the generated list is
   `verification/tests/archtest/selection.txt`).
3. **Test memory.** The tests run from a flat RAM that exists only in the
   testbench: `soc_top` elaborated with `ISRAM_AW = 17`, the instruction SRAM
   512 KB deep behind the fabric at its ratified base `0x1000_0000`. It is
   not the shipped 8 KB / 8 KB / 4 KB map and says nothing about it; the RTL
   is unchanged and the shipped build keeps `ISRAM_AW = 11`.
4. **Unchanged.** The CVE2 core at its pin, the fabric and the ratified memory
   map.

## Consequences

- Row 1's claim becomes: every selected test's ACT4 self-check passes on the
  simulated SoC. The evidence is a `klt functional-verification` report with
  one cocotb test per selected image, recorded under
  `verification/records/archtest/`.
- Tests ACT4 does not select are never run. That includes every test of an
  extension the core does not implement, and the cases inside selected tests
  that need a machine external or software interrupt, which the SoC has no
  source for (`rtl/soc_top.sv` ties both inputs to 0).
- What the suite proves is ISA conformance of the core as the SoC wires it,
  through the fabric and its shipped peripherals (the UART is the console,
  the timer the machine timer). It is simulation evidence on RTL, not timing
  or silicon.
- A failing selected test is recorded, never dropped: at this pin
  `priv/Sm/Sm_mcsr_cntr-00` fails on a case ACT4 generates for a DUT without
  a `time` CSR (#221). How that failure is dispositioned is #221's decision,
  not this record's.
