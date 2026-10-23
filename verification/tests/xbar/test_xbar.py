"""Crossbar / decode tests for rtl/soc_fabric.sv (xbar + ROM + SRAMs + periph stub).

Managers are driven cycle by cycle: requests are applied at the falling edge,
grants (combinational) are sampled 1 ns later, the rising edge accepts, and the
registered response of the previous accepted request is sampled at the next
falling edge.  All subordinates respond exactly one cycle after the grant.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

ROM, ISRAM, DSRAM, PERI = 0x0000_0000, 0x1000_0000, 0x2000_0000, 0x4000_0000
ROM_IMG = [0xB0070000 + i for i in range(16)]  # rtl/boot_rom.hex
UNMAPPED = [0x0000_1000, 0x0FFF_FFFC, 0x1000_2000, 0x2000_2000, 0x3000_0000,
            0x4001_0000, 0x8000_0000, 0xFFFF_FFFC]


def req(addr, we=False, be=0xF, wdata=0):
    return dict(addr=addr, we=int(we), be=be, wdata=wdata)


class Fab:
    def __init__(self, dut):
        self.dut = dut
        self.resp = {"i": None, "d": None}  # responses seen at the last falling edge
        self.cycles = 0

    async def reset(self):
        d = self.dut
        cocotb.start_soon(Clock(d.clk_i, 10, unit="ns").start())
        d.rst_ni.value = 0
        for m in "id":
            getattr(d, f"{m}_req_i").value = 0
            getattr(d, f"{m}_addr_i").value = 0
            getattr(d, f"{m}_we_i").value = 0
            getattr(d, f"{m}_be_i").value = 0
            getattr(d, f"{m}_wdata_i").value = 0
        for _ in range(3):
            await RisingEdge(d.clk_i)
        await FallingEdge(d.clk_i)
        d.rst_ni.value = 1
        await FallingEdge(d.clk_i)

    def _sample(self, m):
        d = self.dut
        if int(getattr(d, f"{m}_rvalid_o").value):
            rd = getattr(d, f"{m}_rdata_o").value
            # write responses carry undefined data from the behavioural SRAMs
            return (int(rd) if rd.is_resolvable else None, bool(int(getattr(d, f"{m}_err_o").value)))
        return None

    async def cycle(self, i=None, d=None):
        """One clock cycle with optional requests; returns (gnt_i, gnt_d)."""
        dut = self.dut
        self.resp = {m: self._sample(m) for m in "id"}
        for m, r in (("i", i), ("d", d)):
            getattr(dut, f"{m}_req_i").value = int(r is not None)
            if r:
                getattr(dut, f"{m}_addr_i").value = r["addr"]
                getattr(dut, f"{m}_we_i").value = r["we"]
                getattr(dut, f"{m}_be_i").value = r["be"]
                getattr(dut, f"{m}_wdata_i").value = r["wdata"]
        await Timer(1, unit="ns")
        g = (int(dut.i_gnt_o.value and i is not None), int(dut.d_gnt_o.value and d is not None))
        await RisingEdge(dut.clk_i)
        await FallingEdge(dut.clk_i)
        self.cycles += 1
        return g

    async def access(self, m, r, max_wait=8):
        """Single access from manager m; returns (rdata, err, cycles_to_response)."""
        n = 0
        while True:
            g = await self.cycle(**{m: r})
            n += 1
            if g[0 if m == "i" else 1]:
                break
            assert n < max_wait, "request never granted"
        while True:
            await self.cycle()
            n += 1
            if self.resp[m] is not None:
                return (*self.resp[m], n)
            assert n < max_wait + 2, "no response: access hung"

    async def write(self, m, addr, data, be=0xF):
        rd, err, _ = await self.access(m, req(addr, True, be, data))
        return err

    async def read(self, m, addr):
        return await self.access(m, req(addr))


@cocotb.test()
async def rom_reachable_by_both_managers(dut):
    f = Fab(dut)
    await f.reset()
    for m in "id":
        for k in (0, 1, 7, 15):
            rd, err, _ = await f.read(m, ROM + 4 * k)
            assert not err and rd == ROM_IMG[k], f"{m} ROM[{k}] = {rd:#x} err={err}"


@cocotb.test()
async def isram_reach_and_partial_writes(dut):
    f = Fab(dut)
    await f.reset()
    assert not await f.write("d", ISRAM + 0x10, 0xAABBCCDD)
    for m in "id":
        rd, err, _ = await f.read(m, ISRAM + 0x10)
        assert not err and rd == 0xAABBCCDD, f"{m}: {rd:#x}"
    # partial strobes: bytes 0 and 2 only; low address bits are ignored (word access)
    assert not await f.write("d", ISRAM + 0x11, 0x11223344, be=0b0101)
    rd, err, _ = await f.read("i", ISRAM + 0x10)
    assert not err and rd == 0xAA22CC44, f"{rd:#x}"
    assert not await f.write("d", ISRAM + 0x10, 0x5566_7788, be=0b1100)
    rd, err, _ = await f.read("d", ISRAM + 0x10)
    assert rd == 0x5566CC44, f"{rd:#x}"
    # last word of the 8 KB window
    assert not await f.write("d", ISRAM + 0x1FFC, 0xCAFEF00D)
    rd, err, _ = await f.read("i", ISRAM + 0x1FFC)
    assert not err and rd == 0xCAFEF00D


@cocotb.test()
async def dsram_reachable_by_data_manager_only(dut):
    f = Fab(dut)
    await f.reset()
    assert not await f.write("d", DSRAM, 0x12345678)
    assert not await f.write("d", DSRAM + 0x1FFC, 0x9ABCDEF0)
    rd, err, _ = await f.read("d", DSRAM)
    assert not err and rd == 0x12345678
    rd, err, _ = await f.read("d", DSRAM + 0x1FFC)
    assert not err and rd == 0x9ABCDEF0
    _, err, _ = await f.read("i", DSRAM)
    assert err, "instruction manager must not reach D-SRAM"
    # the forbidden write must not have modified D-SRAM
    assert await f.write("i", DSRAM, 0xDEADBEEF)
    rd, _, _ = await f.read("d", DSRAM)
    assert rd == 0x12345678


@cocotb.test()
async def peripheral_window_errors_and_forbidden_accesses(dut):
    f = Fab(dut)
    await f.reset()
    for m in "id":
        for a in (PERI, PERI + 0x1000, PERI + 0x2000, PERI + 0xFFFC):
            _, err, n = await f.read(m, a)
            assert err, f"{m} read {a:#x} must be an OBI error"
            assert n <= 3, "error response must be bounded"
    assert await f.write("d", PERI, 1)
    # instruction manager is read-only; boot ROM is read-only
    assert await f.write("i", ISRAM, 0x1234)
    rd, err, _ = await f.read("d", ISRAM)
    assert not err and rd != 0x1234
    assert await f.write("d", ROM, 0x1234)
    rd, err, _ = await f.read("d", ROM)
    assert not err and rd == ROM_IMG[0]


@cocotb.test()
async def unmapped_addresses_error_and_complete(dut):
    f = Fab(dut)
    await f.reset()
    for m in "id":
        for a in UNMAPPED:
            for we in (False, True):
                _, err, n = await f.access(m, req(a, we, wdata=0xFFFFFFFF))
                assert err, f"{m} {'write' if we else 'read'} {a:#x} must error"
                assert n <= 3
    # error responses must not disturb real memory
    rd, err, _ = await f.read("d", ROM)
    assert not err and rd == ROM_IMG[0]


@cocotb.test()
async def rom_contention_gives_instruction_manager_priority(dut):
    f = Fab(dut)
    await f.reset()
    ri, rd_ = req(ROM + 4 * 3), req(ROM + 4 * 9)
    g = await f.cycle(i=ri, d=rd_)
    assert g == (1, 0), f"cycle 0 grants {g}: instruction manager must win"
    # data request stays pending; the instruction manager now idle
    g = await f.cycle(d=rd_)
    assert f.resp["i"] == (ROM_IMG[3], False)
    assert g == (0, 1), f"data manager granted once ROM is free, got {g}"
    # contention again, repeatedly: data never wins while instruction requests
    for k in range(4):
        g = await f.cycle(i=req(ROM + 4 * k), d=rd_)
        assert g[0] == 1 and g[1] == 0
    await f.cycle()  # last fetch's response; the starved data request got none
    assert f.resp["d"] is None
    g = await f.cycle(d=rd_)
    assert g == (0, 1)
    await f.cycle()
    assert f.resp["d"] == (ROM_IMG[9], False)


@cocotb.test()
async def isram_write_and_fetch_in_same_cycle(dut):
    f = Fab(dut)
    await f.reset()
    assert not await f.write("d", ISRAM + 0x40, 0x0BADF00D)
    g = await f.cycle(i=req(ISRAM + 0x40), d=req(ISRAM + 0x80, True, 0xF, 0x600DCAFE))
    assert g == (1, 1), f"both must be granted in one cycle, got {g}"
    await f.cycle()
    assert f.resp["i"] == (0x0BADF00D, False)
    assert f.resp["d"] == (f.resp["d"][0], False)
    rd, err, _ = await f.read("i", ISRAM + 0x80)
    assert not err and rd == 0x600DCAFE


@cocotb.test()
async def back_to_back_and_error_between_accesses(dut):
    f = Fab(dut)
    await f.reset()
    await f.write("d", DSRAM + 4, 0x1111_1111)
    await f.write("d", DSRAM + 8, 0x2222_2222)
    # ROM, unmapped, D-SRAM, peripheral error, D-SRAM: one request per cycle
    seq = [req(ROM + 4), req(0x3000_0000), req(DSRAM + 4), req(PERI), req(DSRAM + 8)]
    got = []
    for r in seq:
        g = await f.cycle(d=r)
        assert g == (0, 1)
        got.append(f.resp["d"])
    for _ in range(2):
        await f.cycle()
        got.append(f.resp["d"])
    got = [x for x in got if x is not None]
    assert got == [(ROM_IMG[1], False), (0, True), (0x1111_1111, False), (0, True),
                   (0x2222_2222, False)], got
    # both managers streaming at once to separate targets
    got_i, got_d = [], []
    for k in range(4):
        await f.cycle(i=req(ISRAM + 4 * k), d=req(DSRAM + 4 * (k + 1) if k < 2 else PERI))
        got_i.append(f.resp["i"]); got_d.append(f.resp["d"])
    await f.cycle(); got_i.append(f.resp["i"]); got_d.append(f.resp["d"])
    assert [x is not None for x in got_i] == [False, True, True, True, True]
    assert [x[1] if x else None for x in got_d] == [None, False, False, True, True]
