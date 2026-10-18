# Toolchain smoke record, 2026-10-18 (place-and-route leg)

**Toolchain evidence, not design evidence.** Same trivial 8-bit counter as
`../2026-10-17/`. It proves the pinned PDK and tools run end to end, including
OpenROAD. It is never cited for a T1 item, an Fmax, or any design claim.
`../2026-10-17/` is untouched; this record supersedes its `not_run` P&R leg.

## Provenance

| Item | Value |
| --- | --- |
| Host | loom-worker-6 (agent user can run `docker info`) |
| klt | `0.7.1.dev1820+g23b4b033a79e` (KLayout 0.30.12) |
| PDK | `sky130A`, open_pdks `f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7` |
| OpenROAD | `26Q3-1510-g6cb3f2b704`, image `openroad/orfs@sha256:bb7f31697fb8466ab61852fc796376cc16d9df38f762ccb733218b8a5e55824b` |
| Yosys | `0.67+post` |

## Synthesis leg

`klt synthesize flow/smoke/synth_request.json --pdk sky130A --format json`
gave `synth_result.json` (here). `klt synthesize flow/smoke/synth_request.json
--pdk sky130A --check verification/records/toolchain-smoke/2026-10-17/synth_result.json`
reported `status: match`. The netlist is byte-identical to
`../2026-10-17/counter_synth.v` (copied here as the P&R input).

## Place-and-route leg: run, status ok

`cd verification/records/toolchain-smoke/2026-10-18 && klt place-and-route
pnr_request.json --pdk sky130A --format json` (exit 0): `pnr_result.json`
is klt's output unedited; `pnr.err` is its stderr. `status: ok`,
`stage_reached: route`, seed 1, 0 setup/hold/antenna/route-DRC violations.

Figures, from `pnr_result.json` (not transcribed by hand):

- die 1255.99 um^2, core 922.134 um^2, utilization 34.5997 %, wirelength 536 um.
- Layout state: **post-route, OpenROAD estimated parasitics, no extracted
  SPEF** (`spef_sta` is `null`), nominal interconnect corner.
- Worst setup slack 18.9347 ns at `tt_025C_1v80` (clock 20 ns request);
  worst across the 16 reported corners 13.0795 ns at `ss_n40C_1v28`.
- klt's `fmax_mhz` of 938.743 is a **post-route STA estimate at
  `tt_025C_1v80` on a toy counter**, not a signoff Fmax and **not measured**.

**Not a signoff result.** No `request.power` was given, so the layout has only
met1 follow-pin rails and filler cells: no tapcells, straps or PDN vias (see
the warnings in `pnr.err`). No metal-density fill or density check was done.

## Notes

- `.klt/` run directories (DEF, GDS, logs) are gitignored and not committed;
  absolute `def_path`/`gds_path` values in `pnr_result.json` refer to them.
- The klt pin in `scripts/setup-env.sh` was bumped to this host's build. The
  worker spec (`2AMLogic/2am` `infra/aws/loom-worker/worker.env`) tracks klt
  `main` and names no version, so the pin can drift again; see the PR.
