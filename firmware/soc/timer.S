# Machine timer interrupt taken exactly once. mtimecmp = mtime + DELAY, set
# with the hi/lo write order of record 0004. The handler (vector slot 7) records
# the count, mcause and mtime at entry, then parks mtimecmp at all ones. The
# main loop then runs for a window far longer than DELAY and writes SIG.
# D-SRAM: [0] SIG at the end, [1] handler count, [2] mcause, [3] mtime at
# handler entry, [4] mtimecmp programmed, [5] mtime when read for programming.
#include "soc.inc"
    .equ DELAY, 1000                  # mtime cycles
    .equ WINDOW, 3000                 # post-programming loop iterations (>= 2 cycles each)
    VECTORS 7, _timer_isr
_entry:
    li   s0, TIMER
    li   s2, DSRAM
    sw   zero, 0(s2)
    sw   zero, 4(s2)
    sw   zero, 8(s2)
    sw   zero, 12(s2)
    lw   t1, MTIME_LO(s0)
    sw   t1, 20(s2)
    addi t1, t1, DELAY
    sw   t1, 16(s2)
    li   t2, -1
    sw   t2, MTIMECMP_LO(s0)          # record 0004 write order: LO = ones,
    sw   zero, MTIMECMP_HI(s0)        # HI (mtime < 2^32 here), then LO
    sw   t1, MTIMECMP_LO(s0)
    li   t1, 0x80                     # mie.MTIE
    csrw mie, t1
    csrsi mstatus, 8                  # mstatus.MIE
    li   t2, WINDOW
1:  addi t2, t2, -1
    bnez t2, 1b
    li   t1, SIG
    sw   t1, 0(s2)
_spin:
    j    _spin

_timer_isr:
    li   t5, TIMER
    lw   t6, MTIME_LO(t5)
    li   t4, DSRAM
    sw   t6, 12(t4)
    lw   t6, 4(t4)
    addi t6, t6, 1
    sw   t6, 4(t4)
    csrr t6, mcause
    sw   t6, 8(t4)
    li   t6, -1
    sw   t6, MTIMECMP_LO(t5)
    sw   t6, MTIMECMP_HI(t5)
    mret
