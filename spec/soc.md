# SoC specification — sky130-riscv-soc

- **Status**: ratified 2026-10-17 by issue #2, with the deferrals listed in
  § Deferrals. Changes go through a new decision record; agents do not relax
  a row to make a result pass.
- **Decision records**: [0001 core](decision-records/0001-core-choice.md),
  [0002 SRAM source](decision-records/0002-sram-source.md).
- **Pins**: [`reuse.lock.json`](../reuse.lock.json).
- Upstream facts carry a source (file, URL or commit). A statement marked
  *unverified* was not read from a source at ratification.

**Fmax rule.** Every frequency here is a *target* for a **signoff Fmax**
from static timing, stated with corner and layout state (pre-route /
post-route / extracted). No figure in this repo is *measured* until silicon is
on a bench, and a simulated or STA figure is never called measured.

## Parameter table

One row per README table row and per bullet in issue #2 "Parameters to
decide". Status is `ratified` or `deferred`; a deferral names what settles it.

| # | Parameter | Status | Ratified value | Fallback / stretch (deferrals only) | Record |
|---|---|---|---|---|---|
| 1 | Core | ratified | CVE2 (CV32E20), `cve2_top`, pinned `d7f21568028a1114be663599bd42145dccf28928`, unmodified | Ibex `small` (pin read `65368a4c…`) needs a new record; fallback ISA RV32EC | [0001](decision-records/0001-core-choice.md) |
| 2 | ISA configuration | ratified | RV32IMC: `RV32E=0`, `RV32M=RV32MFast`, C extension built into the core | RV32EC, `RV32MSlow` (area) — taken only via a record | 0001 |
| 3 | Multiplier variant | ratified | `cve2_pkg::RV32MFast` | `RV32MSlow`; `RV32MSingleCycle` rejected (critical path) | 0001 |
| 4 | Debug module | ratified: out of scope | `debug_req_i` tied 0, no JTAG | README stretch; adding it is a spec change | 0001 |
| 5 | Interconnect | ratified | OBI v1.4 crossbar, 2 managers (instruction, data), 4 subordinates | single shared OBI bus (fallback) | § Interconnect |
| 6 | Memory map, reset vector | ratified | § Memory map | — | § Memory map |
| 7 | SRAM source | ratified | adopt OpenRAM sky130 macros; `sky130-sram-compiler` named, not adopted | standard-cell RAM | [0002](decision-records/0002-sram-source.md) |
| 8 | SRAM size | ratified; die budget set (assumption, input to P&R) | 8 KB instruction + 8 KB data (16 KB total); die budget 3.8 mm² core | 4 KB unified (by a record, if P&R misses the budget); 32 KB stretch | 0002, [0004](decision-records/0004-sram-macro-organization.md) |
| 8a | SRAM macro organization (count, size per memory) | ratified | 4 x `sky130_sram_2kbyte_1rw1r_32x512_8` per memory (8 macros); data-side port 1 tied off | candidate B (generated 4 KB `1rw`; no views) | 0002, 0004 |
| 9 | Peripherals | ratified | boot ROM, UART, 8-bit GPIO, machine timer | fallback drops the timer; SPI XIP is stretch | § Peripherals |
| 10 | Clock and reset | ratified | one clock `clk_i`; async-assert, sync-deassert reset | — | § Clock and reset |
| 11 | Signoff Fmax | ratified target; **closure at ss/ff deferred** | 50 MHz post-route, `ss_100C_1v60` | 25 MHz fallback, 100 MHz stretch | § Fmax |
| 12 | PVT corner set | ratified; macro coverage gap recorded | `ss_100C_1v60`, `tt_025C_1v80`, `ff_n40C_1v95` | — | § STA corners |
| 13 | Standard cells | ratified | `sky130_fd_sc_hd` | — | README |
| 14 | Signoff | ratified | DRC + LVS clean; STA closed at every ratified corner **that has a macro view** (see § STA corners) | — | § Verification plan |

## Interconnect

OBI v1.4 (https://github.com/openhwgroup/obi, `OBI-v1.4.pdf`; the version
CVE2 cites at `doc/01_specification/index.rst:189`).

| Manager | Reaches |
|---|---|
| Instruction (CVE2 fetch) | boot ROM, instruction SRAM |
| Data (CVE2 load/store) | boot ROM (constants), instruction SRAM (loader writes), data SRAM, peripheral window |

