# Roadmap

A small RV32IMC microcontroller SoC on sky130 (pinned CVE2 core, OBI crossbar, eight OpenRAM
SRAM macros, boot ROM, UART, GPIO, timer) whose deliverable is a signoff Fmax backed by
post-route multi-corner timing, built with klayout-tools (`klt`) and the open flow.

Status as of 2026-11-13, `main` @ `4d18ba5`.

[`WORK_PLAN.md`](../WORK_PLAN.md) and [`WORK_LOG.md`](../WORK_LOG.md) are generated from labels
and merges and do not say why an item waits; this file does. The verdict of record is
[`manifests/sky130-riscv-soc.signoff.json`](../manifests/sky130-riscv-soc.signoff.json); the
tracker is [#4](https://github.com/2AMLogic/sky130-riscv-soc/issues/4).

## Where it stands

On the README's ladder the repo is at **synthesized, not routed**: the spec is ratified, the RTL
boots firmware in simulation, `soc_top` is synthesized, and place-and-route stops at global
routing. The README's "Status" line and "Current position" still say specification phase; that
is stale (see Now 1).

Graded against the T1 checklist of klayout-tools `docs/design-evidence-tiers.md` by `klt signoff`
0.9.1: **2 of 11 met, 1 not applicable, 8 unmet.**

| Item | Verdict | Evidence or owning issue |
|---|---|---|
| 1 Design sources | met | `rtl/`, `netlist/soc_top_synth.v`, `evidence/item1.json` (PR #84) |
| 2 Layout | unmet | #37: four global-route failures recorded, no routed GDS |
| 3 DRC clean | unmet | #38, waits on #37 |
| 4 LVS clean | unmet | #39, waits on #37 |
| 5 Corner verification | unmet | #40, split into #49 (riscv-arch-test) and #50 (`klt sta`) |
| 6 Monte Carlo | not applicable | `spec/statistical-claims-na.json`, bound by hash; `spec/statistical-claims-na.md` is its checked human-readable mirror (#41) |
| 7 Post-layout verification | unmet | #42, waits on #37 and #40 |
| 8 Characterization report | unmet | #69 |
| 9 Testbenches shipped | unmet | #43, PR #55 open and conflicting |
| 10 Repo hygiene | met | `evidence/item10.json` |
| 11 Power delivery | unmet | #45, waits on #37 and #39 |

- **Simulation.** CI (`.github/workflows/ci.yml`) runs the crossbar, peripheral, boot (both
  instruction-SRAM configurations) and firmware tests (banner, echo, GPIO, timer interrupt).
- **Synthesis.** `verification/records/soc-synth/20261114T060249Z-1cab6e0/`: 27 663 cells,
  223 110 µm² of standard cells, the eight macros as black boxes, banner test passing on the
  netlist. It makes no timing claim: the only figure is ABC's estimate, and `sta` is `null`.
- **Place-and-route.** Floorplan, PDN, placement and clock-tree synthesis pass; global route
  fails with `GRT-0116` in all four recorded runs at the 3.8 mm² die of record 0004
  (`verification/records/soc-pnr/`, [`layout/pnr-congestion-analysis.md`](../layout/pnr-congestion-analysis.md), PR #95).
  92 to 97 % of the overflow is in routing tiles inside macro footprints that have zero
  capacity; a 5.44 µm shift of the same arrangement moves the total from 1490 to 5119. Channel
  width is not what limits the route.
- **Timing.** One pre-route, netlist-level estimate exists
  (`verification/records/soc-sta-preroute/20261113T092526Z-33ebe33/`, `klt sta` on the
  synthesized netlist at `tt_025C_1v80`, 20 ns): every data path closes with at least
  +5.46 ns of slack, so the multiplier and the counters are not the limiter; the only
  failing checks are asynchronous recovery on an unbuffered reset net, a netlist artifact
  that placement resolves. **No Fmax is claimed.** It has no placement, no clock tree, no
  routing and no extraction, it is at the typical corner rather than the slow one, and it is
  not signoff timing and not item 5 evidence. Post-route timing at `ss_100C_1v60` still
  waits on #37 and #50.

## Now

1. **Correct the README's status and re-attest item 10.** The README says "Nothing is designed
   yet", places the repo at "spec ratified" and says `make boot` stays local (CI runs it).
   *Done when:* those three statements match `main` and the CI `signoff` workflow passes. The
   item-10 attestation hashes the README, so the edit and the regenerated
   `evidence/item10.json` land together.
2. **Check the SRAM stand-in model against the pinned macro model.** The gate-level regression
   uses `verification/models/sky130_sram_2kbyte_1rw1r_32x512_8_standin.v` because the pinned
   model does not elaborate in Icarus 13.0; the synthesis record names this as the weak point,
   since nothing compares the two. *Done when:* a script fetches the pinned model, shows the
   stand-in differs from it only in the documented ways, fails on any other difference, and
   runs in CI.
3. **Pre-route timing estimate to answer Gate 2 of record 0001.** The gate asks whether
   `RV32MFast` and the default `MHPMCounterNum` meet the 20 ns budget; `spec/soc.md` § Deferrals
   still lists it as open, and synthesis produced no timing. *Done when:* a `klt sta` report on
   `netlist/soc_top_synth.v` at `tt_025C_1v80` (the one corner with a macro Liberty view) is
   committed as an append-only record labelled pre-route, with the worst paths named, or the
   record states why the pinned `klt` could not produce it and links the klayout-tools issue.
   It is not item-5 evidence and not a signoff Fmax.
4. **Characterization report skeleton (first landing of #69).** One row per id in
   `spec/soc.rows.json`, each cited to a record or marked `not_measured` with the issue it waits
   on, under `characterization/`. *Done when:* the report and `rows.json` are committed and the
   record linter passes. #69 carries a blocked label for its second landing; the skeleton has
   no dependency, per the curation note on that issue.

## Next

- **Retry `soc_top` routing with a macro keep-out (#37).** klayout-tools#5314 added
  `macros[].keepout`, independent of the PDN halo, and klayout-tools#5363 added a per-region
  overflow report; both merged on 2026-11-12, after the four recorded runs. *Done when:* one
  more append-only record under `verification/records/soc-pnr/` states the overflow by layer
  for the baseline arrangement with a keep-out set, on a `klt` that contains both changes. A
  run that still fails is a result, posted on klayout-tools#5313. *Blocked by:* the #37 decision.
- **Item 9 attestation (#43, PR #55).** *Done when:* the PR is merged onto current `main`, the
  item-9 envelope is regenerated from a run of the cold-start commands, and item 9 renders
  `met`. *Blocked by:* a host that can run `make -C verification xbar boot` for the
  re-attestation. The inventory also needs the peripheral and firmware benches added since.
- **riscv-arch-test on the RTL SoC (#49).** Ruled 2026-10-28: run the pinned self-checking
  suite against a testbench-only flat RAM. *Done when:* a `klt functional-verification` report
  with per-test pass/fail is committed, with the decision record that maps the self-check halt
  onto the spec's pass criterion. *Blocked by:* a build host with Sail, riscv-unified-db and a
  newer RISC-V GCC; three attempts stopped there.
- **After a routed design exists:** DRC (#38), LVS (#39), three-corner `klt sta` (#50), ERC and
  power delivery (#45), SDF-annotated regression (#42), then the second landing of #69. Each
  issue already states its done-criterion.

## Later

- **Slow- and fast-corner macro timing.** The macro Liberty covers only `tt_025C_1v80`
  (`spec/soc.md` § STA corners). First question: where does a view at `ss_100C_1v60` and
  `ff_n40C_1v95` come from, regenerated or produced by a sibling?
- **The 50 MHz target against the 25 MHz fallback.** First question: what does post-route STA
  report at the corner that has a macro view? Nothing is decided before that number exists.
- **Stretch rows** (debug module over JTAG, 32 KB of SRAM, SPI flash execute-in-place, 100 MHz).
  First question: has the target row closed? `CLAUDE.md` bars stretch work before it does.
- **Shuttle seat and measured silicon**, the last two ladder steps. First question: are all
  eleven T1 items met?

## Blocked and waiting

**Nothing in the tracker is dispatchable today.** No open issue is in the ready state: nine of
eleven carry a blocked label, #43 is held by its conflicting PR #55, and #4 is the tracker. Now
items 1 to 3 need issues; item 4 needs #69 split or released.

- **#37 waits on a decision.** The 2026-11-11 ruling kept the 3.8 mm² die, allowed at most four
  arrangements and said to stop and return if none routed. That stop was reached. The choices
  posted on #37 are: more arrangements, a retry on an upstream keep-out, or accepting
  `route_allow_congestion` with a long detailed-route run (an earlier one did not converge in
  about 70 minutes). The keep-out now exists upstream (see Next), and klayout-tools#5313 is
  still open for a live before-and-after run with one.
- **PR #55 and #49** each wait on a host with the tools named under Next.
- Seven issues (#38, #39, #40, #42, #45, #50, #69) wait on #37 directly or through each other.

## Not planned

- Growing the die or relaxing a spec row to make the route pass (ruled out on #37).
- Designing the core, a bitcell or SRAM macro, a PLL, or the pad ring (README § Scope); local
  edits to CVE2, which need a decision record.
- Any frequency stated as measured before silicon is on a bench.
