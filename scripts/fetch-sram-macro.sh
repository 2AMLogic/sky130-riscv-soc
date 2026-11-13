#!/usr/bin/env bash
# Fetch the pinned SRAM macro views named in reuse.lock.json and verify each one.
#
#   scripts/fetch-sram-macro.sh
#
# Downloads the efabless/sky130_sram_macros files (Verilog, Liberty, LEF, GDS) at
# the pinned commit into $SRAM_OUT (default build/sram_macro, git-ignored), flat
# by file name. Every file's sha256 must match the lock; nothing is moved into
# place unless all of them verify. Exit 1 on any mismatch or download failure.
# The work is done by scripts/fetch-import.sh; this file is the SRAM-macro entry
# point and supplies only its defaults.
#
# Overrides: SRAM_LOCK, SRAM_OUT, SRAM_BASE_URL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/scripts/fetch-import.sh" \
    --import "efabless/sky130_sram_macros" \
    --lock "${SRAM_LOCK:-$ROOT/reuse.lock.json}" \
    --out "${SRAM_OUT:-$ROOT/build/sram_macro}" \
    --base-url "${SRAM_BASE_URL:-https://raw.githubusercontent.com/efabless/sky130_sram_macros}" \
    --layout flat \
    --label "SRAM macro"
