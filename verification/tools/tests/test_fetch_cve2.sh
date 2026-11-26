#!/usr/bin/env bash
# Exit-code tests for the pinned-import fetcher against a local file:// upstream.
#
# The fetcher is scripts/fetch-import.sh, reached through its three entry
# points: scripts/fetch-cve2.sh (tree layout, one file per download),
# scripts/fetch-sram-macro.sh (flat layout, one file per basename) and
# scripts/fetch-arch-test.sh (tree layout, one archive for the whole commit,
# verified against a manifest). Each entry point gets the same three cases —
# clean fetch, sha256 mismatch, missing file — and the archive form three more
# that only a whole tree has: a file the manifest does not list, a symlink to
# the wrong target, and a manifest for another commit. Each entry point also
# asserts that it produced its own layout and not another one. No network: the
# lock, output directory and base URL are overridden to a fixture tree.
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

# ---- scripts/fetch-arch-test.sh: the whole commit as one archive -------------
# The fixture is a tarball with one top-level directory, like the one GitHub
# serves for a commit, and a manifest beside the lock that lists every file and
# symlink in it.

AC=00112233445566778899aabbccddeeff00112233   # riscv-non-isa/riscv-arch-test fixture commit
TREE="$W/act/riscv-arch-test-$AC"              # $TREE is stripped off by --strip-components=1
mkdir -p "$TREE/rtl"
printf 'module a; endmodule\n' > "$TREE/rtl/a.sv"
printf 'module b; endmodule\n' > "$TREE/rtl/b.sv"
ln -s rtl/b.sv "$TREE/link.ld"

pack() { tar -czf "$W/act.tgz" -C "$W/act" "riscv-arch-test-$AC"; }   # repack the fixture as it is now
manifest() {
    python3 -I - "$W" "$AC" "$1" > "$W/act_manifest.json" <<'JSON'
import hashlib, json, os, sys
tree = os.path.join(sys.argv[1], "act", "riscv-arch-test-" + sys.argv[2])
files, symlinks = {}, {}
for root, _, names in os.walk(tree):
    for name in names:
        path = os.path.join(root, name)
        rel = os.path.relpath(path, tree)
        if os.path.islink(path):
            symlinks[rel] = os.readlink(path)
        else:
            files[rel] = hashlib.sha256(open(path, "rb").read()).hexdigest()
print(json.dumps({"from": "riscv-non-isa/riscv-arch-test", "commit": sys.argv[3],
                  "files": files, "symlinks": symlinks}))
JSON
}
cat > "$W/act_lock.json" <<JSON
{"schema":1,"imports":[
 {"from":"riscv-non-isa/riscv-arch-test","commit":"$AC","mode":"fetched",
  "archive":"file://$W/act.tgz","manifest":"act_manifest.json"}]}
JSON
run_arch() { ARCHTEST_LOCK="$W/act_lock.json" ARCHTEST_OUT="$W/out" "$ROOT/scripts/fetch-arch-test.sh" >"$W/log" 2>&1; }

pack; manifest "$AC"
rm -rf "$W/out"
run_arch; expect "archtest: clean archive fetch exits 0" zero $?
[[ -f "$W/out/rtl/a.sv" && -L "$W/out/link.ld" && "$(readlink "$W/out/link.ld")" == rtl/b.sv ]]
check "archtest: clean fetch left the files and the symlink" $?

pack; manifest "$AC"
printf 'drift\n' >> "$TREE/rtl/b.sv"; pack
rm -rf "$W/out"
run_arch; expect "archtest: sha256 mismatch exits non-zero" nonzero $?
[[ ! -e "$W/out" ]]; check "archtest: mismatch left a partial tree" $?

sed -i '$d' "$TREE/rtl/b.sv"; rm "$TREE/rtl/b.sv"; pack
rm -rf "$W/out"
run_arch; expect "archtest: file missing from the archive exits non-zero" nonzero $?
[[ ! -e "$W/out" ]]; check "archtest: missing file left a partial tree" $?

printf 'module b; endmodule\n' > "$TREE/rtl/b.sv"; printf 'module c; endmodule\n' > "$TREE/rtl/c.sv"; pack
rm -rf "$W/out"
run_arch; expect "archtest: file absent from the manifest exits non-zero" nonzero $?
[[ ! -e "$W/out" ]]; check "archtest: unlisted file left a partial tree" $?

rm "$TREE/rtl/c.sv"; rm "$TREE/link.ld"; ln -s rtl/a.sv "$TREE/link.ld"; pack
rm -rf "$W/out"
run_arch; expect "archtest: symlink to the wrong target exits non-zero" nonzero $?
[[ ! -e "$W/out" ]]; check "archtest: wrong symlink left a partial tree" $?

rm "$TREE/link.ld"; ln -s rtl/b.sv "$TREE/link.ld"; pack; manifest deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
rm -rf "$W/out"
run_arch; expect "archtest: manifest for another commit exits non-zero" nonzero $?
[[ ! -e "$W/out" ]]; check "archtest: foreign manifest left a partial tree" $?
grep -q "describes riscv-non-isa/riscv-arch-test@deadbeef" "$W/log"; check "archtest: the foreign manifest is named in the error" $?

exit "$FAILS"
