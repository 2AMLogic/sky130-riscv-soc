#!/usr/bin/env bash
# RTL lint over rtl/: passes as a no-op while the tree has no .v/.sv files.
# Verilator --lint-only (handles SystemVerilog); not yet traced against the
# eventual core sources (spec issue #2), so the tool choice may move.
set -euo pipefail
cd "$(dirname "$0")/../.."
mapfile -t files < <(find rtl \( -name '*.v' -o -name '*.sv' \) -type f | sort)
if [[ ${#files[@]} -eq 0 ]]; then echo "rtl lint: ok (no RTL files yet)"; exit 0; fi
command -v verilator >/dev/null || { echo "rtl lint: verilator not on PATH" >&2; exit 1; }
# several independent tops (rst_sync, soc_fabric, ...) until the SoC top lands
verilator --lint-only -Wno-MULTITOP "${files[@]}"
echo "rtl lint: ok (${#files[@]} files)"
