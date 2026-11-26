// rvmodel_macros.h
// SPDX-License-Identifier: Apache-2.0
// RVMODEL macro definitions for the sky130-riscv-soc testbench (rtl/soc_top.sv,
// issue #49): how an ACT4 test talks to the SoC it runs on.
//
// Shape and wording follow riscv-arch-test's own
// config/cores/cve2/cv32e20/rvmodel_macros.h at the pinned commit. The values
// are the SoC's (spec/soc.md § Memory map):
//   - the test halts by writing its result to the first two words of the
//     data SRAM (0x2000_0000), the result block the boot firmware uses too;
//     the cocotb bench (verification/tests/archtest/test_archtest.py) watches
//     that block. ACT4's self-check calls rvmodel_halt_pass or rvmodel_halt_fail.
//   - the console is the SoC UART (0x4000_0000), decoded by the bench.
//   - the machine timer is the SoC timer (0x4000_2000).
//   - machine external and software interrupts have no source in the SoC
//     (rtl/soc_top.sv ties irq_external_i and irq_software_i to 0), so their
//     RVMODEL_SET/CLR macros are not defined and the UDB config
//     (sky130-riscv-soc.yaml) declares them unimplemented.
// This header is included by the signature (Sail reference) build too, but
// tests/env/sail_macros.h then overrides every macro below except
// RVMODEL_ACCESS_FAULT_ADDRESS, which is deliberately left undefined here as
// in the upstream CV32E20 header.
#ifndef _RVMODEL_MACROS_H
#define _RVMODEL_MACROS_H

#define RVMODEL_DATA_SECTION

#define STANDARD_SM_SUPPORTED

// SoC addresses (spec/soc.md § Memory map, records 0004 and 0005).
#define SOC_DSRAM_BASE      0x20000000
#define SOC_UART_BASE       0x40000000
#define SOC_TIMER_BASE      0x40002000
// First two words of the data SRAM: [0] the halt code, [1] zero.
#define RVMODEL_HALT_ADDRESS SOC_DSRAM_BASE

##### STARTUP #####

// Perform boot operations. Can be empty or left undefined unless needed for
// DUT-specific behavior such as turning on a memory controller or
// initializing custom state.
//#define RVMODEL_BOOT

// Custom RVMODEL_BOOT_TO_MMODE overrides default RVTEST_BOOT_TO_MMODE
// if defined.  For most DUTs, the default should work and this macro
// should not be defined.  If the DUT has no standard M-mode CSRs, do not
// define STANDARD_SM_SUPPORTED.  If a nonconforming
// M-mode is implemented, define this macro to set up the necessary
// state in a fashion similar to RVTEST_BOOT_TO_MMODE.
//#define RVMODEL_BOOT_TO_MMODE

// Address to use for load/store fault tests that should cause an access fault on the DUT.
// Left undefined, as in the upstream CV32E20 header.
//#define RVMODEL_ACCESS_FAULT_ADDRESS 0x00000000

##### TERMINATION #####

// Terminate test with a pass indication.
// When the test is run in simulation, this should end the simulation.
#define RVMODEL_HALT_PASS  \
  li x1, 123456789        ;\
  li t0, RVMODEL_HALT_ADDRESS ;\
  write_halt_pass:        ;\
    sw x1, 0(t0)          ;\
    sw x0, 4(t0)          ;\
  self_loop_pass:         ;\
    j self_loop_pass      ;\

// Terminate test with a fail indication.
// When the test is run in simulation, this should end the simulation.
#define RVMODEL_HALT_FAIL \
  li x1, 1                ;\
  li t0, RVMODEL_HALT_ADDRESS ;\
  write_halt_fail:        ;\
    sw x1, 0(t0)          ;\
    sw x0, 4(t0)          ;\
  self_loop_fail:         ;\
    j self_loop_fail      ;\

##### IO #####

// Initialization steps needed prior to writing to the console
// _R1, _R2, and _R3 can be used as temporary registers if needed.
// Do not modify any other registers (or make sure to restore them).
// Can be empty or left undefined if no initialization is needed.
// UART DIV (record 0005): the bit period is DIV + 1 clocks. 3 gives 4 clocks
// per bit, 40 clocks per character; the reset divisor of 433 would cost 4340.
#define RVMODEL_IO_INIT(_R1, _R2, _R3) \
  li   _R1, SOC_UART_BASE + 0x0C ;\
  li   _R2, 3                    ;\
  sw   _R2, 0(_R1)               ;\

// Prints a null-terminated string using a DUT specific mechanism.
// A pointer to the string is passed in _STR_PTR.
// _R1, _R2, and _R3 can be used as temporary registers if needed.
// Do not modify any other registers (or make sure to restore them).
// STATUS (0x04) bit 0 is TX_BUSY: a DATA write while it is set is dropped
// (record 0005), so wait for it to clear before each byte.
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR) \
1:                           ;                        \
  lbu  _R1, 0(_STR_PTR)      ; /* Load byte */        \
  beqz _R1, 3f               ; /* Exit if null */     \
2:                           ;                        \
  li   _R2, SOC_UART_BASE + 0x04 ; /* UART STATUS */   \
  lw   _R3, 0(_R2)           ;                        \
  andi _R3, _R3, 1           ; /* TX_BUSY */          \
  bnez _R3, 2b               ; /* holding register full */ \
  li   _R2, SOC_UART_BASE        ; /* UART DATA */     \
  sw   _R1, 0(_R2)           ;                        \
  addi _STR_PTR, _STR_PTR, 1 ; /* Next char */        \
  j 1b                       ; /* Loop */             \
3:

##### MTVEC Alignment #####

##### Interrupt Latency #####

#define RVMODEL_INTERRUPT_LATENCY 10

##### Machine Timer #####
#define RVMODEL_MAX_CYCLES_PER_TIMER_TICK 1

#define RVMODEL_TIMER_INT_SOON_DELAY 10000

// SoC machine timer (rtl/timer.sv): mtime low word at the timer base, mtimecmp
// low word 8 bytes above it.
#define RVMODEL_MTIME_ADDRESS     SOC_TIMER_BASE
#define RVMODEL_MTIMECMP_ADDRESS  (SOC_TIMER_BASE + 0x8)

##### Machine Interrupts #####

// No machine external or software interrupt source exists in the SoC:
// RVMODEL_SET/CLR_MEXT_INT and RVMODEL_SET/CLR_MSW_INT are not defined.

#endif // _RVMODEL_MACROS_H
