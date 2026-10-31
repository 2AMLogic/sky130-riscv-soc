#!/usr/bin/env bash
# Place and route soc_top from netlist/soc_top_synth.v.
#
#   scripts/pnr-soc.sh
#
# Fetches the pinned SRAM macro views, then runs `klt place-and-route` on
# flow/soc/pnr_request.json. The macro PDN grid without a core met3 strap
# (klayout-tools#4703) is fixed in klt commit dea6cd06, which is not in a PyPI release
# yet; KLT_SPEC pins that commit.
#
# The request runs on build/pnr_in/soc_top_pnr.v, derived from netlist/soc_top_synth.v by
# renaming only the eight SRAM macro instances (`\g_bank[N].u_macro` -> `\g_bank_N_u_macro`):
# place_macro needs the name with one backslash per bracket, while the macro PDN grid's
# -instances takes it as a glob list and needs six, so no single request value works
# even with the #4701 fix. The record cites both netlist hashes.
# Override KLT_SPEC with a released pin ("klayout-tools==X.Y.Z") once one has the fixes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PDK="${PDK:-sky130A}"
KLT_SPEC="${KLT_SPEC:-git+https://github.com/2AMLogic/klayout-tools.git@dea6cd060f2340c0111c958f57b6d9891a7fffd3}"
KLT=(uvx --from "$KLT_SPEC" klt)

"$ROOT/scripts/fetch-sram-macro.sh"

mkdir -p build/pnr_in
sed 's/\\g_bank\[\([0-9]\)\]\.u_macro /\\g_bank_\1_u_macro /' netlist/soc_top_synth.v > build/pnr_in/soc_top_pnr.v
echo "ok    build/pnr_in/soc_top_pnr.v sha256 $(sha256sum build/pnr_in/soc_top_pnr.v | cut -d' ' -f1)"

rm -rf build/pnr
"${KLT[@]}" place-and-route flow/soc/pnr_request.json --format json > build/pnr_result.json
echo "ok    build/pnr_result.json"
