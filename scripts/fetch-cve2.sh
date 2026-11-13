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
# download failure. The work is done by scripts/fetch-import.sh; this file is
# the CVE2 entry point and supplies only its defaults.
#
# Overrides (used by the shell test): CVE2_LOCK, CVE2_OUT, CVE2_BASE_URL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/scripts/fetch-import.sh" \
    --import "openhwgroup/cve2" \
    --lock "${CVE2_LOCK:-$ROOT/reuse.lock.json}" \
    --out "${CVE2_OUT:-$ROOT/build/cve2/upstream}" \
    --base-url "${CVE2_BASE_URL:-https://raw.githubusercontent.com/openhwgroup/cve2}" \
    --layout tree \
    --label "CVE2"
