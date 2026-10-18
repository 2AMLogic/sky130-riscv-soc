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
| klayout-tools | `klt 0.7.1.dev1820+g23b4b033a79e` | `klt --version` |
| Yosys | `0.67+post`, git `b8e7da6f40ae8f552c116bf6c359b07c6533e159` | `yosys -V` |
| Icarus Verilog | `13.0` | `iverilog -V` |
| OpenROAD | `26Q3-1510-g6cb3f2b704`, image `openroad/orfs@sha256:bb7f31697fb8466ab61852fc796376cc16d9df38f762ccb733218b8a5e55824b` | `openroad -version`; the wrapper's image digest |
| cocotb | `2.0.1` (needed from #6; reported, not required) | `import cocotb` |

The `open_pdks` revision matches the one `2AMLogic/sky130-modexp` records in
its decision record `0008-requalification-under-open-pdks-f6eeac7.md`.

Not pinned here: the SystemVerilog path (sv2v or an alternative simulator),
the core, and the SRAM macros. Those wait on #2.

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
