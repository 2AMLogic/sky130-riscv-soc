# 0002 — SRAM source: adopt OpenRAM sky130 macros; sibling recorded, not adopted yet

- **Status**: accepted (2026-10-17), ratified by issue #2
- **Supersedes**: none
- **Superseded by**: none (expected: a record adopting `sky130-sram-compiler`
  once it delivers views for the corners in `spec/soc.md` § STA corners)
- **Spec rows**: `spec/soc.md` § SRAM source, § SRAM size, § STA corners

## Context

CLAUDE.md makes the SRAM source an adopt-or-record decision under the fleet's
reuse rule (`2AMLogic/2am` `REUSE.md`: a block is designed once; a same-PDK
sibling is adopted or the reason recorded). Three candidates were named.

Facts read on 2026-10-17 from shallow clones; each carries its source.

**`2AMLogic/sky130-sram-compiler`** (the fleet sibling). Its README states
"Status: just opened, specification phase. Nothing is designed yet", targets
a logic-rule 6T bitcell, and lists views per instance (GDS, LEF, Liberty,
Verilog) only as a *target*. No macro, no Liberty view and no maturity rung
beyond "pre-spec" exists to adopt. Not usable today.

**OpenRAM-generated sky130 macros.**
- Generator: https://github.com/VLSIDA/OpenRAM, commit
  `b2b069ce119d1488cbe6883b2240bceb5c7ce29a` (`VERSION` = 1.2.49). sky130
  configs live in `macros/sram_configs/`; the shared config sets
  `nominal_corner_only = True` and `check_lvsdrc = True`
  (`sky130_sram_common.py`).
- Pre-generated macros: https://github.com/efabless/sky130_sram_macros,
  commit `ebfbf5775c8cd433ad38a4d825e46c2275231511`, Apache-2.0. It ships
  GDS, LEF, Verilog and a Liberty view for 1 KB (`32x256`, `8x1024`) and 2 KB
  (`32x512`) `1rw1r` macros. A 4 KB and 16 KB directory exist but hold only a
  log, no views. Every Liberty file in the repo for these sizes is
  `TT_1p8V_25C`; the legacy `sram_1rw1r_32_256_8_sky130` directory also
  has TT 1.7/1.9 V, TT 0/100 C and SS/FF at 1.8 V 25 C.
- The 2 KB macro `sky130_sram_2kbyte_1rw1r_32x512_8`: LEF `SIZE 683.1 BY
  416.54` µm; Liberty `area : 284538.474` µm² (0.2845 mm²). The 1 KB
  `32x256` macro is `479.78 BY 397.5` µm. Ports of the 2 KB macro `clk0 csb0 web0 wmask0[3:0] addr0[8:0] din0[31:0]
  dout0[31:0]` (port 0 read/write) and `clk1 csb1 addr1[8:0] dout1[31:0]`
  (port 1 read-only); supplies `vccd1 vssd1`.
- OpenRAM's own sky130 corner sweep is `supply_voltages = [1.7, 1.8, 1.9]`,
  `temperatures = [0, 25, 100]` (`technology/sky130/tech/tech.py:736,740`).
- OpenRAM has a 4 KB single-port config meant for RISC-V main memory,
  `sky130_sram_4kbyte_1rw_32x1024_8.py` (32-bit words, 1024 words, 8-bit
  write granularity, 1 RW port).

**Standard-cell RAM.** Flop/latch arrays synthesized from `sky130_fd_sc_hd`.
Needs no macro views, but 8 KB x 2 of flops is far larger than macros at
the 8 KB scale (sizing estimate, *unverified*; not measured here) and
provides no macro-integration evidence, which is the point of this repo.

## Decision

1. **Source: adopt OpenRAM-generated sky130 macros** for the target
   instruction and data SRAM. The macros are not designed or modified here.
2. **Pins** (recorded in `reuse.lock.json`): generator OpenRAM
   `b2b069ce…`; pre-generated views from `efabless/sky130_sram_macros`
   `ebfbf577…` for the macro sizes that have views.
3. **Sibling: named, not adopted.** `2AMLogic/sky130-sram-compiler` is
   recorded as `in_tree: evaluate` in `reuse.lock.json`. It is revisited when
   it publishes a simulation-validated macro with Liberty views at the
   `spec/soc.md` corners; adopting it is a new record that supersedes this
   one. This repo does not design an SRAM.
4. **Organization requirement (ratified):** the instruction memory needs two
   independent ports — one the data-side loader writes, one the instruction
   fetch reads — so it is built from `1rw1r` macros; the data memory is a
   single `1rw` port with byte write masks. Word width 32, write
   granularity 8 bits. This follows from the memory map (a boot ROM that
   copies code into instruction SRAM) and the two-manager crossbar.
5. **Organization instance (deferred, named gate):** the exact macro count
   and size per memory is **not** ratified here. Two candidates:
   - *A. Prebuilt views:* four `sky130_sram_2kbyte_1rw1r_32x512_8` per
     memory (8 macros, 8 x 0.2845 = 2.276 mm² of macro area, computed from
     the Liberty `area`). Views exist today, TT only.
   - *B. Generated:* two `4 KB 1rw 32x1024` (data) and a `1rw1r` equivalent
     (instruction) from the pinned OpenRAM; no views exist yet and area is
     unknown.
   Settled by: the SRAM-integration issue under #4 (macro floorplan, with
   die budget set there), by recording macro area and the views produced.

## Alternatives considered

- **Standard-cell RAM** — rejected as the primary (area, and no macro
  integration exercised); kept as the 4 KB-unified-fallback escape if the
  macro views prove unusable.
- **`sky130-sram-compiler`** — rejected today only because nothing is
  delivered; named so the adopt-or-record question stays visible.
- **Designing a macro here** — out of scope (README, CLAUDE.md).

## Consequences

- **Liberty provenance is a recorded risk.** The adopted views are `TT_1p8V_25C`
  only. They cover the `tt_025C_1v80` STA corner and **do not cover**
  `ss_100C_1v60` or `ff_n40C_1v95`. OpenRAM's own sweep also stops at 1.7-1.9 V
  and 0-100 C, so even regenerating cannot natively reach 1.60 V or -40 C
  (*unverified* whether the tech file's lists can be overridden by a user
  config). `spec/soc.md` therefore forbids calling any slow-corner or
  fast-corner Fmax a signoff figure until a macro view exists at that corner,
  and requires interim numbers to be labelled as using the TT macro view.
- A tool gap candidate for klayout-tools or OpenROAD: multi-corner STA with a
  macro Liberty missing at some corners. To be filed generically when first
  hit in the P&R issue.
- Functional simulation uses the macro's Verilog behavioral model, wrapped
  behind a PDK-independent memory interface (`spec/soc.md` § Seam).
