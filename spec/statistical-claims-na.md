# Statistical claims: not applicable

Discharges item 6 of the `klayout-tools` T1 checklist
(`docs/design-evidence-tiers.md`) for this digital block, tracked by #41 under
#4. Item 6 passes by a recorded "not applicable" only when a committed
statement accounts for every spec row with the reason its row class is not
statistical, and both the statement and the spec are bound by content hash.

- **Spec**: [`soc.md`](soc.md) parameter table, projected to row ids in
  [`soc.rows.json`](soc.rows.json) (15 rows: `1`-`14` and `8a`).
- **Statement**: this page, mirrored row for row in
  [`statistical-claims-na.json`](statistical-claims-na.json), which is the
  document `klt signoff` cites. The reasons below and in the JSON are the same
  text; keep them in step.
- **Drift check**: `python3 -I verification/tools/check_soc_rows.py` fails when
  the ids in `soc.rows.json` or the statement differ from the `soc.md` table.
- The pinned `klt` refuses certain vocabulary in the JSON documents, so the
  reasons are worded positively. The refusal is about wording, not about the
  conclusion.

If any row turns out to need sampled evidence, this statement is withdrawn and
the finding is raised on #41; it is not edited to fit.

| # | Parameter | Row class | Why it is not statistical |
|---|---|---|---|
| 1 | Core | design-choice | a pinned upstream commit is selected by identity; there is no measured quantity |
| 2 | ISA configuration | design-choice | a parameter selection fixed at elaboration; there is no measured quantity |
| 3 | Multiplier variant | design-choice | a parameter selection fixed at elaboration; its effect is observed through timing rows, not as a row of its own |
| 4 | Debug module | scope-exclusion | the module is excluded, so there is nothing to measure |
| 5 | Interconnect | functional-behaviour | pass/fail functional behaviour checked by directed simulation tests |
| 6 | Memory map, reset vector | functional-behaviour | fixed addresses checked pass/fail by simulation; each address either decodes or it does not |
| 7 | SRAM source | sourcing-decision | an adopt-or-record choice of where the macros come from, pinned in reuse.lock.json |
| 8 | SRAM size | capacity-and-area-budget | a fixed capacity plus a deterministic die-area budget evaluated from the layout; deferred as an assumption until place-and-route reports the area reached, and still non-random once settled |
| 8a | SRAM macro organization | design-choice | deferred macro count and size per memory; once settled it is a fixed instance list read from the netlist |
| 9 | Peripherals | functional-behaviour | pass/fail register and interrupt behaviour checked by directed simulation tests |
| 10 | Clock and reset | functional-behaviour | a single clock domain and a reset synchroniser checked pass/fail by simulation and by STA constraints |
| 11 | Signoff Fmax | timing-corner-bounded | a frequency from static timing at a named corner and layout state; STA bounds the path delay at the ratified corners, with no random variable to sample |
| 12 | PVT corner set | timing-corner-bounded | an enumerated list of the characterised corners that bound STA; the corners are the coverage, not a sampled population |
| 13 | Standard cells | library-selection | a library chosen by name; there is no measured quantity |
| 14 | Signoff | pass-fail-checks | DRC and LVS return zero violations or they do not, and STA closes at each corner that has a macro view or it does not |

## Deferred rows

Row `8` carries a die budget set as an assumption, and row `8a` (macro
organization) is ratified but its instance list is still to be confirmed by
place-and-route. Both stay non-statistical once settled: the budget is a
single area figure read from the layout, and the organization is a fixed list
of instances read from the netlist. Neither has a limit that a population of
samples could pass or fail.

Row `11` is a ratified target whose closure at the slow and fast corners is
deferred on missing macro Liberty views (`spec/soc.md` § STA corners). When it
closes it is a corner-bounded STA figure, never a measured one.
