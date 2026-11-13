#!/usr/bin/env bash
# Report tests for check_cocotb in scripts/setup-env.sh: a cocotb that python3
# cannot import must be reported FAIL, not warn, now that every verification
# target needs it. Only the cocotb probe is stubbed; no other check in --check
# prints a cocotb line, so the host's own tool versions do not affect these.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
FAILS=0

PIN="$(sed -n 's/^PIN_COCOTB="\([^"]*\)".*/\1/p' "$ROOT/scripts/setup-env.sh")"
if [[ -z "$PIN" ]]; then echo "FAIL  no PIN_COCOTB in scripts/setup-env.sh"; exit 1; fi
PIN_RE="${PIN//./\\.}"

mkdir -p "$W/bin"
stub() { printf '%s\n%s\n' '#!/bin/sh' "$1" > "$W/bin/python3"; chmod +x "$W/bin/python3"; }

# PDK_ROOT points at nothing so check_pdk fails fast instead of reading a host PDK.
run() { PATH="$W/bin:$PATH" PDK_ROOT="$W/no-pdk" "$ROOT/scripts/setup-env.sh" --check >"$W/log" 2>&1; }

expect_line() { # name regex
    if grep -qE "$2" "$W/log"; then echo "ok    $1"
    else echo "FAIL  $1"; grep -i cocotb "$W/log" || cat "$W/log"; FAILS=1; fi
}

stub 'exit 1'          # import cocotb raises: not installed
run; expect_line "absent cocotb reports FAIL" "^FAIL +cocotb"

stub "echo $PIN"       # installed at the pin
run; expect_line "pinned cocotb reports ok" "^ok +cocotb +${PIN_RE}\$"

stub 'echo 0.0.0'      # installed at the wrong version
run; expect_line "mismatched cocotb reports FAIL" "^FAIL +cocotb"

exit "$FAILS"
