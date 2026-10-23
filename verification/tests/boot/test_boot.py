"""RTL boot test for rtl/soc_top.sv: CVE2 + fabric running firmware/boot.

The ROM image is firmware/boot/boot_rom.hex (generated from boot.S). The
firmware writes a signature to D-SRAM, reads two unmapped addresses (the OBI
error becomes a load-access-fault trap that the firmware steps over), records
the trap state, and spins. Result block layout is documented in boot.S.
Every wait is bounded by a cycle timeout so a hang fails the test.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge

SIG, RESUME = 0x600DC0DE, 0xD00DFEED
UNMAP_A, UNMAP_B = 0x4000_3000, 0x3000_0000
LOAD_ACCESS_FAULT = 5
TIMEOUT = 3000  # cycles; the whole run takes well under 200

OFF = dict(sig=0, mtvec=1, traps=2, mcause=3, mepc=4, mtval=5, resume=6, boots=7)


class Soc:
    def __init__(self, dut):
        self.dut = dut
        self.mem = dut.u_fabric.u_dsram.mem
        self.cycles = 0
        self.err_log = []  # (cycle, address) of every data-side OBI error
        self.pending = None

    def word(self, name):
        return int(self.mem[OFF[name]].value)

    def start(self):
        cocotb.start_soon(Clock(self.dut.clk_i, 20, unit="ns").start())
        cocotb.start_soon(self._monitor())

    async def _monitor(self):
        d = self.dut
        while True:
            await RisingEdge(d.clk_i)
            self.cycles += 1
            if int(d.rst_ni.value) == 0:
                self.pending = None
                continue
            try:
                if self.pending is not None and int(d.data_rvalid.value) and int(d.data_err.value):
                    self.err_log.append((self.cycles, self.pending))
                self.pending = int(d.data_addr.value) if int(d.data_req.value) and int(d.data_gnt.value) else None
            except ValueError:  # X before the first defined cycle
                self.pending = None

    async def reset(self, cycles=4):
        self.dut.rst_ni.value = 0
        for _ in range(cycles):
            await RisingEdge(self.dut.clk_i)
        await FallingEdge(self.dut.clk_i)
        self.dut.rst_ni.value = 1

    async def run_until_resume(self):
        for _ in range(TIMEOUT):
            await RisingEdge(self.dut.clk_i)
            if self.word("resume") == RESUME:
                return
        raise AssertionError(f"boot did not finish in {TIMEOUT} cycles (hang?)")


def init_dsram(soc):
    for i in range(8):
        soc.mem[i].value = 0


@cocotb.test()
async def boot_signature_and_unmapped_read(dut):
    soc = Soc(dut)
    init_dsram(soc)
    soc.start()
    await soc.reset()
    await soc.run_until_resume()
    assert soc.word("sig") == SIG, f"signature {soc.word('sig'):#x}"
    assert soc.word("traps") == 2, f"expected 2 load faults, got {soc.word('traps')}"
    assert soc.word("mcause") == LOAD_ACCESS_FAULT, f"mcause {soc.word('mcause'):#x}"
    assert soc.word("boots") == 1
    errs = [a for _, a in soc.err_log]
    assert errs == [UNMAP_A, UNMAP_B], [hex(a) for a in errs]
    dut._log.info("unmapped-access trace (cycle, addr): %s",
                  [(c, hex(a)) for c, a in soc.err_log])
    dut._log.info("mtvec readback %#x, last mepc %#x, mtval %#x",
                  soc.word("mtvec"), soc.word("mepc"), soc.word("mtval"))


@cocotb.test()
async def trap_vector_behaviour(dut):
    """Records what the boot test observes about mtvec (spec/soc.md 'unverified')."""
    soc = Soc(dut)
    init_dsram(soc)
    soc.start()
    await soc.reset()
    await soc.run_until_resume()
    # boot_addr_i = 0 -> mtvec = {boot_addr[31:8], 6'b0, 2'b01}: base 0, vectored.
    assert soc.word("mtvec") == 0x0000_0001, f"mtvec {soc.word('mtvec'):#x}"
    # The trap handler ran from offset 0 (the shared reset/exception entry): the
    # firmware only counts a trap when entry at 0x0 saw non-zero mcause.
    assert soc.word("traps") == 2


@cocotb.test()
async def reset_mid_run_restarts_from_zero(dut):
    soc = Soc(dut)
    init_dsram(soc)
    soc.start()
    await soc.reset()
    for _ in range(30):  # part-way through the run, before the first fault retires
        await RisingEdge(dut.clk_i)
    assert soc.word("resume") != RESUME
    await soc.reset()
    await soc.run_until_resume()
    assert soc.word("sig") == SIG and soc.word("traps") == 2
    boots_after_midrun = soc.word("boots")
    assert boots_after_midrun == 2, f"two boot attempts expected, got {boots_after_midrun}"
    # reset after completion: clear the evidence, the firmware must rewrite it
    soc.mem[OFF["sig"]].value = 0
    soc.mem[OFF["resume"]].value = 0
    await soc.reset()
    await soc.run_until_resume()
    assert soc.word("sig") == SIG and soc.word("traps") == 2
    assert soc.word("boots") == 3
