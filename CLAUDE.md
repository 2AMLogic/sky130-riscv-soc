# sky130-riscv-soc — agent instructions

Open-source canary block: a small RISC-V microcontroller SoC on SkyWater
sky130, designed and verified by AI agents. **Digital** — an integration of a
third-party core, an OBI crossbar, SRAM macros and peripherals.

- **PDK**: SkyWater sky130 (open PDK, google/skywater-pdk), standard cells
  `sky130_fd_sc_hd`. Digital flow: cocotb + Icarus for simulation, Yosys for
  synthesis, OpenROAD for place-and-route and timing. Layout, DRC, and LVS
  through klayout-tools (`klt`).
- **SystemVerilog is a known seam.** Ibex and CVE2 are written in
  SystemVerilog, and Icarus' and Yosys' SystemVerilog support is partial.
  Expect a conversion step (for example sv2v) or a recorded alternative
  simulator. The converted output is generated, never hand-edited, and the
  conversion is pinned like any other input.
- **Macro integration is the point, and the risk.** Hard SRAM macros inside
  a standard-cell floorplan, the timing views that describe them, and paths
  that cross the macro boundary are new ground for the tools here. A timing
  result is only as good as the macro's Liberty view — check where it came
  from and record it. Expect the tools to be weakest here and file
  accordingly.
- **Fmax honesty.** A frequency from STA is a *signoff Fmax*, always stated
  with its corner and the layout state (pre-route, post-route, extracted).
  Nothing here is a *measured* Fmax until silicon is on a bench. Never call a
  simulated or STA figure measured.
- **Scope discipline.** The core is used unmodified from a pinned upstream
  commit; a local core change is a decision record, not a patch. The SRAM
  macros are not designed here: the source (OpenRAM sky130 macros, the
  `sky130-sram-compiler` sibling, or standard-cell RAM) is an adopt-or-record
  decision under the fleet's reuse rule (a block is designed once), and
  whatever is imported is pinned in `reuse.lock.json`. No PLL and no pad
  ring here; the clock is an input.
- **This repo is master for its SoC integration.** `gf180-riscv-soc` is
  ported from this repo, so the PDK-independent half — SoC RTL, memory map,
  firmware, testbenches — is designed here once and stamped into the port.
  Keep it PDK-independent where you can; PDK specifics live behind a clear
  seam.
- **Friction protocol (the canary's job)**: every time klayout-tools is
  awkward, missing a capability, or wrong for what you need, file an issue at
  `2AMLogic/klayout-tools` describing the tool gap generically — that tracker
  is scoped to the tool, so keep design-specific detail out of it and describe
  the gap, not the design.
- **Verification is the product**: no claim without a testbench. Functional
  claims come from the architectural test suite and firmware running on the
  simulated SoC; timing claims come from STA reports at stated corners.
  Recorded results are append-only evidence.
- Spec changes go through `spec/` with a decision record; agents do not relax
  the ratified spec to make results pass.
- **50 MHz post-route at the slow corner is the target.** 25 MHz is the
  fallback and 100 MHz is a stretch. Do not let stretch-frequency pipelining
  drive the architecture before the target closes.

<!-- BEGIN LOOM ORCHESTRATION -->
This repository uses [Loom](https://github.com/rjwalters/loom) for AI-powered development orchestration — see the Loom repository for the full guide (roles, labels, worktrees, configuration). When installed, Loom also writes a locally-substituted copy of that guide to `.loom/CLAUDE.md`.

Work is coordinated through `loom:` labels on issues and pull requests, and the same roles run either under `loom-daemon` or by hand in an attended session — daemon mode is optional. Create the labels once with `.loom/scripts/sync-labels.sh` (an install ships `.github/labels.yml` but does not create the labels on the forge). A pull request ready for review carries `loom:review-requested`; Judge reviews it and applies `loom:pr` (approved) or `loom:changes-requested`; Doctor fixes a `loom:changes-requested` pull request and returns it to `loom:review-requested`. Only a `loom:pr` pull request gets merged, and always via this repo's merge script (`.loom/scripts/merge-pr.sh`) — never a raw forge merge command such as `gh pr merge`. Full state machine: `.loom/docs/label-state-machine.md`.
<!-- END LOOM ORCHESTRATION -->

<!-- BEGIN REPO-SKILLS -->
This repository has [Repo Skills](https://github.com/rjwalters/repo) v0.24.3 installed —
general repository hygiene and environment commands invoked as `/repo:<command>`. Run
`/repo:help` for the command list, or see `.claude/skills/repo/SKILL.md` for the full
guide. Hygiene commands apply safe, reversible fixes by default and report each
change; run with `--ask` to review first, and `--prune` to allow irreversible
removals. Managed by `install.sh` — edit outside the markers only.
<!-- END REPO-SKILLS -->
