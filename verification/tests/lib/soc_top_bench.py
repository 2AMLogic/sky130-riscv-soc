"""Shared cocotb bench core for rtl/soc_top.sv: the whole SoC running one ROM
image.  Importable from every testbench directory (verification/cocotb.mk puts
this directory on PYTHONPATH).

Two testbenches drive this DUT -- verification/tests/boot (the boot test) and
verification/tests/soc (the firmware tests, including the synthesized-netlist
run) -- and the Makefile builds it from one source list (`SOC_SRC`,
verification/Makefile) at one clock period for both.  So the clocking, the
reset sequence, the D-SRAM peek and the result-block preload are stated once
here instead of twice.

**The reset sequence, stated once.**  Hold `rst_ni` low, four rising edges,
release it on a falling edge.  `reset` is callable on its own, separately from
`start_clock`, because verification/tests/boot/test_boot.py resets a running
SoC three times in one test.

**The D-SRAM peek.**  The firmware writes its result block into the first
words of D-SRAM, a behavioural memory (`u_fabric.u_dsram.mem`) the tests read
straight out of.  `words` lets a bench address those words by name
(the boot firmware's block has a fixed, documented layout) as well as by
index.  Set `SOC_GATE=1` and the DUT is the synthesized netlist instead, whose
D-SRAM is the macro stand-in rather than `soc_sram_i.mem`: `mem` is then None
and `word`/`wait_word` are unavailable, so only tests that decode the UART run.

**Not shared, deliberately: what each bench watches.**  The boot test's
data-side OBI error monitor (verification/tests/boot/test_boot.py) and the
firmware tests' UART codecs (verification/tests/soc/soc_bench.py) have no
counterpart on the other side; each bench keeps its own.
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge

#: Clock period the soc_top benches run at, nanoseconds.
#: (tests/xbar and tests/periph clock soc_fabric at obi_bench.CLOCK_NS.)
CLOCK_NS = 20

#: Rising edges `rst_ni` is held low for before it is released.
RESET_CYCLES = 4

#: D-SRAM result-block words zeroed before a run, so a value left by an
#: earlier run cannot pass for one the firmware wrote this time.
PRELOAD_WORDS = 8


class SocTop:
    """`soc_top`'s shared half: clock, reset, and the D-SRAM result block.

    `words` is an optional name -> index map for `word`/`wait_word`; a bench
    whose firmware has a documented result-block layout passes it and then
    addresses words by name.
    """

    def __init__(self, dut, words=None):
        self.dut = dut
        self.gate = os.environ.get("SOC_GATE") == "1"
        self.mem = None if self.gate else dut.u_fabric.u_dsram.mem
        self.words = words or {}

    def word(self, i):
        """D-SRAM word `i`, an index or a `words` name (RTL builds only)."""
        return int(self.mem[self.words.get(i, i)].value)

    def preload(self, nwords=PRELOAD_WORDS):
        """Zero the result block; a no-op on the netlist, which has no peek."""
        if not self.gate:
            for i in range(nwords):
                self.mem[i].value = 0

    def start_clock(self):
        """Idle the non-bus inputs and start `clk_i`.  Does not reset."""
        self.dut.uart_rxd_i.value = 1
        self.dut.gpio_i.value = 0  # GPIO pins undriven would feed X into the irq inputs
        cocotb.start_soon(Clock(self.dut.clk_i, CLOCK_NS, unit="ns").start())

    async def reset(self, cycles=RESET_CYCLES):
        """Hold `rst_ni` low for `cycles` rising edges, release on a falling edge."""
        self.dut.rst_ni.value = 0
        for _ in range(cycles):
            await RisingEdge(self.dut.clk_i)
        await FallingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1

    async def wait_word(self, i, value, timeout):
        """Wait for D-SRAM word `i` to read `value`; fail after `timeout` cycles."""
        index = self.words.get(i, i)
        for _ in range(timeout):
            await RisingEdge(self.dut.clk_i)
            if int(self.mem[index].value) == value:
                return
        raise AssertionError(f"D-SRAM word {i} never became {value:#x} in {timeout} cycles")
