#!/usr/bin/env bash
# Fetch the pinned CVE2 sources named in reuse.lock.json and verify each one.
#
#   scripts/fetch-cve2.sh
#
# Downloads every file listed under the openhwgroup/cve2 import at its pinned
# commit into $CVE2_OUT (default build/cve2/upstream, git-ignored), keeping the
# upstream layout. Every file's sha256 must match the lock. Files are staged in
# a temp dir and only moved into place when all of them verify, so a failure
# never leaves a partial tree behind. Exit 1 on any mismatch, missing file or
# download failure.
#
# Overrides (used by the shell test): CVE2_LOCK, CVE2_OUT, CVE2_BASE_URL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="${CVE2_LOCK:-$ROOT/reuse.lock.json}"
OUT="${CVE2_OUT:-$ROOT/build/cve2/upstream}"

# "<commit>" then one "<sha256> <path>" line per file.
mapfile -t ENTRIES < <(python3 -I - "$LOCK" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1]))
imp = next(i for i in lock["imports"] if i["from"] == "openhwgroup/cve2")
print(imp["commit"])
for f in imp["files"]:
    print(f["sha256"], f["upstream"])
PY
)
COMMIT="${ENTRIES[0]}"
BASE="${CVE2_BASE_URL:-https://raw.githubusercontent.com/openhwgroup/cve2}/$COMMIT"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

for entry in "${ENTRIES[@]:1}"; do
    want="${entry%% *}"
    path="${entry#* }"
    mkdir -p "$STAGE/$(dirname "$path")"
    if ! curl -fsS --retry 2 -o "$STAGE/$path" "$BASE/$path"; then
        echo "FAIL  $path: download failed ($BASE/$path)" >&2
        exit 1
    fi
    got="$(sha256sum "$STAGE/$path" | cut -d' ' -f1)"
    if [[ "$got" != "$want" ]]; then
        echo "FAIL  $path: sha256 $got, lock says $want" >&2
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
mv "$STAGE" "$OUT"
trap - EXIT
echo "ok    fetched $((${#ENTRIES[@]} - 1)) CVE2 files @ ${COMMIT} into ${OUT}"
