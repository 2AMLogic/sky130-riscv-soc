"""firmware/soc/banner: boot from ROM and print the banner at the reset divisor."""
import cocotb

from soc_bench import Soc, golden

BIT = 434  # reset DIV 433 -> DIV + 1 clocks per bit (record 0005)


@cocotb.test()
async def banner_matches_golden(dut):
    soc = Soc(dut)
    want = golden("banner")
    await soc.start()
    # 10 bit times per byte plus polling slack; a stuck UART fails here.
    got = await soc.uart_rx(len(want), BIT, timeout=2 * BIT * 10)
    assert got == want, f"transcript {got!r} != golden {want!r}"
