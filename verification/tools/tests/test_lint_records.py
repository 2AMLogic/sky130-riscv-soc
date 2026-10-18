"""Fixture test for lint_records.py: good passes, each bad fixture fails.

    python3 -I verification/tools/tests/test_lint_records.py
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
LINT = HERE.parent / "lint_records.py"


def run(root):
    return subprocess.run([sys.executable, "-I", str(LINT), str(root)],
                          capture_output=True, text=True)


class LintRecords(unittest.TestCase):
    def test_good_fixture_passes(self):
        self.assertEqual(run(HERE / "good").returncode, 0)

    def test_missing_key_fails(self):
        r = run(HERE / "bad")
        self.assertEqual(r.returncode, 1)
        self.assertIn("missing key 'tool_versions'", r.stderr)
        self.assertIn("name must be", r.stderr)

    def test_absent_and_empty_tree_pass(self):
        self.assertEqual(run(HERE / "does-not-exist").returncode, 0)
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(run(d).returncode, 0)

    def test_legacy_record_needs_readme(self):
        with tempfile.TemporaryDirectory() as d:
            rec = Path(d) / "kind" / "2026-10-17"
            rec.mkdir(parents=True)
            self.assertEqual(run(d).returncode, 1)
            (rec / "README.md").write_text("x")
            self.assertEqual(run(d).returncode, 0)


if __name__ == "__main__":
    unittest.main()
