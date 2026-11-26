#!/usr/bin/env bash
# Fetch one "mode": "fetched" import from reuse.lock.json and verify every file.
#
#   scripts/fetch-import.sh --import <owner/repo> --lock <reuse.lock.json> \
#                           --out <dir> --base-url <url> \
#                           --layout tree|flat --label <text>
#
# Downloads every file listed under <owner/repo> at its pinned commit into
# <dir>. --layout tree keeps the upstream directory layout; --layout flat writes
# each file under its basename. Every file's sha256 must match the lock. Files
# are staged in a temp dir and only moved into place when all of them verify, so
# a failure never leaves a partial tree behind. Exit 1 on any mismatch, missing
# file or download failure.
#
# Per-file downloads come from <base-url>/<commit>/<upstream-path>. An import
# may instead name an "archive" (the tarball of the commit) and a "manifest" (a
# JSON object beside the lock holding "files": {path: sha256} and "symlinks":
# {path: target} for the commit's whole tree): the archive is downloaded once
# and unpacked, every manifest file and symlink is verified the same way, and
# the unpacked tree may hold nothing the manifest does not list. That is the
# form a tree of thousands of files takes (riscv-arch-test).
#
# This is the one hash-verifying fetch path: scripts/fetch-cve2.sh,
# scripts/fetch-sram-macro.sh and scripts/fetch-arch-test.sh are thin entry
# points that supply the arguments above (and their own CVE2_* / SRAM_* /
# ARCHTEST_* overrides). Its exit codes are tested, through every entry point,
# by verification/tools/tests/test_fetch_cve2.sh.
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

# "<commit>", then the archive URL or "-", then one "<sha256> <path>" line per
# file and one "symlink <path> <target>" line per symlink.
ENTRIES_TEXT="$(python3 -I - "$LOCK" "$IMPORT" <<'PY'
import json, sys
from pathlib import Path

lock_file = Path(sys.argv[1])
lock = json.load(open(lock_file))
imp = next(i for i in lock["imports"] if i["from"] == sys.argv[2])
print(imp["commit"])
print(imp.get("archive", "-"))
for f in imp.get("files", []):
    print(f["sha256"], f["upstream"])
if "manifest" in imp:
    manifest = json.load(open(lock_file.parent / imp["manifest"]))
    if (manifest["from"], manifest["commit"]) != (imp["from"], imp["commit"]):
        sys.exit(f"FAIL  {imp['manifest']} describes {manifest['from']}@{manifest['commit']}, the lock pins {imp['from']}@{imp['commit']}")
    for path, digest in sorted(manifest["files"].items()):
        print(digest, path)
    for path, target in sorted(manifest["symlinks"].items()):
        print("symlink", path, target)
PY
)"
mapfile -t ENTRIES <<<"$ENTRIES_TEXT"
COMMIT="${ENTRIES[0]}"
ARCHIVE="${ENTRIES[1]}"
ENTRIES=("${ENTRIES[@]:2}")
BASE="$BASE_URL/$COMMIT"

# Every path the lock lists, for the nothing-else check below.
declare -A LOCKED=()
FILES=0
for entry in "${ENTRIES[@]}"; do
    if [[ "$entry" == symlink\ * ]]; then
        read -r _ path _ <<<"$entry"
    else
        read -r _ path <<<"$entry"
        FILES=$((FILES + 1))
    fi
    LOCKED["$path"]=1
done
if [[ "$ARCHIVE" != "-" && "$LAYOUT" != tree ]]; then
    echo "FAIL  an archive import must use --layout tree" >&2
    exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/tree"

if [[ "$ARCHIVE" != "-" ]]; then
    # The archive holds one top-level directory (<repository>-<commit>).
    if ! curl -fsSL --retry 2 -o "$STAGE/archive.tar.gz" "$ARCHIVE"; then
        echo "FAIL  archive download failed ($ARCHIVE)" >&2
        exit 1
    fi
    if ! tar -xzf "$STAGE/archive.tar.gz" -C "$STAGE/tree" --strip-components=1; then
        echo "FAIL  archive is not a gzip tarball ($ARCHIVE)" >&2
        exit 1
    fi
fi

for entry in "${ENTRIES[@]}"; do
    if [[ "$entry" == symlink\ * ]]; then
        read -r _ path target <<<"$entry"
        dest="$STAGE/tree/$path"
        [[ -L "$dest" ]] || { echo "FAIL  $path: not a symlink in the fetched tree" >&2; exit 1; }
        got="$(readlink "$dest")"
        [[ "$got" == "$target" ]] || { echo "FAIL  $path: symlink to $got, lock says $target" >&2; exit 1; }
        continue
    fi
    want="${entry%% *}"
    path="${entry#* }"
    if [[ "$LAYOUT" == tree ]]; then
        dest="$STAGE/tree/$path"
    else
        dest="$STAGE/tree/$(basename "$path")"
    fi
    if [[ "$ARCHIVE" == "-" ]]; then
        mkdir -p "$(dirname "$dest")"
        if ! curl -fsS --retry 2 -o "$dest" "$BASE/$path"; then
            echo "FAIL  $path: download failed ($BASE/$path)" >&2
            exit 1
        fi
    elif [[ ! -f "$dest" ]]; then
        echo "FAIL  $path: not in the fetched tree" >&2
        exit 1
    fi
    got="$(sha256sum "$dest" | cut -d' ' -f1)"
    if [[ "$got" != "$want" ]]; then
        echo "FAIL  $path: sha256 $got, lock says $want" >&2
        exit 1
    fi
done

# A tree layout holds exactly what the lock lists: a file or symlink that is
# there and not in the lock is as much a mismatch as a wrong digest.
if [[ "$LAYOUT" == tree ]]; then
    while IFS= read -r -d '' found; do
        rel="${found#"$STAGE/tree/"}"
        if [[ -z "${LOCKED[$rel]:-}" ]]; then
            echo "FAIL  $rel: in the fetched tree, not in the lock" >&2
            exit 1
        fi
    done < <(find "$STAGE/tree" \( -type f -o -type l \) -print0)
fi

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
mv "$STAGE/tree" "$OUT"
trap - EXIT
echo "ok    fetched $FILES ${LABEL} files @ ${COMMIT} into ${OUT}"
