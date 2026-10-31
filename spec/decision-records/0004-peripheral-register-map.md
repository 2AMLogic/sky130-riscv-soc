# 0004 — Peripheral register map: decoder, GPIO and machine timer

- **Status**: accepted (2026-10-27), issue #46
- **Supersedes**: none
- **Superseded by**: none
- **Spec rows**: `spec/soc.md` § Memory map (peripheral window), § Peripherals (rows 9)

## Context

`spec/soc.md` ratifies an 8-bit GPIO at `0x4000_1000`, a 64-bit machine timer
at `0x4000_2000`, the UART at `0x4000_0000`, and the interrupt lines (timer →
`irq_timer_i`, UART → `irq_fast_i[0]`, GPIO → `irq_fast_i[1]`), but no register
layout. This record adds that detail; it relaxes no ratified row.

## Decision

### Window decode

`per_addr[15:12]` selects the page inside `0x4000_0000`–`0x4000_FFFF`:

| Page | Base | Target |
|---|---|---|
| 0 | `0x4000_0000` | UART (reserved for the UART sibling issue; **OBI error** until it lands) |
| 1 | `0x4000_1000` | GPIO |
| 2 | `0x4000_2000` | timer |
| 3–15 | `0x4000_3000`… | OBI error |

Inside GPIO and timer, any word offset past the last register is an OBI error
(both reads and writes). Every access, mapped or error, is granted in the
request cycle and answered exactly one cycle later (`rdata`/`err` registered),
the fabric timing `obi_xbar` relies on. Register addressing uses `addr[11:2]`;
`addr[1:0]` is ignored. Only the data manager reaches the window.

### GPIO (`0x4000_1000`)

All registers are 8 bits wide in byte lane 0 (bits `[7:0]`); reads return the
value zero-extended; a write takes effect only if `be[0]` is set, and the
upper write bits are ignored.

| Offset | Name | Access | Reset | Meaning |
|---|---|---|---|---|
| `0x00` | `OUT` | RW | `0x00` | output data, drives `gpio_o` |
| `0x04` | `DIR` | RW | `0x00` | per-pin direction, 1 = output; drives `gpio_oe_o` (no pad ring: the pin-level tri-state is an SoC-boundary concern) |
| `0x08` | `IN` | RO | `0x00` | `gpio_i` after a 2-flop synchroniser (writes ignored) |
| `0x0C` | `IRQ_EN` | RW | `0x00` | per-pin interrupt enable |
| `0x10` | `IRQ_PEND` | RW1C | `0x00` | per-pin sticky pending |

Interrupt: `IRQ_PEND[n]` sets on a **rising edge** of the synchronised input
`n` (`IN[n]` 0→1, regardless of `DIR`); `irq_gpio_o = |(IRQ_PEND & IRQ_EN)`,
a level that stays high until software clears the pending bits by writing 1
to them. Writing 0 clears nothing. An edge arriving in the same cycle as a
clearing write wins (stays pending). Falling-edge and level modes are not
provided; the count and mode are a spec choice and adding them is a record,
not a patch. The input path is `gpio_i` → flop → flop → `IN`: a change on
`gpio_i` is visible to a read accepted two clock edges later. Pulses shorter
than a clock period are outside the synchroniser's contract.

### Timer (`0x4000_2000`)

32-bit register halves, byte-lane writable (`be` per lane).

| Offset | Name | Access | Reset |
|---|---|---|---|
| `0x00` | `MTIME_LO` | RW | `0` |
| `0x04` | `MTIME_HI` | RW | `0` |
| `0x08` | `MTIMECMP_LO` | RW | `0xFFFF_FFFF` |
| `0x0C` | `MTIMECMP_HI` | RW | `0xFFFF_FFFF` |

`mtime` increments every `clk_i`; `irq_timer_o = (mtime >= mtimecmp)` as
64-bit unsigned values, a level (no sticky bit). `mtimecmp` resets to all ones
so no interrupt is pending out of reset. A read returns the register value at
the accept edge. A write to `mtime` in a cycle where it also increments: the
written byte lanes take the write data, all other lanes take the incremented
value (so a `MTIME_LO` write does not lose the carry that cycle would have
made into `MTIME_HI` unless `MTIME_HI` is written too).

**Write-ordering rule (hi/lo are separate 32-bit accesses).** To set
`mtimecmp` without a spurious interrupt from a transient half-updated value:
write `MTIMECMP_LO = 0xFFFF_FFFF`, then `MTIMECMP_HI = hi`, then
`MTIMECMP_LO = lo`. To read `mtime` atomically on a 32-bit bus: read `HI`,
`LO`, `HI` again and retry if the two `HI` reads differ.

### UART page

`0x4000_0000`–`0x4000_0FFF` is reserved for the UART sibling issue, which
fixes its registers in a later record and replaces the error response at page 0.

## Consequences

- `rtl/soc_fabric.sv` holds the decoder and instances `gpio`/`timer`; `soc_top`
  exposes `gpio_i`, `gpio_o`, `gpio_oe_o` and wires `irq_timer_o` →
  `irq_timer_i`, `irq_gpio_o` → `irq_fast_i[1]`.
- Firmware gets one fixed map for GPIO and timer; the UART record extends it.
- Evidence is cocotb simulation on RTL (`make -C verification periph`), not
  timing or silicon.
