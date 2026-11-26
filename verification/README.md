# verification

Testbenches, the evidence-record trail and the checks that keep both valid.
Verification is the product: no claim without a testbench committed here with a
cold-start command a third party can run.

| Path | Holds |
| --- | --- |
| `Makefile`, `cocotb.mk` | the single runner entry point (cocotb + Icarus Verilog) |
| `tests/soc/` | SoC firmware tests (`make soc`): banner, UART echo, GPIO toggle/readback and timer interrupt on `firmware/soc/*.hex`; `make soc-negative` checks a perturbed golden transcript fails |
| `tests/boot/` | SoC top boot test (`make boot`): CVE2 + fabric run `firmware/boot`; needs the converted core |
| `tests/archtest/` | the riscv-arch-test (ACT4) suite on the SoC (`make archtest`): `test_archtest.py` is one cocotb test per selected ACT4 image, `soc_top_archtest.sv` the testbench top, `fv_request.json` the `klt functional-verification` request, `dut/` the SoC's ACT4 configuration (UDB config, linker script, RVMODEL macros, Sail model) and `selection.txt` the generated list of the selected tests and of every other candidate with the reason it is skipped. The images are built, not checked in (`scripts/build-archtest.sh`); needs the ACT4 toolchain |
| `tests/<name>/` | one directory per testbench (DUT sources + cocotb module); `tests/xbar/` holds the fabric and reset-synchroniser tests, `tests/periph/` the GPIO, timer and peripheral-window decode tests |
| `tests/lib/` | not a testbench: the shared bench cores every testbench may import -- `obi_bench.py` (one definition of the `soc_fabric`/peripheral reset-clocking sequence and of the request/accept/response contract) and `soc_top_bench.py` (one definition of the `soc_top` clock, reset, D-SRAM result-block peek and preload, shared by `tests/boot` and `tests/soc`). `cocotb.mk` puts it on `PYTHONPATH` after `TESTDIR`; testbenches still cannot import each other |
| `models/` | `sky130_sram_2kbyte_1rw1r_32x512_8_standin.v`, the Icarus-simulable stand-in `make soc-gate` uses in place of the pinned macro model; its header lists every difference |
| `tools/lint_records.py` | linter for `records/` (stdlib only) |
| `tools/check_sram_standin.py` | fails unless the SRAM stand-in differs from the pinned macro model (sha256 against `reuse.lock.json`) only in the ways its `ALLOWED_EDITS` list documents |
| `tools/lint_rtl.sh` | Verilator lint over `../rtl/`; fails if that tree holds no sources |
| `tools/archtest_select.py` | the tests ACT4 selects for the SoC configuration and, for every other candidate, the select_tests criteria it fails; run inside riscv-arch-test's Python environment by `scripts/build-archtest.sh` |
| `tools/archtest_manifest.py` | turns an ACT4 build into `build/archtest/manifest.json` for the bench (images, RAM, halt codes); refuses a build whose selection differs from the committed `tests/archtest/selection.txt`, or that is inconsistent with the request or the linker script |
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
Drive reset through `obi_bench.reset_dut` (or, for a `soc_top` DUT, build on
`soc_top_bench.SocTop`) rather than reimplementing the sequence, and state the
bus timing by referring to `tests/lib/obi_bench.py` instead of restating it, so
there stays one copy to keep true.

## Architecture tests (`riscv-arch-test`, ACT4)

The ISA conformance suite of spec/soc.md § Verification plan row 1. It stays
local: besides the klt, Icarus and cocotb the other targets need, it takes
Sail, a newer RISC-V GCC, Ruby with the `udb` gems and `uv`, and CI has none
of those four. Check the host with `scripts/setup-env.sh --check-act4`, then:

```
make -C verification archtest            # build the images, run the suite, print klt's report
make -C verification archtest ARCHTEST_REPORT=report.json   # the same run, the JSON report written to a file
make -C verification archtest-negative   # one corrupted reference result must fail its test
```

When a test fails, klt exits 3 and GNU Make exits 2.

`make archtest` is the cold start: `scripts/build-archtest.sh` fetches
riscv-arch-test at the commit pinned in `reuse.lock.json` (every file verified
against `reuse.lock.d/`), generates the tests, builds the self-checking ELFs
ACT4 selects for the SoC (`tests/archtest/dut/` is the configuration; Sail
produces the reference results), and writes `build/archtest/` — nothing is
checked in except `tests/archtest/selection.txt`, the selected tests and the
reason every other candidate is skipped, which the build regenerates and
refuses to differ from. The suite then runs through `klt functional-verification` at
`PIN_KLT`: the executable selected by `KLT` (default `klt` on `PATH`) must match the pin and its Python must import
cocotb (a worktree-local venv with both, first on `PATH`, as the records
describe). The target takes about seven minutes on a dispatch worker: two to
build, five to run.

