# soc_top synthesis and post-synthesis regression, 2026-10-31

First synthesis of the SoC (issue #35, T1 item 1). Append-only; a later record
supersedes it. **Pre-route synthesis only.** No placement, no routing, no STA, so
this record makes no Fmax or timing claim.

## What was run

`scripts/synth-soc.sh` (fetch + hash-verify CVE2 and the SRAM macro views, convert
CVE2 with sv2v, `klt synthesize flow/soc/synth_request.json`), then
`make -C verification soc-gate`. Provenance and pins: `provenance.json`.
`synth_request.json` and `synth_result.json` here are the klt request and its
unedited output; the netlist is `netlist/soc_top_synth.v` (sha256 in
`provenance.json`). Re-running the script gave the identical netlist hash.

## Synthesis result (from `synth_result.json`)

- `soc_top`, `sky130_fd_sc_hd`, `tt_025C_1v80`, Yosys 0.67+post, `sv_frontend: sv2v`,
  defines `SOC_SRAM_MACRO` (SRAMs become macro instances), `SYNTHESIS`,
  `SOC_ROM_HEX=firmware/soc/banner.hex`.
- 27 650 instances, `area_um2` 222 298 (standard cells only), sequential 70 879 um^2.
- **SRAM macros are black boxes.** `blackbox_modules` is
  `sky130_sram_2kbyte_1rw1r_32x512_8`, 8 instances (4 I-SRAM + 4 D-SRAM).
  **Their area is not in `area_um2`** (macro Liberty area is 284 538 um^2 each, record 0004).
  Liberty origin: the pinned `efabless/sky130_sram_macros` TT_1p8V_25C view, sha256
  `8656384775f5e10b44bed97b7193dd3188ce8cd60b7c8e02a5a4ad9e35ed03ba`
  (`reuse.lock.json`, `scripts/fetch-sram-macro.sh`).
- **Boot ROM**: `memory_mapping` reports `boot_rom` as 32 768 bits, `lowered_to_logic`:
  Yosys turned the 1024 x 32 `$readmemh` image into combinational logic (no ROM
  macro, no flip-flops for the contents). The banner test below is the check that
  the image is really in the netlist.
- **Latch**: the CVE2 clock gate's latch was mapped to `sky130_fd_sc_hd__dlxtn_1`
  with `latch_map.negative` (one instance); left unmapped Yosys writes a behavioural
  `always @*` latch into the netlist.
- `timing` in the result is ABC's own estimate (`source: abc_stime`, critical path
  6 685 ps, no wire load, no clock constraint). It is **not STA and not a signoff
  Fmax**; `sta` is `null`. Do not cite it as a frequency.
- Observations for later steps (#37), not claims: 7 334 `conb_1` tie cells
  (hilomap emits one per tied bit); the register file is flip-flops, not a macro.

## Post-synthesis regression ("netlist equals RTL")

`make -C verification soc-gate` runs the existing `test_banner` / `soc_bench.py`
against `netlist/soc_top_synth.v` under Icarus 13.0. `test_banner` decodes the UART
output and compares it with `firmware/soc/banner.golden`: **PASS**, 17 bytes equal
to the golden, which the RTL run (`make -C verification soc-banner`) matches too.
Log: `soc-gate.log.txt`. Run time about 6 minutes, so it is local, not in CI.

Models used, exactly:

- **Standard cells**: the PDK's `sky130_fd_sc_hd` Verilog (`primitives.v`,
  `sky130_fd_sc_hd.v`, open_pdks `f6eeac7d...`), `-DFUNCTIONAL -DUNIT_DELAY=#0`
  (zero-delay functional models).
- **SRAM macros**: **not the real macro model.** The pinned
  `sky130_sram_2kbyte_1rw1r_32x512_8.v` does not elaborate in Icarus 13.0 (its
  `$display` lines index `mem` before the declaration). The run uses
  `verification/models/sky130_sram_2kbyte_1rw1r_32x512_8_standin.v`, a copy of that
  model's behaviour (same capture/write/read/T_HOLD-to-X timing) with the `$display`
  lines dropped and memory zero-initialised. This substitution is the weak point of
  "netlist equals RTL": the stand-in is not diffed against the real model by tool.
- **Not run on the netlist**: echo, GPIO and timer. The ROM image is fixed at
  synthesis (banner only), and the GPIO and timer tests read D-SRAM words through RTL
  hierarchy (`SOC_GATE=1` skips that). Gate-level coverage is the banner transcript.
- The `soc-negative` perturbation was not re-run on the netlist; the comparison code
  is shared with the RTL run, where it is checked.

## RTL change

`rtl/boot_rom.sv` gained a `SYNTHESIS` branch (the default simulation path is
unchanged; RTL `soc-banner` and `soc-echo` pass, lint passes). Reason: Yosys reads
a submodule before `chparam`, so the `INIT_FILE` parameter cannot carry the image
path into a synthesis run, and `string`, `$value$plusargs` and `$fatal` do not
synthesize. The image path is the `SOC_ROM_HEX` define instead. The issue's
suggested `soc_top` `INIT_FILE` forward was therefore not used (and not made).
