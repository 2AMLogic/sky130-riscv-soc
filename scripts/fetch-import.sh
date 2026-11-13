#!/usr/bin/env bash
# Fetch one "mode": "fetched" import from reuse.lock.json and verify every file.
#
#   scripts/fetch-import.sh --import <owner/repo> --lock <reuse.lock.json> \
#                           --out <dir> --base-url <url> \
#                           --layout tree|flat --label <text>
#
# Downloads every file listed under <owner/repo> at its pinned commit from
# <base-url>/<commit>/<upstream-path> into <dir>. --layout tree keeps the
# upstream directory layout; --layout flat writes each file under its basename.
# Every file's sha256 must match the lock. Files are staged in a temp dir and
# only moved into place when all of them verify, so a failure never leaves a
# partial tree behind. Exit 1 on any mismatch, missing file or download failure.
#
# This is the one hash-verifying fetch path: scripts/fetch-cve2.sh and
# scripts/fetch-sram-macro.sh are thin entry points that supply the arguments
# above (and their own CVE2_* / SRAM_* overrides). Its exit codes are tested,
# through both entry points, by verification/tools/tests/test_fetch_cve2.sh.
set -euo pipefail

IMPORT="" LOCK="" OUT="" BASE_URL="" LAYOUT="" LABEL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --import)   IMPORT="$2"; shift 2 ;;
        --lock)     LOCK="$2"; shift 2 ;;
        --out)      OUT="$2"; shift 2 ;;
        --base-url) BASE_URL="$2"; shift 2 ;;
        --layout)   LAYOUT="$2"; shift 2 ;;
        --label)    LABEL="$2"; shift 2 ;;
        *) echo "usage: $0 --import X --lock X --out X --base-url X --layout tree|flat --label X" >&2; exit 2 ;;
    esac
done
for v in IMPORT LOCK OUT BASE_URL LAYOUT LABEL; do
    [[ -n "${!v}" ]] || { echo "FAIL  missing --${v,,} argument" >&2; exit 2; }
done
[[ "$LAYOUT" == tree || "$LAYOUT" == flat ]] || { echo "FAIL  --layout must be tree or flat, got $LAYOUT" >&2; exit 2; }

# "<commit>" then one "<sha256> <path>" line per file.
mapfile -t ENTRIES < <(python3 -I - "$LOCK" "$IMPORT" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1]))
imp = next(i for i in lock["imports"] if i["from"] == sys.argv[2])
print(imp["commit"])
for f in imp["files"]:
    print(f["sha256"], f["upstream"])
PY
)
COMMIT="${ENTRIES[0]}"
BASE="$BASE_URL/$COMMIT"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

for entry in "${ENTRIES[@]:1}"; do
    want="${entry%% *}"
    path="${entry#* }"
    if [[ "$LAYOUT" == tree ]]; then
        dest="$STAGE/$path"
        mkdir -p "$(dirname "$dest")"
    else
        dest="$STAGE/$(basename "$path")"
    fi
    if ! curl -fsS --retry 2 -o "$dest" "$BASE/$path"; then
        echo "FAIL  $path: download failed ($BASE/$path)" >&2
        exit 1
    fi
    got="$(sha256sum "$dest" | cut -d' ' -f1)"
    if [[ "$got" != "$want" ]]; then
        echo "FAIL  $path: sha256 $got, lock says $want" >&2
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
mv "$STAGE" "$OUT"
trap - EXIT
echo "ok    fetched $((${#ENTRIES[@]} - 1)) ${LABEL} files @ ${COMMIT} into ${OUT}"
