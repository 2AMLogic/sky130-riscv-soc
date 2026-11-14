"""Shared bench for the SoC firmware tests (issue #48): soc_top running one ROM image.

Each test module runs one image from firmware/soc/ (picked by the Makefile
through +rom_hex). Every wait is bounded by a cycle count so a missing byte or
interrupt fails the test instead of hanging it.

`Soc` is `soc_top_bench.SocTop` (verification/tests/lib/soc_top_bench.py) --
the clock, the reset sequence, the D-SRAM result block and its preload, stated
once there and shared with verification/tests/boot -- plus the UART codecs
below, which are this testbench's own.

Set SOC_GATE=1 when the DUT is the synthesized netlist (make -C verification
soc-gate): the D-SRAM is then the macro stand-in, not soc_sram_i.mem, so the
RTL-only memory peeks are skipped; only tests that decode the UART (banner) run.

Set SOC_PERTURB=1 to flip one byte of every expected transcript; the tests
must then fail (make -C verification soc-negative checks that).
"""
import os
from pathlib import Path

from cocotb.triggers import RisingEdge

from soc_top_bench import SocTop

SIG = 0x600DC0DE
FW = Path(__file__).resolve().parents[3] / "firmware" / "soc"


def golden(name):
    """Expected UART transcript from firmware/soc/<name>.golden (checked in)."""
    data = (FW / f"{name}.golden").read_bytes()
    if os.environ.get("SOC_PERTURB") == "1":
        data = bytes([data[0] ^ 0x01]) + data[1:]
    return data


class Soc(SocTop):
    async def start(self):
        """Preload the result block, start the clock, and come out of reset."""
        self.preload()
        self.start_clock()
        await self.reset()

    async def wait_cycles(self, n):
        for _ in range(n):
            await RisingEdge(self.dut.clk_i)

    async def uart_rx(self, nbytes, bit_clocks, timeout):
        """Decode nbytes 8N1 frames from uart_txd_o; fail if one is late or has a bad stop bit."""
        d = self.dut
        out = bytearray()
        waited = 0
        for _ in range(nbytes):
            while int(d.uart_txd_o.value) == 1:  # idle high; wait for the start bit
                await RisingEdge(d.clk_i)
                waited += 1
                assert waited < timeout, (
                    f"timeout after {timeout} cycles; got {bytes(out)!r}, wanted {nbytes} bytes")
            await self.wait_cycles(bit_clocks // 2)  # centre of the start bit
            assert int(d.uart_txd_o.value) == 0, "start bit glitch"
            b = 0
            for k in range(8):
                await self.wait_cycles(bit_clocks)
                b |= int(d.uart_txd_o.value) << k
            await self.wait_cycles(bit_clocks)
            assert int(d.uart_txd_o.value) == 1, f"bad stop bit after {b:#04x}"
            out.append(b)
            await self.wait_cycles(bit_clocks // 2)  # to the end of the stop bit
            waited = 0
        return bytes(out)

    async def uart_tx(self, data, bit_clocks):
        """Drive 8N1 frames on uart_rxd_i, back to back."""
        d = self.dut
        for byte in data:
            for bit in [0] + [(byte >> k) & 1 for k in range(8)] + [1]:
                d.uart_rxd_i.value = bit
                await self.wait_cycles(bit_clocks)
