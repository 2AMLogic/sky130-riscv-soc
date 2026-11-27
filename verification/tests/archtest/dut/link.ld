/* Linker script for ACT4 on the sky130-riscv-soc testbench (issue #49).
 *
 * The tests link into the testbench-only flat RAM behind the fabric: the
 * instruction SRAM of rtl/soc_fabric.sv elaborated 512 KB deep
 * (soc_top.ISRAM_AW = 17) at its ratified base 0x1000_0000. That RAM is not
 * the shipped 8 KB map (spec/soc.md § Memory map); it exists only in this
 * testbench, so ELF addresses are SoC addresses.
 *
 * TEST_BASE leaves the first 16 KB of the RAM unused. The boot ROM image
 * (built by scripts/build-archtest.sh) jumps to TEST_BASE, where RVTEST_BEGIN
 * puts rvtest_entry_point.
 *
 * Everything below "Most users" is riscv-arch-test's own
 * config/cores/cve2/cv32e20/link.ld at the pinned commit, with the three
 * values above changed.
 */
RAM_ORIGIN = 0x10000000;
RAM_LENGTH = 0x80000;
TEST_BASE = 0x10004000;
NUM_HARTS = 1;

/* Most users should not need to modify anything below this line. */
STACK_SIZE = 0x20000;

OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

MEMORY
{
  ram (rwx) : ORIGIN = RAM_ORIGIN, LENGTH = RAM_LENGTH
}

PROVIDE(__stack_size = STACK_SIZE);
PROVIDE(__num_harts = NUM_HARTS);

SECTIONS
{
  ASSERT(TEST_BASE >= ORIGIN(ram) && TEST_BASE < ORIGIN(ram) + LENGTH(ram), "TEST_BASE is outside RAM; update TEST_BASE and RAM_ORIGIN/RAM_LENGTH in link.ld, and the matching memory.regions entry in sail.json")

  .text.init   TEST_BASE : { *(.text.init) } > ram
  .text.rvtest . : { *(.text.rvtest) *(.text.rvtest.*) } > ram

  . = ALIGN(0x4000);
  .rodata . : { *(.rodata) *(.rodata.*) *(.srodata) *(.srodata.*) } > ram
  .data   . : { *(.data) *(.data.*) *(.sdata) *(.sdata.*) } > ram

  . = ALIGN(16);
  .bss . : {
    __bss_start = .;
    *(.sbss) *(.sbss.*) *(.bss) *(.bss.*) *(COMMON)
    . = ALIGN(16);
    __bss_end = .;
  } > ram

  . = ALIGN(16);
  __stack_bottom = .;
  . += __stack_size * __num_harts;
  __stack_top = .;

  . = ALIGN(0x1000);
  .text.rvmodel . : { *(.text.rvmodel) *(.text.rvmodel.*) *(.text) *(.text.*) } > ram

  . = ALIGN(0x1000);
  _end = .;

  ASSERT(_end <= ORIGIN(ram) + LENGTH(ram), "ACT ELF exceeds RAM; increase RAM_LENGTH in link.ld and the matching memory.regions size in sail.json")
}
