#!/usr/bin/env bash
# RTL lint over rtl/: passes as a no-op while the tree has no .v/.sv files.
# Verilator --lint-only (handles SystemVerilog).
#
# rtl/soc_top.sv instantiates cve2_top, which is generated, not checked in
# (scripts/fetch-cve2.sh then scripts/convert-cve2.sh -> build/cve2/cve2_top.v).
# When that file exists it is linted with the top; warnings in that
# generated file (sv2v output we never edit) are ignored, any warning or error
# located in rtl/ fails. When it is absent soc_top.sv is skipped with a
# notice, or the script fails if LINT_REQUIRE_CORE=1.
set -euo pipefail
cd "$(dirname "$0")/../.."
CORE="${CVE2_BUILD:-build/cve2}/cve2_top.v"
mapfile -t files < <(find rtl \( -name '*.v' -o -name '*.sv' \) -type f | sort)
if [[ ${#files[@]} -eq 0 ]]; then echo "rtl lint: ok (no RTL files yet)"; exit 0; fi
command -v verilator >/dev/null || { echo "rtl lint: verilator not on PATH" >&2; exit 1; }
args=(--lint-only -Wno-MULTITOP)
core_note=""
if [[ -r "$CORE" ]]; then
    # warnings are not fatal for the generated file; they are filtered below
    args+=(-Wno-fatal "$CORE")
    core_note=", generated core not gated"
elif [[ "${LINT_REQUIRE_CORE:-0}" == 1 ]]; then
    echo "rtl lint: $CORE missing; run scripts/fetch-cve2.sh && scripts/convert-cve2.sh" >&2; exit 1
else
    echo "rtl lint: note: $CORE missing; skipping rtl/soc_top.sv (needs the converted core)"
    kept=()
    for f in "${files[@]}"; do [[ "$f" == rtl/soc_top.sv ]] || kept+=("$f"); done
    files=("${kept[@]}")
fi
# several independent tops (rst_sync, soc_fabric, ...) besides soc_top
out="$(mktemp)"; trap 'rm -f "$out"' EXIT
if ! verilator "${args[@]}" "${files[@]}" >"$out" 2>&1; then cat "$out" >&2; exit 1; fi
# with -Wno-fatal, gate on warnings located in our own files only
if grep -E '^%(Warning|Error)[^:]*: rtl/' "$out" >&2; then
    echo "rtl lint: FAIL (warnings in rtl/)" >&2; exit 1
fi
echo "rtl lint: ok (${#files[@]} files${core_note})"
