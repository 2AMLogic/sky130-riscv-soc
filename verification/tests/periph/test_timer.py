"""mtime/mtimecmp tests for rtl/timer.sv."""
import cocotb
from cocotb.triggers import FallingEdge

from periph_bus import Bus

TIME_LO, TIME_HI, CMP_LO, CMP_HI = 0x00, 0x04, 0x08, 0x0C
M64 = (1 << 64) - 1


async def setup(dut):
    b = Bus(dut)
    await b.reset()
    return b


async def set_cmp(b, value):
    """The safe ordering from the register-map record: park lo, write hi, write lo."""
    await b.write(CMP_LO, 0xFFFF_FFFF)
    await b.write(CMP_HI, value >> 32)
    await b.write(CMP_LO, value & 0xFFFF_FFFF)


@cocotb.test()
async def reset_values(dut):
    b = await setup(dut)
    assert (await b.read(CMP_LO))[0] == 0xFFFF_FFFF
    assert (await b.read(CMP_HI))[0] == 0xFFFF_FFFF
    assert int(dut.irq_o.value) == 0
    await b.idle(20)
    assert int(dut.irq_o.value) == 0, "no interrupt out of reset"
    assert int(dut.mtime_q.value) > 0


@cocotb.test()
async def mtime_increments_every_clock(dut):
    b = await setup(dut)
    a = (await b.read(TIME_LO))[0]
    c = (await b.read(TIME_LO))[0]
    assert c - a == 1, "back-to-back reads are one clock apart"
    await b.idle(10)
    d = (await b.read(TIME_LO))[0]
    assert d - c == 11
    assert (await b.read(TIME_HI))[0] == 0


@cocotb.test()
async def write_mtime_halves_and_carry(dut):
    b = await setup(dut)
    await b.write(TIME_HI, 0x0000_0001)
    await b.write(TIME_LO, 0xFFFF_FFF0)
    await b.idle(20)
    hi = (await b.read(TIME_HI))[0]
    lo = (await b.read(TIME_LO))[0]
    assert hi == 2, "carry from lo into hi"
    assert 0 < lo < 40
    # a write to hi replaces it; lo keeps counting
    await b.write(TIME_HI, 0x1234_5678)
    assert int(dut.mtime_q.value) >> 32 == 0x1234_5678


@cocotb.test()
async def byte_lane_writes_to_64bit_halves(dut):
    b = await setup(dut)
    await b.write(CMP_LO, 0x1122_3344)
    await b.write(CMP_HI, 0x5566_7788)
    for be, expect_lo in ((0b0001, 0x1122_33AA), (0b0010, 0x1122_BBAA), (0b0100, 0x11CC_BBAA),
                          (0b1000, 0xDDCC_BBAA)):
        await b.write(CMP_LO, 0xDDCC_BBAA, be)
        assert (await b.read(CMP_LO))[0] == expect_lo, f"be={be:04b}"
    assert (await b.read(CMP_HI))[0] == 0x5566_7788, "other half untouched"
    await b.write(CMP_HI, 0xFFFF_FFFF, 0b0000)
    assert (await b.read(CMP_HI))[0] == 0x5566_7788, "be=0 writes nothing"
    # mtime byte lanes: only the enabled lane takes write data
    await b.write(TIME_HI, 0xAABB_CCDD, 0b1000)
    assert (await b.read(TIME_HI))[0] >> 24 == 0xAA
    assert (await b.read(TIME_HI))[0] & 0x00FF_FFFF == 0


@cocotb.test()
async def interrupt_asserts_at_compare_and_clears(dut):
    b = await setup(dut)
    target = int(dut.mtime_q.value) + 30
    await set_cmp(b, target)
    for _ in range(60):
        await FallingEdge(dut.clk_i)
        t, c = int(dut.mtime_q.value), int(dut.mtimecmp_q.value)
        assert int(dut.irq_o.value) == int(t >= c), f"mtime={t} cmp={c}"
        if t >= c:
            break
    else:
        raise AssertionError("timer interrupt never asserted")
    assert t == target, "interrupt rises exactly when mtime reaches mtimecmp"
    # level stays asserted while mtime >= mtimecmp, drops when mtimecmp moves up
    await b.idle(5)
    assert int(dut.irq_o.value) == 1
    await set_cmp(b, int(dut.mtime_q.value) + 100)
    await b.idle(1)
    assert int(dut.irq_o.value) == 0


@cocotb.test()
async def compare_write_near_mtime(dut):
    b = await setup(dut)
    # mtimecmp written to a value mtime is about to reach / has just passed
    for delta in (4, 3, 2, 1, 0, -1, -5):
        now = int(dut.mtime_q.value)
        await b.write(CMP_HI, 0)
        await b.write(CMP_LO, (now + delta + 2) & 0xFFFF_FFFF)  # the write lands 1-2 clocks later
        await FallingEdge(dut.clk_i)
        t, c = int(dut.mtime_q.value), int(dut.mtimecmp_q.value)
        assert int(dut.irq_o.value) == int(t >= c)
        await b.write(CMP_LO, 0xFFFF_FFFF)


@cocotb.test()
async def compare_is_64bit_unsigned(dut):
    b = await setup(dut)
    await b.write(TIME_HI, 0x0000_0001)
    await b.write(TIME_LO, 0x0000_0000)
    await b.write(CMP_HI, 0x0000_0001)
    await b.write(CMP_LO, 0x1000_0000)
    await b.idle(2)
    assert int(dut.irq_o.value) == 0, "hi equal, lo below"
    await b.write(CMP_HI, 0x0000_0000)
    await b.idle(1)
    assert int(dut.irq_o.value) == 1, "hi above"
    await b.write(CMP_HI, 0x8000_0000)
    await b.idle(1)
    assert int(dut.irq_o.value) == 0, "compare is unsigned"


@cocotb.test()
async def unmapped_offsets_error(dut):
    b = await setup(dut)
    for off in (0x10, 0x14, 0x7F8, 0xFFC):
        for we in (False, True):
            rd, err = await b.access(off, we, 0xF, 0xFFFF_FFFF)
            assert err, f"offset {off:#x} we={we} must error"
            assert rd == 0
    assert (await b.read(CMP_LO))[0] == 0xFFFF_FFFF
