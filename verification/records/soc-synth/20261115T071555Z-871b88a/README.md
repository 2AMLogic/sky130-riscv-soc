# soc_top resynthesis: USE_PORT1=0 macro build's dout1 tie cells removed, 2026-11-15

Resynthesis for issue #173 — `rtl/soc_sram_i`'s `USE_PORT1=0` macro-build off
branch drove `dout1` from a constant, which Yosys realized as 32
`sky130_fd_sc_hd__conb_1` tie cells (120.1152 um^2) driving a module output
that **no instance connects** (`.dout1()` open at both `soc_fabric`'s `u_dsram`
and the `g_isram_1rw` `u_isram`). Under `-DSOC_SRAM_MACRO` the off branch now
aliases bank 0's already-driven port-1 output (`assign dout1 =
bank_dout1[0]`), a pure net rename, so Yosys emits zero cells for it; bank 0's
macro port drives the module output directly. The behavioural branch's `'0` is
unchanged (simulation-only, costs nothing). Append-only; supersedes record
`20261114T060249Z-1cab6e0`. **Pre-route synthesis only** — no placement, no
routing, no STA, so this record makes **no Fmax or timing claim**.

## What was run

`scripts/synth-soc.sh` **twice** with the pinned klt 0.9.1
(`uvx --from "klayout-tools==0.9.1" klt`; the host's dev build was not used),
first on unmodified `origin/main @ 9d8dc9c` (issue #173's baseline criterion —
no committed record carried the post-#171 figure), then on this commit's tree.
`synth_request.json`, `synth_result.json` and `synth_soc_top.ys` here are the
klt request, its unedited JSON output and the Yosys script it ran;
`synth_result_baseline.json` is the unedited output of the baseline run, kept
so the before figures are auditable rather than asserted. The netlist is
`netlist/soc_top_synth.v`, sha256 `ba018bda…` (`provenance.json`).

**Baseline control:** the baseline run reproduced `main`'s committed netlist
byte-for-byte (sha256 `f71571b5…` both) — the netlist is reproducible across
build roots here, and both runs describe the same toolchain.

**Tool environment note:** klt synthesize deadlocks in Yosys' abc pass on this
host when `TMPDIR` is set to the loom sandbox path (`/tmp/loom-nt/<uuid>`) —
`yosys-abc` prints its `YOSYS_ABC_DONE` sentinel and waits at its REPL while
Yosys blocks reading its stdout (reproduced on a 2-gate design with `strace`;
same binaries complete with `TMPDIR` unset). Both runs were made with
`TMPDIR` unset. Filed generically at `2AMLogic/klayout-tools`.

## Synthesis result (from `synth_result.json`)

- `soc_top`, `sky130_fd_sc_hd`, `tt_025C_1v80`, Yosys 0.67+post, `sv2v`
  (v0.0.13), defines `SOC_SRAM_MACRO`, `SYNTHESIS`,
  `SOC_ROM_HEX=firmware/soc/banner.hex`. `status: ok`.
- **SRAM macros are black boxes** from the macro's Liberty view; their area is
  not in `area_um2`. Liberty origin: the pinned `efabless/sky130_sram_macros`
  TT_1p8V_25C view (`reuse.lock.json`, `scripts/fetch-sram-macro.sh`).

## Netlist before/after — measured, same toolchain

| metric | main `9d8dc9c` (baseline run) | this commit `871b88a` | delta |
|---|---:|---:|---:|
| `area_um2` | 222 467.1136 | 222 346.9984 | **−120.1152** |
| `instance_count` | 27 688 | 27 656 | **−32** |
| `conb_1` (elaborated, total) | 7376 | 7344 | **−32** |
| `conb_1` in `$paramod …USE_PORT1=1'0` | 72 | **40** | −32 |
| `conb_1` in `$paramod …USE_PORT1=1'1` | 0 | 0 | 0 |
| `sequential_area_um2` | 70 829.1808 | 70 829.1808 | 0 |

The −120.1152 um^2 is exactly 32 × 3.7536 (`conb_1` area,
`sky130_fd_sc_hd__tt_025C_1v80.lib`) — not rounded. The 40 remaining tie cells
in the `USE_PORT1=1'0` paramod are the required blackbox port ties (36
`addr1('0)` across the four macros + 4 `csb1(1'b1)`); **no `conb_1` output
drives a `dout1` bit** — `dout1` is driven by bank 0's macro `.dout1(dout1)`
port. The `USE_PORT1=1'1` paramod is **byte-identical** between the two
netlists (the two-port build is untouched), and neither `soc_top` instance
gained a `dout1` connection (`.dout1()` open at both, before and after).

## Don't-care contract documented, not silent

`assign dout1 = bank_dout1[0]` is not value-equivalent to `'0`: the stand-in
macro model drives `dout1 = 32'bx` on every `posedge clk1` and reloads only on
`negedge clk1` when `!csb1_reg`, so with `csb1` tied high at `USE_PORT1=0`
the alias — and hence the module output — reads **X** in the macro build's
simulation. This is acceptable for two measured reasons: no instance reads
`dout1` at `USE_PORT1=0`, and no cocotb test elaborates the macro build
(`git grep -l SOC_SRAM_MACRO` hits only `flow/soc/synth_request.json` and
`verification/tools/lint_rtl.sh`). The module header now documents the
don't-care contract instead of claiming a constant.

## Checks run on this tree

- `verification/tools/lint_rtl.sh` **with** `SRAM_MACRO_V` set (the
  `-DSOC_SRAM_MACRO` path that motivated the constant; passes with no
  undriven warning for `dout1`) and **without** it (alternate-fabric
  `ISRAM_1RW=1`/1024-word form included): both `ok`.
- `make -C verification soc-gate`: `test_banner.banner_matches_golden` **PASS**
  (`TESTS=1 PASS=1 FAIL=0 SKIP=0`, 507.57 s) on the regenerated netlist —
  the netlist still boots and emits the golden banner. Transcript:
  `soc-gate.log.txt`. Models: PDK `sky130_fd_sc_hd` Verilog with
  `-DFUNCTIONAL -DUNIT_DELAY=#0`, and the stand-in macro model (not the real
  macro, as in the superseded record).
- `attest/item1.json`, `evidence/item1.json` and the signoff manifest are
  regenerated with the pinned klt 0.9.1; all three `signoff.yml` checks
  reproduce locally (exit 0).
  **Correction (post-review):** the first regeneration of
  `manifests/sky130-riscv-soc.json` pinned `evidence.1.content_hash` to the
  sha256 of the envelope *file* `evidence/item1.json` instead of the
  input-set digest (`provenance.input.content_hash`); the committed report
  from that tree graded item 1 `unmet`/`stale_evidence` and dropped
  `t1_met_count` to 1. The pin now carries the input-set digest
  (`sha256:a6eb388c…`) and the report is regenerated from it: item 1 `met`,
  `t1_met_count` 2, matching `main`. The "checks reproduce (exit 0)"
  statement above held even for the wrong pin — `--check` asserts
  reproduction, not met-ness — so it was not evidence of item 1's state.
- `klt synthesize` runs in this record are local, single-corner synthesis on
  the pinned tools — no batch fleet involved.
