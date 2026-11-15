# soc_top resynthesis: the ISRAM_1RW option and the dead grant/retry path removed, 2026-11-15

Resynthesis for issue #172 — the `ISRAM_1RW` single-port I-SRAM option is
removed (operator ruling 2026-11-15; decision record
`0006-drop-isram-1rw-option.md`). The option had no macro view: `soc_fabric`
raised `$error` on any `ISRAM_1RW=1` + `SOC_SRAM_MACRO` build, so it never
reached P&R, STA or signoff — it existed only in behavioural simulation and
lint while keeping a whole second verification configuration green
(`xbar-1rw`/`boot-1rw` targets, four `skip=not ONE_RW` tests, a second
Verilator lint pass, CI's second boot run). With the option gone every
subordinate grant into `obi_xbar` is constant `1'b1`, so its five `*_gnt_i`
ports are deleted in the same change; `i_gnt_o` is constant and `d_gnt_o`
keeps its real arbitration term (`!i_to_rom` — boot-ROM fetch priority
unchanged). `soc_fabric` keeps the `g_isram_1rw1r` body unconditionally, and
the generate-block name is preserved because `flow/soc/pnr_request.json`
pins the macro instance paths under `u_fabric/g_isram_1rw1r.u_isram`.
Append-only; supersedes record `20261115T110935Z-e0a4e18`. **Pre-route
synthesis only** — no placement, no routing, no STA, so this record makes
**no Fmax or timing claim**.

## What was run

`scripts/synth-soc.sh` **twice** with the pinned klt 0.9.1
(`uvx --from "klayout-tools==0.9.1" klt`; the host's dev build was not
used), first on unmodified `main @ b62c123` (a detached scratch worktree;
baseline criterion), then on this commit's tree. `synth_request.json`,
`synth_result.json` and `synth_soc_top.ys` here are the klt request, its
unedited JSON output and the Yosys script it ran; `synth_result_baseline.json`
is the unedited output of the baseline run, kept so the before figures are
auditable rather than asserted. The netlist is `netlist/soc_top_synth.v`,
sha256 `e4592eca…` (`provenance.json`).

**Baseline control:** the baseline run reproduced `main`'s committed netlist
byte-for-byte (sha256 `0c5cd5ba…` both) — the delta below is attributable to
this change alone, not the toolchain.

**Tool environment note:** klt synthesize deadlocks in Yosys' abc pass on
this host when `TMPDIR` is set to the loom sandbox path
(`/tmp/loom-nt/<uuid>`) — same as the two records this one follows; both
runs were made with `TMPDIR` unset.

## Verification run alongside

`verification/tools/lint_rtl.sh` passes in both forms (default and
`SRAM_MACRO_V=<macro .v>`), single pass now — the alternate-parameter
Verilator pass existed only to lint the removed option and is deleted.
`make -C verification xbar periph boot soc soc-negative` passes: the xbar
suite runs 9 tests including `isram_write_and_fetch_in_same_cycle`, which was
`skip=ONE_RW`-guarded before and now always runs; the four ONE_RW tests are
gone with the option. `verification/tools/tests/test_lint_rtl.sh` passes.
`make -C verification soc-gate` passes on the regenerated netlist and the
gate-level banner transcript equals the golden (`soc-gate.log.txt`). All
three `signoff.yml` legs reproduce locally (`klt signoff --check`: manifest
report `match`, item 10 pass, item 1 pass) against the regenerated
`evidence/item1.json` (new source hashes), `evidence/item10.json` (its
hygiene hashes cover `ci.yml` and `lint_rtl.sh`, both edited here) and
manifest.

## Synthesis result (from `synth_result.json`)

- `soc_top`, `sky130_fd_sc_hd`, `tt_025C_1v80`, Yosys 0.67+post, `sv2v`
  (v0.0.13), defines `SOC_ROM_HEX=firmware/soc/banner.hex`, `SYNTHESIS`,
  `SOC_SRAM_MACRO`. `status: ok`.
- **SRAM macros are black boxes** from the macro's Liberty view; their area
  is not in `area_um2`. Liberty origin: the pinned
  `efabless/sky130_sram_macros` TT_1p8V_25C view (`reuse.lock.json`,
  `scripts/fetch-sram-macro.sh`).

## Netlist before/after — measured, same toolchain

| metric | main `b62c123` (baseline run) | this commit `5e9335c` | delta |
|---|---:|---:|---:|
| `area_um2` | 222 211.8688 | 222 111.7728 | **−100.0960** |
| `instance_count` | 27 620 | 27 597 | **−23** |
| `sequential_area_um2` | 70 829.1808 | 70 829.1808 | **0** |
| sequential cells (`dfrtp_1`/`dfstp_2`/`dlxtn_1`/`edfxtp_1`) | 2683/97/1/38 | 2683/97/1/38 | 0 |
| SRAM macro instances | 8 | 8 | 0 |
| `soc_top` port list | — | — | identical |

The delta is **combinational only**, and it is a re-map, not a clean tie-cell
count: 44 combinational cell types move, netting −23 cells. The two
identifiable mechanisms behind the largest terms, both consequences of the
deleted grant plumbing (the constant `1'b1` fabric ties and the `*_gnt_i`
ports/mux arms are gone, so the cone feeding abc changed):

- `conb_1` 7308 → 7302 (**−6**): the dedicated constant cells that drove the
  removed grant inputs.
- `mux2_1` 13 → 1 (**−12**): the grant muxes' constant-select arms folded
  (`i_gnt_o` is now a direct constant assign; `d_gnt_o` keeps only the
  boot-ROM term).

The remainder (`and2_1` −21, `nor2b_1` +19, `mux2_4` +6, `mux2_2` +3, …) is
abc re-mapping the surrounding combinational cone under the changed
topology; `sequential_area_um2` is byte-identical, every flop count is
identical, `soc_top`'s port list is identical and the SRAM macro hierarchy
(`u_fabric/g_isram_1rw1r.u_isram/g_bank[N].u_macro`, `u_dsram/g_bank[N].u_macro`)
is unchanged, so `flow/soc/pnr_request.json` macro paths remain valid.

## Out of scope here, noted

`records/soc-sta-preroute/` and `records/soc-pnr/` bind the superseded
netlist and so describe a netlist one change old (the record this one
supersedes already carried that caveat). This change is logic-identical on
the default build — the removed grant plumbing was constant — and
combinational-only in effect (`sequential_area_um2` identical), so no
recorded timing claim moves in the unsafe direction, but re-running
pre-route STA and P&R on the current netlist is outstanding work, not
covered here. Global route on `soc_top` still fails (GRT-0116,
macro-interior congestion); nothing in this change claims to fix that. The
retired `boot-1rw`/`xbar-1rw` evidence
(`records/boot/20261029T190315Z-27fc6f5/`, the `boot-1rw` mention in
`records/soc-synth/20261114T060249Z-1cab6e0/README.md`) stands as history of
the retired configuration; its retirement is recorded in decision record
0006, not by editing those files.
