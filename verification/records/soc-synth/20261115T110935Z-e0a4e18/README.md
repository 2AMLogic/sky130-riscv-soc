# soc_top resynthesis: the instruction manager's dead write-payload tie cells removed, 2026-11-15

Resynthesis for issue #161 — `rtl/obi_xbar` declared `i_be_i`/`i_wdata_i` but
never read either: the decode forces every instruction-manager write to the
error responder on `i_we_i` alone (`obi_xbar.sv:113`), so the payload bits
were unreachable by construction. `soc_fabric` only passed them through, and
`soc_top` tied them to `4'hF` / `32'h0`, which synthesis realized as **36
dedicated `sky130_fd_sc_hd__conb_1` tie cells** (4 HI driving the `i_be_i`
bits + 32 LO driving the `i_wdata_i` bits — verified against the baseline
netlist's `.i_be_i({_003_,_002_,_001_,_000_})` / `.i_wdata_i({_036_,…,_005_})`
concatenations; every driven net is exclusive to its port, shared with no
other load). 135.1296 um^2 of pre-route standard-cell area and 36 top-level
nets existing only to feed a channel the design cannot use. The ports are
deleted from `obi_xbar`/`soc_fabric` and the tie-offs from `soc_top`;
`i_we_i`, the read reachability check, is kept. Append-only; supersedes
record `20261115T071555Z-871b88a`. **Pre-route synthesis only** — no
placement, no routing, no STA, so this record makes **no Fmax or timing
claim**.

## What was run

`scripts/synth-soc.sh` **twice** with the pinned klt 0.9.1
(`uvx --from "klayout-tools==0.9.1" klt`; the host's dev build was not used),
first on unmodified `origin/main @ 4d17473` (baseline criterion), then on
this commit's tree. `synth_request.json`, `synth_result.json` and
`synth_soc_top.ys` here are the klt request, its unedited JSON output and the
Yosys script it ran; `synth_result_baseline.json` is the unedited output of
the baseline run, kept so the before figures are auditable rather than
asserted. The netlist is `netlist/soc_top_synth.v`, sha256 `0c5cd5ba…`
(`provenance.json`).

**Baseline control:** the baseline run reproduced `main`'s committed netlist
byte-for-byte (sha256 `ba018bda…` both) — the delta below is attributable to
this change alone, not the toolchain.

**Tool environment note:** klt synthesize deadlocks in Yosys' abc pass on
this host when `TMPDIR` is set to the loom sandbox path
(`/tmp/loom-nt/<uuid>`) — yosys-abc waits at its REPL while Yosys blocks
reading its stdout (same binaries complete with `TMPDIR` unset; filed
generically at `2AMLogic/klayout-tools`, see also klayout-tools #5780). Both
runs were made with `TMPDIR` unset.

## Verification run alongside

`verification/tools/lint_rtl.sh` passes in both forms (default and
`SRAM_MACRO_V=<macro .v>`); `make -C verification xbar periph soc boot`
passes unchanged (no test asserted anything about the instruction-side
payload; `verification/tests/lib/obi_bench.py` now idles the read-only
`MANAGER_INPUTS_I` subset for the `i_` prefix and
`verification/tests/xbar/test_xbar.py` drives `be`/`wdata` only for the data
manager); `make -C verification soc-gate` passes on the regenerated netlist
and the gate-level banner transcript equals the golden (`soc-gate.log.txt`).

## Synthesis result (from `synth_result.json`)

- `soc_top`, `sky130_fd_sc_hd`, `tt_025C_1v80`, Yosys 0.67+post, `sv2v`
  (v0.0.13), defines `SOC_ROM_HEX=firmware/soc/banner.hex`, `SYNTHESIS`,
  `SOC_SRAM_MACRO`. `status: ok`.
- **SRAM macros are black boxes** from the macro's Liberty view; their area
  is not in `area_um2`. Liberty origin: the pinned
  `efabless/sky130_sram_macros` TT_1p8V_25C view (`reuse.lock.json`,
  `scripts/fetch-sram-macro.sh`).

## Netlist before/after — measured, same toolchain

| metric | main `4d17473` (baseline run) | this commit `e0a4e18` | delta |
|---|---:|---:|---:|
| `area_um2` | 222 346.9984 | 222 211.8688 | **−135.1296** |
| `instance_count` | 27 656 | 27 620 | **−36** |
| `conb_1` (elaborated, total) | 6240 | 6204 | **−36** |
| `conb_1` in the `soc_top` body | 276 | 240 | −36 |
| `sequential_area_um2` | 70 829.1808 | 70 829.1808 | 0 |

The −135.1296 um^2 is exactly 36 × 3.7536 (`conb_1` area,
`sky130_fd_sc_hd__tt_025C_1v80.lib`) — not rounded. The −36 `conb_1` in the
`soc_top` body is the **only** cell-type change in the whole netlist; the
remaining tie cells (`240` in the body) drive required constants elsewhere.
No `conb_1` output drives an `i_be_i`/`i_wdata_i` bit any more — the ports
no longer exist on `soc_top`, `soc_fabric` or `obi_xbar`.

## Out of scope here, noted

`records/soc-sta-preroute/` and `records/soc-pnr/` bind the superseded
netlist and so describe a netlist one change old. As with the `dout1` record
this one supersedes, the change is strictly tie-cell-removing (combinational
only: `sequential_area_um2` is identical, and the removed cells drove module
inputs that no longer exist), so no recorded timing claim moves in the unsafe
direction — but re-running pre-route STA and P&R on the current netlist is
outstanding work, not covered here. Global route on `soc_top` still fails
(GRT-0116, macro-interior congestion); nothing in this change claims to fix
that.
