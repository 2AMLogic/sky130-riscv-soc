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

- **#149**: u_dsram carries a dead bsel1 register and dout1 mux after the soc_sram_d removal: +1022 um2 pre-route
- **#153**: Remove the dead tx_sh_q[0] bit in rtl/uart.sv: the start bit is driven directly, so bit 0 is never read
- **#161**: Remove the dead instruction-side write channel: obi_xbar never reads i_be_i or i_wdata_i, and 36 tie cells exist only to feed them

## In Progress

Issues currently being built (`loom:building`).

- **#43**: T1 item 9 (Testbenches shipped): inventory the benches and attest with klt signoff --attest 9
- **#147**: Two decision records share the number 0004, so a bare "record 0004" citation is ambiguous
- **#155**: Remove the duplicate soc_top bench: test_boot.Soc and soc_bench.Soc reimplement one reset and D-SRAM preload, plus two write-only cycle counters
- **#157**: Dedupe .github/workflows/ci.yml: the sv2v install and CVE2 convert prelude is copied byte-for-byte into both jobs
- **#164**: Remove the hand-maintained sync between the two item-6 statements: CI compares ids only, so the human-readable .md can contradict the hash-bound .json

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#160**: ci: extract the sv2v install and CVE2 convert prelude into one composite action
- **#163**: docs: cite record 0004 by filename at the 14 sites that named only the number

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#165**: check: compare item-6 row class and reason against the hash-bound JSON
- **#166**: refactor: factor the soc_top bench core into tests/lib, drop two dead counters

## Proposed

Issues carrying `loom:curated`.

- **#4**: Track the gap to T1 (klayout-tools design-evidence-tiers.md) *(curated)*
- **#37**: T1 item 2 (Layout): klt place-and-route of soc_top with macros and PDN, committed routed GDS *(curated)*
- **#43**: T1 item 9 (Testbenches shipped): inventory the benches and attest with klt signoff --attest 9 *(curated)*
- **#49**: T1 item 5: riscv-arch-test on the RTL SoC via klt functional-verification *(curated)*
- **#69**: T1 item 8 (characterization): per-row report with Fmax, area and power per ratified corner, attested with klt signoff --attest 8 *(curated)*
- **#147**: Two decision records share the number 0004, so a bare "record 0004" citation is ambiguous *(curated)*
- **#149**: u_dsram carries a dead bsel1 register and dout1 mux after the soc_sram_d removal: +1022 um2 pre-route *(curated)*

## Proposed (Architect / Hermit)

- **#103**: Remove the npm check scripts: check:ci runs 4 of CI's 13 commands *(hermit)*
- **#122**: Remove the unfetched VLSIDA/OpenRAM import from reuse.lock.json: candidate B was declined in record 0004 *(hermit)*
- **#132**: Remove the no-op Verilator lint from scripts/convert-cve2.sh: it prints ok when Verilator is absent *(hermit)*
- **#159**: Remove PIN_RISCV_GCC_SHA256, or say it is unchecked: the pin table advertises a tarball sha256 that nothing in the repo verifies *(hermit)*
- **#162**: Remove the repo-wide *.log ignore rule: it silently blocks record evidence, and four soc-pnr records cite a log it swallowed *(hermit)*

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 1 |
| Important | 1 |
| Ready (`loom:issue`) | 3 |
| In Progress (`loom:building`) | 5 |
| PRs awaiting review | 2 |
| Approved PRs awaiting merge | 2 |
| Curated | 7 |
| Architect / Hermit proposals | 5 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
