#!/usr/bin/env bash
# Pin and prove the sky130 PDK + open toolchain for this repo.
#
#   scripts/setup-env.sh           fetch sky130A at the pinned open_pdks
#                                  revision into $PDK_ROOT (default ~/.ciel),
#                                  then run --check
#   scripts/setup-env.sh --check        verify PDK revision and tool versions
#                                       against the pins below; exit 1 on mismatch
#   scripts/setup-env.sh --check-act4   verify the ACT4 toolchain of the
#                                       architecture tests, including a zero-time
#                                       cocotb run through ${KLT:-klt}; no PDK needed
#
# This file is the single source of truth for the pins; docs/environment.md
# describes them by variable name and copies no values. It never installs a
# tool: tools are only checked. The PDK fetch runs ciel through a throwaway
# `uvx` environment and writes only into $PDK_ROOT.
set -euo pipefail

# ---- pins -----------------------------------------------------------------
PIN_PDK_FAMILY="sky130"
PIN_PDK_VARIANT="sky130A"
PIN_OPEN_PDKS_REV="f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7"
PIN_CIEL="3.1.0"
PIN_KLT="0.9.2"   # PyPI release: `uvx --from "klayout-tools==${PIN_KLT}"`; CI signoff reads it
PIN_YOSYS="0.67+post"
PIN_YOSYS_SHA="b8e7da6f40ae8f552c116bf6c359b07c6533e159"
PIN_IVERILOG="13.0"
PIN_SV2V="v0.0.13"        # SystemVerilog -> Verilog for CVE2 (record 0001); scripts/convert-cve2.sh
PIN_SV2V_SHA256="552799a1d76cd177b9b4cc63a3e77823a3d2a6eb4ec006569288abeff28e1ff8"  # zachjs/sv2v release asset sv2v-Linux.zip at PIN_SV2V; CI checks it
PIN_RISCV_GCC="14.2.0"    # xPack riscv-none-elf-gcc 14.2.0-3 (boot and SoC firmware, firmware/build-image.sh)
PIN_RISCV_GCC_SHA256="f574415b63f12b09bdd3475223ab492a465d23810646c90c13a4c3b676c83503"  # xpack-riscv-none-elf-gcc-14.2.0-3-linux-x64.tar.gz; recorded provenance for the checked-in firmware/boot/boot_rom.hex and firmware/soc/*.hex, not a checked pin: no script or CI job verifies it
PIN_COCOTB="2.0.1"       # every verification/Makefile target needs it; required here
PIN_OPENROAD="26Q3-1510-g6cb3f2b704"
PIN_OPENROAD_IMAGE="openroad/orfs@sha256:bb7f31697fb8466ab61852fc796376cc16d9df38f762ccb733218b8a5e55824b"
# ---- ACT4 toolchain: the riscv-arch-test suite (scripts/build-archtest.sh) ----
# Checked by `--check-act4` only: these tools are not on every host the rest of
# the pins are, and nothing else in the repo needs them. The two sha256s are
# recorded provenance like PIN_RISCV_GCC_SHA256: digests of the release
# tarballs, equal to the ones the fleet worker spec installs (2AMLogic/2am
# infra/aws/loom-worker/worker.env), re-downloaded and matched 2026-11-26; no
# script verifies them.
PIN_SAIL="0.16"           # riscv/sail-riscv release 0.16: ACT4's reference model, `sail_riscv_sim`
PIN_SAIL_SHA256="f9bb8a32b8f3eddbdf69b3a29d96dff4ba1e77f45877165e0478418367da6bee"  # sail-riscv-Linux-x86_64.tar.gz at PIN_SAIL
PIN_ACT_GCC="16.1.0"      # riscv64-unknown-elf-gcc 16.1.0 from riscv-collab/riscv-gnu-toolchain release 2026.08.27; ACT4 needs GCC 15 or later
PIN_ACT_GCC_SHA256="fe7dadf99dfaee59855b4be5f8d491dc66593bec295090e155a3ec51f0d14f56"  # riscv64-elf-ubuntu-24.04-gcc.tar.xz of that release
PIN_ACT_RUBY="3.4.11"     # ACT4's .mise.toml pins this Ruby
PIN_ACT_UDB="0.1.17 0.1.16 0.1.4 0.1.8"  # udb udb-gen udb_helpers idlc: the gem versions ACT4's Gemfile.lock pins
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
    if [[ $# -gt 0 ]]; then
        if ! got="$(python3 -I "$(dirname "${BASH_SOURCE[0]}")/../verification/tools/klt_cocotb_version.py" "$1")"; then
            fail cocotb "could not read the version from $1 functional-verification"
            return
        fi
    else
        got="$(python3 -c 'import cocotb;print(cocotb.__version__)' 2>/dev/null || true)"
    fi
    if [[ "$got" == "$PIN_COCOTB" ]]; then ok cocotb "$got"
    else fail cocotb "got '${got:-not installed}', pinned ${PIN_COCOTB}"; fi
}

run_check() {
    check_pdk
    check_tool klt "klt ${PIN_KLT}" klt --version
    check_tool yosys "Yosys ${PIN_YOSYS} (git sha1 ${PIN_YOSYS_SHA}" yosys -V
    check_tool sv2v "sv2v ${PIN_SV2V}" sv2v --version
    check_tool riscv-gcc "xPack GNU RISC-V Embedded GCC x86_64) ${PIN_RISCV_GCC}" riscv-none-elf-gcc --version
    check_tool iverilog "version ${PIN_IVERILOG} " iverilog -V
    check_openroad
    check_cocotb
    if [[ "$FAILED" -ne 0 ]]; then echo "environment does not match the pins" >&2; exit 1; fi
    echo "environment matches the pins"
}

# The ACT4 toolchain of the architecture tests (scripts/build-archtest.sh,
# `make -C verification archtest`): Sail, a newer RISC-V GCC and the Ruby gems
# riscv-arch-test drives, beside klt, Icarus and cocotb. `bundle check` against
# riscv-arch-test's own Gemfile.lock runs in scripts/build-archtest.sh, once
# that tree is fetched.
check_udb() {
    local got want
    read -r udb udb_gen helpers idlc <<<"$PIN_ACT_UDB"
    want="udb $udb;udb-gen $udb_gen;udb_helpers $helpers;idlc $idlc;"
    # `require "udb"` loads the gem and the Z3 library it needs (2am#8028).
    got="$(ruby -e 'require "udb"; %w[udb udb-gen udb_helpers idlc].each { |g| puts "#{g} #{Gem::Specification.find_by_name(g).version}" }' 2>&1 | tail -n 4 | tr '\n' ';')" || true
    if [[ "$got" == "$want" ]]; then ok udb "$(printf '%s' "${got%;}" | tr ';' ' ')"
    else fail udb "got '${got:-not installed}', pinned $(printf '%s' "${want%;}" | tr ';' ' ')"; fi
}

check_sail() {
    local got
    if ! command -v sail_riscv_sim >/dev/null 2>&1; then fail sail "'sail_riscv_sim' not on PATH (pinned ${PIN_SAIL})"; return; fi
    got="$(sail_riscv_sim --version 2>&1 | head -n 1)" || true
    if [[ "$got" == "$PIN_SAIL" ]]; then ok sail "sail_riscv_sim $got (the ACT4 reference model)"
    else fail sail "got '${got}', pinned ${PIN_SAIL}"; fi
}

check_act4_lock() {
    local lock
    lock="${ARCHTEST_LOCK:-$(dirname "${BASH_SOURCE[0]}")/../reuse.lock.json}"
    if python3 -I - "$lock" "$PIN_SAIL" "$PIN_SAIL_SHA256" "$PIN_ACT_GCC" "$PIN_ACT_GCC_SHA256" "$PIN_ACT_RUBY" "$PIN_ACT_UDB" <<'PYLOCK'
import json, sys
from pathlib import Path

lock, sail, sail_sha, gcc, gcc_sha, ruby, gem_versions = sys.argv[1:]
gems = dict(zip(("udb", "udb-gen", "udb_helpers", "idlc"), gem_versions.split(), strict=True))
expected = {
    "sail": {"version": sail, "sha256": sail_sha},
    "gcc": {"version": gcc, "sha256": gcc_sha},
    "ruby": {"version": ruby, "gems": gems},
}
sys.exit(0 if json.loads(Path(lock).read_text()).get("act4_toolchain") == expected else 1)
PYLOCK
    then ok act4-lock "$lock matches the ACT4 pins"
    else fail act4-lock "$lock differs from the ACT4 pins"; fi
}

run_check_act4() {
    local klt="${KLT:-klt}" version
    check_act4_lock
    check_sail
    check_tool act-gcc ") ${PIN_ACT_GCC}" riscv64-unknown-elf-gcc --version
    check_tool ruby "ruby ${PIN_ACT_RUBY} " ruby --version
    check_udb
    check_tool uv "uv " uv --version
    if version="$("$klt" --version 2>&1)" && [[ "$version" == "klt $PIN_KLT" ]]; then
        ok klt "$version"
        check_cocotb "$klt"
    else fail klt "$klt reported '$version', expected 'klt $PIN_KLT'"; fi
    check_tool iverilog "version ${PIN_IVERILOG} " iverilog -V
    if [[ "$FAILED" -ne 0 ]]; then echo "environment does not match the ACT4 pins" >&2; exit 1; fi
    echo "environment matches the ACT4 pins"
}

case "${1:-}" in
    --check)      run_check ;;
    --check-act4) run_check_act4 ;;
    "")           fetch_pdk; run_check ;;
    *)            echo "usage: $0 [--check | --check-act4]" >&2; exit 2 ;;
esac
