#!/usr/bin/env bash
# Report tests for the ACT4 pins, selected klt executable and check_cocotb in scripts/setup-env.sh: a cocotb that python3
# cannot import must be reported FAIL, not warn, now that every verification
# target needs it. Only the cocotb probe is stubbed for --check; no other check
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
    else echo "FAIL  $1"; cat "$W/log"; FAILS=1; fi
}

stub 'exit 1'          # import cocotb raises: not installed
run; expect_line "absent cocotb reports FAIL" "^FAIL +cocotb"

stub "echo $PIN"       # installed at the pin
run; expect_line "pinned cocotb reports ok" "^ok +cocotb +${PIN_RE}\$"

stub 'echo 0.0.0'      # installed at the wrong version
run; expect_line "mismatched cocotb reports FAIL" "^FAIL +cocotb"

# Exercise --check-act4 with a private copy so lock drift never edits the checkout.
mkdir -p "$W/scripts" "$W/verification/tools"
cp "$ROOT/verification/tools/klt_cocotb_version.py" "$W/verification/tools/"
cp "$ROOT/scripts/setup-env.sh" "$W/scripts/"
cp "$ROOT/reuse.lock.json" "$W/"
rm "$W/bin/python3"  # use the real interpreter for the JSON lock check
klt_pin="$(sed -n 's/^PIN_KLT="\([^"]*\)".*/\1/p' "$W/scripts/setup-env.sh")"
# Model two independent klt installs without network or host packages.
python3 -m venv --without-pip "$W/with" "$W/without" || exit 1
site="$("$W/with/bin/python" -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
printf '__version__ = "%s"\n' "$PIN" > "$site/cocotb.py"
for venv in "$W/with" "$W/without"; do
    cat > "$venv/bin/klt" <<PYKLT
#!$venv/bin/python
import json, sys
if sys.argv[1:] == ["--version"]:
    print("klt $klt_pin")
elif sys.argv[1] == "functional-verification":
    import cocotb
    print(json.dumps({"environment": {"cocotb_version": cocotb.__version__}}))
else:
    sys.exit(2)
PYKLT
    chmod +x "$venv/bin/klt"
done
printf '#!/bin/sh\necho "klt %s.dev1"\n' "$klt_pin" > "$W/bin/development-klt"
chmod +x "$W/bin/development-klt"
run_act4() { PYTHONDONTWRITEBYTECODE=1 PATH="$W/$1/bin:$PATH" KLT="$2" "$W/scripts/setup-env.sh" --check-act4 >"$W/log" 2>&1; }

run_act4 with "$W/bin/development-klt"
expect_line "ACT4 rejects the selected development klt" '^FAIL +klt '
expect_line "ACT4 lock agrees with setup pins" '^ok +act4-lock '
run_act4 with "$W/without/bin/klt"
expect_line "PATH cocotb cannot satisfy a klt missing cocotb" '^FAIL +cocotb '
run_act4 without "$W/with/bin/klt"
expect_line "ACT4 accepts the exact klt release" '^ok +klt '
expect_line "klt supplies cocotb even when PATH lacks it" "^ok +cocotb +${PIN_RE}\$"
printf '__version__ = "0.0.0"\n' > "$site/cocotb.py"
run_act4 without "$W/with/bin/klt"
expect_line "ACT4 rejects the runner's wrong cocotb version" "^FAIL +cocotb .*0\.0\.0"

cp "$W/reuse.lock.json" "$W/alternate.lock.json"
python3 -I - "$W/alternate.lock.json" <<'PYLOCK'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
lock = json.loads(path.read_text())
lock["act4_toolchain"]["ruby"]["gems"]["idlc"] = "fixture-drift"
path.write_text(json.dumps(lock))
PYLOCK
ARCHTEST_LOCK="$W/alternate.lock.json" run_act4 without "$W/with/bin/klt"
expect_line "ACT4 checks the selected lock for toolchain drift" '^FAIL +act4-lock '

exit "$FAILS"
