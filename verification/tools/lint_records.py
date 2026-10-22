#!/usr/bin/env python3
"""Validate the evidence-record layout under verification/records/.

    python3 -I verification/tools/lint_records.py [RECORDS_DIR]

Layout: <records>/<kind>/<timestamp>-<sha>/provenance.json, where timestamp is
UTC `YYYYMMDDTHHMMSSZ` and sha is 7-40 hex chars. provenance.json must be a
JSON object with the keys commit, pdk_revision, tool_versions, command.

Records that predate this layout are named `YYYY-MM-DD` and must carry a
README.md instead; the date form is accepted only for them and is not for new
records. An absent or empty records tree passes. Stdlib only. Exit 1 on any
problem.
"""
import json
import re
import sys
from pathlib import Path

REQUIRED_KEYS = ("commit", "pdk_revision", "tool_versions", "command")
NEW_NAME = re.compile(r"^\d{8}T\d{6}Z-[0-9a-f]{7,40}$")
LEGACY_NAME = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def lint_record(rec: Path) -> list[str]:
    if NEW_NAME.match(rec.name):
        prov = rec / "provenance.json"
        if not prov.is_file():
            return [f"{rec}: missing provenance.json"]
        try:
            data = json.loads(prov.read_text())
        except (OSError, ValueError) as e:
            return [f"{prov}: not valid JSON ({e})"]
        if not isinstance(data, dict):
            return [f"{prov}: top level must be an object"]
        errs = [f"{prov}: missing key '{k}'" for k in REQUIRED_KEYS if k not in data]
        errs += [f"{prov}: key '{k}' is empty" for k in REQUIRED_KEYS
                 if k in data and data[k] in ("", None, [], {})]
        return errs
    if LEGACY_NAME.match(rec.name):
        if not (rec / "README.md").is_file():
            return [f"{rec}: legacy record has no README.md"]
        return []
    return [f"{rec}: name must be <YYYYMMDDTHHMMSSZ>-<sha> (legacy: YYYY-MM-DD)"]


def lint_tree(root: Path) -> list[str]:
    if not root.is_dir():
        return []
    errs = []
    for kind in sorted(p for p in root.iterdir() if p.is_dir()):
        for rec in sorted(p for p in kind.iterdir() if p.is_dir()):
            errs += lint_record(rec)
    return errs


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parent.parent / "records"
    errs = lint_tree(root)
    for e in errs:
        print(f"FAIL {e}", file=sys.stderr)
    print(f"records lint: {'FAIL' if errs else 'ok'} ({root})")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
