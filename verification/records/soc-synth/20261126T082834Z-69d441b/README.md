# soc_top resynthesis: `obi_xbar.rom_addr_o` narrowed to the 10 bits `boot_rom` reads, 2026-11-26

Resynthesis for issue #225. `boot_rom` is a 4 KB word-addressed ROM whose
address port has been `input logic [11:2] addr_i` since the initial commit,
and `obi_xbar`'s `decode()` already matches `a[31:12] == 0` before `T_ROM`
can be selected. Yet `obi_xbar` exported a 32-bit `rom_addr_o`, muxed per bit
between the instruction and data managers, and `soc_fabric` declared a 32-bit
`rom_addr` only to slice `[11:2]` at `u_rom`: 22 of the 32 bits were driven
into wires nothing reads. The RTL change is two lines in each file — the port
is `[11:2]` and the mux slices both managers; `soc_fabric`'s `rom_addr` is
`[11:2]` and connects to `u_rom` directly. `decode()` still checks the full
32-bit addresses, so unmapped-address and ROM-contention behaviour is
untouched. Append-only; supersedes record `20261117T185051Z-73e3afe`.
**Pre-route synthesis only** — no placement, no routing, no STA, so this
record makes **no Fmax or timing claim**.

## What was run

`scripts/synth-soc.sh` **twice** with the pinned klt 0.9.2
(`uvx --from "klayout-tools==0.9.2" klt` behind a PATH shim; the host's own
klt dev build was not used), first on unmodified `main @ f4b8d9c` (a detached
scratch worktree; baseline criterion), then on this commit's tree.
`synth_request.json`, `synth_result.json` and `synth_soc_top.ys` here are the
klt request, its unedited JSON output and the Yosys script it ran — the same
request and the same script as the record this one supersedes;
`synth_result_baseline.json` is the unedited output of the baseline run, kept
so the before figures are auditable rather than asserted. The netlist is
`netlist/soc_top_synth.v`, sha256 `6d13b4d8…` (`provenance.json`).

**Baseline control:** the baseline run reproduced `main`'s committed netlist
byte-for-byte (sha256 `4b8ecd67…` both) — the delta below is attributable to
the RTL change alone, not the toolchain.

**Repeatability control:** a synthesis of this commit's tree had been made
once before the run recorded here (an interrupted attempt at the same change);
it produced the same sha256 `6d13b4d8…`, so the run recorded here reproduced
that netlist byte-for-byte as well.

**Tool environment note:** klt synthesize deadlocks in Yosys' abc pass on
this host when `TMPDIR` is set to the loom sandbox path — same as the records
this one follows; both runs were made with `TMPDIR` unset. No Yosys timeout
relaxation was needed.

**Counting convention:** `instance_count` and `instance_counts_by_type` in
the klt results are hierarchical counts — a module instantiated N times under
`soc_top` contributes its cells N times (three `cve2_csr` / `cve2_counter`
parameterisations are). Checked against the netlist: the weighted per-type
counts equal klt's for every cell type. The netlist text itself holds 23 864 →
23 844 unique standard cells plus the 8 SRAM macros.

## Verification run alongside

- **The flagged symptom is gone.** `verilator --lint-only -Wno-MULTITOP -Wall
  --top-module soc_fabric` over the fabric sources reports 16 warnings on
  `main @ f4b8d9c` and 15 on this tree; the one that disappeared is
  `%Warning-UNUSEDSIGNAL: rtl/soc_fabric.sv:44:16: Bits of signal are not
  used: 'rom_addr'[31:12,1:0]`. The other 15 are the same before and after
  (line numbers shift by one): the `isd_addr`/`isi_addr`/`dsr_addr`/`per_addr`
  slices, the `uart`/`gpio`/`timer` bus slices, `soc_sram_i`'s unused port-1
  pins and the empty `dout1` connection.
- `verification/tools/lint_rtl.sh` passes in all three forms (default, which
  includes the `soc_fabric 1024 words` leg; `LINT_REQUIRE_CORE=1`;
  `SRAM_MACRO_V=<macro .v>`, the `SOC_SRAM_MACRO` build). Its exit-code test
  (`verification/tools/tests/test_lint_rtl.sh`) passes.
