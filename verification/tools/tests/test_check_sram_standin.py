"""Test for check_sram_standin.py: the committed stand-in passes, any other difference fails.

    python3 -I verification/tools/tests/test_check_sram_standin.py

Needs the pinned macro Verilog, so run scripts/fetch-sram-macro.sh first (or
verification/tools/check_sram_standin.py once, which fetches it). The altered-pinned
cases pass --unpinned, because altering the pinned text necessarily breaks its sha256.
"""
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CHECK = HERE.parent / "check_sram_standin.py"
STANDIN = ROOT / "verification" / "models" / "sky130_sram_2kbyte_1rw1r_32x512_8_standin.v"
PINNED = ROOT / "build" / "sram_macro" / "sky130_sram_2kbyte_1rw1r_32x512_8.v"


def run(pinned, standin, unpinned=False):
    cmd = [sys.executable, "-I", str(CHECK), "--pinned", str(pinned), "--standin", str(standin)]
    if unpinned:
        cmd.append("--unpinned")
    return subprocess.run(cmd, capture_output=True, text=True)


def edit(path, old, new, count=1):
    text = path.read_text()
    assert text.count(old) == count, f"{old!r} occurs {text.count(old)} times in {path}, want {count}"
    path.write_text(text.replace(old, new))


class CheckSramStandin(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not PINNED.exists():
            raise unittest.SkipTest(f"{PINNED} missing: run scripts/fetch-sram-macro.sh first")

    def copies(self, d):
        """(pinned, standin) copies in `d`, both unaltered."""
        pinned, standin = Path(d) / PINNED.name, Path(d) / STANDIN.name
        shutil.copy(PINNED, pinned)
        shutil.copy(STANDIN, standin)
        return pinned, standin

    # --- the committed state passes, with the real pin check on ---

    def test_committed_standin_passes(self):
        r = run(PINNED, STANDIN)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("skipped", r.stderr)

    # --- a stand-in difference outside ALLOWED_EDITS fails, naming the line ---

    def test_altered_write_mask_slice_fails(self):
        with tempfile.TemporaryDirectory() as d:
            pinned, standin = self.copies(d)
            edit(standin, "mem[addr0_reg][23:16] = din0_reg[23:16];",
                 "mem[addr0_reg][23:16] = din0_reg[31:24];")
            r = run(pinned, standin)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("not in ALLOWED_EDITS", r.stderr)
            self.assertIn("-mem[addr0_reg][23:16] = din0_reg[23:16];", r.stderr)
            self.assertIn("+mem[addr0_reg][23:16] = din0_reg[31:24];", r.stderr)

    def test_altered_delay_fails(self):
        with tempfile.TemporaryDirectory() as d:
            pinned, standin = self.copies(d)
            edit(standin, "parameter DELAY = 3 ;", "parameter DELAY = 4 ;")
            r = run(pinned, standin)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("+parameter DELAY = 4 ;", r.stderr)

    def test_dropped_statement_fails(self):
        """A removal the allowed set does not cover is caught too, not just a change."""
        with tempfile.TemporaryDirectory() as d:
            pinned, standin = self.copies(d)
            edit(standin, "    #(T_HOLD) dout1 = 32'bx;\n", "")
            r = run(pinned, standin)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("-#(T_HOLD) dout1 = 32'bx;", r.stderr)

    def test_extra_statement_fails(self):
        with tempfile.TemporaryDirectory() as d:
            pinned, standin = self.copies(d)
            edit(standin, "endmodule", "initial $display(\"hello\");\nendmodule")
            r = run(pinned, standin)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn('+initial $display("hello");', r.stderr)

    # --- comment-only and whitespace-only changes still pass ---

    def test_comment_only_change_passes(self):
        with tempfile.TemporaryDirectory() as d:
            pinned, standin = self.copies(d)
            edit(standin, "  reg  csb0_reg;", "  // an added remark\n  reg  csb0_reg;")
            r = run(pinned, standin)
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_whitespace_only_change_passes(self):
        with tempfile.TemporaryDirectory() as d:
            pinned, standin = self.copies(d)
            edit(standin, "  parameter DELAY = 3 ;", "\n\n        parameter   DELAY  =  3  ;")
            r = run(pinned, standin)
            self.assertEqual(r.returncode, 0, r.stderr)

    # --- an allowed edit that no longer applies to the pinned text fails ---

    def test_allowed_edit_that_no_longer_applies_fails(self):
        """The pin moved under an allowed edit: a skip would silently stop checking it."""
        with tempfile.TemporaryDirectory() as d:
            pinned, standin = self.copies(d)
            edit(pinned, "  parameter VERBOSE = 1 ;", "  parameter VERBOSE = 0 ;")
            r = run(pinned, standin, unpinned=True)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("no longer applies", r.stderr)
            self.assertIn("remove the VERBOSE parameter", r.stderr)
            self.assertIn("found 0", r.stderr)

    def test_allowed_edit_matching_twice_fails(self):
        """An ambiguous match is a failure, not a first-hit guess."""
        with tempfile.TemporaryDirectory() as d:
            pinned, standin = self.copies(d)
            edit(pinned, "  parameter VERBOSE = 1 ;",
                 "  parameter VERBOSE = 1 ;\n  parameter VERBOSE = 1 ;")
            r = run(pinned, standin, unpinned=True)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("no longer applies", r.stderr)
            self.assertIn("found 2", r.stderr)

    # --- the pin itself is checked ---

    def test_unpinned_macro_fails_the_sha256_check(self):
        with tempfile.TemporaryDirectory() as d:
            pinned, standin = self.copies(d)
            edit(pinned, "// OpenRAM SRAM model", "// OpenRAM SRAM model (tampered)")
            r = run(pinned, standin)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("reuse.lock.json pins", r.stderr)

    # --- every allowed edit must be documented in the stand-in header ---

    def test_undocumented_allowed_edit_fails(self):
        with tempfile.TemporaryDirectory() as d:
            pinned, standin = self.copies(d)
            text = standin.read_text()
            tag = "added `timescale`"
            self.assertIn(tag, text)
            standin.write_text(text.replace(tag, "added a directive", 1))
            r = run(pinned, standin)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("not documented in the stand-in header", r.stderr)
            self.assertIn(tag, r.stderr)

    def test_every_allowed_edit_tag_is_in_the_header(self):
        """Read the tags out of the script and require each in the committed header."""
        tags = set(re.findall(r'^\s*"header": "(.*)",$', CHECK.read_text(), re.M))
        self.assertTrue(tags, "no header tags found in check_sram_standin.py")
        header = STANDIN.read_text()
        for tag in sorted(tags):
            self.assertIn(tag.replace('\\"', '"'), header)


if __name__ == "__main__":
    unittest.main()
