"""Peripheral-window decode through rtl/soc_fabric.sv (data manager)."""
import cocotb
from cocotb.triggers import FallingEdge

from periph_bus import Bus

UART, GPIO, TIMER = 0x4000_0000, 0x4000_1000, 0x4000_2000
G_OUT, G_DIR, G_IN, G_EN, G_PEND = 0x00, 0x04, 0x08, 0x0C, 0x10
T_LO, T_HI, C_LO, C_HI = 0x00, 0x04, 0x08, 0x0C


async def setup(dut):
    b = Bus(dut, fabric=True)
    await b.reset(gpio_i=0, uart_rxd_i=1)
    return b


@cocotb.test()
async def pages_reach_their_peripheral(dut):
    b = await setup(dut)
    assert not await b.write(GPIO + G_OUT, 0xA5)
    assert int(dut.gpio_o.value) == 0xA5
    assert (await b.read(GPIO + G_OUT)) == (0xA5, False)
    # same offsets in the timer page are timer registers, not GPIO
    assert (await b.read(TIMER + C_LO)) == (0xFFFF_FFFF, False)
    assert not await b.write(TIMER + C_LO, 0x1234)
    assert (await b.read(TIMER + C_LO)) == (0x1234, False)
    assert (await b.read(GPIO + G_OUT)) == (0xA5, False), "timer write did not hit GPIO"
    lo, err = await b.read(TIMER + T_LO)
    assert not err and lo > 0, "mtime runs"


@cocotb.test()
async def unused_pages_error(dut):
    b = await setup(dut)
    for base in (0x4000_3000, 0x4000_4000, 0x4000_8000, 0x4000_F000):
        for off in (0x0, 0x4, 0xFFC):
            for we in (False, True):
                rd, err = await b.access(base + off, we, 0xF, 0xFFFF_FFFF)
                assert err, f"{base + off:#x} we={we} must be an OBI error"
                assert rd == 0
    # nothing above changed the mapped peripherals
    assert (await b.read(GPIO + G_OUT)) == (0, False)
    assert (await b.read(TIMER + C_HI)) == (0xFFFF_FFFF, False)


@cocotb.test()
async def unmapped_offsets_inside_mapped_pages_error(dut):
    b = await setup(dut)
    for a in (GPIO + 0x14, GPIO + 0xFFC, TIMER + 0x10, TIMER + 0xFFC):
        _, err = await b.read(a)
        assert err, f"{a:#x}"
        assert await b.write(a, 1)


@cocotb.test()
async def bounded_latency_no_hang(dut):
    """Back-to-back mixed accesses: each is granted at once and answered one cycle later."""
    b = await setup(dut)
    addrs = [GPIO + G_DIR, UART + 0x4, TIMER + T_LO, 0x4000_3000, GPIO + 0x40, TIMER + C_HI, 0x4001_0000]
    for a in addrs * 2:
        await b.read(a)  # Bus.access asserts gnt in the request cycle and rvalid one cycle later


@cocotb.test()
async def interrupt_lines(dut):
    b = await setup(dut)
    assert int(dut.irq_timer_o.value) == 0 and int(dut.irq_gpio_o.value) == 0
    # GPIO
    await b.write(GPIO + G_EN, 0x02)
    dut.gpio_i.value = 0x02
    await b.idle(4)
    assert int(dut.irq_gpio_o.value) == 1
    await b.write(GPIO + G_PEND, 0x02)
    await b.idle(1)
    assert int(dut.irq_gpio_o.value) == 0
    # timer
    await b.write(TIMER + C_HI, 0)
    await b.write(TIMER + C_LO, 0)
    await b.idle(1)
    assert int(dut.irq_timer_o.value) == 1
    await b.write(TIMER + C_LO, 0xFFFF_FFFF)
    await b.write(TIMER + C_HI, 0xFFFF_FFFF)
    await b.idle(1)
    assert int(dut.irq_timer_o.value) == 0


@cocotb.test()
async def instruction_manager_cannot_reach_window(dut):
    b = await setup(dut)
    d = dut
    for a in (GPIO, TIMER):
        d.i_req_i.value = 1
        d.i_addr_i.value = a
        d.i_we_i.value = 0
        await FallingEdge(d.clk_i)
        d.i_req_i.value = 0
        assert int(d.i_rvalid_o.value) == 1 and int(d.i_err_o.value) == 1
        await FallingEdge(d.clk_i)
