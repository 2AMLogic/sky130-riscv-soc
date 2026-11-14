#!/usr/bin/env python3
"""Fail if the row-id projections drift from the spec/soc.md parameter table.

    python3 -I verification/tools/check_soc_rows.py [SPEC_DIR]

Compares the ids in the `## Parameter table` of soc.md with the ids in
soc.rows.json and statistical-claims-na.json (and the rows of
statistical-claims-na.md), and compares each row's class and reason in
statistical-claims-na.md against statistical-claims-na.json, so the
human-readable mirror cannot contradict the hash-bound statement `klt signoff`
cites. Stdlib only. Exit 1 on any difference.
"""
import json
import re
import sys
from pathlib import Path

ROW = re.compile(r"^\|\s*(\d+a?)\s*\|")
# `| # | Parameter | Row class | Why it is not statistical |` — id, class, reason.
CLAIM_ROW = re.compile(r"^\|\s*(\d+a?)\s*\|[^|]*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|\s*$")


def table_ids(path, heading=None):
    ids, active = [], heading is None
    for line in path.read_text().splitlines():
        if heading is not None and line.startswith("## "):
            active = line.strip() == heading
        m = ROW.match(line) if active else None
        if m:
            ids.append(m.group(1))
    return ids


def claim_rows(path):
    """(id, class, reason) per row of the statistical-claims-na.md table."""
    lines = path.read_text().splitlines()
    return [m.groups() for m in (CLAIM_ROW.match(line) for line in lines) if m]


def claim_errors(md_rows, md_ids, json_rows):
    """Row-by-row class/reason mismatches between the .md mirror and the .json statement."""
    errs, md_parsed = [], [r[0] for r in md_rows]
    if md_parsed != md_ids:
        errs.append(f"statistical-claims-na.md: rows {md_parsed} parsed as id/class/reason "
                    f"differ from the ids {md_ids} found in the table")
    md = {r[0]: r[1:] for r in md_rows}
    js = {r[0]: r[1:] for r in json_rows}
    for rid in [r[0] for r in json_rows] + [r for r in md if r not in js]:
        if rid not in md:
            errs.append(f"statistical-claims-na.md: row {rid} is absent, but "
                        f"statistical-claims-na.json states class {js[rid][0]!r}")
            continue
        if rid not in js:
            errs.append(f"statistical-claims-na.md: row {rid} differs from "
                        f"statistical-claims-na.json, which has no such row")
            continue
        for field, got, wanted in zip(("class", "reason"), md[rid], js[rid]):
            if got != wanted:
                errs.append(f"statistical-claims-na.md: row {rid} {field} {got!r} differs from "
                            f"statistical-claims-na.json {wanted!r}")
    return errs


def main(argv):
    spec = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parents[2] / "spec"
    want = table_ids(spec / "soc.md", "## Parameter table")
    sources, claims = {}, []
    try:
        sources["soc.rows.json"] = [r["id"] for r in json.loads((spec / "soc.rows.json").read_text())["rows"]]
        statement = json.loads((spec / "statistical-claims-na.json").read_text())["rows"]
        sources["statistical-claims-na.json"] = [r["id"] for r in statement]
        sources["statistical-claims-na.md"] = table_ids(spec / "statistical-claims-na.md")
        claims = claim_errors(claim_rows(spec / "statistical-claims-na.md"),
                              sources["statistical-claims-na.md"],
                              [(r["id"], r["class"], r["reason"]) for r in statement])
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    errs = []
    if not want:
        errs.append("no rows found in soc.md parameter table")
    for name, ids in sources.items():
        if ids != want:
            errs.append(f"{name}: ids {ids} differ from soc.md table {want}")
    errs += claims
    for e in errs:
        print(e, file=sys.stderr)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
