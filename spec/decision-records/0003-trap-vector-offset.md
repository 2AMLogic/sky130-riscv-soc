# 0003 — Trap-vector offset resolved by the first RTL boot test

- **Status**: accepted (2026-10-23), issue #22
- **Supersedes**: none (resolves the "unverified" notes in `spec/soc.md`)
- **Superseded by**: none
- **Spec rows**: `spec/soc.md` § Memory map (reset vector), § Deferrals

## Context

`spec/soc.md` fixed `boot_addr_i = 0x0000_0000` as the reset vector and left
the trap-vector offset from `boot_addr_i` *unverified*, to be "settled by the
first RTL boot test". CVE2 is used unmodified at the pinned commit
`d7f21568028a1114be663599bd42145dccf28928` (converted by sv2v v0.0.13).

## Source reading

- `rtl/cve2_cs_registers.sv:520`: on boot, `mtvec = {boot_addr_i[31:8], 6'b0, 2'b01}`
  (vectored mode, 256-byte-aligned base).
- `rtl/cve2_if_stage.sv:126-127`: exceptions enter at `{mtvec[31:8], 8'h00}`;
  interrupt `n` enters at `{mtvec[31:8], n[5:0], 2'b00}` (base + 4n).
- `rtl/cve2_if_stage.sv:140`: reset fetches from `{boot_addr_i[31:2], 2'b00}`.
  There is no Ibex-style `+0x80` reset offset.

## Observed (RTL boot test)

`make -C verification boot`, Icarus 13.0 on the sv2v output, firmware
`firmware/boot/boot.S` built with riscv-none-elf-gcc 14.2.0:

- `csrr mtvec` at reset reads `0x0000_0001`: base `0x0`, vectored.
- The OBI error on a read of `0x4000_3000` (unused peripheral page) and of
  `0x3000_0000` (unmapped) is taken as a load access fault (`mcause = 5`,
  `mtval` = the faulting address), and execution re-enters at `0x0000_0000`.
- Reset and every synchronous exception therefore share the entry `0x0`;
  interrupt `n` enters at `4n`. The firmware tells them apart by `mcause`
  (zero after reset).
- A reset asserted mid-run restarts from `0x0`; D-SRAM is not cleared by reset.

## Decision

The trap-vector offset is **0 from `boot_addr_i`**: exceptions at
`boot_addr_i`, interrupts at `boot_addr_i + 4n`. The boot ROM image therefore
begins with a 32-entry vector table (`j` per slot); offset 0 holds the
reset/exception dispatcher. No core change and no change to the memory map.

## Consequences

- `spec/soc.md` drops the "unverified" marks on the trap-vector offset.
- Later firmware (UART init, loader) keeps the vector table at the start of
  the ROM and branches on `mcause` at offset 0.
- This is simulation evidence on RTL, not a timing or silicon claim.
