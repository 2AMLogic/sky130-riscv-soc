"""GPIO register, synchroniser and interrupt tests for rtl/gpio.sv."""
import cocotb
from cocotb.triggers import FallingEdge

from periph_bus import Bus

OUT, DIR, IN, IRQ_EN, IRQ_PEND = 0x00, 0x04, 0x08, 0x0C, 0x10


async def setup(dut):
    b = Bus(dut)
    await b.reset(gpio_i=0)
    return b


@cocotb.test()
async def reset_values(dut):
    b = await setup(dut)
    for off in (OUT, DIR, IN, IRQ_EN, IRQ_PEND):
        rd, err = await b.read(off)
        assert rd == 0 and not err, f"reg {off:#x} = {rd:#x} err={err}"
    assert int(dut.gpio_o.value) == 0 and int(dut.gpio_oe_o.value) == 0
    assert int(dut.irq_o.value) == 0


@cocotb.test()
async def read_write_and_byte_enables(dut):
    b = await setup(dut)
    for off, pin in ((OUT, dut.gpio_o), (DIR, dut.gpio_oe_o)):
        assert not await b.write(off, 0xFFFF_FFA5)
        rd, _ = await b.read(off)
        assert rd == 0xA5, "upper write bits are dropped, reads zero-extend"
        assert int(pin.value) == 0xA5, "register drives its output pin vector"
        # byte lanes other than 0 do not touch the 8-bit register
        for be in (0b0010, 0b0100, 0b1000, 0b1110):
            await b.write(off, 0x0000_00FF, be)
            rd, _ = await b.read(off)
            assert rd == 0xA5, f"be={be:04b} must not write"
        await b.write(off, 0x1234_5600, 0b1111 ^ 0b0001)
        assert (await b.read(off))[0] == 0xA5
        await b.write(off, 0x0000_005A, 0b0001)
        assert (await b.read(off))[0] == 0x5A
    # DATA_IN is read-only: a write is ignored
    assert not await b.write(IN, 0xFF)
    assert (await b.read(IN))[0] == 0


@cocotb.test()
async def input_has_two_flop_synchroniser(dut):
    b = await setup(dut)
    dut.gpio_i.value = 0x3C
    # back-to-back reads accept on consecutive edges: the pin value reaches
    # DATA_IN at the third, i.e. after two flops
    seen = [(await b.read(IN))[0] for _ in range(4)]
    assert seen == [0, 0, 0x3C, 0x3C], [hex(x) for x in seen]


@cocotb.test()
async def input_change_inside_synchroniser_window(dut):
    b = await setup(dut)
    # a one-cycle pulse still propagates (sampled, not lost); a pulse shorter
    # than a clock period is outside the synchroniser's contract
    dut.gpio_i.value = 0x01
    await FallingEdge(dut.clk_i)
    dut.gpio_i.value = 0x00
    await b.idle(3)
    rd, _ = await b.read(IRQ_PEND)
    assert rd == 0x01, "one-cycle pulse is captured as a rising edge"
    await b.write(IRQ_PEND, 0x01)
    # change while the previous value is still in the synchroniser
    dut.gpio_i.value = 0x80
    await FallingEdge(dut.clk_i)
    dut.gpio_i.value = 0x40
    await b.idle(3)
    rd, _ = await b.read(IN)
    assert rd == 0x40
    rd, _ = await b.read(IRQ_PEND)
    assert rd == 0xC0, "both pins saw a rising edge"


@cocotb.test()
async def interrupt_assert_and_clear(dut):
    b = await setup(dut)
    await b.write(IRQ_EN, 0x01)
    dut.gpio_i.value = 0x01
    await b.idle(4)
    assert int(dut.irq_o.value) == 1
    assert (await b.read(IRQ_PEND))[0] == 0x01
    # writing 0 or a different bit does not clear it
    await b.write(IRQ_PEND, 0x00)
    await b.write(IRQ_PEND, 0x02)
    assert int(dut.irq_o.value) == 1
    # write-1-to-clear
    await b.write(IRQ_PEND, 0x01)
    await b.idle(1)
    assert int(dut.irq_o.value) == 0
    assert (await b.read(IRQ_PEND))[0] == 0
    # a falling edge does not set pending
    dut.gpio_i.value = 0x00
    await b.idle(4)
    assert (await b.read(IRQ_PEND))[0] == 0 and int(dut.irq_o.value) == 0
    # a new rising edge sets it again
    dut.gpio_i.value = 0x01
    await b.idle(4)
    assert int(dut.irq_o.value) == 1


@cocotb.test()
async def interrupt_enable_masks_output_not_pending(dut):
    b = await setup(dut)
    dut.gpio_i.value = 0x10
    await b.idle(4)
    assert int(dut.irq_o.value) == 0
    assert (await b.read(IRQ_PEND))[0] == 0x10, "pending records edges while disabled"
    await b.write(IRQ_EN, 0x10)
    await b.idle(1)
    assert int(dut.irq_o.value) == 1
    await b.write(IRQ_EN, 0x00)
    await b.idle(1)
    assert int(dut.irq_o.value) == 0


@cocotb.test()
async def unmapped_offsets_error(dut):
    b = await setup(dut)
    for off in (0x14, 0x18, 0x7C, 0x800, 0xFFC):
        for we in (False, True):
            rd, err = await b.access(off, we, 0xF, 0xFFFF_FFFF)
            assert err, f"offset {off:#x} we={we} must error"
            assert rd == 0
    # an error leaves state untouched and mapped offsets still work
    assert (await b.read(OUT))[0] == 0
    assert not (await b.read(OUT))[1]
