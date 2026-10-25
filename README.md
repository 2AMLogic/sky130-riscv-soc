# sky130-riscv-soc

A small RISC-V microcontroller SoC on
[SkyWater sky130](https://github.com/google/skywater-pdk), the 130 nm open
PDK — an Ibex/CVE2-class RV32 core, an OBI crossbar, SRAM macros and a
minimal peripheral set — designed by AI agents driving
[klayout-tools](https://github.com/2AMLogic/klayout-tools) and the
open-source cocotb + Icarus, Yosys and OpenROAD flow.

**Status: just opened, specification phase.** Nothing is designed yet.

**Built agent-native.** Every specification, decision record, testbench, and
line of documentation here is produced by AI agents working from a ratified
spec and an append-only evidence trail — not human-authored work that agents
merely assisted with. Verification is the product: every claim traces to a
recorded result. Where the agents hit friction with the open-source tooling —
most often [klayout-tools](https://github.com/2AMLogic/klayout-tools) — that
friction is filed as a public issue against the tool itself, so the fix
benefits everyone using sky130, not just this repo.

## Why this block, on this node

The fleet's earlier digital canaries are single-function blocks. An SoC is
the first **integration** problem: a third-party processor core, a bus
fabric, hard SRAM macros placed among standard cells, and a clock and reset
tree that has to reach all of them. Macro placement, macro-aware routing,
and timing paths that leave the standard-cell fabric, enter a macro and come
back are tool surface no sibling has exercised.

The gap it targets is a **frequency claim with evidence behind it**. Open
RISC-V cores have been taped out on sky130 many times; to our knowledge, few
of those designs publish a maximum clock frequency tied to multi-corner
signoff timing of the routed layout, and fewer still to a bench measurement.
This repo's deliverable is an Fmax stated from post-route static timing
across the library's corners — and, only after tape-out, a measured Fmax,
reported separately and never conflated with the first.

## Standing on public prior art

- **Core**: [Ibex](https://github.com/lowRISC/ibex) (lowRISC, Apache-2.0) or
  its OpenHW Group fork [CVE2](https://github.com/openhwgroup/cve2) — both
  small in-order RV32 cores. The choice is made in `spec/`; the chosen core
  is used unmodified, pinned to an upstream commit.
- **Bus**: OBI (the OpenHW Open Bus Interface), the native interface of
  both cores.
- **Compliance**: the RISC-V architectural test suite
  ([riscv-arch-test](https://github.com/riscv-non-isa/riscv-arch-test)).
- **SRAM**: not designed here. Candidates are the OpenRAM-generated sky130
  macros, the fleet's `sky130-sram-compiler` canary once it delivers, and
  standard-cell RAM. The choice is an adopt-or-record decision in `spec/`.

## Scope

- **In scope**: SoC integration — core configuration, OBI crossbar,
  instruction and data SRAM placement, boot ROM, UART, GPIO, timer, clock and
  reset distribution, and the physical design and timing closure of the
  whole.
- **Not in scope**: designing the core (local core edits are a decision
  record, not a patch), designing a bitcell or SRAM macro, a PLL (the clock
  is an input), and the pad ring.

## Target specification (ratified — see [spec/soc.md](spec/soc.md))

| Parameter | Target | Fallback | Stretch |
|---|---|---|---|
| Core | RV32IMC, CVE2 (pinned, unmodified) | RV32EC | + RISC-V debug module over JTAG |
| Interconnect | OBI crossbar, instruction + data managers | single shared OBI bus | — |
| SRAM | 8 KB instruction + 8 KB data, OpenRAM sky130 macros (macro instance deferred) | 4 KB unified | 32 KB total |
| Peripherals | boot ROM, UART, 8-bit GPIO, timer | boot ROM, UART, GPIO | SPI flash execute-in-place |
| Signoff Fmax (post-route STA, slow corner `ss_100C_1v60`) | 50 MHz | 25 MHz | 100 MHz |
| Standard cells | `sky130_fd_sc_hd` | — | — |
| Signoff | DRC + LVS clean, STA closed at every ratified corner that has a macro view (see spec) | — | — |

All frequencies are targets for a signoff Fmax from static timing, not
measurements. The macro Liberty views cover only the typical corner today;
`spec/soc.md` § STA corners states what that means for the slow and fast
corners.

Maturity ladder: spec ratified → SoC RTL passing the architectural tests and
firmware tests in simulation → synthesized with timing met at the target →
placed and routed with the SRAM macros, DRC/LVS-clean → post-route
multi-corner STA closed → shuttle seat → measured silicon (bench Fmax).
**Current position: spec ratified.**

## Repo layout

```
spec/          ratified spec + decision records
rtl/           SoC integration RTL (the core is pinned upstream, not copied in by hand)
verification/  cocotb testbenches, evidence records, architectural-test and firmware runs
layout/        GDS + DRC/LVS reports + STA reports (klayout-tools driven)
measurements/  silicon characterization (empty until tape-out)
```

## Reproduce

Cold-start commands, from a clean checkout (tool and PDK pins are in
[`scripts/setup-env.sh`](scripts/setup-env.sh); setup notes in
[`docs/environment.md`](docs/environment.md)):

```
scripts/setup-env.sh --check                    # environment matches the pins
python3 -m venv .venv && .venv/bin/pip install cocotb==2.0.1
. .venv/bin/activate && make -C verification xbar    # cocotb + Icarus: OBI crossbar, fabric, reset sync
npm run lint                                    # record linter, its fixture test, RTL lint
npm run test                                    # the same xbar tests as above
```

CI runs the lint and the xbar tests (`make boot` needs the converted CVE2 and
stays local); synthesis, place-and-route, DRC and LVS stay
local (see [`verification/README.md`](verification/README.md)).

## License

Apache License 2.0 — see [LICENSE](LICENSE).
