# soc_top resynthesis and post-synthesis regression, 2026-11-14

Resynthesis for PR #150 / issue #142 — `rtl/obi_err_resp.sv` and both of its
instances removed, the OBI error response taken straight off `obi_xbar`'s own
response flops. Append-only; a later record supersedes it. **Pre-route
synthesis only.** No placement, no routing, no STA, so this record makes **no
Fmax or timing claim**.

Supersedes record `20261031T061631Z-3c1fd5a` (netlist `0e03ac74…`). Provenance,
pins and the superseded-netlist note: `provenance.json`.

## Why this run exists

The change was first synthesized at `2d1732e`. Before it could merge, `main`
regenerated the *same* file (`d7d6499`, PR #148 — `soc_sram_d` dropped,
`soc_sram_i` instantiated with port 1 tied off), so the PR went `CONFLICTING`
on `netlist/soc_top_synth.v`. A generated netlist cannot be conflict-resolved
by picking a side — either side would describe sources that no longer exist —
so `origin/main` @ `bd60402` was merged (RTL merged cleanly; only generated
files conflicted) and the netlist was **regenerated from the merged RTL** at
merge commit `1cab6e0`. That commit's tree holds both the sources and the
netlist this run produced.

## What was run

`scripts/synth-soc.sh` (fetch + hash-verify CVE2 and the SRAM macro views,
convert CVE2 with sv2v, `klt synthesize flow/soc/synth_request.json`), then
`make -C verification soc-gate`. `synth_request.json`, `synth_result.json` and
`synth_soc_top.ys` here are the klt request, its unedited JSON output and the
Yosys script it ran; the netlist is `netlist/soc_top_synth.v`, sha256
`53f361e4…` in `provenance.json`.

**Tool pin.** klt was the pinned PyPI release **0.9.1**, invoked as
`uvx --from "klayout-tools==0.9.1" klt` — the `PIN_KLT` value in
`scripts/setup-env.sh` that CI's `signoff` job also reads. The host's own klt is
a newer dev build (`0.9.2.dev1022+g2a9c52b27ce7`) and was **not** used, so this
netlist is attributable to a released, reinstallable tool version.

## Synthesis result (from `synth_result.json`)

- `soc_top`, `sky130_fd_sc_hd`, `tt_025C_1v80`, Yosys 0.67+post,
  `sv_frontend: sv2v` (v0.0.13), defines `SOC_SRAM_MACRO`, `SYNTHESIS`,
  `SOC_ROM_HEX=firmware/soc/banner.hex`. `status: ok`.
- 27 663 instances, `area_um2` 223 110.2304 (standard cells only), sequential
  70 889.2384 um^2, leakage 102.22 nW.
- **SRAM macros are black boxes**, from the macro's Liberty view
  (`blackbox_source: liberty`): `sky130_sram_2kbyte_1rw1r_32x512_8`, 8
  instances. **Their area is not in `area_um2`** (`cells_without_area` lists
  that cell). Liberty origin: the pinned `efabless/sky130_sram_macros`
  TT_1p8V_25C view, sha256 `8656384775f5e1…` (`reuse.lock.json`,
  `scripts/fetch-sram-macro.sh`).
- **Boot ROM**: `boot_rom` is `lowered_to_logic` — Yosys turned the 1024 x 32
  `$readmemh` image into combinational logic (32 768 elaborated memory bits, no
  ROM macro, no flops for the contents). The banner test below is the check
  that the image is really in the netlist.
- **Latch**: the CVE2 clock gate's latch mapped to `sky130_fd_sc_hd__dlxtn_1`
  via `latch_map.negative`, one instance, `validated: true`.
- `timing` is ABC's own estimate (`source: abc_stime`, critical path 6 685.44 ps,
  no wire load, no clock constraint). It is **not STA and not a signoff Fmax**;
  `sta` is `null` (`sta_unavailable_reason`: the optional `klt_statime_native`
  extension is not installed). Do not cite it as a frequency.
- 7 304 `conb_1` tie cells (hilomap emits one per tied bit) — an observation for
  later steps, not a claim.

## Netlist before/after — measured, same toolchain

`main` @ `bd60402` was synthesized **in a separate scratch clone with the same
pinned klt 0.9.1** so the delta is attributable to this change alone and not to
a tool difference. That baseline run reproduced `main`'s *committed* netlist
**byte-for-byte** (`aeb01692…` both), which is also the evidence that the
netlist is reproducible across build roots here.

