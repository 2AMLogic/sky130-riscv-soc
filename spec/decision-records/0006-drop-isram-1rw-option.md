# 0006 — Drop the ISRAM_1RW single-port I-SRAM option

- **Status**: accepted (2026-11-15), issue #172, operator ruling by @rjwalters
  (attended `/fleet:decide` round 20261111-r14, q93d)
- **Supersedes**: the port-compatibility statement in `spec/soc.md`
  § Interconnect ("a build with a single-port instruction SRAM (`ISRAM_1RW=1`
  ... ) arbitrates the data-side access against the fetch onto that one port")
  and the option's original intent (PR #73, `WORK_LOG.md`)
- **Superseded by**: none
- **Spec rows**: `spec/soc.md` § Interconnect (row 8a organization unchanged;
  the option paragraph is removed)

## Context

The ratified I-SRAM organization (row 8a, `spec/soc.md` § Parameter table /
§ Interconnect; record 0004 decision 1) is four `1rw1r` macros per memory, two
ports: the data manager on port 0, the fetch on port 1, a data-side write and
a fetch proceeding in the same cycle. Alongside it, `soc_fabric` carried an
`ISRAM_1RW` parameter selecting a single-port I-SRAM: `isd` and `isi` arbitrated
onto one `USE_PORT1=0` wrapper with fixed data-side priority, the fetch's grant
held low while a data access targeted the I-SRAM.

The option was added on purpose, as a port-compatibility aid for a
single-port memory shape (PR #73). It never fit the shipped design:

- No macro view exists for it. `soc_fabric` raised `$error` on any
  `ISRAM_1RW=1` + `SOC_SRAM_MACRO` build (the macro build is 1rw1r per record
  0004), so the option could not reach place-and-route, STA or signoff — it
  lived only in behavioural simulation and lint.
- It kept the ratified row 8a statement company as an unratified alternative
  the spec explicitly called "not the ratified row 8a organization".
- It was the only source of a deasserting subordinate grant in the design:
  `obi_xbar`'s grant/retry path existed mainly for it. With it gone, every
  subordinate grant is constant `1'b1`, and the ONE_RW tests were the only
  direct coverage of a subordinate withholding a grant.
- It cost a whole second verification configuration that had to stay green:
  the `xbar-1rw` and `boot-1rw` Makefile targets, four `skip=not ONE_RW`
  crossbar tests skipped in every other run, one extra Verilator lint pass,
  and CI's second boot run.

## Decision

Remove the option, and in the same change tie the instruction-side grants high
and retire the now-dead grant/retry path:

- `soc_fabric` keeps the `g_isram_1rw1r` body unconditionally; the `g_isram_1rw`
  branch, the `g_no_1rw_macro` guard and the `ISRAM_1RW` parameters
  (`soc_fabric`, `soc_top`) are deleted. The `g_isram_1rw1r` generate-block
  name is kept: `flow/soc/pnr_request.json` pins the macro instance paths
  under `u_fabric/g_isram_1rw1r.u_isram`.
- `obi_xbar` loses its five `*_gnt_i` ports; `i_gnt_o` is constant `1'b1` and
  `d_gnt_o` keeps its real arbitration term (`!i_to_rom` at the boot ROM —
  fetch-priority there is untouched). The one-cycle response contract is
  unchanged.
- The `xbar-1rw` and `boot-1rw` Makefile targets, the `FABRIC_ISRAM_1RW` /
  `FABRIC_SRAM_AW` test plumbing, the four `skip=not ONE_RW` tests and the
  second Verilator lint pass are deleted. CI's boot step runs the default
  build only.

## Consequences

- ~130 LOC fewer across RTL, tests, Makefile and lint; one fewer verification
  configuration to keep green while P&R and STA close. No sim-only
  configuration competes for attention.
- The default (`ISRAM_1RW=0`) netlist is unchanged: the removed logic was
  constant in that build (all grants already tied to `1'b1` at the fabric),
  so re-running `scripts/synth-soc.sh` must reproduce the committed synthesis
  cell count (record `20261115T110935Z-e0a4e18`).
- **Recorded evidence is append-only.** `verification/records/boot/20261029T190315Z-27fc6f5/`
  holds a passing `make -C verification boot-1rw` run, and
  `verification/records/soc-synth/20261114T060249Z-1cab6e0/README.md` lists
  `boot-1rw` in its suite set. Both describe the now-retired configuration and
  stand as history; the targets' retirement is recorded here, not by editing
  those files. No further evidence will be produced for them.
- Record 0004's candidate-B description ("generated 4 KB `1rw` for data, a
  `1rw1r` equivalent for instruction") remains accurate: candidate B was
  already not taken ("nothing from it is imported"), and the `ISRAM_1RW`
  branch was not its reserved escape hatch.
- If a single-port I-SRAM shape is ever needed again, that is a new decision
  record with its own macro-view answer — not a restoration of this option.
