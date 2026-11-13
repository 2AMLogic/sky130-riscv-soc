#!/usr/bin/env bash
# Exit-code tests for the pinned-import fetcher against a local file:// upstream.
#
# The fetcher is scripts/fetch-import.sh, reached through both of its entry
# points: scripts/fetch-cve2.sh (tree layout) and scripts/fetch-sram-macro.sh
# (flat layout, one file per basename). Each entry point gets the same three
# cases — clean fetch, sha256 mismatch, missing file — plus an assertion that
# it produced its own layout and not the other one. No network: the lock,
# output directory and base URL are overridden to a fixture tree.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
FAILS=0

CC=0123456789abcdef0123456789abcdef01234567   # openhwgroup/cve2 fixture commit
CS=89abcdef0123456789abcdef0123456789abcdef   # efabless/sky130_sram_macros fixture commit

mkdir -p "$W/up/$CC/rtl" "$W/up/$CS/views"
printf 'module a; endmodule\n' > "$W/up/$CC/rtl/a.sv"
printf 'module b; endmodule\n' > "$W/up/$CC/rtl/b.sv"
printf 'VERSION 5.7 ;\n'       > "$W/up/$CS/views/sram.lef"
printf 'library (sram) { }\n'  > "$W/up/$CS/views/sram.lib"
sha() { sha256sum "$1" | cut -d' ' -f1; }
cat > "$W/lock.json" <<JSON
{"schema":1,"imports":[
 {"from":"openhwgroup/cve2","commit":"$CC","mode":"fetched","files":[
  {"upstream":"rtl/a.sv","sha256":"$(sha "$W/up/$CC/rtl/a.sv")"},
  {"upstream":"rtl/b.sv","sha256":"$(sha "$W/up/$CC/rtl/b.sv")"}]},
 {"from":"efabless/sky130_sram_macros","commit":"$CS","mode":"fetched","files":[
  {"upstream":"views/sram.lef","sha256":"$(sha "$W/up/$CS/views/sram.lef")"},
  {"upstream":"views/sram.lib","sha256":"$(sha "$W/up/$CS/views/sram.lib")"}]}]}
JSON

run() { # run <entry>; both entry points write to the same $W/out, one at a time
    case "$1" in
        cve2) CVE2_LOCK="$W/lock.json" CVE2_OUT="$W/out" CVE2_BASE_URL="file://$W/up" \
              "$ROOT/scripts/fetch-cve2.sh" >"$W/log" 2>&1 ;;
        sram) SRAM_LOCK="$W/lock.json" SRAM_OUT="$W/out" SRAM_BASE_URL="file://$W/up" \
              "$ROOT/scripts/fetch-sram-macro.sh" >"$W/log" 2>&1 ;;
    esac
}

expect() { # name want_rc got_rc
    if [[ "$2" == zero && "$3" -eq 0 ]] || [[ "$2" == nonzero && "$3" -ne 0 ]]; then echo "ok    $1"
    else echo "FAIL  $1 (rc=$3, wanted $2)"; cat "$W/log"; FAILS=1; fi
}
check() { # name condition-already-evaluated
    [[ "$2" == 0 ]] || { echo "FAIL  $1"; FAILS=1; }
}

for entry in cve2 sram; do
    case "$entry" in
        cve2) victim="$W/up/$CC/rtl/b.sv"; kept="$W/out/rtl/b.sv"; other="$W/out/b.sv" ;;
        sram) victim="$W/up/$CS/views/sram.lef"; kept="$W/out/sram.lef"; other="$W/out/views" ;;
    esac

    rm -rf "$W/out"
    run "$entry"; expect "$entry: clean fetch exits 0" zero $?
    [[ -f "$kept" ]]; check "$entry: clean fetch left no $kept" $?
    [[ ! -e "$other" ]]; check "$entry: clean fetch wrote the other layout ($other)" $?

    cp "$victim" "$W/victim.orig"
    printf 'drift\n' >> "$victim"
    rm -rf "$W/out"
    run "$entry"; expect "$entry: sha256 mismatch exits non-zero" nonzero $?
    [[ ! -e "$W/out" ]]; check "$entry: mismatch left a partial tree" $?

    cp "$W/victim.orig" "$victim"
    rm "$victim"
    rm -rf "$W/out"
    run "$entry"; expect "$entry: missing file exits non-zero" nonzero $?
    [[ ! -e "$W/out" ]]; check "$entry: missing file left a partial tree" $?
    cp "$W/victim.orig" "$victim"
done

exit "$FAILS"
