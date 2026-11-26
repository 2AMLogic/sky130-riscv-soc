#!/usr/bin/env bash
# Fetch the pinned riscv-arch-test (ACT4) tree named in reuse.lock.json and verify it.
#
#   scripts/fetch-arch-test.sh
#
# Downloads the tarball of riscv-non-isa/riscv-arch-test at its pinned commit
# into $ARCHTEST_OUT (default build/archtest/upstream, git-ignored), keeping
# the upstream layout. Every file's sha256 and every symlink's target must match
# the manifest the lock names (reuse.lock.d/riscv-arch-test-<commit>.json, the
# commit's whole tree), and the tree may hold nothing else. Everything is staged
# in a temp dir and only moved into place when all of it verifies, so a failure
# never leaves a partial tree behind. Exit 1 on any mismatch, missing or extra
# file or download failure. The work is done by scripts/fetch-import.sh; this
# file is the riscv-arch-test entry point and supplies only its defaults. The
# tree is fetched whole: ACT4's generators import across the repository.
#
# Overrides: ARCHTEST_LOCK, ARCHTEST_OUT.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/scripts/fetch-import.sh" \
    --import "riscv-non-isa/riscv-arch-test" \
    --lock "${ARCHTEST_LOCK:-$ROOT/reuse.lock.json}" \
    --out "${ARCHTEST_OUT:-$ROOT/build/archtest/upstream}" \
    --base-url "https://raw.githubusercontent.com/riscv-non-isa/riscv-arch-test" \
    --layout tree \
    --label "riscv-arch-test"
