#!/usr/bin/env bash
# Build the ACT4 architecture-test images for the sky130-riscv-soc testbench (issue #49).
#
#   scripts/build-archtest.sh
#
# Fetches riscv-arch-test at the commit pinned in reuse.lock.json, generates
# its tests, builds the self-checking ELFs it selects for the SoC configuration
# in verification/tests/archtest/dut/ (the expected results come from the Sail
# reference model of that same configuration), and writes build/archtest/:
#   upstream/      the fetched tree, with ACT4's Python environment and generated tests
#   work/          ACT4's build directory: the ELFs and the Sail signatures
#   images/        each selected test flattened to the bytes the bench loads
#   manifest.json  what verification/tests/archtest/test_archtest.py runs
#   selection.json the selected tests, and for every other candidate why not
#   selection.txt  the same as a listing; it must equal the committed
#                  verification/tests/archtest/selection.txt or the build stops
#   rom/rom.hex    the boot ROM image that jumps to the tests' entry point
# Nothing here is committed; `make -C verification archtest` runs this, then
# the suite through klt. Needs the ACT4 toolchain, which
# scripts/setup-env.sh --check-act4 checks first, and the converted CVE2 core
# (scripts/fetch-cve2.sh and scripts/convert-cve2.sh, run here).
#
# JOBS (default 2) bounds the parallel builds: the suite runs on shared hosts.
# Overrides: ARCHTEST_LOCK, ARCHTEST_OUT (scripts/fetch-arch-test.sh), JOBS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/archtest"
ACT="$BUILD/upstream"
WORK="$BUILD/work"
DUT="$ROOT/verification/tests/archtest/dut"
REQUEST="$ROOT/verification/tests/archtest/fv_request.json"
PREFIX=riscv64-unknown-elf   # the toolchain test_config.yaml names; ACT4 needs GCC 15 or later
JOBS="${JOBS:-2}"

# A bench can only use this output after the entire rebuild succeeds.
rm -f "$BUILD/manifest.json"
"$ROOT/scripts/setup-env.sh" --check-act4

# udb and udb-gen, the Ruby gems ACT4 drives through `bundle exec`, live in the
# Ruby prefix beside `bundle`, and a Ruby prefix puts only ruby and bundle on
# PATH; bundler resolves `bundle exec udb` through PATH, so add that directory.
PATH="$(dirname "$(readlink -f "$(command -v bundle)")"):$PATH"
export PATH

"$ROOT/scripts/fetch-arch-test.sh"
"$ROOT/scripts/fetch-cve2.sh"
"$ROOT/scripts/convert-cve2.sh"

# ACT4 runs `bundle install` into the Ruby prefix when the udb gems do not
# satisfy its Gemfile.lock. Refuse before it can: installing is the host's job.
GEMFILE="$ACT/framework/src/act/data/Gemfile"
if ! BUNDLE_GEMFILE="$GEMFILE" bundle check >/dev/null 2>&1; then
    echo "the udb gems are not installed at the versions $GEMFILE.lock pins (scripts/setup-env.sh --check-act4 names what is missing)" >&2
    exit 1
fi

cd "$ACT"
# ACT4's own environment, from its uv.lock: the act, testgen and covergroupgen
# programs. --frozen never updates the lock, --no-dev leaves out its linters.
UV=(uv run --frozen --no-dev)
uv sync --frozen --no-dev
"${UV[@]}" testgen testplans -o tests --jobs "$JOBS"
"${UV[@]}" act "$DUT/test_config.yaml" --workdir "$WORK" --jobs "$JOBS"
"${UV[@]}" python "$ROOT/verification/tools/archtest_select.py" "$DUT/test_config.yaml" \
    --test-dir tests --workdir "$WORK" > "$BUILD/selection.json"
cd "$ROOT"

# The boot ROM jumps to TEST_BASE (dut/link.ld), where every test's entry point is.
ROM="$BUILD/rom"
rm -rf "$ROM"
mkdir -p "$ROM"
cp "$DUT/archtest_rom.S" "$ROM/"
TEST_BASE="$(sed -n 's/^TEST_BASE = \(0x[0-9A-Fa-f]\+\);.*/\1/p' "$DUT/link.ld")"
[[ -n "$TEST_BASE" ]] || { echo "$DUT/link.ld: no TEST_BASE" >&2; exit 1; }
printf '#define ARCHTEST_ENTRY %s\n' "$TEST_BASE" > "$ROM/entry.h"
RISCV_PREFIX="$PREFIX" "$ROOT/firmware/build-image.sh" "$ROM" archtest_rom.S:rom.hex

python3 -I "$ROOT/verification/tools/archtest_manifest.py" "$BUILD/selection.json" "$WORK" "$BUILD" \
    "$DUT/link.ld" "$REQUEST" "$PREFIX-objcopy" "$ROOT/reuse.lock.json" "$ROOT/verification/tests/archtest/selection.txt"

echo "ok    $(python3 -I -c 'import json, sys; print(len(json.load(open(sys.argv[1]))["tests"]))' "$BUILD/manifest.json") ACT4 test images in $BUILD (manifest.json)"
