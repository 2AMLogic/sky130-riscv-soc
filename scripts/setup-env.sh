#!/usr/bin/env bash
# Pin and prove the sky130 PDK + open toolchain for this repo.
#
#   scripts/setup-env.sh           fetch sky130A at the pinned open_pdks
#                                  revision into $PDK_ROOT (default ~/.ciel),
#                                  then run --check
#   scripts/setup-env.sh --check   verify PDK revision and tool versions
#                                  against the pins below; exit 1 on mismatch
#
# This file is the single source of truth for the pins; docs/environment.md
# quotes it. It never installs a tool: tools are only checked. The PDK fetch
# runs ciel through a throwaway `uvx` environment and writes only into
# $PDK_ROOT.
set -euo pipefail

# ---- pins -----------------------------------------------------------------
PIN_PDK_FAMILY="sky130"
PIN_PDK_VARIANT="sky130A"
PIN_OPEN_PDKS_REV="f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7"
PIN_CIEL="3.1.0"
PIN_KLT="0.7.1.dev2517+g6bb7cf233677"
PIN_KLT_SHA="6bb7cf2336776b9f768fab21c678ee8a2c54e709"   # full commit for `uvx --from git+...@SHA`; CI signoff reads it
PIN_YOSYS="0.67+post"
PIN_YOSYS_SHA="b8e7da6f40ae8f552c116bf6c359b07c6533e159"
PIN_IVERILOG="13.0"
PIN_SV2V="v0.0.13"        # SystemVerilog -> Verilog for CVE2 (record 0001); scripts/convert-cve2.sh
PIN_COCOTB="2.0.1"       # not needed until the harness (#6); optional here
PIN_OPENROAD="26Q3-1510-g6cb3f2b704"
PIN_OPENROAD_IMAGE="openroad/orfs@sha256:bb7f31697fb8466ab61852fc796376cc16d9df38f762ccb733218b8a5e55824b"
# ---------------------------------------------------------------------------

PDK_ROOT="${PDK_ROOT:-$HOME/.ciel}"

fetch_pdk() {
    echo "fetching ${PIN_PDK_VARIANT} @ open_pdks ${PIN_OPEN_PDKS_REV} into ${PDK_ROOT}"
    uvx --from "ciel==${PIN_CIEL}" ciel enable --pdk-family "${PIN_PDK_FAMILY}" \
        --pdk-root "${PDK_ROOT}" "${PIN_OPEN_PDKS_REV}"
}

FAILED=0
ok()   { printf 'ok    %-10s %s\n' "$1" "$2"; }
fail() { printf 'FAIL  %-10s %s\n' "$1" "$2" >&2; FAILED=1; }
warn() { printf 'warn  %-10s %s\n' "$1" "$2"; }

check_pdk() {
    local src="${PDK_ROOT}/${PIN_PDK_VARIANT}/SOURCES" got
    if [[ ! -r "$src" ]]; then
        fail pdk "no ${src}; run scripts/setup-env.sh (PDK_ROOT=${PDK_ROOT})"
        return
    fi
    got="$(awk '/^open_pdks/ {print $2; exit}' "$src")"
    if [[ "$got" == "$PIN_OPEN_PDKS_REV" ]]; then ok pdk "${PIN_PDK_VARIANT} open_pdks ${got}"
    else fail pdk "open_pdks ${got:-unknown}, pinned ${PIN_OPEN_PDKS_REV}"; fi
}

# check_tool NAME EXPECT CMD... : run the version probe, expect EXPECT in line 1
check_tool() {
    local name="$1" expect="$2"; shift 2
    local out
    if ! command -v "$1" >/dev/null 2>&1; then fail "$name" "'$1' not on PATH (pinned ${expect})"; return; fi
    out="$("$@" 2>&1 | head -n 1)" || true
    if [[ "$out" == *"$expect"* ]]; then ok "$name" "$out"
    else fail "$name" "got '${out}', pinned '${expect}'"; fi
}

check_openroad() {
    local wrapper out
    if ! wrapper="$(command -v openroad 2>/dev/null)"; then fail openroad "not on PATH (pinned ${PIN_OPENROAD})"; return; fi
    # The binary may be a docker wrapper that records its image digest.
    if grep -q "openroad/orfs@sha256" "$wrapper" 2>/dev/null \
        && ! grep -q "${PIN_OPENROAD_IMAGE}" "$wrapper"; then
        fail openroad "wrapper ${wrapper} does not use pinned image ${PIN_OPENROAD_IMAGE}"; return
    fi
    out="$(openroad -version 2>&1 | head -n 1)" || true
    if [[ "$out" == *"$PIN_OPENROAD"* ]]; then ok openroad "$out"
    else
        # Not runnable here (e.g. no docker access): not a version mismatch,
        # so warn; the smoke record must then mark place-and-route "not run".
        warn openroad "cannot report a version here (${out:-no output}); pinned ${PIN_OPENROAD}"
    fi
}

check_cocotb() {
    local got
    got="$(python3 -c 'import cocotb;print(cocotb.__version__)' 2>/dev/null || true)"
    if [[ -z "$got" ]]; then warn cocotb "not installed (pinned ${PIN_COCOTB}; needed from #6)"
    elif [[ "$got" == "$PIN_COCOTB" ]]; then ok cocotb "$got"
    else fail cocotb "got ${got}, pinned ${PIN_COCOTB}"; fi
}

run_check() {
    check_pdk
    check_tool klt "$PIN_KLT" klt --version
    check_tool yosys "Yosys ${PIN_YOSYS} (git sha1 ${PIN_YOSYS_SHA}" yosys -V
    check_tool sv2v "sv2v ${PIN_SV2V}" sv2v --version
    check_tool iverilog "version ${PIN_IVERILOG} " iverilog -V
    check_openroad
    check_cocotb
    if [[ "$FAILED" -ne 0 ]]; then echo "environment does not match the pins" >&2; exit 1; fi
    echo "environment matches the pins"
}

case "${1:-}" in
    --check) run_check ;;
    "")      fetch_pdk; run_check ;;
    *)       echo "usage: $0 [--check]" >&2; exit 2 ;;
esac
