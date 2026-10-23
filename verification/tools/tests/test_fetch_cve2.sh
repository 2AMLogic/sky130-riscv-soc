#!/usr/bin/env bash
# Exit-code tests for scripts/fetch-cve2.sh against a local file:// upstream.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
FAILS=0

C=0123456789abcdef0123456789abcdef01234567
mkdir -p "$W/up/$C/rtl"
printf 'module a; endmodule\n' > "$W/up/$C/rtl/a.sv"
printf 'module b; endmodule\n' > "$W/up/$C/rtl/b.sv"
SA="$(sha256sum "$W/up/$C/rtl/a.sv" | cut -d' ' -f1)"
SB="$(sha256sum "$W/up/$C/rtl/b.sv" | cut -d' ' -f1)"
cat > "$W/lock.json" <<JSON
{"schema":1,"imports":[{"from":"openhwgroup/cve2","commit":"$C","mode":"fetched","files":[
 {"upstream":"rtl/a.sv","sha256":"$SA"},{"upstream":"rtl/b.sv","sha256":"$SB"}]}]}
JSON

run() { CVE2_LOCK="$W/lock.json" CVE2_OUT="$W/out" CVE2_BASE_URL="file://$W/up" \
        "$ROOT/scripts/fetch-cve2.sh" >"$W/log" 2>&1; }
expect() { # name want_rc got_rc
    if [[ "$2" == zero && "$3" -eq 0 ]] || [[ "$2" == nonzero && "$3" -ne 0 ]]; then echo "ok    $1"
    else echo "FAIL  $1 (rc=$3, wanted $2)"; cat "$W/log"; FAILS=1; fi
}

run; expect "clean fetch exits 0" zero $?
[[ -f "$W/out/rtl/b.sv" ]] || { echo "FAIL  clean fetch left no files"; FAILS=1; }

rm -rf "$W/out"; cp "$W/up/$C/rtl/b.sv" "$W/b.orig"
printf 'module b; wire x; endmodule\n' > "$W/up/$C/rtl/b.sv"
run; expect "sha256 mismatch exits non-zero" nonzero $?
[[ ! -e "$W/out" ]] || { echo "FAIL  mismatch left a partial tree"; FAILS=1; }

cp "$W/b.orig" "$W/up/$C/rtl/b.sv"; rm "$W/up/$C/rtl/b.sv"
run; expect "missing file exits non-zero" nonzero $?
[[ ! -e "$W/out" ]] || { echo "FAIL  missing file left a partial tree"; FAILS=1; }

exit "$FAILS"
