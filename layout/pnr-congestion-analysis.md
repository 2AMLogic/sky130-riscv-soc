# soc_top global-route congestion: analysis (issue #37)

State: **not routed.** Four runs at the 3.8 mm² die
([record 0004](../spec/decision-records/0004-sram-macro-organization.md), unchanged) fail global route
(`GRT-0116`). No routed GDS, no timing, no Fmax figure exists. Evidence is under
`verification/records/soc-pnr/20261111T19280{0..3}Z-11a90b0/` (a0 baseline, a1, a3, a4).
Tools: klt git `34a20645`, OpenROAD `26Q3-1510-g6cb3f2b704`. a0 is a re-run of the earlier
arrangement, not one of the four new arrangements (a1, a3, a4 are three of them; a fourth was not run, see § 3).

## 1. Channel capacity against facing pins (done first)

Macro: 683.1 x 416.54 µm, 123 signal pins: 72 S and 35 N (met4), 10 W and 6 E (met3), plus 2 power.
The LEF has full-footprint obstructions on met1-met3 and met4 around the pins, so nothing routes over a
macro below met5. `scripts/pnr_channel_capacity.py` counts pins facing each vertical gap.

| Arrangement | Pins facing each gap (bottom to top) | Gap height (µm) | Pins / µm |
|---|---|---|---|
| a0 baseline | 144 / 70 / 144 | 78.5 each | 1.83 / 0.89 / 1.83 |
| a1 rebalanced | 144 / 70 / 144 | 94.82 / 51.30 / 94.82 | 1.52 / 1.36 / 1.52 |
| a3 all N+S facing | 107 / 107 / 107 | 78.5 each | 1.36 each |
| a4 baseline +5.44 µm | 144 / 70 / 144 | 78.5 each | 1.83 / 0.89 / 1.83 |

The free vertical space is 1930 - 4 x 416.54 = about 264 µm to share between three gaps. The standard
cells are 0.222 mm² (pre-route) in a 564 µm centre corridor, so cell area is not the constraint.
The global-route report of the 2026-10-31 attempts was not kept; the records above replace it.

## 2. What the router reports

`scripts/pnr_congestion_by_region.py` bins `global_route -congestion_report_file` by macro footprint.

| Attempt | Total congestion | In macro-interior tiles | Tiles with capacity 0 (of macro-interior tiles) |
|---|---|---|---|
| a0 baseline | 1490 | 1368 (92 %) | 1357 of 1360 |
| a1 rebalanced | 8504 | 8274 (97 %) | 7460 of 7493 |
| a3 | 4098 | 3755 (92 %) | 3598 of 3605 |
| a4 (+5.44 µm) | 5119 | 4982 (97 %) | 4709 of 4738 |

Reading: 92-97 % of the overflow is in g-cells whose centre lies inside a macro footprint and whose
capacity is 0. The gaps between macros, which is what the arrangement changes, carry the rest. A 5.44 µm
shift alone moves the total from 1490 to 5119 with identical channel demand, so the total tracks where the
macro pin tiles land against the router's g-cell grid (6.9 µm tiles in these reports), not channel width.
Channel width is not the limiting factor at this die size. This is the evidence for klayout-tools#5313
(an edge keep-out and a per-region overflow report).

## 3. Not established

- The mechanism inside OpenROAD's capacity model for pin tiles inside an obstructed macro. Read from the
  reports only; the OpenROAD source was not read.
- Whether an arrangement with every macro edge on the g-cell grid routes. The 2.72 µm row pitch and the
  6.9 µm tile coincide only at multiples of 938.4 µm, so this cannot be tried by moving macros.
- A fourth arrangement was not run: after a4 the data show arrangement changes move the total by an
  alignment effect, not a capacity trend, so another guess would not follow from the analysis.
  The operator bound is "at most four".
