# Environment

The PDK and open toolchain are pinned in one place: the variables at the top
of [`scripts/setup-env.sh`](../scripts/setup-env.sh). This page describes them;
if the two disagree, the script wins.

## Pins

| Item | Pin | How it is checked |
| --- | --- | --- |
| PDK | `PIN_PDK_VARIANT` at open_pdks `PIN_OPEN_PDKS_REV` | `$PDK_ROOT/$PIN_PDK_VARIANT/SOURCES` |
| Standard cells | `sky130_fd_sc_hd`, corner `tt_025C_1v80` for the smoke run | named in each request, not a script pin |
| PDK fetcher | `PIN_CIEL` (ciel, run through `uvx`) | used by the fetch step only |
| klayout-tools | `PIN_KLT` (PyPI `klayout-tools`; has `signoff --check` and `--attest`) | `klt --version`; the CI `signoff` job reads `PIN_KLT` and checks `klt --version` |
| Yosys | `PIN_YOSYS`, git `PIN_YOSYS_SHA` | `yosys -V` |
| Icarus Verilog | `PIN_IVERILOG` | `iverilog -V` |
| OpenROAD | `PIN_OPENROAD`, image `PIN_OPENROAD_IMAGE` | `openroad -version`; the wrapper's image digest |
| sv2v | `PIN_SV2V`, release-asset sha256 `PIN_SV2V_SHA256` (SystemVerilog to Verilog for CVE2) | `sv2v --version` |
| RISC-V GCC | xPack `riscv-none-elf-gcc` `PIN_RISCV_GCC`, tarball sha256 `PIN_RISCV_GCC_SHA256`; builds the boot and SoC firmware | `riscv-none-elf-gcc --version` |
| cocotb | `PIN_COCOTB` (every `verification/Makefile` target needs it) | `import cocotb` |

Each `PIN_*` above is a variable in
[`scripts/setup-env.sh`](../scripts/setup-env.sh). No pinned value is copied
onto this page, so a pin bump is a change to that one file;
`scripts/setup-env.sh --check` prints the live values.

The `open_pdks` revision matches the one `2AMLogic/sky130-modexp` records in
its decision record `0008-requalification-under-open-pdks-f6eeac7.md`.

The CVE2 core and the imported SRAM macro views are both pinned in
[`reuse.lock.json`](../reuse.lock.json), which carries a sha256 for every file
the build consumes. The core is converted as described under "CVE2 fetch and
conversion"; which SRAM source the SoC finally adopts is still an open
decision, tracked by the `in_tree` entry in the same file.

## Reproduce from a clean checkout

```bash
export PDK_ROOT=~/.ciel          # or any directory you own
scripts/setup-env.sh             # fetch sky130A at the pinned revision, then check
scripts/setup-env.sh --check     # check only
```

`--check` exits non-zero and names the item on any PDK or tool mismatch,
including a cocotb `python3` cannot import (run it inside the venv
`verification/README.md` tells you to create). One item only warns: an
OpenROAD that cannot report a version (for example no docker access). That
warning means any place-and-route leg must be recorded as not run. What
`--check` reports for each cocotb state is tested by
`verification/tools/tests/test_setup_env_check.sh`.

The script installs no tools. It writes only into `$PDK_ROOT`. Install or
upgrade tools through the host's provisioning, or use a throwaway environment
such as `uvx --from "klayout-tools==X.Y.Z" klt ...`.

The klt pin is a PyPI release, and it lives in exactly one place: `PIN_KLT`
in [`scripts/setup-env.sh`](../scripts/setup-env.sh), which the CI `signoff`
job reads the version from. A pin bump is a change to that line, plus
regenerating any recorded evidence the new klt re-grades.

## Smoke run

`flow/smoke/counter.v` is a trivial counter that proves the toolchain runs. It
is **toolchain evidence, not design evidence** and is never cited for a T1
item, an Fmax, or any design claim. The dated records are under
[`verification/records/toolchain-smoke/`](../verification/records/toolchain-smoke/);
each one's README gives the commands that produced it and the results they
reported. Records are append-only: a later run adds a new dated directory
rather than editing an existing one.

## CVE2 fetch and conversion

The pinned CVE2 commit and the sha256 of every file the build consumes are in
[`reuse.lock.json`](../reuse.lock.json). The converted Verilog is generated and
git-ignored (`build/`); it is never committed or edited.

```bash
scripts/fetch-cve2.sh      # download + verify every locked file -> build/cve2/upstream
scripts/convert-cve2.sh    # sv2v -> build/cve2/cve2_top.v, then Icarus elaboration + Verilator lint
```

`fetch-cve2.sh` exits non-zero on any sha256 mismatch, missing file or failed
download, and leaves no partial tree. It is a thin entry point over
`scripts/fetch-import.sh`, the one hash-verifying fetch path, which
`scripts/fetch-sram-macro.sh` shares (same guarantees, flat output layout).
Both entry points' exit codes and layouts are tested against a `file://`
fixture by `verification/tools/tests/test_fetch_cve2.sh`, which CI runs.

The conversion is pinned by (CVE2 commit, `PIN_SV2V`, the command printed by
`convert-cve2.sh`). It defines `SYNTHESIS`, which drops a simulation-only DPI
export block in `cve2_if_stage.sv`; without it Icarus rejects the output.
`cve2_core.f` upstream omits `cve2_csr.sv`, `cve2_pmp.sv` and `cve2_wb.sv`, so the
lock lists them explicitly. With these, Icarus 13.0 elaborates `cve2_top`
(no Verilator alternative needed per record 0001 Gate 1); Verilator lint runs
with width warnings from the sv2v output, which are not treated as fatal.

`convert-cve2.sh` uses `sv2v` from `PATH` or `$SV2V`. sv2v is not provisioned on
the dispatch workers; use a throwaway download of the pinned release outside
the repo.

The RISC-V GCC is likewise not on the workers. For the firmware builders
(`firmware/boot/build.sh` and `firmware/soc/build.sh`, both entry points to
`firmware/build-image.sh`) and for `make boot` use a throwaway unpack of the
xPack tarball (sha256 in `scripts/setup-env.sh`) under `build/tools/` and put
its `bin/` on `PATH`; the checked-in hex images let `make boot` and `make soc`
run without it.
A worker-spec change would provision both tools.
