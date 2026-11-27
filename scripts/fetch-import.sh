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

# Keep the archive and verified tree beside OUT. A full ACT4 tree is larger
# than a worker's /tmp, and publication must stay on the same filesystem.
parent="$(dirname -- "$OUT")"
mkdir -p "$parent"
STAGE="$(mktemp -d "$parent/.fetch-import.XXXXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/tree"

# Merge inline digests with the external manifest, then hand the declared
# objects to the appropriate downloader.
python3 -I - "$LOCK" "$IMPORT" "$STAGE" <<'PYLOCK'
import json, sys
from pathlib import Path

lock_file, repo, stage = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
imp = next(i for i in json.loads(lock_file.read_text())["imports"] if i["from"] == repo)
files, links = {}, {}
if "manifest" in imp:
    manifest_path = lock_file.parent / imp["manifest"]
    manifest = json.loads(manifest_path.read_text())
    if (manifest["from"], manifest["commit"]) != (repo, imp["commit"]):
        sys.exit(f"FAIL  {manifest_path} describes {manifest['from']}@{manifest['commit']}, the lock pins {repo}@{imp['commit']}")
    files, links = manifest["files"], manifest["symlinks"]
for f in imp.get("files", []):
    if files.setdefault(f["upstream"], f["sha256"]) != f["sha256"]:
        sys.exit(f"FAIL  conflicting digests for {f['upstream']}")
if files.keys() & links.keys():
    sys.exit("FAIL  lock declares a path as both file and symlink")
(stage / "pin").write_text(imp["commit"] + "\n" + imp.get("archive", "-") + "\n")
if "archive" in imp:
    (stage / "members.json").write_text(json.dumps({"files": files, "symlinks": links}))
else:
    if links:
        sys.exit("FAIL  symlink imports require an archive")
    (stage / "entries").write_text("".join(f"{digest} {name}\n" for name, digest in files.items()))
PYLOCK
mapfile -t pin < "$STAGE/pin"
COMMIT="${pin[0]}"
ARCHIVE="${pin[1]}"

if [[ "$ARCHIVE" != "-" ]]; then
    [[ "$LAYOUT" == tree ]] || { echo "FAIL  an archive import must use --layout tree" >&2; exit 1; }
    curl -fsSL --retry 2 -o "$STAGE/archive.tar.gz" "$ARCHIVE"
    FILES="$(python3 -I - "$STAGE" <<'PYARCH'
import hashlib
import json
import shutil
import sys
import tarfile
from pathlib import Path

stage = Path(sys.argv[1])
manifest = json.loads((stage / "members.json").read_text())
files, links = manifest["files"], manifest["symlinks"]
tree = stage / "tree"
expected = files.keys() | links.keys()
seen = set()
root = None
with tarfile.open(stage / "archive.tar.gz", "r|gz") as archive:
    for member in archive:
        parts = member.name.split("/")
        if root is None:
            root = parts[0]
        if parts[0] != root or any(p in ("", ".", "..") for p in parts):
            sys.exit(f"FAIL  unexpected archive path: {member.name}")
        name = "/".join(parts[1:]) or "."
        if member.isdir() and name not in expected:
            (tree / name).mkdir(parents=True, exist_ok=True)
            continue
        if name in seen:
            sys.exit(f"FAIL  duplicate archive member: {name}")
        seen.add(name)
        dest = tree / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        if member.type in (tarfile.REGTYPE, tarfile.AREGTYPE) and name in files:
            with archive.extractfile(member) as src, dest.open("xb") as dst:
                shutil.copyfileobj(src, dst)
            with dest.open("rb") as src:
                digest = hashlib.file_digest(src, "sha256").hexdigest()
            if digest != files[name]:
                sys.exit(f"FAIL  {name}: sha256 {digest}, lock says {files[name]}")
            dest.chmod(member.mode & 0o777)
        elif member.issym() and name in links and member.linkname == links[name]:
            continue  # Create checked links after the last file has been written.
        else:
            sys.exit(f"FAIL  {name}: archive member type, path or link target differs from the lock")
missing = expected - seen
if missing:
    sys.exit(f"FAIL  {min(missing)}: not in the fetched tree")
for name, target in links.items():
    (tree / name).symlink_to(target)
print(len(files))
PYARCH
)"
else
    mapfile -t ENTRIES < "$STAGE/entries"
    FILES="${#ENTRIES[@]}"
    for entry in "${ENTRIES[@]}"; do
        want="${entry%% *}"
        path="${entry#* }"
        dest="$STAGE/tree/$path"
        if [[ "$LAYOUT" == flat ]]; then dest="$STAGE/tree/$(basename "$path")"; fi
        mkdir -p "$(dirname "$dest")"
        curl -fsS --retry 2 -o "$dest" "$BASE_URL/$COMMIT/$path"
        got="$(sha256sum "$dest" | cut -d' ' -f1)"
        if [[ "$got" != "$want" ]]; then
            echo "FAIL  $path: sha256 $got, lock says $want" >&2
            exit 1
        fi
    done
fi

rm -rf "$OUT"
mv -T -- "$STAGE/tree" "$OUT"
echo "ok    fetched $FILES ${LABEL} files @ ${COMMIT} into ${OUT}"
