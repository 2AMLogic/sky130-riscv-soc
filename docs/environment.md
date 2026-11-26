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
| RISC-V GCC | xPack `riscv-none-elf-gcc` `PIN_RISCV_GCC`; builds the boot and SoC firmware. `PIN_RISCV_GCC_SHA256` is a recorded provenance digest (the toolchain tarball behind the checked-in `firmware/boot/boot_rom.hex` and `firmware/soc/*.hex`), not a checked pin | `riscv-none-elf-gcc --version` |
| cocotb | `PIN_COCOTB` (every `verification/Makefile` target needs it) | `import cocotb` |
| ACT4 toolchain | `PIN_SAIL`, `PIN_ACT_GCC`, `PIN_ACT_RUBY` and `PIN_ACT_UDB` (the `udb`, `udb-gen`, `udb_helpers` and `idlc` gem versions riscv-arch-test's Gemfile.lock pins); only the architecture tests need them, and `scripts/setup-env.sh --check-act4` checks them alone, PDK excepted. `PIN_SAIL_SHA256` and `PIN_ACT_GCC_SHA256` are recorded provenance digests like `PIN_RISCV_GCC_SHA256` | `sail_riscv_sim --version`, `riscv64-unknown-elf-gcc --version`, `ruby --version`, a `ruby -e 'require "udb"'` that prints the four gem versions |

Each `PIN_*` above is a variable in
[`scripts/setup-env.sh`](../scripts/setup-env.sh). No pinned value is copied
onto this page, so a pin bump is a change to that one file;
`scripts/setup-env.sh --check` prints the live values.

The `open_pdks` revision matches the one `2AMLogic/sky130-modexp` records in
its decision record `0008-requalification-under-open-pdks-f6eeac7.md`.

The CVE2 core, the imported SRAM macro views and riscv-arch-test are all
pinned in [`reuse.lock.json`](../reuse.lock.json), which carries a sha256 for
every file the build consumes (for riscv-arch-test, through the manifest it
names; see "riscv-arch-test (ACT4) and its toolchain" below). The core is
converted as described under "CVE2 fetch and
conversion"; which SRAM source the SoC finally adopts is still an open
decision, tracked by the `in_tree` entry in the same file.

## Reproduce from a clean checkout

```bash
export PDK_ROOT=~/.ciel          # or any directory you own
scripts/setup-env.sh             # fetch sky130A at the pinned revision, then check
scripts/setup-env.sh --check     # check only
scripts/setup-env.sh --check-act4   # the ACT4 toolchain of the architecture tests only
```

`--check` exits non-zero and names the item on any PDK or tool mismatch,
including a cocotb `python3` cannot import (run it inside the venv
`verification/README.md` tells you to create). One item only warns: an
OpenROAD that cannot report a version (for example no docker access). That
warning means any place-and-route leg must be recorded as not run. What
`--check` reports for each cocotb state is tested by
`verification/tools/tests/test_setup_env_check.sh`. `--check-act4` needs no PDK
and checks only what `make -C verification archtest` needs: Sail, the newer
RISC-V GCC, Ruby with the `udb` gems, `uv`, klt, Icarus and cocotb.

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
scripts/convert-cve2.sh    # sv2v -> build/cve2/cve2_top.v, then Icarus elaboration
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
lock lists them explicitly. With these, the pinned Icarus elaborates `cve2_top`
(no Verilator alternative needed per record 0001 Gate 1). The converted core is
linted separately by [`verification/tools/lint_rtl.sh`](../verification/tools/lint_rtl.sh).

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

## riscv-arch-test (ACT4) and its toolchain

The architecture-test suite is the other pinned import. `reuse.lock.json`
names the riscv-arch-test commit by its tarball URL and by a manifest,
`reuse.lock.d/riscv-arch-test-<commit>.json`: the sha256 of every file in the
commit's tree and the target of every symlink. `scripts/fetch-arch-test.sh`
downloads the tarball once, verifies all of it and refuses a tree that holds
anything the manifest does not list; the tree lands in `build/archtest/upstream`
(git-ignored) and is never edited. It is fetched whole because ACT4's
generators import across the repository. The same script family fetches CVE2
and the SRAM views file by file; `scripts/fetch-import.sh` is the one
hash-verifying path behind all three.

```bash
scripts/fetch-arch-test.sh                     # download + verify the whole tree
scripts/setup-env.sh --check-act4              # Sail, GCC, Ruby/udb, uv, klt, Icarus, cocotb
make -C verification archtest                  # scripts/build-archtest.sh, then the suite through klt
```

ACT4's own requirements fix the toolchain: it refuses a Sail other than
`PIN_SAIL` and a GCC older than 15 (`framework/src/act/config.py` at the pin),
its `.mise.toml` names the Ruby, and its Gemfile.lock pins the `udb` gems. On
the fleet workers they come from the worker spec (`2AMLogic/2am`,
`infra/aws/loom-worker/`); the two tarball digests in `scripts/setup-env.sh`
are copied from it. Three things are not obvious on such a worker:

- `udb` and `udb-gen` sit in the Ruby prefix beside `bundle`, which is not on
  `PATH`; `scripts/build-archtest.sh` adds that directory itself, because
  bundler resolves `bundle exec udb` through `PATH`.
- ACT4 runs `bundle install` when the gems do not satisfy its lockfile, which
  would write into the Ruby prefix; the build script runs `bundle check` first
  and stops instead.
- ACT4's Python environment (`act`, `testgen`, `covergroupgen`, from its
  `uv.lock`) is created by `uv sync --frozen --no-dev` inside the fetched tree,
  so `uv` has to be on `PATH`.

`uv` itself is not pinned: any version that can read ACT4's `uv.lock` produces
the same environment. The suite's results and their provenance are recorded
under `verification/records/archtest/`.
