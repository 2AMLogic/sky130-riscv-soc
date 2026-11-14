# Work Log

Chronological record of merged PRs and closed issues, newest first.
Maintained by the Loom Guide role.

### 2026-11-14

- **PR #152**: test: assert the granted store responded, and drop two dead xbar-test constructs
- **Issue #151** (closed): Tighten three weak spots in verification/tests/xbar/test_xbar.py
- **PR #148**: refactor: instantiate soc_sram_i with port 1 tied off, drop soc_sram_d
- **Issue #139** (closed): Remove rtl/soc_sram_d.sv: it is soc_sram_i with port 1 tied off, in both the behavioural and macro builds
- **PR #144**: docs: name the PIN_* variables in environment.md instead of copying values
- **Issue #137** (closed): Remove the hand-copied pin values and stale statements from docs/environment.md: scripts/setup-env.sh is the one source
- **PR #146**: docs: replace five README statements that records now contradict
- **Issue #141** (closed): Remove the stale statements from README.md, spec/README.md and layout/README.md: each contradicts a committed record

### 2026-11-13

- **PR #140**: docs: point item-10 regeneration at the cocotb venv on PATH
- **Issue #136** (closed): docs: manifests/README.md item 10 regeneration note omits putting the cocotb venv on PATH
- **PR #135**: docs: keep one complete CI inventory in verification/README.md
- **Issue #133** (closed): Remove two of the three prose lists of what CI runs: each copy omits steps ci.yml executes
- **PR #134**: chore: drop the SPICE harness .gitignore rules and fix the stale UART-page headers
- **Issue #131** (closed): Remove the SPICE sim/ harness rules from .gitignore and the stale UART-page comment in soc_fabric.sv
- **PR #130**: build: take the klt version in pnr-soc.sh from PIN_KLT
- **Issue #125** (closed): Remove the separate klt commit pin in scripts/pnr-soc.sh: release 0.9.1 contains it
- **PR #128**: refactor: move the T1 item-1 netlist freshness check onto klt's recorded record
- **Issue #126** (closed): Remove scripts/check-soc-netlist.py and flow/soc/synth.sha256: pinned klt 0.9.1 has the recorded freshness record
- **PR #129**: refactor: state each verification/Makefile guard once, pattern the periph tests
- **Issue #121** (closed): Dedupe verification/Makefile: the cocotb guard is copied 11 times and three periph recipes are identical
- **PR #124**: refactor(firmware): fold both ROM image builders onto one encoder
- **Issue #116** (closed): Merge the two firmware build scripts: firmware/soc/build.sh is a looped copy of firmware/boot/build.sh
- **PR #123**: docs: point the klt pin note at PIN_KLT instead of calling it a dev build
- **Issue #119** (closed): docs: correct the stale "klt pin is a development build" note in docs/environment.md
- **PR #114**: docs: check the pins after creating the venv in the README Reproduce block
- **Issue #112** (closed): README Reproduce block runs setup-env.sh --check before the venv that provides cocotb exists
- **PR #120**: ci: run the lint_rtl and setup-env --check exit-code tests in the lint job
- **Issue #117** (closed): Run test_lint_rtl.sh and test_setup_env_check.sh in CI: two exit-code tests nothing invokes
- **PR #118**: chore: pin klayout-tools to 0.9.1 and regenerate the signoff records
- **Issue #115** (closed): Bump PIN_KLT to 0.9.1 so attestation regeneration works through the documented uvx recipe
- **PR #111**: refactor(scripts): fold both reuse.lock fetchers onto one tested path
- **Issue #108** (closed): Merge the two reuse.lock fetch scripts: fetch-sram-macro.sh is an untested copy of fetch-cve2.sh
- **PR #110**: fix: fail the RTL lint on an empty tree and the env check on absent cocotb
- **Issue #106** (closed): Remove the bootstrap vacuous-pass branches: RTL lint passes on zero files, env check treats cocotb as optional
- **PR #105**: test(verification): check the SRAM stand-in against the pinned macro model
- **Issue #101** (closed): Check the SRAM stand-in simulation model against the pinned macro model
- **PR #107**: evidence: record the first pre-route klt sta estimate of the soc_top netlist
- **Issue #102** (closed): Pre-route klt sta estimate on the synthesized netlist, to answer Gate 2 of record 0001
- **PR #104**: docs: replace stale README status, ladder position and CI paragraph; re-attest item 10
- **Issue #100** (closed): README status and ladder position are stale: update them and re-attest T1 item 10
- **PR #99**: docs: roadmap as of 2026-11-13

### 2026-11-12

- **PR #97**: Bump Repo Skills 0.25.10 -> 0.26.1

### 2026-11-11

- **PR #95**: docs: record failed soc_top global-route attempts and congestion analysis

### 2026-11-07

- **PR #93**: Bump Repo Skills 0.25.1 -> 0.25.10

### 2026-10-31

- **PR #90**: Bump Repo Skills 0.24.7 -> 0.25.1
- **PR #87**: chore: drop tracked synth_result.json, default scratch result to flow/build
- **Issue #85** (closed): Remove flow/soc/synth_result.json: byte-identical duplicate of the committed synthesis record
- **PR #88**: build: reuse SOC_SRC in boot and boot-1rw sim targets
- **Issue #77** (closed): Dedupe verification/Makefile boot source lists (boot-1rw omits gpio/timer)
- **PR #84**: feat: synthesize soc_top with gate-level banner regression and T1 item 1 attestation
- **Issue #35** (closed): T1 item 1 (Design sources): synthesize soc_top to sky130_fd_sc_hd and attest RTL plus netlist
- **PR #82**: feat: add SoC firmware tests (banner, echo, GPIO, timer interrupt) and CI leg
- **Issue #48** (closed): T1 item 1: SoC firmware tests (banner, echo, GPIO, timer interrupt) and CI leg
- **PR #80**: ci: build pinned CVE2 core and run soc_top lint and boot tests
- **Issue #79** (closed): CI does not build or simulate soc_top (make boot, soc_top lint skipped)
- **Issue #34** (closed): T1 item 1 (Design sources): UART, GPIO and machine-timer RTL per spec/soc.md Peripherals, with tests
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
