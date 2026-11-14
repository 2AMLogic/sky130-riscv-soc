"""Shared cocotb bench core for the OBI managers of rtl/soc_fabric.sv and for
the standalone peripherals.  Importable from every testbench directory
(verification/cocotb.mk puts this directory on PYTHONPATH).

**The request/accept/response contract, stated once.**  A request is applied at
a falling edge; the grant, being combinational, is readable 1 ns later; the
rising edge accepts the request; the registered response of the accepted
request is sampled at the next falling edge.  Every subordinate answers exactly
one cycle after the grant, so one access takes one cycle and accesses can be
issued back to back.  The drivers under verification/tests/ reference this
paragraph rather than restating it, so there is one copy to keep true.

`reset_dut` is the single definition of the reset and clocking sequence those
drivers share (the soc_top benches have their own, in `soc_top_bench`): start
the clock, hold `rst_ni` low with every manager input idle, three rising edges,
release `rst_ni` on a falling edge, and return one falling edge later -- that
is, at the falling edge where the first request may be applied.

**Not shared, deliberately: how a driver handles the grant.**  The peripheral
window drives `per_gnt = 1'b1` (rtl/soc_fabric.sv), so
verification/tests/periph/periph_bus.py asserts the grant in the request cycle,
while single-port I-SRAM arbitration can make a manager wait, so
verification/tests/xbar/test_xbar.py retries until granted.  Both grant models
are real contracts of the same DUT; each bench keeps its own.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge

#: Clock period the fabric and peripheral benches run at, nanoseconds.
#: (tests/soc and tests/boot clock soc_top at soc_top_bench.CLOCK_NS.)
CLOCK_NS = 10

#: The OBI manager request inputs a bench holds idle through reset, unprefixed.
MANAGER_INPUTS = ("req_i", "we_i", "be_i", "addr_i", "wdata_i")


async def reset_dut(dut, managers=("",), *, period_ns=CLOCK_NS, **inputs):
    """Start `dut.clk_i` and bring `dut` out of reset; sequence as above.

    `managers` are the port prefixes whose `MANAGER_INPUTS` are held idle:
    `("",)` for a standalone peripheral, `("i_", "d_")` for soc_fabric's two
    managers -- including a manager the caller never drives, which must still
    be tied off for the DUT to elaborate quietly.  `inputs` names any extra
    non-bus DUT input to drive before reset is released (`gpio_i=0`,
    `uart_rxd_i=1`); every name must be a port on `dut`.

    Returns at a falling edge with reset released, ready for the first request.
    """
    cocotb.start_soon(Clock(dut.clk_i, period_ns, unit="ns").start())
    dut.rst_ni.value = 0
    for prefix in managers:
        for name in MANAGER_INPUTS:
            getattr(dut, f"{prefix}{name}").value = 0
    for name, value in inputs.items():
        getattr(dut, name).value = value
    for _ in range(3):
        await RisingEdge(dut.clk_i)
    await FallingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    await FallingEdge(dut.clk_i)
