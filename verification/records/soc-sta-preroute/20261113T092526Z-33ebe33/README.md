# soc_top pre-route STA estimate, `tt_025C_1v80`, 2026-11-13

First timing numbers for the synthesized `soc_top` netlist (issue #102).
Append-only; a later record supersedes it.

> **Every figure below is a pre-route, netlist-level estimate at
> `tt_025C_1v80`.** There is no floorplan, no placement, no clock tree and no
> routing anywhere in this run; the only interconnect model is OpenSTA's own
> liberty wire-load table. These numbers are **not a signoff Fmax**, **not a
> measured Fmax** (nothing here is measured until silicon is on a bench), and
> **not T1 item 5 evidence**. This record says nothing whatsoever about
> `ss_100C_1v60` or `ff_n40C_1v95` — neither corner was analysed, and the
> pinned SRAM macro has no Liberty view at either (`spec/soc.md` § Deferrals).

## What was run

`scripts/fetch-sram-macro.sh` (fetch + hash-verify the pinned macro views),
then one local `klt sta` run, one `openroad` process, one corner:

```
PDK=sky130A klt sta flow/soc/sta_preroute_request.json --format json
```

- `flow/soc/sta_preroute_request.json` — the committed request. `verilog` mode:
  the structural netlist is linked with `read_lef`/`read_verilog`/`link_design`
  and timed against liberty plus `create_clock` alone. No DEF of any kind.
- `sta_preroute_request.json` / `sta_preroute_response.json` here are that
  request and its **unedited** response. `sta_soc_top_synth.tcl` is the OpenSTA
  script `klt` generated, and `openroad-stdout.log.txt` the unedited OpenROAD
  stdout of invocation `91be44f63cad4703bd6b63d96c913ade`. Versions and input
  digests: `provenance.json`.
- Input: `netlist/soc_top_synth.v`, sha256 `0e03ac74…`, matching
  `flow/soc/synth.sha256` and the netlist the synthesis record
  (`soc-synth/20261031T061631Z-3c1fd5a`) produced. No re-synthesis; `rtl/`,
  `spec/` and `netlist/` are untouched by this issue.
- `klt 0.9.2.dev885+ge4c446bd91f2` — **newer than the repo pin**
  (`PIN_KLT=0.8.0` in `scripts/setup-env.sh`). The version above is what
  actually ran. OpenROAD `26Q3-1510-g6cb3f2b704` matches `PIN_OPENROAD`.

Constraints: `clk_i`, 20 ns (50 MHz), `sky130_fd_sc_hd` at `tt_025C_1v80`,
wire load `Small` / mode `top`, the pinned SRAM macro's `TT_1p8V_25C` Liberty
and LEF. No input or output delays, no clock uncertainty, ideal clock.

## The SRAM macros were timed, not black-boxed

This was the open question (AC 6 of #102): whether `klt sta`'s DEF-free
`verilog` mode links a netlist whose 8 instances are hard macros. **It does.**

- The generated Tcl reads the macro Liberty and LEF alongside the standard-cell
  views (`sta_soc_top_synth.tcl` lines 2 and 5), and `link_design soc_top`
  succeeded.
- The OpenROAD log contains **no** `[WARNING STA-0198] module … not found.
  Creating black box …` and no `[ERROR ORD-2013]`. The only warning in the
  whole run is `[WARNING ODB-0220]`, an obsolete-LEF-statement notice from the
  standard-cell LEF.
- The macro Liberty carries real arcs (`setup_rising`/`hold_rising` on
  `din0`/`addr0`/`wmask0`/`csb0`/`web0` against `clk0`, and a `falling_edge`
  `clk0 → dout0` delay), so macro-boundary paths participate in the numbers
  below rather than being untimed.
- `constraint_completeness.unclocked_registers` is 0: every sequential element,
  macros included, is clocked.

So AC 6's failure path did not occur, and no klayout-tools issue is filed for
it. A separate, real tool gap *was* hit — see "Tool friction" below.

## Results (pre-route, netlist-level estimate, `tt_025C_1v80`)

From `sta_preroute_response.json`, verbatim:

| Field | Value |
| --- | --- |
| `timing_status` | `constrained` |
| `geometry_source` | `netlist_estimate` |
| `worst_slack_ns` (setup side, aggregate) | **-65.85033** |
| `total_negative_slack_ns` | -180606 |
| `worst_hold_slack_ns` | **+0.23010** |
| `total_negative_hold_slack_ns` | 0 |
| `setup_violation_count` / `hold_violation_count` | 2780 / 0 |
| `fmax_mhz` (aggregate `1/(T-WNS)` extrapolation) | 11.6482 |
| `clock_skew_ns` | 31.5902 |
| `estimated_power_mw` | 29.1573 (`estimate_only` parasitics, engine-default activity) |

**Read `worst_slack_ns` with its check type, not on its own.** `klt sta`'s
setup-side aggregate spans three check families — data setup, asynchronous
recovery, and clock-gating setup — and here the worst member is an
**asynchronous recovery** check, not a data path. The same is true of
`fmax_mhz`: 11.6 MHz is `1/(20 - (-65.85))` on that recovery check and is
**not** a statement about the data path.

### Worst three paths (setup side)

`klt sta` returns the worst path of each setup-side path group. All three, by
start and end point, worst slack first:

| # | Check | Startpoint | Endpoint | Slack (ns) | Through multiplier / counters / SRAM pin? |
| --- | --- | --- | --- | --- | --- |
| 1 | recovery | `u_rst_sync/_1_/Q` | `u_core/_7_/RESET_B` | **-65.85033** | **No.** Reset-synchroniser flop to a core flop's async reset pin. Not a datapath; no multiplier logic, no counter logic and no SRAM pin is on it. |
| 2 | latch setup | `u_fabric/u_timer/_1529_/Q` | `u_core/core_clock_gate_i/_4_/D` | **+5.45667** | **No.** Timer flop (`dfstp_2`) to the CVE2 clock gate's `dlxtn_1` latch. Not the multiplier, not the counters, no SRAM pin. |
| 3 | clock gating setup | `u_core/core_clock_gate_i/_4_/Q` | `u_core/core_clock_gate_i/_3_/B` | **+9.63387** | **No.** Entirely inside the core clock gate. |

Hold side, same shape: `removal` `u_rst_sync/_1_/Q → u_core/_7_/RESET_B`
+38.47223; `clock gating hold` +0.23010 (the reported hold WNS); `hold`
`u_fabric/u_gpio/_250_/Q → u_fabric/u_gpio/_258_/D` +0.33801. Hold is clean —
zero hold violators — but on an **ideal** clock with no clock tree, so a
post-CTS run is the one that decides hold.

### What the 2780 setup violations actually are

Every one of them is an asynchronous reset/set recovery check; there is **not
one data setup violation**. From `openroad-stdout.log.txt`
(`report_check_types -max_delay -recovery -clock_gating_setup -violators`,
which reports a single path group, `max_delay/setup group asynchronous`):

| Endpoint pin | Cell | Count | Slack (ns) |
| --- | --- | --- | --- |
| `RESET_B` | `sky130_fd_sc_hd__dfrtp_1` | 2683 | -65.85 |
| `SET_B` | `sky130_fd_sc_hd__dfstp_2` | 97 | -40.51 |

All 2780 share one cause and one number: every row reports the same
`Actual Delay` of 62.26 ns. The reset net leaves `u_rst_sync/_1_/Q` and reaches
all 2780 asynchronously-reset flops with **no buffering whatsoever** — `soc_top`
contains no buffer or inverter cell at all, and `rst_n` goes straight from the
synchroniser flop through the `u_core` and `u_fabric` port boundaries to every
`RESET_B`/`SET_B` pin. Under a fanout-extrapolated wire-load model one net of
that fanout is charged 62.26 ns. Buffering it is placement/resizer work, which
has not happened — this run has no placement at all. **It is an artifact of timing an unbuffered netlist, not a
design defect, and it is not evidence about the datapath.** No SRAM macro pin
appears anywhere in the violator list.

The multiplier (81 endpoints under
`u_core/u_cve2_core/ex_block_i/genblk2.gen_multdiv_fast.multdiv_i/`) and the
performance counters (400 endpoints under
`u_core/u_cve2_core/cs_registers_i/…mcounters_variable_i/`) appear in that list
**only as `RESET_B` pins of that same reset net, at that same -65.85 ns**, i.e.
only as reset-distribution endpoints and never as data endpoints.

### The data path, which is what Gate 2 asks about

Two independent readings of the same run agree:

1. The violator report lists **zero** data setup endpoints — every data setup
   path has non-negative slack at a 20 ns period.
2. `find_timing_paths` returned exactly three max-delay path groups — the
   three rows above. Two of them are the `asynchronous` group (#1) and the
   clock-gating group (#3), so the third is the `clk_i` group, where every
   register-to-register data path lives, and #2 is its **worst** member at
   **+5.45667 ns**. Every data path in this netlist — multiplier and counters
   included — therefore has at least +5.46 ns of slack at 20 ns.

So the longest data path under this estimate is at most 20 - 5.4567 =
**14.54 ns**. Applying the same `1/(T-WNS)` extrapolation `klt` uses, that
group alone extrapolates to about **69 MHz** — a pre-route, netlist-level
estimate at `tt_025C_1v80`, nothing more.

## Control run: the wire-load setting is load-bearing

The request sets `wire_load_model: "Small"` / `wire_load_mode: "top"`, which is
what `sky130_fd_sc_hd__tt_025C_1v80.lib` itself declares as
`default_wire_load` / `default_wire_load_mode`. A control run with both fields
omitted (`control_nowireload_request.json`, `control_nowireload_response.json`)
was made to check that stating them explicitly changes nothing. **It is not
identical** — omitting them is not the same as setting them to the liberty
default:

| | explicit `Small`/`top` | omitted |
| --- | --- | --- |
| `worst_slack_ns` | -65.85033 | -63.12115 |
| worst data-group path slack | +5.45667 | +5.66211 |
| `fmax_mhz` | 11.6482 | 12.0306 |
| `clock_skew_ns` | 31.5902 | 29.7029 |
| `setup_violation_count` | 2780 | 2780 |

Same path identities, same conclusion, numbers about 2 ns apart on the reset
check and 0.2 ns on the data group. The explicit form is the one recorded,
because a record whose parasitics basis is only implied by a liberty default is
not reproducible from the request alone. To reproduce the control, copy
`control_nowireload_request.json` into `flow/soc/` and run `klt sta` on it
(its relative paths resolve from that directory).

## What this does and does not constrain

- **I/O paths were not timed.** No `set_input_delay` / `set_output_delay` was
  given, so `constraint_completeness` is `incomplete`: 27 unconstrained
  endpoints. The tool samples only the first 20 (`sample_limit: 20`), but the
  27 account for exactly the design's I/O boundary, and nothing else: the 18
  output bits (`uart_txd_o`, `gpio_o[7:0]`, `gpio_oe_o[7:0]`, `core_sleep_o`)
  plus the 9 first-stage input synchroniser flops whose `D` is driven straight
  from an input port (`u_fabric/u_gpio/_250_…_257_` from `gpio_i[7:0]`, and
  `u_fabric/u_uart/_892_` from `rxd_i`). 18 + 9 = 27 — derived from the
  netlist, since the response truncates the list. No interior path is
  unconstrained. Declaring an I/O budget is a spec decision this issue does not
  make, so none was invented.
- **Ideal clock, no clock tree.** `clock_mode: "ideal"`; `clock_skew_ns`
  31.5902 is a wire-load artifact of the unbuffered clock net, not a measured
  skew.
- **No parasitics.** `power_basis.parasitics` is `estimate_only`, so
  `estimated_power_mw` 29.16 is a wire-load-model estimate, not an extracted
  one.
- **Macro paths are bounded, not enumerated.** Macro-boundary paths are timed
  and all sit at or above +5.46 ns of slack, but `klt sta` cannot list them
  individually (see below), so this record bounds them rather than naming them.

## What this implies for Gate 2 of decision record 0001

`spec/decision-records/0001-core-choice.md` Gate 2: the `RV32MFast` multiplier
and the default `MHPMCounterNum` (10) meet the 50 MHz budget, otherwise take
`RV32MSlow` and/or trim counters, each recorded.

**This estimate gives no reason to leave `RV32MFast` or to trim
`MHPMCounterNum`.** At the 20 ns (50 MHz) target every data path, multiplier
and counters included, has at least +5.46 ns of slack, and neither block
appears as a data endpoint in any violation. The only failing checks are
asynchronous recovery/removal on an unbuffered reset net, which no multiplier
or counter choice affects.

**No path here would justify a decision record**, and this record changes
nothing: `rtl/`, `spec/` and `spec/soc.md` § Deferrals are untouched, and the
deferral stays open. It is deliberately weak evidence — a pre-route estimate
with a liberty wire-load model, no placement, no clock tree, no extraction, and
at the typical corner, not the slow one the 50 MHz target is stated against. It
is **not** sufficient to close Gate 2; closing it needs post-route timing at
`ss_100C_1v60`, which needs place-and-route (#37) and the routed multi-corner
run (#50), both held. What it does establish is that the multiplier and the
counters are not the limiter today, so neither should be changed pre-emptively
ahead of that evidence.

The first thing post-route timing should check, on this evidence, is the reset
distribution network — not the datapath.

## Tool friction

Filed as [`2AMLogic/klayout-tools#5424`](https://github.com/2AMLogic/klayout-tools/issues/5424)
(friction protocol): `klt sta`'s
response exposes only a single worst path per side and no per-check-family or
per-path-group slack, so an asynchronous recovery violation silently captures
`worst_slack_ns` and `fmax_mhz`, and the data-path answer this record needed
had to be recovered by scraping the retained OpenROAD stdout log. The
per-group worst-path table and the violator breakdown used above exist only in
`openroad-stdout.log.txt`, which is unstructured text under gitignored `.klt/`
scratch — hence its copy here.
