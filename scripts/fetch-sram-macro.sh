#!/usr/bin/env bash
# Fetch the pinned SRAM macro views named in reuse.lock.json and verify each one.
#
#   scripts/fetch-sram-macro.sh
#
# Downloads the efabless/sky130_sram_macros files (Verilog, Liberty, LEF, GDS) at
# the pinned commit into $SRAM_OUT (default build/sram_macro, git-ignored), flat
# by file name. Every file's sha256 must match the lock; nothing is moved into
# place unless all of them verify. Exit 1 on any mismatch or download failure.
#
# Overrides: SRAM_LOCK, SRAM_OUT, SRAM_BASE_URL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="${SRAM_LOCK:-$ROOT/reuse.lock.json}"
OUT="${SRAM_OUT:-$ROOT/build/sram_macro}"

mapfile -t ENTRIES < <(python3 -I - "$LOCK" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1]))
imp = next(i for i in lock["imports"] if i["from"] == "efabless/sky130_sram_macros")
print(imp["commit"])
for f in imp["files"]:
    print(f["sha256"], f["upstream"])
PY
)
COMMIT="${ENTRIES[0]}"
BASE="${SRAM_BASE_URL:-https://raw.githubusercontent.com/efabless/sky130_sram_macros}/$COMMIT"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

for entry in "${ENTRIES[@]:1}"; do
    want="${entry%% *}"
    path="${entry#* }"
    if ! curl -fsS --retry 2 -o "$STAGE/$(basename "$path")" "$BASE/$path"; then
        echo "FAIL  $path: download failed ($BASE/$path)" >&2
        exit 1
    fi
    got="$(sha256sum "$STAGE/$(basename "$path")" | cut -d' ' -f1)"
    if [[ "$got" != "$want" ]]; then
        echo "FAIL  $path: sha256 $got, lock says $want" >&2
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
mv "$STAGE" "$OUT"
trap - EXIT
echo "ok    fetched $((${#ENTRIES[@]} - 1)) SRAM macro files @ ${COMMIT} into ${OUT}"
