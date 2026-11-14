"""Cocotb bus driver for the peripheral tests.

`Bus` drives either a standalone peripheral (req_i/we_i/be_i/addr_i/wdata_i,
rdata_o/err_o) or the data-manager port of soc_fabric (prefix "d_", with grant
and rvalid checked).  The request/accept/response timing it follows, and the
reset sequence `reset` runs, are stated once in `obi_bench`
(verification/tests/lib/obi_bench.py).  The grant assertion in `access` is this
bench's own contract -- the peripheral window grants in the request cycle --
and is deliberately not shared with the fabric bench; see that module.
"""
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from obi_bench import reset_dut


class Bus:
    def __init__(self, dut, fabric=False):
        self.dut = dut
        self.fabric = fabric
        p = "d_" if fabric else ""
        # Reset ties off soc_fabric's instruction manager too: this driver never
        # drives it, but it is an input of the DUT whenever the DUT is the fabric.
        self.managers = ("d_", "i_") if fabric else ("",)
        self.req = getattr(dut, f"{p}req_i")
        self.we = getattr(dut, f"{p}we_i")
        self.be = getattr(dut, f"{p}be_i")
        self.addr = getattr(dut, f"{p}addr_i")
        self.wdata = getattr(dut, f"{p}wdata_i")
        self.rdata = getattr(dut, f"{p}rdata_o")
        self.err = getattr(dut, f"{p}err_o")
        self.gnt = getattr(dut, "d_gnt_o", None) if fabric else None
        self.rvalid = getattr(dut, "d_rvalid_o", None) if fabric else None

    async def reset(self, **inputs):
        """Clock and release reset; `inputs` names extra non-bus DUT inputs."""
        await reset_dut(self.dut, self.managers, **inputs)

    async def idle(self, n=1):
        for _ in range(n):
            await FallingEdge(self.dut.clk_i)

    async def access(self, addr, we=False, be=0xF, wdata=0):
        """One access; returns (rdata, err).  Call at a falling edge."""
        self.req.value = 1
        self.we.value = int(we)
        self.be.value = be
        self.addr.value = addr
        self.wdata.value = wdata
        if self.fabric:
            await Timer(1, unit="ns")
            assert int(self.gnt.value) == 1, "peripheral window must grant in the request cycle"
        await RisingEdge(self.dut.clk_i)
        await FallingEdge(self.dut.clk_i)
        self.req.value = 0
        if self.fabric:
            assert int(self.rvalid.value) == 1, "response must arrive one cycle after the grant"
        return int(self.rdata.value), bool(int(self.err.value))

    async def read(self, addr):
        """`access` with its defaults, named for the ~90 read call sites."""
        return await self.access(addr)

    async def write(self, addr, data, be=0xF):
        _, err = await self.access(addr, True, be, data)
        return err
