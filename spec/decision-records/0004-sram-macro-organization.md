# 0004 — SRAM macro organization: eight 2 KB `1rw1r` macros; die budget 3.8 mm²

- **Status**: accepted (2026-10-27), settles spec row 8a and the die budget of row 8 (issue #36)
- **Supersedes**: none (completes the deferred item 5 of [0002](0002-sram-source.md))
- **Superseded by**: none
- **Spec rows**: `spec/soc.md` rows 8, 8a, § SRAM source and size, § Deferrals

## Context

[0002](0002-sram-source.md) ratified the source (OpenRAM sky130 macros) and the
organization requirement, and left the instance open between candidate A (four
prebuilt 2 KB `1rw1r` per memory) and candidate B (generated 4 KB `1rw` for data,
a `1rw1r` equivalent for instruction). Place-and-route (#37) needs both settled.

## Measurements

Pinned views: `efabless/sky130_sram_macros` @ `ebfbf5775c8cd433ad38a4d825e46c2275231511`
(`reuse.lock.json`). Read 2026-10-27 from the Liberty and Verilog copies in the
local ciel sky130 install (`sky130A/libs.ref/sky130_sram_macros/`), whose sha256
equal the pinned ones; the LEF was fetched from the pinned commit (sha256
`e35072ac…` = the pin). The ciel GDS/LEF differ from the pin
(`c3f1322c…` vs `c91d3552…`, `8584db5b…` vs `e35072ac…`); the LEF differs
in a `FOREIGN` line (geometry rows not compared), so the ciel GDS/LEF were not used.

| Quantity | Value | Source and command |
|---|---|---|
| Macro size | 683.1 x 416.54 µm | pinned LEF: `grep -n SIZE sky130_sram_2kbyte_1rw1r_32x512_8.lef` → `SIZE 683.1 BY 416.54 ;` |
| Macro area (bbox) | 0.284538 mm² | 683.1 x 416.54 µm = 284538.474 µm² |
| Macro area (Liberty) | 284538.474 µm² | `grep -n '^ *area' …_TT_1p8V_25C.lib` → `area : 284538.474;` (equal to the bbox) |
| Macros | 8 (4 instruction + 4 data) | 4 x 512 words x 32 bit = 8 KB per memory |
| Total macro area | 2.2763 mm² | 8 x 0.284538 |

## Decision

1. **Candidate A.** Each memory is four `sky130_sram_2kbyte_1rw1r_32x512_8`
   macros, bank = `addr[10:9]`, word address inside the bank `addr[8:0]`. The
   views exist and are pinned; candidate B has no views, so its area is unknown
   and it cannot be placed. B is not taken and nothing from it is imported.
2. **Data memory uses `1rw1r` macros with port 1 tied off** (`csb1` = 1,
   `addr1` = 0, `dout1` unconnected, `clk1` = `clk0`). No `1rw` view exists, so
   the data side pays for an unused read port; its area cost is *not
   quantified* (no `1rw` macro area to compare). This is the price of using
   views that exist; a `1rw` macro would be a new record.
3. **Die budget: 3.8 mm² core area** (about 1.95 x 1.95 mm). Derivation:
   2.2763 mm² of macros / 0.60 macro share = 3.79 mm², rounded up. The 0.60 is
   an **assumption** (macro share of the core area, leaving ~1.5 mm² for CVE2,
   the crossbar, peripherals, 4 KB boot ROM, macro halos, routing channels and
   PDN). It is an input to #37, not a measured result: standard-cell area is not
   yet synthesised, and #37 reports the utilisation it actually reaches.
4. **16 KB fits the budget, so the 4 KB unified fallback is not taken**, and the
   memory map in `spec/soc.md` is unchanged. If #37 shows the budget is missed,
   the fallback is taken by a new record that supersedes this one.
5. **Wrappers.** `rtl/soc_sram_i.sv` — the one wrapper for every SRAM in
   `soc_fabric` — instantiates the macros under `-DSOC_SRAM_MACRO`; the
   default (no define) is the behavioural model, unchanged. Read data is
   selected by a bank select registered on each read, matching the one-cycle
   registered read. Power pins (`USE_POWER_PINS`) are left to #37. Rejected:
   separate wrapper modules per macro style (changes the module the fabric
   instantiates).

   **Amended 2026-11-15 (#149):** the wrapper gains a
   `parameter bit USE_PORT1` (default `1'b1`). Single-port use — the D-SRAM
   and the `ISRAM_1RW=1` I-SRAM — elaborates `USE_PORT1=0`, which builds no
   port-1 bank select or output mux, drives `dout1` to a constant, and under
   `-DSOC_SRAM_MACRO` ties every macro's `csb1` high with `addr1` zero. A
   plain instance-level tie-off leaves the port-1 register and output mux in
   the shared wrapper elaboration (+1022 um2 pre-route standard-cell area,
   measured in #149); parameterizing the port recovers it while the memory
   model, byte mask, read timing and bank decode stay in this one wrapper.
   The synthesized macro hierarchy `u_fabric/u_dsram/g_bank[k].u_macro` and
   its `g_isram_1rw1r.u_isram` twin are unchanged, so the P&R macro paths
   stand.

## Verification status of the macro build

- **Default build**: `make -C verification xbar-fabric`, 8 of 8 tests pass.
  (`boot` needs the generated core and was not run.)
- **Macro build**: `SRAM_MACRO_V=<macro .v> verification/tools/lint_rtl.sh`
  lints clean with Verilator (`--timing`).
- **Not simulated.** Icarus 13.0 does not compile the pinned macro `.v`
  ("Scope index expression is not constant: addr0_reg", `mem` is used in
  `$display` before its declaration). The model is generated and pinned, so it
  is not edited here. Functional claims about the macro build are therefore
  *unverified* by simulation; they rest on the lint and the review below.

## Behaviour differences to check when the macro build is first simulated

Read from the pinned `.v`, not yet exercised:

- The model writes and reads at `negedge clk` and `dout` is `x` for `T_HOLD`
  after every `posedge`, driven valid `DELAY` after the next `negedge`; the
  behavioural model holds `dout` until the next read. Consumers sample at
  `posedge`, so they see valid data only for the cycle after a read.
- A same-cycle port-0 write and port-1 read of one address prints a warning and
  the order is a race at `negedge`; the behavioural model returns old data.
  The fabric does not rely on that case (comment in `soc_sram_i.sv`).
- Bank boundaries and byte masks per bank are covered by the existing xbar
  tests only in the behavioural build.

## Consequences

- Macro Liberty is `TT_1p8V_25C` only; the corner gap in
  [0002](0002-sram-source.md) and `spec/soc.md` § STA corners stands unchanged.
- #37 gets: 8 macros of 683.1 x 416.54 µm, a 3.8 mm² core budget and the
  assumption behind it.

## Amendment note (2026-11-23, issue #122)

Decision 1 declined candidate B and imported nothing from it. The generator pin
that [0002](0002-sram-source.md) Decision 2 recorded in `reuse.lock.json`
(`VLSIDA/OpenRAM`, the two `macros/sram_configs/` files) served only candidate B
and no script fetched or verified it, so it left the lock on this date. 0002 is
unchanged and keeps the OpenRAM commit and the facts read from it as recorded
context. The operator ruled this removal (option a) on 2026-11-23; T1 item 1 was
re-attested for the changed `reuse.lock.json`.
