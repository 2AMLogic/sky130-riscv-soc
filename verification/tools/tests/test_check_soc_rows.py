"""Test for check_soc_rows.py: the committed spec passes, drift in any projection fails.

    python3 -I verification/tools/tests/test_check_soc_rows.py
"""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
CHECK = HERE.parent / "check_soc_rows.py"
SPEC = HERE.parents[2] / "spec"
FILES = ("soc.md", "soc.rows.json", "statistical-claims-na.json", "statistical-claims-na.md")


def run(spec):
    return subprocess.run([sys.executable, "-I", str(CHECK), str(spec)],
                          capture_output=True, text=True)


class CheckSocRows(unittest.TestCase):
    def copy(self, d):
        for f in FILES:
            shutil.copy(SPEC / f, d)

    def test_committed_spec_passes(self):
        self.assertEqual(run(SPEC).returncode, 0, run(SPEC).stderr)

    def drift(self, name, old, new):
        with tempfile.TemporaryDirectory() as d:
            self.copy(d)
            p = Path(d) / name
            text = p.read_text()
            self.assertIn(old, text)
            p.write_text(text.replace(old, new, 1))
            r = run(d)
            self.assertEqual(r.returncode, 1)
            self.assertIn("differ" if name != "soc.md" else name.split(".")[0], r.stderr)

    def test_rows_json_drift_fails(self):
        self.drift("soc.rows.json", '"id": "8a"', '"id": "8b"')

    def test_statement_json_drift_fails(self):
        self.drift("statistical-claims-na.json", '"id": "14"', '"id": "15"')

    def test_statement_md_drift_fails(self):
        self.drift("statistical-claims-na.md", "| 14 | Signoff |", "| 15 | Signoff |")

    def test_spec_table_drift_fails(self):
        self.drift("soc.md", "| 8a | SRAM macro", "| 8b | SRAM macro")


if __name__ == "__main__":
    unittest.main()
