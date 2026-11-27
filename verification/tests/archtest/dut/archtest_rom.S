// Boot ROM image for the ACT4 architecture tests (issue #49).
//
// The SoC's reset vector is the boot ROM (spec/soc.md § Memory map), and an
// ACT4 test starts at its own entry point in the test RAM. This image is that
// jump and nothing else. scripts/build-archtest.sh assembles it with
// firmware/build-image.sh and writes entry.h first, from TEST_BASE in link.ld:
// RVTEST_BEGIN puts rvtest_entry_point first in .text.init, which link.ld
// places at TEST_BASE, so the ELF entry point is always TEST_BASE.
#include "entry.h"

    .section .text.init
    .globl _start
_start:
    lui   t0, %hi(ARCHTEST_ENTRY)
    addi  t0, t0, %lo(ARCHTEST_ENTRY)
    jr    t0
