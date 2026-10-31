"""Shared bench for the SoC firmware tests (issue #48): soc_top running one ROM image.

Each test module runs one image from firmware/soc/ (picked by the Makefile
through +rom_hex). Every wait is bounded by a cycle count so a missing byte or
interrupt fails the test instead of hanging it.

Set SOC_PERTURB=1 to flip one byte of every expected transcript; the tests
must then fail (make -C verification soc-negative checks that).
"""
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge

SIG = 0x600DC0DE
FW = Path(__file__).resolve().parents[3] / "firmware" / "soc"


def golden(name):
    """Expected UART transcript from firmware/soc/<name>.golden (checked in)."""
    data = (FW / f"{name}.golden").read_bytes()
    if os.environ.get("SOC_PERTURB") == "1":
        data = bytes([data[0] ^ 0x01]) + data[1:]
    return data


class Soc:
    def __init__(self, dut):
        self.dut = dut
        self.mem = dut.u_fabric.u_dsram.mem
        self.cycles = 0

    def word(self, i):
        return int(self.mem[i].value)

    async def start(self):
        d = self.dut
        d.uart_rxd_i.value = 1
        d.gpio_i.value = 0
        for i in range(8):
            self.mem[i].value = 0
        cocotb.start_soon(Clock(d.clk_i, 20, unit="ns").start())
        cocotb.start_soon(self._count())
        d.rst_ni.value = 0
        for _ in range(4):
            await RisingEdge(d.clk_i)
        await FallingEdge(d.clk_i)
        d.rst_ni.value = 1

    async def _count(self):
        while True:
            await RisingEdge(self.dut.clk_i)
            self.cycles += 1

    async def wait_cycles(self, n):
        for _ in range(n):
            await RisingEdge(self.dut.clk_i)

    async def wait_word(self, i, value, timeout):
        for _ in range(timeout):
            await RisingEdge(self.dut.clk_i)
            if self.word(i) == value:
                return
        raise AssertionError(f"D-SRAM word {i} never became {value:#x} in {timeout} cycles")

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
