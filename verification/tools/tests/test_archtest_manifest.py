"""Test for archtest_manifest.py: the checks between an ACT4 build and the bench.

    python3 -I verification/tools/tests/test_archtest_manifest.py

The tool turns an ACT4 selection and its ELFs into the manifest
verification/tests/archtest/test_archtest.py loads. Its inputs are faked here
(a one-segment ELF written byte by byte, shell scripts standing in for the
toolchain's objcopy and nm), so the test needs no toolchain: what is checked is
that a consistent build becomes a manifest and a selection listing, and that
every inconsistency the tool promises to refuse fails with a message naming
the cause.
"""
import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

MANIFEST = Path(__file__).resolve().parents[1] / "archtest_manifest.py"

COMMIT = "00112233445566778899aabbccddeeff00112233"
RAM_ORIGIN = 0x10000000
RAM_LENGTH = 0x80000
TEST_BASE = 0x10004000
WORDS = (0x12345678, 0x9ABCDEF0)
FILE_OFFSET = 0x1000


def elf(entry=TEST_BASE, address=TEST_BASE, machine=243):
    """A little-endian ELF32 RISC-V executable with one PT_LOAD of two words."""
    ident = b"\x7fELF" + bytes([1, 1, 1, 0]) + bytes(8)
    header = ident + struct.pack("<2H5I6H", 2, machine, 1, entry, 52, 0, 0, 52, 32, 1, 40, 0, 0)
    segment = struct.pack("<8I", 1, FILE_OFFSET, address, address, 8, 8, 5, 0x1000)
    data = bytearray(header + segment)
    data += bytes(FILE_OFFSET - len(data))
    data += struct.pack("<2I", *WORDS)
    return bytes(data)


class Fixture:
    """One build on disk: selection, ELF, request, linker script, lock, fake binutils."""

    def __init__(self, root, *, elf_bytes=None, aw=17, symbols=None, locked=True, deselected=None):
        self.root = Path(root)
        out = self.root / "build"
        work = out / "work" / "sky130-riscv-soc"
        (work / "elfs" / "rv32i" / "I").mkdir(parents=True, exist_ok=True)
        (work / "elfs" / "rv32i" / "I" / "I-add-00.elf").write_bytes(elf_bytes if elf_bytes is not None else elf())
        selection = {
            "config": "sky130-riscv-soc",
            "implemented_extensions": ["I"],
            "selected": ["rv32i/I/I-add-00.S"],
            "deselected": deselected if deselected is not None else [
                {"name": "rv32i/F/F-add-00.S", "reasons": ["extension: needs F, which the configuration does not implement"]},
                {"name": "rv32i/F/F-sub-00.S", "reasons": ["extension: needs F, which the configuration does not implement"]},
            ],
        }
        (out / "selection.json").write_text(json.dumps(selection))
        (out / "dut").mkdir(exist_ok=True)
        (out / "dut" / "link.ld").write_text(f"RAM_ORIGIN = {RAM_ORIGIN:#x};\nRAM_LENGTH = {RAM_LENGTH:#x};\nTEST_BASE = {TEST_BASE:#x};\n")
        (out / "request.json").write_text(json.dumps({"parameters": {"ISRAM_AW": aw}}))
        imports = [{"from": "riscv-non-isa/riscv-arch-test", "commit": COMMIT}] if locked else []
        (out / "lock.json").write_text(json.dumps({"schema": 1, "imports": imports}))
        (out / "bin").mkdir(exist_ok=True)
        (out / "bin" / "objcopy").write_text(f'#!/bin/sh\ndd if="$3" of="$4" bs=1 skip={FILE_OFFSET} count=8 2>/dev/null\n')
        symbols = symbols if symbols is not None else f"{TEST_BASE + 4:x} D begin_signature\n{TEST_BASE + 8:x} D end_signature\n"
        (out / "bin" / "nm").write_text(f"#!/bin/sh\nprintf '%s\\n' '{symbols}'\n")
        for tool in ("objcopy", "nm"):
            (out / "bin" / tool).chmod(0o755)
        self.out = out
        self.listing = out / "committed-selection.txt"

    def commit_listing(self, text):
        self.listing.write_text(text)

    def run(self):
        return subprocess.run(
            [sys.executable, "-I", str(MANIFEST), str(self.out / "selection.json"), str(self.out / "work"),
             str(self.out), str(self.out / "dut" / "link.ld"), str(self.out / "request.json"),
             str(self.out / "bin" / "objcopy"), str(self.out / "lock.json"), str(self.listing)],
            capture_output=True, text=True)

    def manifest(self):
        return json.loads((self.out / "manifest.json").read_text())