| metric | main `bd60402` | this PR `1cab6e0` | delta |
|---|---:|---:|---:|
| `dfrtp_1`, elaborated (`instance_counts_by_type`) | 2685 | 2683 | **−2** |
| `dfrtp_1`, raw declarations in the file | 2133 | 2132 | −1 |
| `instance_count` | 27673 | 27663 | −10 |
| `area_um2` | 223 320.432 | 223 110.2304 | −210.2016 |
| `sequential_area_um2` | 70 939.2864 | 70 889.2384 | −50.048 |
| `conb_1` tie cells | 7306 | 7304 | −2 |
| `obi_err_resp` references | 3 | 0 | −3 |
| module declarations | 40 | 39 | −1 |

The **−2 elaborated flops are exactly the two `obi_err_resp` `rvalid_o` flops**
(one declaration, instantiated twice); the remaining 8 cells are the collapsed
grant/error logic. These area and instance deltas are **identical** to the ones
measured before the merge (−210.2016 / −50.048 / −10), so merging `main`'s
SRAM change did not interact with this one.

## Why the removal is exact (and the gating that makes it so)

`i_pend_q && i_sel_q == T_ERR` at cycle N holds **iff** at N−1
`i_req_i && i_gnt_o && i_tgt == T_ERR` held. The direction that matters is that
`i_sel_q` is a **gated** load — `if (i_req_i && i_gnt_o) i_sel_q <= i_tgt`, not
an unconditional one — and its enable is the *same expression* that feeds
`i_pend_q`. That is precisely why the two flops cannot disagree about which
cycle they describe; an unconditional `i_sel_q` load would break the
equivalence. A `T_ERR` target takes the `default:` grant arm, which was
`obi_err_resp`'s constant `assign gnt_o = 1'b1`, so `i_gnt_o` is implied and the
condition collapses to the responder's own `req_i`. Hence `&& i_er_err` could
never change `i_err_o`, and the same holds for `d_er_err`; `d_err_o` keeps its
independent `d_sel_q == T_PER && per_err_i` disjunct. On reset `i_pend_q`,
`d_pend_q` and the responder's flop all clear to 0, so there is no
reset-window divergence.

## Post-synthesis regression ("netlist equals RTL")

`make -C verification soc-gate` runs `test_banner` / `soc_bench.py` against
`netlist/soc_top_synth.v` under Icarus 13.0 with cocotb 2.0.1. `test_banner`
decodes the UART output and compares it with `firmware/soc/banner.golden`:
**PASS**, `TESTS=1 PASS=1 FAIL=0 SKIP=0`, 437.88 s test time (7m21s wall).
Transcript: `soc-gate.log.txt`. Run time is why this is local, not in CI.

Models used, exactly:

- **Standard cells**: the PDK's `sky130_fd_sc_hd` Verilog (`primitives.v`,
  `sky130_fd_sc_hd.v`, open_pdks `f6eeac7d…`), `-DFUNCTIONAL -DUNIT_DELAY=#0`
  (zero-delay functional models).
- **SRAM macros**: **not the real macro model.** The pinned
  `sky130_sram_2kbyte_1rw1r_32x512_8.v` does not elaborate in Icarus 13.0 (its
  `$display` lines index `mem` before the declaration). The run uses
  `verification/models/sky130_sram_2kbyte_1rw1r_32x512_8_standin.v`. This
  substitution remains the weak point of "netlist equals RTL": the stand-in is
  not diffed against the real model by tool.
- **Not run on the netlist**: echo, GPIO and timer. The ROM image is fixed at
  synthesis (banner only), and the GPIO and timer tests read D-SRAM words
  through RTL hierarchy (`SOC_GATE=1` skips that). Gate-level coverage is the
  banner transcript.
- The `soc-negative` perturbation was not re-run on the netlist; the comparison
  code is shared with the RTL run, where it is checked (and passed here).

## RTL-level checks on the merged tree

Not part of this record's synthesis leg, stated so the merge is not taken on
trust: `verification/tools/lint_rtl.sh` → `ok (9 files, …)`, and
`make -C verification xbar periph boot boot-1rw soc soc-negative` → 13 suites,
**65 PASS, 0 FAIL, 5 SKIP** — the same totals and the same 5 skips as before the
merge. All three `.github/workflows/signoff.yml` checks exit 0 on the pinned
klt, with T1 item 1 graded `met`.
