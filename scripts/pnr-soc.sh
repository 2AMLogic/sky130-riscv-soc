#!/usr/bin/env bash
# Place and route soc_top from netlist/soc_top_synth.v.
#
#   scripts/pnr-soc.sh
#
# Fetches the pinned SRAM macro views, then runs `klt place-and-route` on
# flow/soc/pnr_request.json with the repo's one klt pin, PIN_KLT in
# scripts/setup-env.sh. KLT_SPEC overrides that pin for a run that needs an
# unreleased klt (for example
# "git+https://github.com/2AMLogic/klayout-tools.git@<commit>"); a run that
# overrides it must state the value used in its record's provenance.json.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PDK="${PDK:-sky130A}"
PIN_KLT="$(sed -n 's/^PIN_KLT="\([0-9][0-9.]*\)".*/\1/p' scripts/setup-env.sh)"
test -n "$PIN_KLT" || { echo "no PIN_KLT in scripts/setup-env.sh" >&2; exit 1; }
KLT_SPEC="${KLT_SPEC:-klayout-tools==${PIN_KLT}}"
KLT=(uvx --from "$KLT_SPEC" klt)
echo "klt   ${KLT_SPEC}"

"$ROOT/scripts/fetch-sram-macro.sh"

rm -rf build/pnr
"${KLT[@]}" place-and-route flow/soc/pnr_request.json --format json > build/pnr_result.json
echo "ok    build/pnr_result.json"