- `make -C verification xbar periph boot soc soc-negative` passes unchanged:
  xbar 9/9 (including `rom_reachable_by_both_managers`,
  `unmapped_addresses_error_and_complete` and
  `rom_contention_gives_instruction_manager_priority`) and `rst_sync` 2/2;
  uart 11, gpio 7, timer 8 and window decode 6; boot 3; banner, echo, GPIO
  and timer-interrupt firmware tests 1/1 each; the perturbed transcript is
  rejected. No test was added, removed or skipped.
- `make -C verification soc-gate` passes on the regenerated netlist with the
  golden banner transcript (`soc-gate.log`, `TESTS=1 PASS=1 FAIL=0`).
- All three `signoff.yml` legs reproduce locally (`klt signoff --check`,
  pinned 0.9.2): manifest report `status: match`, item 1 `match` / `pass`,
  item 10 `match` / `pass` — against the regenerated `attest/item1.json` /
  `evidence/item1.json`, the manifest's item 1 input-set digest and the
  signoff report.

## RTL equivalence check (`equiv/`)

The simulations above sample the change; `equiv/` is a proof that the
narrowing keeps every surviving output of the crossbar unchanged, for every
input sequence. `make_copies.py` derives two copies of `rtl/obi_xbar.sv` —
the file at the parent commit (`f4b8d9c`, sha256 `5c34f600…`) and the
narrowed one (sha256 `b052f981…`) — renaming the module and the narrowed
output so the two pair by name only where intended, and asserts that each of
its edits hits exactly one line. `equiv.ys` and `equiv_aw10.ys` (the default
depth and `ISRAM_AW=10 DSRAM_AW=10`, where the region decode differs) run
sv2v's output of those copies through Yosys `equiv_make`, `equiv_simple -seq
5`, `equiv_induct -seq 5` and `equiv_status -assert`.

- **Result:** `Found 330 $equiv cells … 330 are proven and 0 are unproven`
  at both depths (`equiv.log`, `equiv_aw10.log`). The 330 cells are all 324
  output bits of the narrowed module against the 32-bit original (`rom_addr_o`
  compared on `[11:2]`) plus its 6 state bits (`i_sel_q`, `d_sel_q`); the 22
  dropped bits are paired nowhere, by construction. The two copies share the
  reset branch textually, and `async2sync` is applied to both alike.
- **The check bites:** `equiv_mutated.ys` runs the same proof against a
  narrowed copy with bit 2 of the instruction manager's ROM address forced to
  0 (`make_copies.py --mutate-new`). Exactly one cell stays unproven —
  `rom_addr_o_wide_gold[2]` against `rom_addr_o_narrow_gate[0]` — and
  `equiv_status -assert` exits 1 (`equiv_mutated.log`).

To repeat, from the repository root (needs only `sv2v` and `yosys` at the
pins in `scripts/setup-env.sh`; the generated files stay under the
git-ignored `build/`):

```
mkdir -p build/equiv
git show f4b8d9cd7c34d2681f1b02452099d20ca1aefe44:rtl/obi_xbar.sv > build/equiv/xbar_baseline.sv
python3 -I verification/records/soc-synth/20261126T082834Z-69d441b/equiv/make_copies.py \
    build/equiv/xbar_baseline.sv rtl/obi_xbar.sv build/equiv --mutate-new
for f in xbar_old xbar_new xbar_old_aw10 xbar_new_aw10 xbar_new_mut; do
  sv2v build/equiv/$f.sv -w build/equiv/$f.v; done
