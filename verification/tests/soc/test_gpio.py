"""firmware/soc/gpio: toggle the outputs, read OUT and IN (looped back) back."""
import cocotb
from cocotb.triggers import RisingEdge

from soc_bench import SIG, Soc

PATTERNS = [0xA5, 0x5A, 0xFF, 0x00]
TIMEOUT = 2000  # cycles; the run takes a few hundred


@cocotb.test()
async def gpio_toggle_and_readback(dut):
    soc = Soc(dut)
    await soc.start()

    seen = []  # distinct gpio_o values after DIR is set, in order

    async def loopback():  # gpio_i follows gpio_o; the firmware reads it via IN
        while True:
            await RisingEdge(dut.clk_i)
            dut.gpio_i.value = dut.gpio_o.value
            o = int(dut.gpio_o.value)
            if not seen or seen[-1] != o:
                seen.append(o)

    cocotb.start_soon(loopback())
    await soc.wait_word(0, SIG, TIMEOUT)
    assert int(dut.gpio_oe_o.value) == 0xFF
    assert [soc.word(1 + i) for i in range(4)] == PATTERNS, "IN readback"
    assert [soc.word(5 + i) for i in range(4)] == PATTERNS, "OUT readback"
    # gpio_o resets to 0, then follows each pattern; the last 0x00 differs from 0xFF.
    assert seen == [0x00] + PATTERNS, [hex(v) for v in seen]
