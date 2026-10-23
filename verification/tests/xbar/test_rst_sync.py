"""rst_sync: asynchronous assert, synchronous (two-flop) deassert."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


@cocotb.test()
async def assert_is_asynchronous(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    dut.rst_ni.value = 1
    for _ in range(4):
        await RisingEdge(dut.clk_i)
    assert dut.rst_no.value == 1
    await Timer(3, unit="ns")  # mid-cycle, no clock edge
    dut.rst_ni.value = 0
    await Timer(1, unit="ns")
    assert dut.rst_no.value == 0, "reset must assert without waiting for a clock edge"


@cocotb.test()
async def deassert_is_synchronous_after_two_edges(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    dut.rst_ni.value = 0
    await RisingEdge(dut.clk_i)
    await Timer(3, unit="ns")  # release off-edge
    dut.rst_ni.value = 1
    await Timer(1, unit="ns")
    assert dut.rst_no.value == 0, "output must not follow the async release"
    await RisingEdge(dut.clk_i)
    await Timer(1, unit="ns")
    assert dut.rst_no.value == 0, "still held after the first edge"
    await Timer(4, unit="ns")  # between edges: no change
    assert dut.rst_no.value == 0
    await RisingEdge(dut.clk_i)
    await Timer(1, unit="ns")
    assert dut.rst_no.value == 1, "released on the second edge"
    # an assert/release pair seen mid-cycle never produces an unsynchronised release
    await FallingEdge(dut.clk_i)
    dut.rst_ni.value = 0
    await Timer(1, unit="ns")
    dut.rst_ni.value = 1
    await Timer(1, unit="ns")
    assert dut.rst_no.value == 0
