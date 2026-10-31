"""firmware/soc/echo: prompt, then every received byte comes back (DIV = 15)."""
import cocotb

from soc_bench import Soc, golden

BIT = 16  # firmware sets DIV = 15 before the first byte
STIMULUS = b"Hi!\x00\xff"


@cocotb.test()
async def echo_matches_golden(dut):
    soc = Soc(dut)
    want = golden("echo")
    await soc.start()
    nprompt = len(want) - len(STIMULUS)
    # The prompt comes out at DIV = 15, so the firmware is listening at 16 clocks/bit.
    got = await soc.uart_rx(nprompt, BIT, timeout=2000)
    tx = cocotb.start_soon(soc.uart_tx(STIMULUS, BIT))
    got += await soc.uart_rx(len(STIMULUS), BIT, timeout=2000)
    await tx
    assert got == want, f"transcript {got!r} != golden {want!r}"
