# Work Plan

Roadmap generated from GitHub label state by the Loom Guide role.

<!-- guide:plan-body:start -->
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs under a hold (`loom:blocked` or `loom:operator`) — only a human merge decision is missing.

_None._

## Very Important

`loom:very-important` (one counts per workspace); every stage takes these first.

_None._

## Important

`loom:important`; taken before unlabelled work.

- **#46**: T1 item 1: peripheral window decoder, GPIO and machine timer RTL, register-map record, with tests

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#43**: T1 item 9 (Testbenches shipped): inventory the benches and attest with klt signoff --attest 9
- **#46**: T1 item 1: peripheral window decoder, GPIO and machine timer RTL, register-map record, with tests
- **#59**: Run firmware boot at default and ISRAM_1RW=1 / 1024-word parameters once the converted CVE2 core is available
- **#72**: Remove soc_sram_i_1rw: duplicate of soc_sram_d behavioural model

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#54**: feat(rtl): add peripheral window decoder, GPIO and machine timer
- **#71**: test: record boot and boot-1rw simulation evidence
- **#73**: refactor: reuse soc_sram_d for ISRAM_1RW=1, drop duplicate soc_sram_i_1rw

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

_None._

## Proposed

Issues carrying `loom:curated`.

- **#4**: Track the gap to T1 (klayout-tools design-evidence-tiers.md) *(curated)*
- **#43**: T1 item 9 (Testbenches shipped): inventory the benches and attest with klt signoff --attest 9 *(curated)*
- **#46**: T1 item 1: peripheral window decoder, GPIO and machine timer RTL, register-map record, with tests *(curated)*
- **#49**: T1 item 5: riscv-arch-test on the RTL SoC via klt functional-verification *(curated)*
- **#59**: Run firmware boot at default and ISRAM_1RW=1 / 1024-word parameters once the converted CVE2 core is available *(curated)*
- **#69**: T1 item 8 (characterization): per-row report with Fmax, area and power per ratified corner, attested with klt signoff --attest 8 *(curated)*

## Proposed (Architect / Hermit)

_None._

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 0 |
| Important | 1 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 4 |
| PRs awaiting review | 3 |
| Approved PRs awaiting merge | 0 |
| Curated | 6 |
| Architect / Hermit proposals | 0 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
