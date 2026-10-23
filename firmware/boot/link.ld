/* Boot ROM at 0x0000_0000, 4 KB; the image is the whole ROM. */
MEMORY { ROM (rx) : ORIGIN = 0x00000000, LENGTH = 4K }
SECTIONS
{
  .text : { KEEP(*(.vectors)) *(.text*) } > ROM
  /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
