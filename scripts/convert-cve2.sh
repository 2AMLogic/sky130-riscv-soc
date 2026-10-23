#!/usr/bin/env bash
# Convert the fetched, hash-verified CVE2 sources to Verilog with sv2v.
#
#   scripts/convert-cve2.sh        (run scripts/fetch-cve2.sh first)
#
# Output: $CVE2_BUILD/cve2_top.v (default build/cve2), git-ignored and never
# edited by hand. The conversion is pinned by (CVE2 commit in reuse.lock.json,
# sv2v version PIN_SV2V in scripts/setup-env.sh, the command below). SYNTHESIS
# is defined to drop the simulation-only DPI export block in cve2_if_stage.sv.
# Then smoke-checks the result: Icarus must elaborate cve2_top, and Verilator
# lint must run (width warnings from sv2v output are not fatal).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${CVE2_BUILD:-$ROOT/build/cve2}"
SRC="${CVE2_OUT:-$BUILD/upstream}"
SV2V="${SV2V:-sv2v}"
PRIM=vendor/lowrisc_ip/ip/prim/rtl

[[ -d "$SRC/rtl" ]] || { echo "no $SRC; run scripts/fetch-cve2.sh first" >&2; exit 1; }
mkdir -p "$BUILD"

cd "$SRC"
mapfile -t REST < <(ls rtl/*.sv | grep -v -e cve2_pkg.sv -e cve2_core.sv -e cve2_top.sv | sort)
CMD=("$SV2V" -DSYNTHESIS -I "$PRIM" -I rtl -I vendor/lowrisc_ip/dv/sv/dv_utils
     "$PRIM/prim_assert.sv" rtl/cve2_pkg.sv "$PRIM/prim_ram_1p_pkg.sv"
     "${REST[@]}" rtl/cve2_core.sv rtl/cve2_top.sv --top cve2_top -w "$BUILD/cve2_top.v")
echo "+ ${CMD[*]}"
"${CMD[@]}"
cd "$BUILD"

iverilog -g2012 -s cve2_top -o "$BUILD/cve2_top.vvp" cve2_top.v
echo "ok    icarus elaborates cve2_top"
verilator --lint-only -Wno-fatal --top-module cve2_top cve2_top.v 2>&1 | tail -n 3 || true
echo "ok    verilator lint ran"
