#!/usr/bin/env bash
# Exit-code test for verification/tools/lint_rtl.sh: an rtl/ tree with no
# .v/.sv files must fail rather than report ok, so a moved or mis-globbed
# rtl/ cannot turn the lint job green without linting anything.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
FAILS=0

# lint_rtl.sh resolves the repo root from its own path, so a scratch copy with
# an empty rtl/ exercises the zero-file branch without touching the real tree.
mkdir -p "$W/verification/tools" "$W/rtl"
cp "$ROOT/verification/tools/lint_rtl.sh" "$W/verification/tools/lint_rtl.sh"

"$W/verification/tools/lint_rtl.sh" >"$W/log" 2>&1
rc=$?
if [[ "$rc" -ne 0 ]]; then echo "ok    empty rtl/ exits non-zero"
else echo "FAIL  empty rtl/ exited 0 (vacuous pass)"; cat "$W/log"; FAILS=1; fi

if grep -q 'no RTL files' "$W/log"; then echo "ok    empty rtl/ names what was missing"
else echo "FAIL  empty rtl/ printed no message naming the empty tree"; cat "$W/log"; FAILS=1; fi

exit "$FAILS"
