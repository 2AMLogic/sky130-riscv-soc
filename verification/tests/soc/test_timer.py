"""firmware/soc/timer: the machine timer interrupt is taken exactly once, in bound.

Cycle bound. The firmware reads mtime (T0, D-SRAM word 5), programs
mtimecmp = T0 + DELAY (word 4, DELAY = 1000 mtime ticks = 1000 clocks, as
mtime increments every clk_i). irq_timer rises when mtime >= mtimecmp; the
handler's first mtime read (word 3) must land in [mtimecmp, mtimecmp + LATENCY].
LATENCY = 40 clocks covers the registered interrupt, the pipeline flush, the
vector jump and the handler's li + lw before it samples mtime (measured value
is logged, the bound is set with margin). The main loop then runs 3000 iterations
(>= 2 clocks each) after the interrupt, so a second interrupt would be seen as
count 2. The whole run is bounded by TIMEOUT clocks.
"""
import cocotb

from soc_bench import SIG, Soc

DELAY = 1000
LATENCY = 40
TIMEOUT = 40000  # the 3000-iteration window takes about 9000-12000 clocks
MCAUSE_TIMER = 0x80000007  # interrupt bit | machine timer (7)


@cocotb.test()
async def timer_interrupt_exactly_once(dut):
    soc = Soc(dut)
    await soc.start()
    await soc.wait_word(0, SIG, TIMEOUT)
    t0, cmp_, entry = soc.word(5), soc.word(4), soc.word(3)
    count, mcause = soc.word(1), soc.word(2)
    dut._log.info("mtime at programming %d, mtimecmp %d, mtime at handler entry %d (latency %d)",
                  t0, cmp_, entry, entry - cmp_)
    assert cmp_ == t0 + DELAY
    assert t0 < 100, f"programmed late ({t0})"
    assert count == 1, f"timer interrupt taken {count} times, expected exactly 1"
    assert mcause == MCAUSE_TIMER, f"mcause {mcause:#x}"
    assert cmp_ <= entry <= cmp_ + LATENCY, f"entry {entry} outside [{cmp_}, {cmp_ + LATENCY}]"