Subordinates: boot ROM, instruction SRAM, data SRAM, peripheral bridge. An
access to an unmapped address returns an OBI error response, never a hang.
Arbitration where both managers target the same subordinate in one cycle:
instruction SRAM has separate ports so a data-side write and an instruction
fetch proceed in parallel; at the boot ROM the data manager yields to the
instruction manager (fetch-priority, fixed). The single-shared-bus fallback is
taken only by a record, if the crossbar cannot close timing.

## Memory map

| Region | Base | Size | Backing |
|---|---|---|---|
| Boot ROM | `0x0000_0000` | 4 KB | synthesized standard-cell ROM, firmware image generated from source |
| Instruction SRAM | `0x1000_0000` | 8 KB | OpenRAM `1rw1r` macros |
| Data SRAM | `0x2000_0000` | 8 KB | OpenRAM `1rw` macros |
| UART | `0x4000_0000` | 4 KB | standard cells |
| GPIO | `0x4000_1000` | 4 KB | standard cells |
| Timer | `0x4000_2000` | 4 KB | standard cells |

The peripheral window is `0x4000_0000`–`0x4000_FFFF`; unused pages answer
with an OBI error. **Reset vector: `0x0000_0000`** — `boot_addr_i` is tied to
the boot ROM base (CVE2 fetches from `boot_addr_i[31:2]` on reset,
`rtl/cve2_if_stage.sv:140`, and the port comment says it is also used for
`mtvec`, `rtl/cve2_if_stage.sv:20`; the trap-vector offset is 0 from
`boot_addr_i`, resolved by the first RTL boot test, see
[record 0003](decision-records/0003-trap-vector-offset.md)). Boot flow: ROM firmware
initialises the UART, copies or receives code into instruction SRAM, and
jumps to it. Interrupts: timer → `irq_timer_i`; UART → `irq_fast_i[0]`;
GPIO → `irq_fast_i[1]`; other lines tied 0.

## Peripherals

- **Boot ROM** — read-only, 4 KB, contents built from checked-in firmware
  source; the image is generated, not hand-edited.
- **UART** — one instance, 8N1, TX and RX, programmable baud divisor, TX/RX
  interrupt.
- **GPIO** — 8 bits, per-pin direction, input synchronizers, one interrupt.
  Count is a spec choice with no pad ring to constrain it; raising it is a
  spec change.
- **Timer** — RISC-V machine-timer style 64-bit `mtime`/`mtimecmp`, drives
  `irq_timer_i`.
- **SPI flash XIP** — stretch, not ratified into the target.

## Clock and reset

Single clock domain; `clk_i` is a chip input (no PLL, no pad ring). Reset
`rst_ni` (active low, the CVE2 port polarity, *unverified* at the top level)
is asynchronously asserted and synchronously released by a two-flop
synchronizer in the SoC top. The clock tree reaches the core, crossbar,
peripherals and every SRAM `clk0`/`clk1`; no clock gating in the target.

## SRAM source and size

Source: [0002](decision-records/0002-sram-source.md). Ratified: OpenRAM
adopted; organization requirement (instruction `1rw1r`, data `1rw`, 32-bit
words, 8-bit write granularity); 8 KB + 8 KB. Instance and die budget:
[0004](decision-records/0004-sram-macro-organization.md) — four 2 KB `1rw1r`
`32x512` macros per memory (683.1 x 416.54 µm, 0.2845 mm² each per its
Liberty), 8 macros = 2.276 mm²; die budget 3.8 mm² core area, derived from an
assumed 0.60 macro share, an input to P&R and not a measured result. If P&R
misses the budget, the 4 KB unified fallback is taken by a new record.

## STA corners

