# Boot, then print the banner on the UART at the reset divisor and spin.
#include "soc.inc"
    VECTORS
_entry:
    la   s1, banner
1:  lbu  a0, 0(s1)
    beqz a0, _spin
    PUTC a0
    addi s1, s1, 1
    j    1b
_spin:
    j    _spin
    .section .rodata
banner:
    .asciz "sky130-riscv-soc\n"