class ConsistentBuild(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.fx = Fixture(self._tmp.name)

    def listing(self, **kwargs):
        """The listing the tool renders for this fixture, committed ahead of a run."""
        fx = Fixture(self._tmp.name, **kwargs)
        fx.listing.unlink(missing_ok=True)
        self.assertEqual(fx.run().returncode, 1)  # refused: nothing committed yet
        return (fx.out / "selection.txt").read_text()

    def test_build_matches_the_committed_listing_and_becomes_a_manifest(self):
        self.fx.commit_listing(self.listing())
        r = self.fx.run()
        self.assertEqual(r.returncode, 0, r.stderr)
        m = self.fx.manifest()
        self.assertEqual(m["ram"], {"base": RAM_ORIGIN, "words": RAM_LENGTH // 4, "aw": 17})
        self.assertEqual(m["halt"], {"word": 0, "pass_code": 123456789, "fail_code": 1})
        self.assertEqual(m["riscv_arch_test"], COMMIT)
        (test,) = m["tests"]
        self.assertEqual(test["name"], "rv32i/I/I-add-00.S")
        self.assertEqual((test["load_address"], test["entry"]), (TEST_BASE, TEST_BASE))
        self.assertEqual(test["signature"], [TEST_BASE + 4, TEST_BASE + 8])
        self.assertEqual(len(test["elf_sha256"]), 64)
        image = self.fx.out / test["image"]
        self.assertEqual(image.read_bytes(), struct.pack("<2I", *WORDS))  # the ELF's bytes, flattened
        self.assertEqual(test["image_sha256"], hashlib.sha256(image.read_bytes()).hexdigest())
        self.assertEqual(image.parent, self.fx.out / "images" / "rv32i" / "I")

    def test_listing_names_every_selected_and_deselected_test(self):
        text = self.listing()
        self.assertIn(f"riscv-arch-test commit: {COMMIT}\n", text)
        self.assertIn("Candidates: 3   selected: 1   deselected: 2\n", text)
        self.assertIn("\n## Selected\nrv32i/I/I-add-00.S\n", text)
        self.assertIn("\nrv32i/F/ (2 tests): extension: needs F, which the configuration does not implement\n", text)

    def test_listing_covers_a_directory_whose_tests_fail_differently(self):
        text = self.listing(deselected=[
            {"name": "rv32i/F/F-add-00.S", "reasons": ["extension: needs F, which the configuration does not implement"]},
            {"name": "rv32i/F/F-sub-00.S", "reasons": ["extension: needs F, which the configuration does not implement"]},
            {"name": "rv32i/F/F-sub-01.S", "reasons": ["parameter: MXLEN is 32 in the configuration, the test needs 64"]},
        ])
        self.assertIn("\nrv32i/F/ (2 tests, the rest of this directory): extension: needs F", text)
        self.assertIn("\nrv32i/F/F-sub-01.S: parameter: MXLEN is 32", text)

    def test_changed_selection_stops_the_build(self):
        listing = self.listing()
        self.fx.commit_listing(listing)
        self.assertEqual(self.fx.run().returncode, 0)
        self.assertTrue(self.fx.manifest()["tests"])
        self.fx.commit_listing(listing + "stale line\n")
        r = self.fx.run()
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("does not list what riscv-arch-test", r.stderr)
        self.assertFalse((self.fx.out / "manifest.json").exists(), "a refused build left a manifest")

    def test_lock_without_the_import_is_refused(self):
        fx = Fixture(self._tmp.name, locked=False)
        r = fx.run()
        self.assertEqual(r.returncode, 1)
        self.assertIn("expected one riscv-non-isa/riscv-arch-test import, found 0", r.stderr)

    def check_refused(self, message, **kwargs):
        """A build refused for a reason other than its listing: the listing the
        fixture renders is committed first, so that check passes."""
        fx = Fixture(self._tmp.name, **kwargs)
        fx.listing.unlink(missing_ok=True)
        self.assertEqual(fx.run().returncode, 1)
        fx.commit_listing((fx.out / "selection.txt").read_text())
        r = fx.run()
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn(message, r.stderr)
        self.assertFalse((fx.out / "manifest.json").exists(), "a refused build left a manifest")

    def test_request_depth_must_match_the_linker_script(self):
        self.check_refused("parameters.ISRAM_AW is 16", aw=16)

    def test_entry_point_must_be_test_base(self):
        self.check_refused("entry point 0x10004004 is not TEST_BASE", elf_bytes=elf(entry=TEST_BASE + 4))

    def test_segment_outside_the_ram_is_refused(self):
        self.check_refused("outside the test RAM", elf_bytes=elf(address=RAM_ORIGIN - 0x1000))

    def test_non_riscv_elf_is_refused(self):
        self.check_refused("not a little-endian ELF32 RISC-V executable", elf_bytes=elf(machine=62))

    def test_signature_outside_the_image_is_refused(self):
        self.check_refused("signature", symbols=f"{TEST_BASE + 8:x} D begin_signature\n{TEST_BASE + 16:x} D end_signature\n")

    def test_elf_without_signature_symbols_is_refused(self):
        self.check_refused("no begin_signature/end_signature symbols", symbols="10004000 D rvtest_entry_point\n")

    def test_selected_test_without_an_elf_is_refused(self):
        fx = Fixture(self._tmp.name)
        fx.commit_listing(self.listing())
        self.assertEqual(fx.run().returncode, 0)
        (fx.out / "work" / "sky130-riscv-soc" / "elfs" / "rv32i" / "I" / "I-add-00.elf").unlink()
        r = fx.run()
        self.assertEqual(r.returncode, 1)
        self.assertIn("selected test was not built", r.stderr)
        self.assertFalse((fx.out / "manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
