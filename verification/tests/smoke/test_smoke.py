"""Harness smoke test: proves cocotb + Icarus run from a clean checkout.

Toolchain evidence only; it says nothing about the SoC.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


@cocotb.test()
async def register_follows_input_after_reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.d.value = 0xA5
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.q.value == 0, "q must be 0 while reset is asserted"
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert dut.q.value == 0xA5, f"q={dut.q.value}, expected 0xA5"
