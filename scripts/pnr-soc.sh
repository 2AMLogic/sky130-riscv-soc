#!/usr/bin/env bash
# Place and route soc_top from netlist/soc_top_synth.v.
#
#   scripts/pnr-soc.sh
#
# Fetches the pinned SRAM macro views, then runs `klt place-and-route` on
# flow/soc/pnr_request.json. The macro PDN grid without a core met3 strap
# (klayout-tools#4703), the escaped-bracket macro instance names (#4715/#4717) and the
# placement-density / route-congestion request fields (#4716/#4719) are all in klt commit
# 34a20645, which is not in a PyPI release yet; KLT_SPEC pins that commit.
# Override KLT_SPEC with a released pin ("klayout-tools==X.Y.Z") once one has the fixes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PDK="${PDK:-sky130A}"
KLT_SPEC="${KLT_SPEC:-git+https://github.com/2AMLogic/klayout-tools.git@34a20645968b8865ca4ec8711fad580f9fd0a38e}"
KLT=(uvx --from "$KLT_SPEC" klt)

"$ROOT/scripts/fetch-sram-macro.sh"

rm -rf build/pnr
"${KLT[@]}" place-and-route flow/soc/pnr_request.json --format json > build/pnr_result.json
echo "ok    build/pnr_result.json"