E=verification/records/soc-synth/20261126T082834Z-69d441b/equiv
yosys -q -l build/equiv/equiv.log        -s $E/equiv.ys          # exit 0
yosys -q -l build/equiv/equiv_aw10.log   -s $E/equiv_aw10.ys     # exit 0
yosys -q -l build/equiv/equiv_mutated.log -s $E/equiv_mutated.ys # exit 1 (negative control)
```

This is an RTL-level proof of the source change, not a gate-level
equivalence check of ABC's re-mapped netlist; the netlist is covered by the
`soc-gate` run above.

## Synthesis result (from `synth_result.json`)

- `soc_top`, `sky130_fd_sc_hd`, `tt_025C_1v80`, Yosys 0.67+post, `sv2v`
  (v0.0.13), defines `SOC_ROM_HEX=firmware/soc/banner.hex`, `SYNTHESIS`,
  `SOC_SRAM_MACRO`. `status: ok`.
- **SRAM macros are black boxes** from the macro's Liberty view; their area is
  not in `area_um2`. Liberty origin: the pinned `efabless/sky130_sram_macros`
  TT_1p8V_25C view (`reuse.lock.json`, `scripts/fetch-sram-macro.sh`; its
  sha256 is in `provenance.json` and matches the pin this record follows).

## Netlist before/after — measured, same toolchain

| metric | main `f4b8d9c` (baseline run) | this commit `69d441b` | delta |
|---|---:|---:|---:|
| `area_um2` | 222 095.5072 | 221 981.6480 | **−113.8592** |
| `instance_count` (hierarchical) | 27 612 | 27 592 | **−20** |
| `sequential_area_um2` | 70 829.1808 | 70 829.1808 | **0** |
| sequential cells (`dfrtp_1`/`dfstp_2`/`dlxtn_1`/`edfxtp_1`) | 2683/97/1/38 | 2683/97/1/38 | 0 |
| `conb_1` | 7301 | 7301 | 0 |
| SRAM macro instances | 8 | 8 | 0 |
| `obi_xbar` standard cells | 314 | 294 | **−20** |
| `obi_xbar` area (Liberty-priced) | 2061.9776 | 1948.1184 | **−113.8592** |
| `soc_fabric` standard cells | 58 | 58 | 0 |
| `soc_top` port list | — | — | identical |
| netlist lines | 145 505 | 145 425 | −80 |

**Where the delta sits.** 37 of the 40 modules are byte-identical, `soc_top`
port list included; `soc_fabric` changes two lines (`wire [31:0] rom_addr` →
`wire [11:2] rom_addr`, i.e. 22 dangling nets fewer, and `u_rom`'s `addr_i`);
everything measurable is in `obi_xbar`. The issue priced the dead cone
statically at 23 cells / 152.6464 µm², and all 23 are gone, checked by net:
the 20 `nor2b_1` that drove `rom_addr_o[31:12]` (`nor2b_1` 21 → 1), the two
`mux2_2` on `rom_addr_o[1:0]`, and the `buf_2` whose ten loads were all dead
(`buf_2` 2 → 0, `buf_6` 1 → 0, `buf_12` 1 → 0). ABC then re-mapped the rest
of `obi_xbar`, which is not area-neutral: the six live `mux2_4` on
`rom_addr_o[11:6]` became `mux2_2` and the decoders changed cell mix, for a
net **+3 cells / +38.7872 µm²** on top of the removal. Landed total:
**−20 cells / −113.8592 µm²**, not the −23 / −152.6464 of the static
estimate. Cell areas are the pinned `tt_025C_1v80` Liberty values
(`nor2b_1` 6.2560, `mux2_2` 11.2608, `mux2_4` 15.0144, `buf_2` 5.0048,
`buf_6` 11.2608, `buf_12` 20.0192 µm²).

**One unrelated module is not byte-identical.** `cve2_register_file_ff`
differs from the baseline netlist in the order its 4257 instances are emitted
and numbered, and in nothing else: same declaration lines, same cell-type
counts, and the same multiset of cell-type + pin-to-net connections. It is
the reason a textual diff of the netlist is thousands of lines long while the
circuit change is 80. The same order-only difference, checked the same way,
sits between the netlists of the two records before this one (`b3be3df` →
`73e3afe`), so it is not specific to this change.

## Out of scope here, noted

- `records/soc-sta-preroute/` and `records/soc-pnr/` bind the superseded
  netlist and so describe a netlist one change old (the record this one
  supersedes already carried that caveat). This change is combinational-only
  (`sequential_area_um2` identical, every flop count identical), so no
  recorded timing claim moves in the unsafe direction, but re-running
  pre-route STA and P&R on the current netlist is outstanding work, not
  covered here. The SRAM macro instance hierarchy is unchanged, so
  `flow/soc/pnr_request.json` macro paths remain valid.
- This does not resolve the #37 global-route failure (`GRT-0116`), where
  92–97 % of overflow sits in capacity-0 macro-interior tiles
  (`layout/pnr-congestion-analysis.md`); nothing in this change claims to.
- The other `-Wall` unused-signal hits listed above are untouched.
