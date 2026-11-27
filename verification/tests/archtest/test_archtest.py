"""ACT4 self-checking architecture tests on rtl/soc_top.sv (issue #49).

One cocotb test per test image that riscv-arch-test (ACT4, pinned in
reuse.lock.json) selected for this SoC.  Each test loads its image into the
testbench-only RAM, comes out of reset, and waits for ACT4's own self-check to
halt the core: on the DUT a test ends in RVMODEL_HALT_PASS or RVMODEL_HALT_FAIL
(dut/rvmodel_macros.h), which writes a result code to the first word of the
D-SRAM.  The test passes when that code is the pass code.  The fail code, any
other code, a hang, or a malformed UART frame fails it, with the test's console
transcript in the message.

**The DUT is `dut.u_soc`.**  The request's top level is soc_top_archtest.sv, a
wrapper with no logic that hands the suite the two things it cannot give
rtl/soc_top.sv from outside: `ISRAM_AW` and the boot ROM image.

**The RAM.**  No ACT4 image fits the shipped 8 KB instruction SRAM, so the
wrapper elaborates `soc_top` with `ISRAM_AW = 17`: the instruction SRAM of
rtl/soc_fabric.sv, 512 KB deep, at its ratified base 0x1000_0000.  The crossbar
derives its decode from the same parameter (rtl/obi_xbar.sv), so instruction
fetch (port 1) and data accesses (port 0) reach one flat RAM behind the fabric.
No RTL changes and the shipped build keeps `ISRAM_AW = 11`; the RAM is not the
ratified memory map (spec/soc.md § Memory map).  The RAM is not reset, so an
image is loaded while reset is held: the previous test has stopped by then,
and the result block is zeroed after the load.

**The boot ROM.**  The reset vector is the boot ROM, whose image is a jump to
the tests' entry point (scripts/build-archtest.sh; TEST_BASE of dut/link.ld,
where RVTEST_BEGIN puts `rvtest_entry_point`).

**What is shared, what is not.**  `Soc` is `soc_top_bench.SocTop`
(verification/tests/lib/soc_top_bench.py): the clock, the D-SRAM result block
and its preload, stated once there for tests/boot and tests/soc as well.  The
reset sequence below is that module's (`SocTop.reset`), with the image loaded
between the rising edges and the release; it is spelled out here rather than
shared because no other bench has anything to do while reset is held.  The
UART decoder is this testbench's own: tests/soc decodes a known number of bytes,
this one follows whatever the test prints.

build/archtest/manifest.json (scripts/build-archtest.sh) lists the selected
tests and their images; `ARCHTEST_MANIFEST` overrides where it is read from.
"""
import hashlib
import json
import os
import struct
import sys
from pathlib import Path

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer, ValueChange
from cocotb.utils import get_sim_time

# The shared bench core lives in tests/lib. verification/cocotb.mk puts that
# directory on PYTHONPATH for the Makefile targets; klt 0.9.2 accepts one
# testbench.search_path directory and it has to be the one holding this
# module, so the bench adds tests/lib itself.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

from soc_top_bench import CLOCK_NS, RESET_CYCLES, SocTop  # noqa: E402

MANIFEST = Path(os.environ.get("ARCHTEST_MANIFEST") or Path(__file__).resolve().parents[3] / "build" / "archtest" / "manifest.json")
#: A test name (`make -C verification archtest-negative` sets it): the bench
#: corrupts that test's first reference result before loading it.
PERTURB = os.environ.get("ARCHTEST_PERTURB", "")

#: Clocks a test may run after reset before it fails as hung.  The longest
#: selected test takes 0.3 % of it (verification/records/archtest).
TIMEOUT_CYCLES = 50_000_000
#: Clocks between reads of the result block.
POLL_CLOCKS = 200
#: uart_txd_o bit period in clocks: dut/rvmodel_macros.h programs UART DIV = 3,
#: and a bit lasts DIV + 1 clocks (record 0005).
UART_BIT_CLOCKS = 4


def read_manifest():
    try:
        manifest = json.loads(MANIFEST.read_text())
        for test in manifest["tests"]:
            data = (MANIFEST.parent / test["image"]).read_bytes()
            if hashlib.sha256(data).hexdigest() != test["image_sha256"]:
                raise ValueError(f"{test['image']}: image SHA-256 differs from the manifest")
            test["bytes"] = data
    except (OSError, ValueError, KeyError) as e:
        raise RuntimeError(f"no readable test manifest at {MANIFEST} (scripts/build-archtest.sh writes it): {e}") from None
    return manifest


