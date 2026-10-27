"""Shared cocotb bus driver for the peripheral tests.

Requests are applied at the falling edge, accepted at the next rising edge, and
the registered response is sampled at the falling edge after that, so one access
takes one cycle and accesses can be issued back to back.  `Bus` drives either a
standalone peripheral (req_i/we_i/be_i/addr_i/wdata_i, rdata_o/err_o) or the
data-manager port of soc_fabric (prefix "d_", with grant and rvalid checked).
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


class Bus:
    def __init__(self, dut, fabric=False):
        self.dut = dut
        self.fabric = fabric
        p = "d_" if fabric else ""
        self.req = getattr(dut, f"{p}req_i")
        self.we = getattr(dut, f"{p}we_i")
        self.be = getattr(dut, f"{p}be_i")
        self.addr = getattr(dut, f"{p}addr_i")
        self.wdata = getattr(dut, f"{p}wdata_i")
        self.rdata = getattr(dut, f"{p}rdata_o")
        self.err = getattr(dut, f"{p}err_o")
        self.gnt = getattr(dut, "d_gnt_o", None) if fabric else None
        self.rvalid = getattr(dut, "d_rvalid_o", None) if fabric else None

    def idle_inputs(self):
        d = self.dut
        d.rst_ni.value = 0
        self.req.value = 0
        self.we.value = 0
        self.be.value = 0
        self.addr.value = 0
        self.wdata.value = 0
        if self.fabric:
            for n in ("i_req_i", "i_we_i", "i_addr_i", "i_wdata_i"):
                getattr(d, n).value = 0
            d.i_be_i.value = 0

    async def reset(self, **inputs):
        d = self.dut
        cocotb.start_soon(Clock(d.clk_i, 10, unit="ns").start())
        self.idle_inputs()
        for name, v in inputs.items():
            getattr(d, name).value = v
        for _ in range(3):
            await RisingEdge(d.clk_i)
        await FallingEdge(d.clk_i)
        d.rst_ni.value = 1
        await FallingEdge(d.clk_i)

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
        rd, err = await self.access(addr)
        return rd, err

    async def write(self, addr, data, be=0xF):
        _, err = await self.access(addr, True, be, data)
        return err
