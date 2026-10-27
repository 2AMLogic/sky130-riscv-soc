#!/usr/bin/env python3
"""Fail if the row-id projections drift from the spec/soc.md parameter table.

    python3 -I verification/tools/check_soc_rows.py [SPEC_DIR]

Compares the ids in the `## Parameter table` of soc.md with the ids in
soc.rows.json and statistical-claims-na.json (and the rows of
statistical-claims-na.md). Stdlib only. Exit 1 on any difference.
"""
import json
import re
import sys
from pathlib import Path

ROW = re.compile(r"^\|\s*(\d+a?)\s*\|")


def table_ids(path, heading=None):
    ids, active = [], heading is None
    for line in path.read_text().splitlines():
        if heading is not None and line.startswith("## "):
            active = line.strip() == heading
        m = ROW.match(line) if active else None
        if m:
            ids.append(m.group(1))
    return ids


def main(argv):
    spec = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parents[2] / "spec"
    want = table_ids(spec / "soc.md", "## Parameter table")
    sources = {}
    try:
        sources["soc.rows.json"] = [r["id"] for r in json.loads((spec / "soc.rows.json").read_text())["rows"]]
        sources["statistical-claims-na.json"] = [r["id"] for r in json.loads((spec / "statistical-claims-na.json").read_text())["rows"]]
        sources["statistical-claims-na.md"] = table_ids(spec / "statistical-claims-na.md")
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    errs = []
    if not want:
        errs.append("no rows found in soc.md parameter table")
    for name, ids in sources.items():
        if ids != want:
            errs.append(f"{name}: ids {ids} differ from soc.md table {want}")
    for e in errs:
        print(e, file=sys.stderr)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