class Console:
    """Decodes 8N1 frames from uart_txd_o into `text` as the test sends them;
    `errors` collects the frames that were not 8N1."""

    def __init__(self, dut):
        self.dut = dut
        self.text = ""
        self.errors = []

    async def run(self):
        txd = self.dut.uart_txd_o
        bit = Timer(UART_BIT_CLOCKS * CLOCK_NS, unit="ns")
        while True:
            await ValueChange(txd)
            if int(txd.value) != 0:
                continue  # not a start bit
            await Timer(UART_BIT_CLOCKS * CLOCK_NS // 2, unit="ns")  # centre of the start bit
            if int(txd.value) != 0:
                self.errors.append("start bit glitch")
                continue
            byte = 0
            for k in range(8):
                await bit
                byte |= int(txd.value) << k
            await bit
            if int(txd.value) == 1:
                self.text += chr(byte)
            else:
                self.errors.append(f"bad stop bit after byte {byte:#04x}")


class Soc(SocTop):
    """SocTop plus the test RAM, the image load and the UART console."""

    def __init__(self, dut):
        super().__init__(dut)
        self.ram = dut.u_fabric.g_isram_1rw1r.u_isram.mem
        self.console = Console(dut)

    async def reset_with_image(self, test, ram_base):
        """Hold `rst_ni` low for RESET_CYCLES rising edges, load the image and
        zero the result block meanwhile, release on a falling edge.  Returns
        the release time in clocks."""
        d = self.dut
        d.rst_ni.value = 0
        for _ in range(RESET_CYCLES):
            await RisingEdge(d.clk_i)
        self.load(test, ram_base)
        self.preload()
        await FallingEdge(d.clk_i)
        d.rst_ni.value = 1
        return get_sim_time(unit="ns") // CLOCK_NS

    def load(self, test, ram_base):
        """Write the image into the test RAM at its load address."""
        data = bytearray(test["bytes"])
        if test["name"].removesuffix(".S") == PERTURB:
            # make archtest-negative: corrupt the first reference result after
            # the canary; the self-check must then halt with the fail code.
            data[test["signature"][0] + 4 - test["load_address"]] ^= 1
            self.dut._log.warning("%s: one bit of its first reference result flipped (ARCHTEST_PERTURB)", test["name"])
        first = (test["load_address"] - ram_base) // 4
        assert test["load_address"] % 4 == 0 and len(data) % 4 == 0, "image is not a whole number of words"
        assert 0 <= first and first + len(data) // 4 <= len(self.ram), "image lies outside the test RAM"
        for i, word in enumerate(struct.unpack(f"<{len(data) // 4}I", data)):
            self.ram[first + i].value = word


async def run_act_test(dut, manifest, test):
    soc = Soc(dut.u_soc)  # the soc_top instance under the testbench top
    ram = manifest["ram"]
    halt = soc.mem[manifest["halt"]["word"]]
    assert len(soc.ram) == ram["words"], f"the DUT's instruction SRAM holds {len(soc.ram)} words, the manifest was built for {ram['words']}"
    soc.start_clock()
    console = cocotb.start_soon(soc.console.run())
    try:
        started = await soc.reset_with_image(test, ram["base"])
        code = 0
        poll = Timer(POLL_CLOCKS * CLOCK_NS, unit="ns")
        while code == 0 and get_sim_time(unit="ns") // CLOCK_NS - started < TIMEOUT_CYCLES:
            await poll
            code = int(halt.value)
        await Timer(12 * UART_BIT_CLOCKS * CLOCK_NS, unit="ns")  # the last frame leaves the wire
    finally:
        console.cancel()
    text = soc.console.text
    dut._log.info("console:\n%s", text)
    name = test["name"]
    if code == 0:
        raise AssertionError(f"{name}: no halt within {TIMEOUT_CYCLES} clocks (hung)\nconsole:\n{text}")
    if soc.console.errors:
        raise AssertionError(f"{name}: {soc.console.errors}\nconsole:\n{text}")
    if code != manifest["halt"]["pass_code"]:
        verdict = "ACT4 self-check FAILED" if code == manifest["halt"]["fail_code"] else f"unexpected halt code {code:#x}"
        raise AssertionError(f"{name}: {verdict}\nconsole:\n{text}")
    dut._log.info("%s: ACT4 self-check passed after %d clocks", name, get_sim_time(unit="ns") // CLOCK_NS - started)


def build_tests(manifest):
    """One cocotb test per selected ACT4 test, named after it (without .S)."""
    for test in manifest["tests"]:
        name = test["name"].removesuffix(".S")

        def make(test=test):
            async def archtest(dut):
                await run_act_test(dut, manifest, test)

            return archtest

        yield name, make()


if MANIFEST.is_file():
    for _name, _test in build_tests(read_manifest()):
        globals()[f"test_{_name.replace('/', '_').replace('-', '_').replace('.', '_')}"] = cocotb.test(name=_name)(_test)
    del _name, _test
else:

    @cocotb.test()
    async def manifest_missing(dut):
        """Fails, naming the build step, rather than registering no test at all."""
        raise RuntimeError(f"no test manifest at {MANIFEST}: run scripts/build-archtest.sh, which make -C verification archtest does")
