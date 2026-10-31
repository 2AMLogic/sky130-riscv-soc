# Work Log

Chronological record of merged PRs and closed issues, newest first.
Maintained by the Loom Guide role.

### 2026-10-31

- **PR #78**: feat: add 8N1 UART peripheral and register-map record 0005
- **Issue #47** (closed): T1 item 1: UART RTL (8N1, baud divisor, TX/RX interrupt) with tests
- **PR #54**: feat(rtl): add peripheral window decoder, GPIO and machine timer
- **Issue #46** (closed): T1 item 1: peripheral window decoder, GPIO and machine timer RTL, register-map record, with tests

### 2026-10-30

- **PR #71**: test: record boot and boot-1rw simulation evidence
- **Issue #59** (closed): Run firmware boot at default and ISRAM_1RW=1 / 1024-word parameters once the converted CVE2 core is available
- **PR #73**: refactor: reuse soc_sram_d for ISRAM_1RW=1, drop duplicate soc_sram_i_1rw
- **Issue #72** (closed): Remove soc_sram_i_1rw: duplicate of soc_sram_d behavioural model

### 2026-10-27

- **PR #67**: refactor: generate xbar test ROM image and drop boot_rom.hex placeholder
- **Issue #32** (closed): Remove rtl/boot_rom.hex placeholder: firmware image has landed
- **PR #65**: chore: pin klayout-tools to PyPI 0.8.0 and regenerate signoff records
- **Issue #64** (closed): Bump klayout-tools pin 6bb7cf233677 → 0.8.0
- **PR #62**: test: add boot-1rw make target for the 1RW/1024-word SoC boot configuration
- **PR #56**: feat: attest T1 item 10 repo hygiene and complete README reproduce steps
- **Issue #44** (closed): T1 item 10 (Repo hygiene): README reproduction steps and klt signoff --attest 10
- **PR #58**: feat: parametrize SRAM depth and add single-port I-SRAM mode in soc_fabric
- **Issue #52** (closed): Parametrize SRAM depth and allow a single-port instruction SRAM in soc_fabric
- **PR #57**: feat: record T1 item 6 as hash-bound not-applicable statement over all spec rows
- **Issue #41** (closed): T1 item 6 (Monte Carlo): record "not applicable" as a hash-bound statement covering every spec/soc.md row
- **PR #53**: feat: bank 2 KB sky130 SRAM macros behind SOC_SRAM_MACRO, record row 8a and die budget
- **Issue #36** (closed): T1 item 2 (Layout): settle SRAM macro organisation (spec row 8a) and die budget, instantiate the macros

### 2026-10-25

- **PR #31**: refactor(verification): retire placeholder smoke DUT, run xbar tests in CI
- **Issue #30** (closed): Retire placeholder smoke DUT: CI and npm test simulate nothing of the SoC

### 2026-10-24

- **Issue #19** (closed): SoC integration RTL, step 1: fetch CVE2 at the pin and boot it on the OBI crossbar with boot ROM and behavioural SRAMs

### 2026-10-23

- **PR #27**: feat: add SoC top, boot firmware and RTL boot test
- **PR #23**: feat(rtl): add OBI crossbar, error responder, boot ROM, SRAM wrappers, reset sync
- **Issue #22** (closed): SoC RTL step 1c: SoC top with CVE2 and firmware boot test
- **Issue #21** (closed): SoC RTL step 1b: OBI crossbar, error responder, boot ROM, behavioural SRAM wrappers, reset sync
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
