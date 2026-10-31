# Print a prompt, then echo every received byte forever. DIV is set to 15
# (16 clocks per bit) only so the simulation is short.
#include "soc.inc"
    VECTORS
_entry:
    li   s0, UART
    li   t1, 15
    sw   t1, UART_DIV(s0)
    la   s1, prompt
1:  lbu  a0, 0(s1)
    beqz a0, _loop
    PUTC a0
    addi s1, s1, 1
    j    1b
_loop:
    lw   t1, UART_STATUS(s0)
    andi t1, t1, 2                    # RX_VALID
    beqz t1, _loop
    lbu  a0, UART_DATA(s0)
    PUTC a0
    j    _loop
_spin:
    j    _spin
    .section .rodata
prompt:
    .asciz "ECHO\n"
