# 0001 — Core choice: CVE2 (CV32E20), RV32IMC, no debug module

- **Status**: accepted (2026-10-17), ratified by issue #2
- **Supersedes**: none
- **Superseded by**: none
- **Spec rows**: `spec/soc.md` § Core, § Interconnect, § SystemVerilog handling

## Context

The README names "Ibex or CVE2" and a pinned, unmodified upstream core
(CLAUDE.md: a local core change is a decision record, not a patch). Both
cores are small in-order RV32 cores under Apache-2.0, and both ship an
sv2v + Yosys synthesis flow in their own `syn/` directory. The decision
needs: which core, which ISA configuration, which multiplier, whether a debug
module is in scope, which upstream commit, and how SystemVerilog reaches
Icarus and Yosys.

Facts below were read from shallow clones on 2026-10-17; each carries the
file it came from. Anything not read from a file is marked *unverified*.

| Fact | Ibex | CVE2 |
|---|---|---|
| Upstream | https://github.com/lowRISC/ibex | https://github.com/openhwgroup/cve2 |
| HEAD read | `65368a4c41d8e6c2e56ce816e418e21fc4e7b328` (2026-10-17) | `d7f21568028a1114be663599bd42145dccf28928` (2026-10-09) |
| License | Apache-2.0 (`LICENSE`) | Apache-2.0 (`LICENSE`, sha256 equals the macro repo's Apache text) |
| Bus protocol | req/gnt/rvalid ports; OBI compliance **unverified** (Ibex docs call a port "OBI compliant" only for the CHERIoT bitmap port, `doc/03_reference/cheriot.rst:88`) | "Instruction fetch bus and data load/store OBI buses", OBI v1.4 (`doc/01_specification/index.rst:96,189`) |
| M extension option | `RV32MNone/Slow/Fast/SingleCycle` (`rtl/ibex_pkg.sv`) | `RV32MNone/Slow/Fast/SingleCycle` (`rtl/cve2_pkg.sv:36-39`) |
| RV32E option | parameter `RV32E` (`rtl/ibex_top.sv:27`) | parameter `RV32E` (`rtl/cve2_top.sv:20`) |
| Optional features beyond RV32IMC | B ext, PMP, I-cache, branch predictor, secure/lockstep, CHERIoT | none of those; top-level parameters are `MHPMCounterNum`, `MHPMCounterWidth`, `RV32E`, `RV32M`, `XInterface` (`rtl/cve2_top.sv:18-22`) |
| Debug | debug request input + triggers (`DbgTriggerEn`) | `debug_req_i` / `debug_halted_o` ports present (`rtl/cve2_top.sv:79-80`) |
| sv2v + Yosys flow shipped | `syn/README.md:39` | `syn/README.md:22` |

## Decision

1. **Core: CVE2** (OpenHW Group CV32E20), top module `cve2_top`.
2. **Pinned upstream commit: `d7f21568028a1114be663599bd42145dccf28928`**
   (openhwgroup/cve2 main, committed 2026-10-09). Recorded in
   `reuse.lock.json`. Used unmodified; any local change needs a new decision
   record.
3. **ISA configuration: RV32IMC** — `RV32E=0`, `RV32M=cve2_pkg::RV32MFast`
   (the multi-cycle multiplier that CVE2's `small` configuration uses,
   `cve2_configs.yaml`). The C extension is part of the CVE2 pipeline
   (`rtl/cve2_compressed_decoder.sv`), not a parameter.
   `MHPMCounterNum` is left at the upstream default (10); trimming it is
   a parameter choice deferred to the synthesis issue, to be decided from
   area evidence.
4. **Debug module: out of scope** for the target (README stretch row).
   `debug_req_i` is tied low; no RISC-V debug module and no JTAG port are
   built. Adding one later is a spec change with its own record.
5. **SystemVerilog handling: sv2v.** The pinned CVE2 RTL is converted by
   sv2v to plain Verilog; Yosys synthesizes the converted output and Icarus
   simulates the **same** converted output, so the netlist under test is the
   netlist synthesized. The converted files are generated into a build
   directory, never hand-edited and not committed. The conversion is
   pinned by (CVE2 commit, sv2v version, conversion command); the sv2v
   version pin is made by #5 (toolchain pin) and the command is recorded
   there. Reference flow: `syn/` in the pinned CVE2 tree.
   - **Recorded alternative** if Icarus cannot elaborate the sv2v output:
     Verilator (cocotb-supported) as the simulator for the core, with
     Icarus kept for the non-core blocks. *Unverified* — whether Icarus
     accepts CVE2's sv2v output is a named gate (see Consequences).

## Alternatives considered

- **Ibex `small` configuration** (pin read: `65368a4c…`). Rejected as the
  primary because it brings a larger option surface (PMP, B extension,
  I-cache, CHERIoT, secure mode) that this SoC does not use, and because
  OBI conformance of its core ports is not documented in the pinned tree.
  It remains the **recorded fallback**: if CVE2 cannot close the 50 MHz
  target for a core-internal reason, switching is a new decision record that
  supersedes this one and re-pins the core.
- **RV32EC (16 registers)** as the primary. Rejected; it is the README
  fallback, retained as such. Selected only if register-file area forces it.
- **`RV32MSingleCycle`** multiplier. Rejected for the target: its
  combinational multiplier is on the critical path of a design whose goal is
  a post-route frequency claim. `RV32MSlow` is the area fallback.
- **Debug module in scope.** Rejected: it adds a second manager, a JTAG
  TAP and a clock-domain question for a feature the target does not need.

## Consequences

- The crossbar (spec § Interconnect) is specified against OBI v1.4 on both
  manager ports.
- **Gate 1 (RTL issue):** the sv2v-converted CVE2 elaborates in Icarus and
  synthesizes in Yosys; otherwise the Verilator alternative is recorded.
- **Gate 2 (synthesis issue):** the `RV32MFast` multiplier and the default
  `MHPMCounterNum` meet the 50 MHz budget; otherwise take `RV32MSlow`
  and/or trim counters, each recorded.
- Local patches to CVE2 are not made; RTL defects found upstream are filed
  upstream.