Standard-cell Liberty: `sky130_fd_sc_hd` library files named per
google/skywater-pdk (`sky130_fd_sc_hd__<corner>.lib`; file presence in the
pinned PDK is *unverified* here and is pinned by #5). Macro views: the pinned
`efabless/sky130_sram_macros` commit.

| Corner | Role | Standard-cell Liberty | Macro view | Macro coverage |
|---|---|---|---|---|
| `ss_100C_1v60` | slow — signoff Fmax corner | `sky130_fd_sc_hd__ss_100C_1v60.lib` | none exists | **not covered** |
| `tt_025C_1v80` | typical | `sky130_fd_sc_hd__tt_025C_1v80.lib` | `*_TT_1p8V_25C.lib` | covered |
| `ff_n40C_1v95` | fast — hold | `sky130_fd_sc_hd__ff_n40C_1v95.lib` | none exists | **not covered** |

OpenRAM's own corner sweep stops at 1.7–1.9 V and 0–100 °C
(`technology/sky130/tech/tech.py:736,740`), so 1.60 V and −40 °C are outside
it even if regenerated. **Rules:** (1) no signoff Fmax or hold claim at an
uncovered corner for paths crossing the macro boundary; (2) an interim
figure at such a corner may be reported only labelled "macro paths use the
`TT_1p8V_25C` view — not signoff"; (3) the 50 MHz *signoff* claim is therefore
gated on a macro view at `ss_100C_1v60`, whose source is open (regenerate with
a user corner config, or the `sky130-sram-compiler` sibling).

## Fmax

| Figure | Value | Corner | Layout state | Status |
|---|---|---|---|---|
| Target | 50 MHz (20 ns) | `ss_100C_1v60` | post-route | target; none exists yet |
| Fallback | 25 MHz | `ss_100C_1v60` | post-route | fallback |
| Stretch | 100 MHz | `ss_100C_1v60` | post-route | stretch; must not drive architecture before the target closes |

Nothing above is measured, and there is no STA result yet.

## SystemVerilog handling

Answer to the open question (details in
[0001](decision-records/0001-core-choice.md)): sv2v converts the pinned CVE2
to Verilog; Yosys and Icarus both consume the converted output; it is
generated, not committed or edited; pin = (CVE2 commit, sv2v version via #5,
conversion command). Recorded alternative: Verilator for the core if Icarus
rejects the output. *Unverified* until the RTL issue's elaboration smoke test.

## Verification plan

Suite → claim → pass criterion. Each result is recorded append-only.

| Claim | Suite (issue under #4) | Pass criterion |
|---|---|---|
| ISA conformance of the SoC | `riscv-arch-test` (https://github.com/riscv-non-isa/riscv-arch-test, HEAD read `9929db1c3a84f90f808f39f21678d9cd98776147`) for RV32 I, M, C, privileged/Zicsr as applicable to CVE2, run on the simulated SoC | every selected test's signature matches the reference; skipped tests are listed with a reason |
| Crossbar and decode | cocotb unit tests | every mapped region reachable by its allowed managers; unmapped and forbidden accesses get an OBI error; no hang |
| Peripherals | cocotb register and interrupt tests | register reset values and behaviour match § Peripherals |
| SoC functional | firmware on the simulated SoC: boot from ROM and print a banner on UART; UART echo; GPIO toggle and readback; timer interrupt taken; code loaded into instruction SRAM and executed | golden UART transcript matches; every interrupt is taken exactly once within its cycle bound |
| Netlist equals RTL | the same firmware on the post-synthesis netlist | same transcript as RTL |
| Timing | OpenROAD STA on the routed layout at each § STA corner | WNS ≥ 0 and TNS = 0 at 20 ns at each corner **with a macro view**; hold clean at `ff_n40C_1v95`; report archived with corner, Liberty names and layout state |
| Physical | `klt` DRC and LVS | zero violations; reports archived |

Mapping to the gap tracker #4: items 5–8 (core/RTL, SRAM, P&R, STA) each own
the rows of this table that touch their stage; nothing here is verified yet.

## PDK-independent seam for `gf180-riscv-soc`

This repo is master for the left column; the port stamps it by pinned
reference. The right column is re-derived per PDK.

| PDK-independent (master here) | PDK-specific (per port) |
|---|---|
| SoC top RTL, OBI crossbar, peripherals, boot ROM source | SRAM macros and their views (behind a `soc_sram_*` memory-interface wrapper with a behavioural model) |
| Memory map, reset vector, interrupt map | standard-cell library, corner set, STA constraints (SDC timing numbers) |
| Firmware sources and golden transcripts | floorplan, macro placement, power grid, CTS/PnR recipe |
| cocotb testbenches, `riscv-arch-test` target config | DRC/LVS decks and reports |
| Core choice and pin (CVE2 commit), sv2v conversion | the 50 MHz target — re-set per PDK |

## Deferrals

| Item | Settled by |
|---|---|
| SRAM macro instance and die budget | resolved: [record 0004](decision-records/0004-sram-macro-organization.md); the P&R issue reports the utilisation actually reached |
| Macro Liberty at `ss_100C_1v60` and `ff_n40C_1v95` | a regenerated or sibling-produced view; until then slow/fast macro-path claims are not signoff |
| Icarus accepts the sv2v output | RTL issue elaboration smoke test |
| `MHPMCounterNum` trim, `RV32MFast` vs `RV32MSlow` | synthesis issue timing/area result |
| Trap-vector offset from `boot_addr_i` | resolved: 0, [record 0003](decision-records/0003-trap-vector-offset.md) |
| Liberty file names in the pinned PDK, sv2v version | #5 (PDK/toolchain pin) |
