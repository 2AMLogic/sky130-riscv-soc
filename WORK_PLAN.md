# Work Plan

Roadmap generated from GitHub label state by the Loom Guide role.

<!-- guide:plan-body:start -->
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs under a hold (`loom:blocked` or `loom:operator`) — only a human merge decision is missing.

_None._

## Very Important

`loom:very-important` (one counts per workspace); every stage takes these first.

- **#37**: T1 item 2 (Layout): klt place-and-route of soc_top with macros and PDN, committed routed GDS

## Important

`loom:important`; taken before unlabelled work.

- **#49**: T1 item 5: riscv-arch-test on the RTL SoC via klt functional-verification

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#43**: T1 item 9 (Testbenches shipped): inventory the benches and attest with klt signoff --attest 9
- **#142**: Remove rtl/obi_err_resp.sv: its grant is a constant and its error flag repeats what obi_xbar already registers

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

_None._

## Proposed

Issues carrying `loom:curated`.

- **#4**: Track the gap to T1 (klayout-tools design-evidence-tiers.md) *(curated)*
- **#37**: T1 item 2 (Layout): klt place-and-route of soc_top with macros and PDN, committed routed GDS *(curated)*
- **#43**: T1 item 9 (Testbenches shipped): inventory the benches and attest with klt signoff --attest 9 *(curated)*
- **#49**: T1 item 5: riscv-arch-test on the RTL SoC via klt functional-verification *(curated)*
- **#69**: T1 item 8 (characterization): per-row report with Fmax, area and power per ratified corner, attested with klt signoff --attest 8 *(curated)*

## Proposed (Architect / Hermit)

- **#103**: Remove the npm check scripts: check:ci runs 4 of CI's 13 commands *(hermit)*
- **#122**: Remove the unfetched VLSIDA/OpenRAM import from reuse.lock.json: candidate B was declined in record 0004 *(hermit)*
- **#132**: Remove the no-op Verilator lint from scripts/convert-cve2.sh: it prints ok when Verilator is absent *(hermit)*
- **#153**: Remove the dead tx_sh_q[0] bit in rtl/uart.sv: the start bit is driven directly, so bit 0 is never read *(hermit)*
- **#154**: Remove the duplicate soc_fabric bus driver: periph_bus.Bus reimplements the reset sequence and response contract that test_xbar.Fab already has *(hermit)*
- **#155**: Remove the duplicate soc_top bench: test_boot.Soc and soc_bench.Soc reimplement one reset and D-SRAM preload, plus two write-only cycle counters *(hermit)*

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 1 |
| Important | 1 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 2 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 0 |
| Curated | 5 |
| Architect / Hermit proposals | 6 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
