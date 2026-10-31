"""UART register, TX/RX waveform and interrupt tests for rtl/uart.sv."""
import cocotb
from cocotb.triggers import FallingEdge

from periph_bus import Bus

DATA, STATUS, CTRL, DIV = 0x00, 0x04, 0x08, 0x0C
TX_BUSY, RX_VALID, OVR, FE, TX_ACTIVE = 1, 2, 4, 8, 16
DIVISOR = 7            # bit period = 8 clocks
BIT = DIVISOR + 1


async def setup(dut, div=DIVISOR):
    b = Bus(dut)
    await b.reset(rxd_i=1)
    if div is not None:
        assert not await b.write(DIV, div)
    return b


async def clocks(dut, n):
    for _ in range(n):
        await FallingEdge(dut.clk_i)


async def capture_frame(dut, bit=BIT, timeout=200):
    """Wait for a start bit on txd_o, then return (start, data byte, stop, bit-edge spacings)."""
    for _ in range(timeout):
        if int(dut.txd_o.value) == 0:
            break
        await FallingEdge(dut.clk_i)
    else:
        raise AssertionError("no start bit")
    bits, spacings, last = [], [], int(dut.txd_o.value)
    run = 0
    # sample each bit in its middle, and check every bit lasts exactly `bit` clocks
    for i in range(10):
        vals = []
        for _ in range(bit):
            vals.append(int(dut.txd_o.value))
            await FallingEdge(dut.clk_i)
        assert len(set(vals)) == 1, f"bit {i} not stable for {bit} clocks: {vals}"
        bits.append(vals[0])
    return bits


def frame_bits(byte):
    return [0] + [(byte >> i) & 1 for i in range(8)] + [1]


async def drive_frame(dut, byte, bit=BIT, stop=1):
    for v in frame_bits(byte)[:-1] + [stop]:
        dut.rxd_i.value = v
        await clocks(dut, bit)
    dut.rxd_i.value = 1


@cocotb.test()
async def reset_values(dut):
    b = await setup(dut, div=None)
    assert (await b.read(DATA)) == (0, False)
    assert (await b.read(STATUS)) == (0, False)
    assert (await b.read(CTRL)) == (0, False)
    assert (await b.read(DIV)) == (433, False)
    assert int(dut.txd_o.value) == 1 and int(dut.irq_uart_o.value) == 0


@cocotb.test()
async def register_access_and_errors(dut):
    b = await setup(dut)
    assert not await b.write(CTRL, 0xFFFF_FFFF)
    assert (await b.read(CTRL))[0] == 0x3
    await b.write(CTRL, 0, 0b0010)
    assert (await b.read(CTRL))[0] == 0x3, "be[0] clear must not write"
    await b.write(CTRL, 0)
    await b.write(DIV, 0xABCD)
    assert (await b.read(DIV))[0] == 0xABCD
    await b.write(DIV, 0x1111_1100, 0b0010)
    assert (await b.read(DIV))[0] == 0x11CD, "byte lane 1 writes DIV[15:8]"
    for off in (0x10, 0x14, 0xFFC):
        for we in (False, True):
            rd, err = await b.access(off, we, 0xF, 1)
            assert err and rd == 0, f"{off:#x} we={we}"
    # STATUS RO bits ignore writes
    await b.write(STATUS, 0xFF)
    assert (await b.read(STATUS))[0] == 0


@cocotb.test()
async def tx_waveform(dut):
    b = await setup(dut)
    for byte in (0xA5, 0x00, 0xFF, 0x01):
        await b.write(DATA, byte)
        bits = await capture_frame(dut)
        assert bits == frame_bits(byte), f"{byte:#x}: {bits}"
        await clocks(dut, 3)
        assert int(dut.txd_o.value) == 1, "line idles high"


@cocotb.test()
async def tx_status_and_busy_write(dut):
    b = await setup(dut)
    wave = []

    async def probe():
        while True:
            await FallingEdge(dut.clk_i)
            wave.append(int(dut.txd_o.value))

    p = cocotb.start_soon(probe())
    await b.write(DATA, 0x55)
    # first byte moves to the shifter at once, holding register frees
    await b.idle(2)
    st = (await b.read(STATUS))[0]
    assert st & TX_ACTIVE and not st & TX_BUSY, st
    await b.write(DATA, 0x66)              # holding register: accepted
    st = (await b.read(STATUS))[0]
    assert st & TX_BUSY
    await b.write(DATA, 0x77)              # holding register full: dropped
    await clocks(dut, 22 * BIT)
    p.cancel()
    assert (await b.read(STATUS))[0] & (TX_BUSY | TX_ACTIVE) == 0
    start = wave.index(0)
    exp = frame_bits(0x55) + frame_bits(0x66)
    got = [wave[start + i * BIT] for i in range(20)]
    assert got == exp, f"{got} != {exp}"
    # every bit lasts exactly BIT clocks, the second start bit follows the first stop bit with no gap
    for i in range(20):
        assert set(wave[start + i * BIT:start + (i + 1) * BIT]) == {exp[i]}, i
    assert set(wave[start + 20 * BIT:]) == {1}, "0x77 was dropped, line idles high"


