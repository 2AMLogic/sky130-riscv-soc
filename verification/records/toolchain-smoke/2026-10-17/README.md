# Toolchain smoke record, 2026-10-17

**Toolchain evidence, not design evidence.** The module is a trivial 8-bit
counter (`flow/smoke/counter.v`). It proves the pinned PDK and tools run. It
is never cited for a T1 item, an Fmax, or any design claim.

## Provenance

| Item | Value |
| --- | --- |
| PDK | `sky130A`, open_pdks `f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7` (via ciel, `PDK_ROOT=~/.ciel`) |
| Cell library / corner | `sky130_fd_sc_hd` / `tt_025C_1v80` |
| klt | `0.7.1.dev1765+gb61f753d0369` (KLayout 0.30.12) |
| Yosys | `0.67+post` (git `b8e7da6f40ae8f552c116bf6c359b07c6533e159`) |
| Icarus Verilog | `13.0` (not used by this record) |
| OpenROAD | pinned `26Q3-1510-g6cb3f2b704`; **not run**, see below |
| Host | loom-worker-4 |

## Synthesis leg: run

- Command: `klt synthesize synth_request.json --pdk sky130A --format json`
- Request: `synth_request.json` (sources path is relative to `flow/smoke/`)
- Result: `synth_result.json`; mapped netlist: `counter_synth.v`
- Result: status `ok`, **22 cells** (8 `dfrtp_1`, 14 combinational), area
  296.5344 um^2 (of which 200.192 um^2 sequential), liberty
  `sky130_fd_sc_hd__tt_025C_1v80`.
- The `abc_stime` critical path in the report is a pre-placement synthesis
  estimate, not an Fmax and not a signoff figure.
- `sta` is `null`: the optional `klt_statime_native` extension is not
  installed on this host.
- Re-check: `klt synthesize flow/smoke/synth_request.json --pdk sky130A --check
  verification/records/toolchain-smoke/2026-10-17/synth_result.json` exits 0
  (`status: match`).

## Place-and-route leg: NOT RUN

`klt place-and-route pnr_request.json` was attempted and failed at the
`floorplan` stage before any OpenROAD code ran. The host's `openroad` is a
docker wrapper (image pinned by digest) and the agent user cannot reach the
docker socket: `permission denied while trying to connect to the docker API at
unix:///var/run/docker.sock`. The error text is kept in `pnr_result_not_run.json`; the file was first
committed empty, so it is transcribed from this README, not a verbatim `klt`
capture, and a re-run on a host with docker access succeeded (see the file's
`provenance`).
No P&R figure exists for this module. The fix is host provisioning (docker
access or a native OpenROAD for the worker spec), not a change here.
