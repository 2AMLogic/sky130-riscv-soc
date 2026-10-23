# Environment

The PDK and open toolchain are pinned in one place: the variables at the top
of [`scripts/setup-env.sh`](../scripts/setup-env.sh). This page describes them;
if the two disagree, the script wins.

## Pins

| Item | Pin | How it is checked |
| --- | --- | --- |
| PDK | `sky130A`, open_pdks `f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7` | `$PDK_ROOT/sky130A/SOURCES` |
| Standard cells | `sky130_fd_sc_hd`, corner `tt_025C_1v80` for the smoke run | named in each request |
| PDK fetcher | ciel `3.1.0`, run through `uvx` | used by the fetch step only |
| klayout-tools | `klt 0.7.1.dev2517+g6bb7cf233677`, git `6bb7cf2336776b9f768fab21c678ee8a2c54e709` (has `signoff --check` and `--attest`) | `klt --version`; CI `signoff` job installs from the SHA |
| Yosys | `0.67+post`, git `b8e7da6f40ae8f552c116bf6c359b07c6533e159` | `yosys -V` |
| Icarus Verilog | `13.0` | `iverilog -V` |
| OpenROAD | `26Q3-1510-g6cb3f2b704`, image `openroad/orfs@sha256:bb7f31697fb8466ab61852fc796376cc16d9df38f762ccb733218b8a5e55824b` | `openroad -version`; the wrapper's image digest |
| sv2v | `v0.0.13` (SystemVerilog to Verilog for CVE2) | `sv2v --version` |
| cocotb | `2.0.1` (needed from #6; reported, not required) | `import cocotb` |

The `open_pdks` revision matches the one `2AMLogic/sky130-modexp` records in
its decision record `0008-requalification-under-open-pdks-f6eeac7.md`.

Not pinned here: the SRAM macros. The core is pinned in `reuse.lock.json`
and converted as described under "CVE2 fetch and conversion".

## Reproduce from a clean checkout

```bash
export PDK_ROOT=~/.ciel          # or any directory you own
scripts/setup-env.sh             # fetch sky130A at the pinned revision, then check
scripts/setup-env.sh --check     # check only
```

`--check` exits non-zero and names the item on any PDK or tool mismatch. Two
items only warn: cocotb not yet installed, and OpenROAD that cannot report a
version (for example no docker access). A warning on OpenROAD means any
place-and-route leg must be recorded as not run.

The script installs no tools. It writes only into `$PDK_ROOT`. Install or
upgrade tools through the host's provisioning, or use a throwaway environment
such as `uvx --from "klayout-tools==X.Y.Z" klt ...`.

Note that the klt pin is a development build string, not a release. Moving to
a release is a pin bump in the script plus a new smoke record.

## Smoke run

`flow/smoke/counter.v` is a trivial counter that proves the toolchain runs. It
is **toolchain evidence, not design evidence** and is never cited for a T1
item. The dated record is under
[`verification/records/toolchain-smoke/`](../verification/records/toolchain-smoke/):
synthesis ran (22 cells, `sky130_fd_sc_hd` at `tt_025C_1v80`); place-and-route
was **not run** because the OpenROAD docker wrapper has no docker access on the
recording host. Records are append-only: a later run adds a new dated
directory.

## CVE2 fetch and conversion

The pinned CVE2 commit and the sha256 of every file the build consumes are in
[`reuse.lock.json`](../reuse.lock.json). The converted Verilog is generated and
git-ignored (`build/`); it is never committed or edited.

```bash
scripts/fetch-cve2.sh      # download + verify every locked file -> build/cve2/upstream
scripts/convert-cve2.sh    # sv2v -> build/cve2/cve2_top.v, then Icarus elaboration + Verilator lint
```

`fetch-cve2.sh` exits non-zero on any sha256 mismatch, missing file or failed
download, and leaves no partial tree. Its exit codes are tested by
`verification/tools/tests/test_fetch_cve2.sh`.

The conversion is pinned by (CVE2 commit, `PIN_SV2V`, the command printed by
`convert-cve2.sh`). It defines `SYNTHESIS`, which drops a simulation-only DPI
export block in `cve2_if_stage.sv`; without it Icarus rejects the output.
`cve2_core.f` upstream omits `cve2_csr.sv`, `cve2_pmp.sv` and `cve2_wb.sv`, so the
lock lists them explicitly. With these, Icarus 13.0 elaborates `cve2_top`
(no Verilator alternative needed per record 0001 Gate 1); Verilator lint runs
with width warnings from the sv2v output, which are not treated as fatal.

`convert-cve2.sh` uses `sv2v` from `PATH` or `$SV2V`. sv2v is not provisioned on
the dispatch workers; verification for this change used a throwaway download of
the v0.0.13 release outside the repo.
