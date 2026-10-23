# Boot ROM firmware for the RTL boot test (issue #22). Assembly only, no stack.
#
# CVE2 fetches its reset PC from boot_addr_i (0x0) and sets mtvec to
# {boot_addr_i[31:8], 6'b0, 2'b01} (vectored, base 0). Synchronous exceptions
# enter at base+0 = 0x0 (the reset entry); interrupt n enters at base+4*n. So
# offset 0 is shared by reset and every exception, and `_entry` tells them
# apart by mcause (0 after reset; non-zero after a trap, because
# misaligned-instruction, cause 0, cannot occur with the C extension).
#
# D-SRAM result block (word offsets from 0x2000_0000), read by the cocotb test:
#   0x00 signature   0x600DC0DE once the run reaches the end
#   0x04 mtvec       readback of the CSR at reset
#   0x08 trap count  number of traps taken this run
#   0x0C mcause      cause of the last trap
#   0x10 mepc        PC of the last trapping instruction
#   0x14 mtval       mtval of the last trap
#   0x18 resume      0xD00DFEED, written after both unmapped reads returned
#   0x1C boots       counts boots; survives a reset (D-SRAM is not reset)
    .equ DSRAM,   0x20000000
    .equ UNMAP_A, 0x40003000          # unused page of the peripheral window
    .equ UNMAP_B, 0x30000000          # outside every region

    .section .vectors, "ax"
    .option norvc
    .global _vectors
_vectors:
    j _entry                          # 0x00: reset and all exceptions
    .rept 31                          # 0x04..0x7C: interrupt vectors, none enabled
    j _spin
    .endr

    .section .text
_entry:
    csrr t0, mcause
    bnez t0, _trap
    # ---- reset path ----
    li   s0, DSRAM
    csrr t1, mtvec
    sw   t1, 0x04(s0)
    sw   zero, 0x08(s0)
    lw   t1, 0x1C(s0)
    addi t1, t1, 1
    sw   t1, 0x1C(s0)
    sw   zero, 0x18(s0)
    li   t1, 0x600DC0DE
    sw   t1, 0x00(s0)
    li   a0, UNMAP_A
    lw   a1, 0(a0)                    # OBI error -> load access fault -> _trap
    li   a0, UNMAP_B
    lw   a1, 0(a0)                    # second fault, different region
    li   t1, 0xD00DFEED
    sw   t1, 0x18(s0)
_spin:
    j    _spin

    # mepc points at the faulting 4-byte lw (norvc): step over it and resume.
_trap:
    li   t1, DSRAM
    lw   t2, 0x08(t1)
    addi t2, t2, 1
    sw   t2, 0x08(t1)
    csrr t2, mcause
    sw   t2, 0x0C(t1)
    csrr t2, mepc
    sw   t2, 0x10(t1)
    csrr t0, mtval
    sw   t0, 0x14(t1)
    addi t2, t2, 4
    csrw mepc, t2
    mret