@cocotb.test()
async def rx_frame_and_back_to_back(dut):
    b = await setup(dut)
    for byte in (0x3C, 0xC3):
        await drive_frame(dut, byte)
        await clocks(dut, 2)
        st, _ = await b.read(STATUS)
        assert st & RX_VALID and not st & (OVR | FE), st
        assert (await b.read(DATA)) == (byte, False)
        assert not (await b.read(STATUS))[0] & RX_VALID, "reading DATA clears RX_VALID"
    # two frames with no idle time between stop and next start
    await drive_frame(dut, 0x81)
    await clocks(dut, 1)
    assert (await b.read(DATA))[0] == 0x81
    await drive_frame(dut, 0x7E)
    await clocks(dut, 2)
    assert (await b.read(DATA))[0] == 0x7E


@cocotb.test()
async def rx_back_to_back_without_gap(dut):
    b = await setup(dut)
    got = []

    async def reader():
        for _ in range(2):
            while not (await b.read(STATUS))[0] & RX_VALID:
                pass
            got.append((await b.read(DATA))[0])

    r = cocotb.start_soon(reader())
    await drive_frame(dut, 0x12)
    await drive_frame(dut, 0x34)
    await clocks(dut, 4 * BIT)
    await r
    assert got == [0x12, 0x34], got


@cocotb.test()
async def rx_start_glitch_ignored(dut):
    b = await setup(dut)
    dut.rxd_i.value = 0
    await clocks(dut, BIT // 2 - 2)         # shorter than half a bit
    dut.rxd_i.value = 1
    await clocks(dut, 20 * BIT)
    st, _ = await b.read(STATUS)
    assert st == 0, f"glitch must not produce a frame: {st:#x}"


@cocotb.test()
async def rx_framing_error(dut):
    b = await setup(dut)
    await drive_frame(dut, 0x5A, stop=0)
    await clocks(dut, 1)
    # line held low (break): one error, no byte, no endless re-triggering
    await clocks(dut, 30 * BIT)
    st, _ = await b.read(STATUS)
    assert st == FE, f"{st:#x}"
    dut.rxd_i.value = 1
    await clocks(dut, 3)
    await b.write(STATUS, FE)
    assert (await b.read(STATUS))[0] == 0
    await drive_frame(dut, 0x99)
    await clocks(dut, 2)
    assert (await b.read(DATA))[0] == 0x99


@cocotb.test()
async def rx_overrun_keeps_first_byte(dut):
    b = await setup(dut)
    await drive_frame(dut, 0x11)
    await drive_frame(dut, 0x22)            # first byte unread: dropped
    await clocks(dut, 2)
    st, _ = await b.read(STATUS)
    assert st & RX_VALID and st & OVR, st
    assert (await b.read(DATA))[0] == 0x11, "the unread byte is kept"
    st, _ = await b.read(STATUS)
    assert not st & RX_VALID and st & OVR, "OVERRUN is sticky"
    await b.write(STATUS, OVR)
    assert (await b.read(STATUS))[0] == 0, "write 1 clears OVERRUN"
    await b.write(STATUS, 0)                # writing 0 clears nothing
    await drive_frame(dut, 0x33)
    await clocks(dut, 2)
    assert (await b.read(DATA))[0] == 0x33


@cocotb.test()
async def interrupts(dut):
    b = await setup(dut)
    assert int(dut.irq_uart_o.value) == 0
    await b.write(CTRL, 0b01)               # TX_IE: holding register empty
    await b.idle(1)
    assert int(dut.irq_uart_o.value) == 1
    await b.write(DATA, 0xA1)
    await b.idle(2)
    await b.write(DATA, 0xA2)               # fills the holding register
    await b.idle(1)
    assert int(dut.irq_uart_o.value) == 0, "TX irq is low while holding register full"
    await clocks(dut, 12 * BIT)
    assert int(dut.irq_uart_o.value) == 1
    await b.write(CTRL, 0b10)               # RX_IE only
    await b.idle(1)
    assert int(dut.irq_uart_o.value) == 0
    await drive_frame(dut, 0x42)
    await clocks(dut, 2)
    assert int(dut.irq_uart_o.value) == 1
    assert (await b.read(DATA))[0] == 0x42
    await b.idle(1)
    assert int(dut.irq_uart_o.value) == 0, "reading DATA clears the RX interrupt"
    await b.write(CTRL, 0)
    await drive_frame(dut, 0x43)
    await clocks(dut, 2)
    assert int(dut.irq_uart_o.value) == 0, "disabled"


@cocotb.test()
async def divisor_change_while_idle(dut):
    b = await setup(dut, div=3)
    await b.write(DATA, 0xC9)
    assert await capture_frame(dut, bit=4) == frame_bits(0xC9)
    await clocks(dut, 40)
    await b.write(DIV, 11)
    await b.write(DATA, 0x36)
    assert await capture_frame(dut, bit=12) == frame_bits(0x36)
    await clocks(dut, 24)
    await drive_frame(dut, 0x6D, bit=12)
    await clocks(dut, 2)
    assert (await b.read(DATA))[0] == 0x6D
