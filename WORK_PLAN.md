# Work Plan

Roadmap generated from GitHub label state by the Loom Guide role.

<!-- guide:plan-body:start -->
_Generated: 2026-11-28T14:51:59Z (snapshot; compare against live labels)_
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs under a hold (`loom:blocked` or `loom:operator`) — a human merge decision, or the prerequisite shown, is missing.

- **#241**: chore: resync installed Loom surfaces *(held: merge-gate/kept-set files changed; resync waiver not eligible (title not chore(loom): resync installed Loom to vX))*

## Very Important

`loom:very-important` (one counts per workspace); every stage takes these first.

- **#37**: T1 item 2 (Layout): klt place-and-route of soc_top with macros and PDN, committed routed GDS *(held)*

## Important

`loom:important`; taken before unlabelled work.

- **#49**: T1 item 5: riscv-arch-test on the RTL SoC via klt functional-verification *(held)*
- **#221**: ACT4 Sm_mcsr_cntr-00 fails at the pinned commit: cp_mtime_write is generated for a DUT without a time CSR *(held)*

## Ready

Human-approved issues (`loom:issue`) ready for implementation — excluding held (`loom:blocked`/`loom:operator`/`loom:frozen`), `loom:building`, and issues with an open linked PR (native admission `OPEN_PR`; listed under Issues with Open PRs).

_None._

## Issues with Open PRs (Not Dispatchable)

`loom:issue` issues an open linked PR already holds — native admission would refuse them (`OPEN_PR`); listed with the PR and its stage, not counted above.

_None._

## In Progress

Issues currently being built (`loom:building`).

_None._

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review (`loom:pr`); unmarked PRs are queued for Champion auto-merge, PRs marked `*(held …)*` are not (the hold decides).

- **#241**: chore: resync installed Loom surfaces *(held: merge-gate/kept-set files changed; resync waiver not eligible (title not chore(loom): resync installed Loom to vX))*

## Proposed

Issues carrying `loom:curated`.

- **#4**: Track the gap to T1 (klayout-tools design-evidence-tiers.md) *(curated)*
- **#37**: T1 item 2 (Layout): klt place-and-route of soc_top with macros and PDN, committed routed GDS *(curated)* *(held)*
- **#43**: T1 item 9 (Testbenches shipped): inventory the benches and attest with klt signoff --attest 9 *(curated)* *(held)*
- **#49**: T1 item 5: riscv-arch-test on the RTL SoC via klt functional-verification *(curated)* *(held)*
- **#69**: T1 item 8 (characterization): per-row report with Fmax, area and power per ratified corner, attested with klt signoff --attest 8 *(curated)* *(held)*
- **#147**: Two decision records share the number 0004, so a bare "record 0004" citation is ambiguous *(curated)* *(held)*
- **#203**: Bump PIN_KLT 0.9.1 -> 0.9.2 and regenerate the signoff records; report on #37 what the release does and does not change for the soc_top congestion *(curated)* *(held)*

## Proposed (Architect / Hermit)

_None._

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 1 |
| Very important | 1 |
| Important | 2 |
| Ready (`loom:issue`, net of holds/building/open-linked-PRs) | 0 |
| In Progress (`loom:building`) | 0 |
| Held, no other bucket | 10 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 1 |
| Curated | 7 |
| Architect / Hermit proposals | 0 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
