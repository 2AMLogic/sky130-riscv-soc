# Drive four patterns on the GPIO outputs; for each, read OUT back and read IN
# (which the bench loops back from gpio_o) once the synchroniser has settled.
# D-SRAM: [0] SIG at the end, [1+i] IN readback, [5+i] OUT readback, i = 0..3.
#include "soc.inc"
    VECTORS
_entry:
    li   s0, GPIO
    li   s2, DSRAM
    sw   zero, 0(s2)
    li   t1, 0xFF
    sw   t1, GPIO_DIR(s0)
    la   s1, patterns
    li   s3, 0
1:  add  t2, s1, s3
    lbu  t1, 0(t2)
    sw   t1, GPIO_OUT(s0)
    li   t2, 8                        # > 2-flop synchroniser latency
2:  addi t2, t2, -1
    bnez t2, 2b
    slli t3, s3, 2
    add  t3, t3, s2
    lw   t4, GPIO_IN(s0)
    sw   t4, 4(t3)
    lw   t4, GPIO_OUT(s0)
    sw   t4, 20(t3)
    addi s3, s3, 1
    li   t2, 4
    blt  s3, t2, 1b
    li   t1, SIG
    sw   t1, 0(s2)
_spin:
    j    _spin
    .section .rodata
patterns:
    .byte 0xA5, 0x5A, 0xFF, 0x00
