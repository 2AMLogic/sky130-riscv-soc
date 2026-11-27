# archtest: riscv-arch-test (ACT4) on the SoC (simulation)

Issue #49, the functional half of T1 item 5: riscv-arch-test at `9929db1c`
(run on `rtl/soc_top.sv` with the converted CVE2 `d7f21568`), recorded at
commit `534a1a7`. **Simulation evidence only. It says nothing about timing.**

| Run | Result |
| --- | --- |
| `make -C verification archtest` (klt 0.9.2, Icarus 13.0, cocotb 2.0.1) | **131 of 132 passed, 1 failed, 0 skipped** (`report.json`, `results_icarus.xml`, `test_icarus.log`) |
| `make -C verification archtest-negative` | the corrupted reference result is rejected (`archtest-negative.log`, `archtest-negative.json`) |

**The issue's "all selected tests passed" is not met by this record.** One
selected test fails, for a reason that is not a defect of the SoC (#221), and
how to disposition it is an open operator decision. The test is recorded as
failed, not skipped.

## What ran

ACT4 selects 132 tests for the SoC's configuration
(`verification/tests/archtest/selection.txt`; every other of the 7167
candidate tests is listed there with the reason it is rejected). Each is one
cocotb test in `verification/tests/archtest/test_archtest.py`: the image is
loaded into the testbench-only RAM, the SoC comes out of reset through a boot
ROM that jumps to the test's entry point, and ACT4's own self-check decides.
Every image's reference results were produced by the Sail model of the same
configuration (`dut/sail.json`) when `scripts/build-archtest.sh` built it.

| Suite | Selected | Passed | Failed |
| --- | ---: | ---: | ---: |
| `priv/ExceptionsSm` | 4 | 4 | 0 |
| `priv/ExceptionsZc` | 1 | 1 | 0 |
| `priv/InterruptsSm` | 7 | 7 | 0 |
| `priv/Sm` | 27 | 26 | 1 |
| `rv32i/I` | 39 | 39 | 0 |
| `rv32i/M` | 8 | 8 | 0 |
| `rv32i/Misalign` | 9 | 9 | 0 |
| `rv32i/Zca` | 26 | 26 | 0 |
| `rv32i/Zicsr` | 6 | 6 | 0 |
| `rv32i/Zifencei` | 1 | 1 | 0 |
| `rv32i/Zmmul` | 4 | 4 | 0 |

26.5 ms of simulated time in 277 s of wall time; the longest test is
`priv/Sm/Sm_csr_ro-00` at 2.45 ms (about 122 000 clocks), so the bench's 50 million
 clock hang limit is some 400 times the longest test. `test_icarus.log` holds
the console transcript of every test, decoded from the SoC's UART: 131 read
`RVCP-SUMMARY: TEST PASSED`, one `TEST FAILED`.

## The failure

`priv/Sm/Sm_mcsr_cntr-00` fails ACT4's self-check on test case 547:

```
RVCP: Test Info: "test: 547; cg: Sm_mcsr_cg; cp: cp_mtime_write; bin: h"
RVCP: Instruction: 0xc8102373
RVCP: Register: x6
RVCP: Bad Value:      0x40001fbd
RVCP: Expected Value: 0x0200bfb5
```

This is the failure #221 reports, with the same values. `0xc8102373` is
`csrrs x6, timeh`; CVE2 has no `time` CSR, so the read leaves `x6` holding the
`mtime` address the case loaded. The address differs between the SoC
(`0x4000_2000`, the timer base) and Sail's CLINT (`0x0200_BFF8`), and so does
the signature entry. ACT4's generator emits the case for any DUT with an
`mtime` address whether or not it has `time` (#221). The UDB configuration
stays truthful (no `Zicntr`): declaring it would make ACT4 select three more
tests that then fail (#221).

## The configuration describes the SoC, not upstream's CV32E20 card

`dut/` starts from riscv-arch-test's own `config/cores/cve2/cv32e20/` and
changes only what `rtl/soc_top.sv` and the CVE2 sources make different. Each
change is cited at its line in the file that carries it. The last column is
what this bench observed with the upstream value left in place; a dash means
the change was not tried the other way:

| Change | From the RTL | Observed otherwise |
| --- | --- | --- |
| `MEI_INTR_IMPL`, `MSI_INTR_IMPL` false | `irq_external_i`, `irq_software_i` tied to 0 | - (with them true ACT4 generates interrupt cases that need sources the SoC does not have) |
| `HPM_COUNTER3..12_WIDTH` 40, `hpmcounter_width_bits` 40 | `MHPMCounterWidth(40)` | - |
| `writable_hpm_counters` `0x0000_1FF8`, `mcountinhibit.writable_bits` `0x0000_1FFD` | `MHPMCounterNum(10)`: `mhpmcounter3..12` exist, an absent one reads 0 and ignores writes | `Sm_mcsr_cntr-00` failed at test 344 (`mhpmcounter13_csrrw_some`) |
| `impid` 0, `archid` 35 | `CSR_MIMPID_VALUE = 0`, `MARCHID = 35` (`cve2_pkg.sv`) | `Sm_mcsr_access-00` failed at test 723 (`mimpid_csrrw1`) |
| console on the UART, `mtime`/`mtimecmp` at `0x4000_2000`/`0x4000_2008` | `spec/soc.md` § Memory map | - |
| tests linked at `0x1000_4000`, RAM `0x1000_0000` + 512 KB | the instruction SRAM base; testbench-only depth | - |

## What this record does and does not show

- It is ISA-conformance evidence for the core as the SoC wires it: through the
  OBI fabric, with the shipped UART as console and the shipped timer as the
  machine timer, on RTL under Icarus. It is not gate-level, timing or silicon
  evidence.
- Pass/fail is ACT4's self-check halt, not a signature compare against a
  stored reference; record 0007 (proposed) is the decision that lets row 1 of
  the verification plan be read that way.
- Tests ACT4 does not select never ran (their reasons are in `selection.txt`),
  and neither did the cases inside selected tests that need a machine external
  or software interrupt.
- `--check` of the committed report is not available: klt 0.9.2's report
  schema (2) carries no source hashes. `provenance.json` records the sha256 of
  the request, every RTL source, the converted core and the bench instead, and
  the report's own hashes of `results_icarus.xml`, `test_icarus.log` and
  `build_icarus.log` match the copies here.

## Files

| File | What it is |
| --- | --- |
| `provenance.json` | commit, tool versions, commands, input digests, result |
| `request.json` | the `klt functional-verification` request, byte-identical to `verification/tests/archtest/fv_request.json` |
| `report.json` | klt's report (`--format json`) |
| `results_icarus.xml`, `test_icarus.log`, `build_icarus.log` | the run's own results file, console transcript and build transcript |
| `manifest.json` | the 132 images the bench loaded, each with its ELF's sha256 |
| `archtest-negative.log`, `archtest-negative.json` | the negative check and its report |

Re-run from the repository root at this commit with the ACT4 toolchain
(`scripts/setup-env.sh --check-act4`): `make -C verification archtest
ARCHTEST_REPORT=report.json`, then `make -C verification archtest-negative`.