How the tests reach the SoC, and why the result is what it is, is in the
record under `records/archtest/` (its `README.md`); `tests/archtest/test_archtest.py`'s
and `soc_top_archtest.sv`'s headers describe the testbench. In short: the DUT
is `rtl/soc_top.sv` with its instruction SRAM elaborated 512 KB deep
(testbench-only, behind the fabric) and a boot ROM that jumps to the test;
pass/fail is ACT4's own self-check halt, read from the D-SRAM.

## What CI runs, and what stays local

This is the one complete list of what CI runs; `README.md` and the `ci.yml`
header point here rather than repeating it, so a new or changed CI step is
added here and nowhere else. Every command the two jobs of
`.github/workflows/ci.yml` (on pull requests, merge-group queue entries and
`main`) run, in order, paths
relative to the repository root:

| Job | Runs | What it covers |
| --- | --- | --- |
| `lint` | `apt-get install -y verilator iverilog` | Verilator for RTL lint; Icarus because the CVE2 convert smoke test elaborates with it |
| `lint` | `verification/tools/lint_records.py`, `verification/tools/tests/test_lint_records.py` | the record linter over `records/`, and its good/bad fixture test |
| `lint` | `verification/tools/tests/test_fetch_cve2.sh` | the pinned-import fetcher's exit codes, both entry points, against a `file://` fixture |
| `lint` | `verification/tools/tests/test_lint_rtl.sh`, `verification/tools/tests/test_setup_env_check.sh` | the check scripts' exit codes: `lint_rtl.sh` on an empty `rtl/` tree, `setup-env.sh --check` on each cocotb state |
| `lint` | `verification/tools/tests/test_archtest_manifest.py` | the ACT4 manifest tool with faked inputs: a consistent build becomes a manifest, and each inconsistency the tool promises to refuse fails naming its cause |
| `lint` | `verification/tools/check_workflow_triggers.py`, `verification/tools/tests/test_check_workflow_triggers.py` | the workflow triggers satisfy the merge-queue contract — `merge_group` declared with no path filters, each queue entry its own concurrency group, never cancelled — and its fixture test |
| `lint` | `verification/tools/check_soc_rows.py`, `verification/tools/tests/test_check_soc_rows.py` | the spec row projections match `spec/soc.md`, and its fixture test |
| `lint` | `scripts/fetch-sram-macro.sh`, `verification/tools/check_sram_standin.py`, `verification/tools/tests/test_check_sram_standin.py` | the SRAM stand-in against the pinned macro views (fetched hash-verified), and its fixture test |
| `lint`, `sim` | sv2v at `PIN_SV2V` (sha256 `PIN_SV2V_SHA256` in `scripts/setup-env.sh`) | the pinned converter, downloaded and hash-checked per job; both jobs run it from the one shared composite action, `.github/actions/cve2-core` |
| `lint`, `sim` | `scripts/fetch-cve2.sh`, `scripts/convert-cve2.sh` | the second step of that same shared action: the pinned CVE2 core, hash-verified against `reuse.lock.json` and converted on every run; the converted output is never checked in |
| `lint` | `LINT_REQUIRE_CORE=1 verification/tools/lint_rtl.sh` | RTL lint with `rtl/soc_top.sv` included |
| `sim` | `apt-get install -y iverilog`, then `cocotb==PIN_COCOTB` in a venv | Icarus from the runner image; cocotb at `PIN_COCOTB` in `scripts/setup-env.sh` |
| `sim` | `make -C verification xbar` | OBI crossbar, fabric and reset-synchroniser tests |
| `sim` | `make -C verification periph` | GPIO, timer, UART and peripheral-window decode tests |
| `sim` | `make -C verification boot` | SoC top boot test |
| `sim` | `make -C verification soc`, `make -C verification soc-negative` | SoC firmware tests, and the perturbed-transcript negative check |

What the commands alone do not say: the stand-in check is what keeps `make
soc-gate` honest, because that run simulates the netlist against
`models/…_standin.v` rather than the macro model, so if the `reuse.lock.json`
pin moves or the stand-in is edited, CI fails instead of passing against a
model that no longer matches the macro. `LINT_REQUIRE_CORE=1` is what makes a
missing core fail rather than skip. The boot run uses the checked-in
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
| architecture tests | `make -C verification archtest` (ACT4 toolchain, see above) | `records/archtest/` |

Pre-route STA times `netlist/soc_top_synth.v` directly (`klt sta`'s DEF-free
`verilog` mode) at `tt_025C_1v80` against a liberty wire-load model: a
netlist-level estimate with no placement, clock tree or routing. It is never a
signoff Fmax.
