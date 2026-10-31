# Shared definitions for the SoC firmware tests (issue #48). Register offsets
# and semantics are from spec/decision-records/0004 (GPIO, timer) and 0005 (UART).
    .equ DSRAM,   0x20000000
    .equ UART,    0x40000000
    .equ GPIO,    0x40001000
    .equ TIMER,   0x40002000

    .equ UART_DATA,   0x00
    .equ UART_STATUS, 0x04            # bit0 TX_BUSY, bit1 RX_VALID
    .equ UART_DIV,    0x0C
    .equ GPIO_OUT,    0x00
    .equ GPIO_DIR,    0x04
    .equ GPIO_IN,     0x08
    .equ MTIME_LO,    0x00
    .equ MTIME_HI,    0x04
    .equ MTIMECMP_LO, 0x08
    .equ MTIMECMP_HI, 0x0C

    .equ SIG, 0x600DC0DE              # D-SRAM word 0 once a run reaches its end

# Vector table at ROM offset 0: slot 0 is reset and every exception, slot n an
# interrupt of cause n (CVE2 vectored mode, mtvec base 0). \irq_slot is the
# slot given a handler; every other slot, and any exception after reset, spins.
    .macro VECTORS irq_slot=-1, handler=_spin
    .section .vectors, "ax"
    .option norvc
    .global _vectors
_vectors:
    .set n, 0
    .rept 32
    .if n == 0
    j _entry
    .elseif n == \irq_slot
    j \handler
    .else
    j _spin
    .endif
    .set n, n + 1
    .endr
    .section .text
    .endm

# PUTC reg: wait for TX_BUSY to clear, then queue the byte in reg. Clobbers t0, t1.
    .macro PUTC reg
    li   t0, UART
9:  lw   t1, UART_STATUS(t0)
    andi t1, t1, 1
    bnez t1, 9b
    sw   \reg, UART_DATA(t0)
    .endm
