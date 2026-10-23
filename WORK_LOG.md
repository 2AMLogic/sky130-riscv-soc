# Work Log

Chronological record of merged PRs and closed issues, newest first.
Maintained by the Loom Guide role.

### 2026-10-23

- **PR #25**: feat: add block manifest, signoff record and CI re-grade
- **PR #24**: feat: fetch, verify and sv2v-convert pinned CVE2 sources
- **Issue #20** (closed): SoC RTL step 1a: fetch CVE2 at the pin, sha256-verify against the lock, sv2v conversion
- **Issue #18** (closed): T1 verdict of record: commit a klt signoff block manifest and a CI job that keeps its report fresh

### 2026-10-22

- **PR #12**: feat(verification): add cocotb smoke harness, record linter and CI
- **Issue #6** (closed): Verification harness and CI skeleton (T1 items 9 and 10)

### 2026-10-21

- **PR #15**: Bump Repo Skills 0.24.3 -> 0.24.7

### 2026-10-18

- **PR #10**: fix(env): bump klt pin and record the smoke P&R leg
- **Issue #9** (closed): Reconcile klt pin in setup-env.sh with the klt on the fleet workers, and re-run the smoke P&R leg on a docker-capable host

### 2026-10-17

- **PR #8**: feat: pin sky130A PDK and toolchain with setup-env.sh and smoke synthesis record
- **PR #7**: docs(spec): ratify SoC spec with core and SRAM decision records
- **PR #3**: chore(loom): commit the Loom merge-driver .gitattributes
- **PR #1**: chore(loom): Install Loom 0.19.1180
- **Issue #5** (closed): Pin the sky130 PDK and open toolchain, and commit a smoke synthesis that proves it runs
- **Issue #2** (closed): Draft and ratify the target spec
