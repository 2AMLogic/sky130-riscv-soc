# soc_top resynthesis: UART TX shifter narrowed to 9 bits (PR #168), 2026-11-17

Resynthesis for issue #153 via PR #168: `tx_sh_q` in `rtl/uart.sv` was 10
bits wide, but bit 0 was written three times and read zero times — the
start bit is driven onto `txd_o` directly at frame start and every later
wire value comes from bit 1, so the register narrows to 9 bits (reset
`9'h1FF`, load `{1'b1, data[7:0]}`, shift `{1'b1, tx_sh_q[8:1]}`, drive
`tx_sh_q[0]`). The branch also merged current `origin/main`, whose
`b3be3df` had removed `soc_fabric`'s dead `per_gnt` tie cell (#182), so
the merged tree's attested sources moved again and this record
re-establishes the chain on the combined tree. Append-only; supersedes
record `20261117T002826Z-b3be3df` (itself the supersedor of
`20261115T205309Z-5e9335c`, which the PR review originally asked this
record to name — main moved again while the PR waited). **Pre-route
synthesis only** — no placement, no routing, no STA, so this record
makes **no Fmax or timing claim**.

## What was run

`scripts/synth-soc.sh` **twice** with the pinned klt 0.9.1
(worktree-local venv install of `klayout-tools==0.9.1`; the host's dev
build was not used), first on unmodified `main @ 566365d` (a detached
scratch worktree; baseline criterion), then on this commit's tree.
`synth_request.json`, `synth_result.json` and `synth_soc_top.ys` here
are the klt request, its unedited JSON output and the Yosys script it
ran; `synth_result_baseline.json` is the unedited output of the
baseline run, kept so the before figures are auditable rather than
asserted. The netlist is `netlist/soc_top_synth.v`, sha256 `4b8ecd67…`
(`provenance.json`). The venv copy's `DEFAULT_YOSYS_TIMEOUT_S` was
relaxed 300 → 3600 (timeout only; same deck) — the same relaxation
prior records made in their uvx cache copies.

**Baseline control:** the baseline run reproduced `main`'s committed
netlist byte-for-byte (sha256 `160672fe…` both) — the delta below is
attributable to the RTL changes alone, not the toolchain.

**Merge control:** the merged tree's regenerated netlist is
byte-identical to the netlist git's textual auto-merge produced when
`origin/main` was merged into the branch — the two sides' changed
regions did not overlap, and running the synthesis confirms the
auto-merge was the true netlist of the combined sources rather than a
coincidence of line splicing.

**Tool environment note:** klt synthesize deadlocks in Yosys' abc pass
on this host when `TMPDIR` is set to the loom sandbox path — same as
the records this one follows; both runs were made with `TMPDIR` unset.

## Verification run alongside

`verification/tools/lint_rtl.sh` passes (default and
`LINT_REQUIRE_CORE=1` forms). Verilator's `UNUSEDSIGNAL` hit on
`tx_sh_q[0]` — the flagged dead bit the PR removes — is gone; the
remaining uart warnings are only the bus `be_i`/`addr_i`/`wdata_i`
slices the issue called normal. `make -C verification soc-gate` passes
on the regenerated netlist with the golden banner transcript
(`soc-gate.log.txt`, `TESTS=1 PASS=1 FAIL=0`). All three `signoff.yml`
legs reproduce locally (`klt signoff --check`: manifest report
`match`, item 1 pass, item 10 pass) against the regenerated
`attest/item1.json` / `evidence/item1.json`, the manifest's item 1
input-set digest and the signoff report.

## Synthesis result (from `synth_result.json`)

- `soc_top`, `sky130_fd_sc_hd`, `tt_025C_1v80`, Yosys 0.67+post, `sv2v`
  (v0.0.13), defines `SOC_ROM_HEX=firmware/soc/banner.hex`,
  `SYNTHESIS`, `SOC_SRAM_MACRO`. `status: ok`.
- **SRAM macros are black boxes** from the macro's Liberty view; their
  area is not in `area_um2`. Liberty origin: the pinned
  `efabless/sky130_sram_macros` TT_1p8V_25C view (`reuse.lock.json`,
  `scripts/fetch-sram-macro.sh`; its sha256 is in `provenance.json`
  and matches the pin this record follows).

## Netlist before/after — measured, same toolchain

| metric | main `566365d` (baseline run) | this commit `73e3afe` | delta |
|---|---:|---:|---:|
| `area_um2` | 222 108.0192 | 222 095.5072 | **−12.5120** |
| `instance_count` | 27 596 | 27 612 | **+16** |
| `sequential_area_um2` | 70 829.1808 | 70 829.1808 | **0** |
| sequential cells (`dfrtp_1`/`dfstp_2`/`dlxtn_1`/`edfxtp_1`) | 2132/97/1/38 | 2132/97/1/38 | 0 |
| `conb_1` | 6197 | 6197 | 0 |
| SRAM macro instances | 8 | 8 | 0 |
| `soc_top` port list | — | — | identical |

The RTL flop count drops by one (`tx_sh_q` 10 → 9 bits), but the
deleted bit was already merged into the `txd_o` output drive in the
baseline netlist too, so the sequential inventory and
`sequential_area_um2` are unchanged; the measurable delta is ABC's
re-mapping of the combinational cone around the narrowed register
(+16 cells, −12.512 µm²). This matches the PR body's observation that
the `tx_sh_q[0]` flop was already merged into `txd_o`.

## Out of scope here, noted

`records/soc-sta-preroute/` and `records/soc-pnr/` bind the superseded
netlist and so describe a netlist one change old (the record this one
supersedes already carried that caveat). This change is
combinational-only against the superseded netlist
(`sequential_area_um2` identical, every flop count identical), so no
recorded timing claim moves in the unsafe direction, but re-running
pre-route STA and P&R on the current netlist is outstanding work, not
covered here. Global route on `soc_top` still fails (GRT-0116,
macro-interior congestion); nothing in this change claims to fix that.
