#!/usr/bin/env bash
# Place and route soc_top from the synthesized netlist (WIP: does not yet complete).
#
#   scripts/pnr-soc.sh
#
# Fetches the pinned SRAM macro views, derives build/pnr_in/soc_top_pnr.v from
# netlist/soc_top_synth.v, and runs `klt place-and-route` on flow/soc/pnr_request.json.
# The derived netlist differs from the synthesized one only in the eight SRAM macro
# instance names (`\g_bank[N].u_macro` -> `\g_bank_N_u_macro`): klt cannot address an
# instance name with escaped brackets in both place_macro and the macro PDN grid
# (2AMLogic/klayout-tools#4701). Status: the floorplan stage fails with PDN-0179
# because a macro halo forces a core met3 strap (2AMLogic/klayout-tools#4703).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PDK="${PDK:-sky130A}"

"$ROOT/scripts/fetch-sram-macro.sh"

mkdir -p build/pnr_in
sed 's/\\g_bank\[\([0-9]\)\]\.u_macro /\\g_bank_\1_u_macro /' netlist/soc_top_synth.v > build/pnr_in/soc_top_pnr.v
echo "ok    build/pnr_in/soc_top_pnr.v sha256 $(sha256sum build/pnr_in/soc_top_pnr.v | cut -d' ' -f1)"

rm -rf build/pnr
klt place-and-route flow/soc/pnr_request.json --format json > build/pnr_result.json
echo "ok    build/pnr_result.json"
