# 0005 — UART register map (`0x4000_0000`)

- **Status**: accepted (2026-10-31), issue #47
- **Supersedes**: none (fills the UART page that [0004](0004-peripheral-register-map.md) reserved; its page-0 row "OBI error until it lands" no longer applies)
- **Superseded by**: none
- **Spec rows**: `spec/soc.md` § Peripherals (row 9), § Memory map (peripheral window)

## Context

`spec/soc.md` ratifies one UART (8N1, TX and RX, programmable baud divisor,
TX/RX interrupt) at `0x4000_0000`, routed to `irq_fast_i[0]`. Record 0004
reserved the page. This record fixes the registers; it relaxes no ratified row.
FIFOs, parity, flow control and other frame formats are not provided; adding
any is a spec change.

## Decision

Same conventions as 0004: `addr[11:2]` selects the word, `addr[1:0]` ignored;
every access is granted in the request cycle and answered one cycle later;
a word offset past `DIV` is an OBI error (read and write). `DATA`, `STATUS` and
`CTRL` are byte-lane 0 registers (a write needs `be[0]`); `DIV` is 16 bits
(`be[0]` writes `[7:0]`, `be[1]` writes `[15:8]`). Reads return zero-extended values.

| Offset | Name | Access | Reset | Meaning |
|---|---|---|---|---|
| `0x00` | `DATA` | W: TX, R: RX | `0x00` | write queues a byte for TX; read returns the received byte and clears `RX_VALID` |
| `0x04` | `STATUS` | RO / RW1C | `0x00` | see below |
| `0x08` | `CTRL` | RW | `0x00` | bit 0 `TX_IE`, bit 1 `RX_IE` |
| `0x0C` | `DIV` | RW | `0x01B1` (433) | bit period = `DIV + 1` clocks |

`STATUS`: bit 0 `TX_BUSY` (holding register full: a `DATA` write is dropped),
bit 1 `RX_VALID` (a byte is waiting), bit 2 `OVERRUN` (sticky, write 1 to
clear), bit 3 `FRAME_ERR` (sticky, write 1 to clear), bit 4 `TX_ACTIVE`
(shifter running; with `TX_BUSY` clear, all bytes have left once it is 0).
Writing 0 clears nothing; read-only bits ignore writes.

The reset divisor gives 434 clocks per bit: 115200 baud at 50 MHz.

### Behaviour

- **TX**: one holding register plus the shifter. A `DATA` write while
  `TX_BUSY` is set is silently dropped (no error response). The holding byte
  moves to the shifter at once when it is idle, or at the end of the previous
  stop bit, so queued frames are back to back. Frame: start (0), 8 data bits
  LSB first, stop (1), each exactly `DIV + 1` clocks. `txd_o` idles high.
- **RX**: `rxd_i` passes a 2-flop synchroniser. A low level starts a frame; the
  start bit is re-checked at its middle and a high level there (a glitch
  shorter than about half a bit) is ignored. Data are sampled every `DIV + 1`
  clocks, then the stop bit. A high stop bit completes the byte; a low one sets
  `FRAME_ERR`, drops the byte and holds the receiver off until the line is high
  again (a break gives one error, not a stream).
- **Overrun**: a byte completing while `RX_VALID` is still set (and not being
  read that cycle) is dropped: the unread byte is kept and `OVERRUN` sets.
- **Divisor changes** take effect at the next bit period; change it only while
  both directions are idle.
- **Interrupt**: `irq_uart_o = (TX_IE & !TX_BUSY) | (RX_IE & RX_VALID)`, a
  level, to `irq_fast_i[0]`. The TX source is "holding register empty" (high
  as soon as `TX_IE` is set); it clears by writing `DATA`. The RX source clears
  by reading `DATA`.

## Consequences

- `rtl/uart.sv` is instanced in `rtl/soc_fabric.sv` on page 0; `soc_top`
  exposes `uart_rxd_i`/`uart_txd_o` and wires `irq_uart_o` → `irq_fast_i[0]`.
- Evidence is cocotb simulation on RTL (`make -C verification periph`), not
  timing or silicon.
