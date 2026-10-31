# verification

Testbenches, the evidence-record trail and the checks that keep both valid.
Verification is the product: no claim without a testbench committed here with a
cold-start command a third party can run.

| Path | Holds |
| --- | --- |
| `Makefile`, `cocotb.mk` | the single runner entry point (cocotb + Icarus Verilog) |
| `tests/boot/` | SoC top boot test (`make boot`, `make boot-1rw`): CVE2 + fabric run `firmware/boot`; needs the converted core |
| `tests/<name>/` | one directory per testbench (DUT sources + cocotb module); `tests/xbar/` holds the fabric and reset-synchroniser tests, `tests/periph/` the GPIO, timer and peripheral-window decode tests |
| `tools/lint_records.py` | linter for `records/` (stdlib only) |
| `tools/lint_rtl.sh` | Verilator lint over `../rtl/`; a no-op while it is empty |
| `tools/tests/` | good and bad record fixtures plus the linter's own test |
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

CI (`.github/workflows/ci.yml`, on pull requests and `main`) runs the record
linter and its fixture test, RTL lint, and the cocotb `xbar` (OBI
crossbar, fabric and reset synchroniser), `periph` and SoC boot tests. The
`lint` and `sim` jobs each install sv2v at `PIN_SV2V` (sha256
`PIN_SV2V_SHA256` in `scripts/setup-env.sh`), then run
`scripts/fetch-cve2.sh` and `scripts/convert-cve2.sh` to build the pinned
core. `lint` runs with `LINT_REQUIRE_CORE=1`, so `rtl/soc_top.sv` is always
linted and a missing core fails instead of skipping. `sim` runs `make boot`
and `make boot-1rw` (the same test with the single-port I-SRAM and 1024-word
SRAMs) from the checked-in `firmware/boot/boot_rom.hex`, so CI needs no
RISC-V GCC.

The PDK-heavy legs stay **local**, run by hand and recorded under `records/`:
synthesis, place-and-route, DRC and LVS (they need the pinned sky130 PDK, Yosys,
OpenROAD and `klt`; see [`../docs/environment.md`](../docs/environment.md)).
CI does not check them, so a green CI says nothing about timing or layout.
