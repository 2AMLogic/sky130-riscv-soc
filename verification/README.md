# verification

Testbenches, the evidence-record trail and the checks that keep both valid.
Verification is the product: no claim without a testbench committed here with a
cold-start command a third party can run.

| Path | Holds |
| --- | --- |
| `Makefile`, `cocotb.mk` | the single runner entry point (cocotb + Icarus Verilog) |
| `tests/soc/` | SoC firmware tests (`make soc`): banner, UART echo, GPIO toggle/readback and timer interrupt on `firmware/soc/*.hex`; `make soc-negative` checks a perturbed golden transcript fails |
| `tests/boot/` | SoC top boot test (`make boot`, `make boot-1rw`): CVE2 + fabric run `firmware/boot`; needs the converted core |
| `tests/<name>/` | one directory per testbench (DUT sources + cocotb module); `tests/xbar/` holds the fabric and reset-synchroniser tests, `tests/periph/` the GPIO, timer and peripheral-window decode tests |
| `models/` | `sky130_sram_2kbyte_1rw1r_32x512_8_standin.v`, the Icarus-simulable stand-in `make soc-gate` uses in place of the pinned macro model; its header lists every difference |
| `tools/lint_records.py` | linter for `records/` (stdlib only) |
| `tools/check_sram_standin.py` | fails unless the SRAM stand-in differs from the pinned macro model (sha256 against `reuse.lock.json`) only in the ways its `ALLOWED_EDITS` list documents |
| `tools/lint_rtl.sh` | Verilator lint over `../rtl/`; fails if that tree holds no sources |
| `tools/tests/` | good and bad record fixtures, the tools' own fixture tests, and exit-code tests for the check scripts (`test_lint_rtl.sh`, `test_setup_env_check.sh`, `test_fetch_cve2.sh`) |
| `records/` | append-only evidence; layout in [`records/README.md`](records/README.md) |

## Cold start

Needs `iverilog` 13.0 and `cocotb` 2.0.1 (pins in
[`../scripts/setup-env.sh`](../scripts/setup-env.sh), the one pin source).

```
python3 -m venv .venv && .venv/bin/pip install cocotb==2.0.1
. .venv/bin/activate
make -C verification xbar       # fabric + reset-synchroniser tests; fails if cocotb is missing
make -C verification periph     # GPIO, timer and peripheral-window decode tests
```

Adding a testbench: put it in `tests/<name>/` and add a target to the
`Makefile` that sets `TESTDIR`, `TOPLEVEL`, `MODULE` and `VERILOG_SOURCES`.

## What CI runs, and what stays local

This is the one complete list of what CI runs; `README.md` and the `ci.yml`
header point here rather than repeating it, so a new or changed CI step is
added here and nowhere else. Every command the two jobs of
`.github/workflows/ci.yml` (on pull requests and `main`) run, in order, paths
relative to the repository root:

| Job | Runs | What it covers |
| --- | --- | --- |
| `lint` | `apt-get install -y verilator iverilog` | Verilator for RTL lint; Icarus because the CVE2 convert smoke test elaborates with it |
| `lint` | `verification/tools/lint_records.py`, `verification/tools/tests/test_lint_records.py` | the record linter over `records/`, and its good/bad fixture test |
| `lint` | `verification/tools/tests/test_fetch_cve2.sh` | the pinned-import fetcher's exit codes, both entry points, against a `file://` fixture |
| `lint` | `verification/tools/tests/test_lint_rtl.sh`, `verification/tools/tests/test_setup_env_check.sh` | the check scripts' exit codes: `lint_rtl.sh` on an empty `rtl/` tree, `setup-env.sh --check` on each cocotb state |
| `lint` | `verification/tools/check_soc_rows.py`, `verification/tools/tests/test_check_soc_rows.py` | the spec row projections match `spec/soc.md`, and its fixture test |
| `lint` | `scripts/fetch-sram-macro.sh`, `verification/tools/check_sram_standin.py`, `verification/tools/tests/test_check_sram_standin.py` | the SRAM stand-in against the pinned macro views (fetched hash-verified), and its fixture test |
| `lint`, `sim` | sv2v at `PIN_SV2V` (sha256 `PIN_SV2V_SHA256` in `scripts/setup-env.sh`) | the pinned converter, downloaded and hash-checked per job; both jobs run it from the one shared composite action, `.github/actions/cve2-core` |
| `lint`, `sim` | `scripts/fetch-cve2.sh`, `scripts/convert-cve2.sh` | the second step of that same shared action: the pinned CVE2 core, hash-verified against `reuse.lock.json` and converted on every run; the converted output is never checked in |
| `lint` | `LINT_REQUIRE_CORE=1 verification/tools/lint_rtl.sh` | RTL lint with `rtl/soc_top.sv` included |
| `sim` | `apt-get install -y iverilog`, then `cocotb==PIN_COCOTB` in a venv | Icarus from the runner image; cocotb at `PIN_COCOTB` in `scripts/setup-env.sh` |
| `sim` | `make -C verification xbar` | OBI crossbar, fabric and reset-synchroniser tests |
| `sim` | `make -C verification periph` | GPIO, timer, UART and peripheral-window decode tests |
| `sim` | `make -C verification boot`, `make -C verification boot-1rw` | SoC top boot, default and single-port I-SRAM configurations |
| `sim` | `make -C verification soc`, `make -C verification soc-negative` | SoC firmware tests, and the perturbed-transcript negative check |

What the commands alone do not say: the stand-in check is what keeps `make
soc-gate` honest, because that run simulates the netlist against
`models/…_standin.v` rather than the macro model, so if the `reuse.lock.json`
pin moves or the stand-in is edited, CI fails instead of passing against a
model that no longer matches the macro. `LINT_REQUIRE_CORE=1` is what makes a
missing core fail rather than skip. `boot-1rw` is the boot test again with the
single-port I-SRAM and 1024-word SRAMs; both boot runs use the checked-in
`firmware/boot/boot_rom.hex`.

The `soc` images (`firmware/soc/*.hex`) are checked in and CI simulates them as they are, so CI needs no
RISC-V compiler. `firmware/soc/build.sh --check` (pinned xPack GCC, local) rebuilds them and compares.

The PDK-heavy legs stay **local**, run by hand and recorded under `records/`:
synthesis, pre-route STA, place-and-route, DRC and LVS (they need the pinned
sky130 PDK, Yosys, OpenROAD and `klt`; see
[`../docs/environment.md`](../docs/environment.md)). CI does not check them, so
a green CI says nothing about timing or layout.

| Local leg | Command | Records under |
| --- | --- | --- |
| synthesis | `scripts/synth-soc.sh` | `records/soc-synth/` |
| pre-route STA | `scripts/fetch-sram-macro.sh` then `klt sta flow/soc/sta_preroute_request.json --format json` | `records/soc-sta-preroute/` |
| place-and-route | `scripts/pnr-soc.sh` | `records/soc-pnr/` |

Pre-route STA times `netlist/soc_top_synth.v` directly (`klt sta`'s DEF-free
`verilog` mode) at `tt_025C_1v80` against a liberty wire-load model: a
netlist-level estimate with no placement, clock tree or routing. It is never a
signoff Fmax.
