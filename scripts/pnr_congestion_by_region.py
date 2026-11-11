#!/usr/bin/env python3
"""Bin an OpenROAD global-route congestion report by macro footprint (issue #37).

    python3 -I scripts/pnr_congestion_by_region.py REQUEST.json MACRO.lef CONG.rpt

CONG.rpt is the file written by `global_route -congestion_report_file`.  Each
violation is assigned to the macro footprint its g-cell centre lies in
("inside"), to the free space between/around the macros of a column
("channel/edge"), or to the space outside the columns ("open").  The sum of the
reported congestion and the number of violations whose capacity is 0 are given
per bin.  The router's own per-layer table does not carry this breakdown.
"""
import collections
import json
import re
import sys


def main(req, lef, rpt):
    w, h = map(float, re.search(r"SIZE ([\d.]+) BY ([\d.]+)", open(lef).read()).groups())
    macros = json.load(open(req))["macros"]
    xs = sorted({m["x_um"] for m in macros})

    def where(x, y):
        for m in macros:
            if m["x_um"] <= x <= m["x_um"] + w and m["y_um"] <= y <= m["y_um"] + h:
                return "inside macro"
        if any(x0 - 20 <= x <= x0 + w + 20 for x0 in xs):
            return "column channel/edge"
        return "open (std-cell region / die edge)"

    n, tot, cap0 = collections.Counter(), collections.Counter(), collections.Counter()
    pat = (r"violation type: (\w+) congestion.*?capacity:(\d+) usage:(\d+) congestion:(\d+)"
           r"\s+bbox = \(([\d.]+), ([\d.]+)\) - \(([\d.]+), ([\d.]+)\)")
    for m in re.finditer(pat, open(rpt).read(), re.S):
        d, cap, _u, cong, x1, y1, x2, y2 = m.groups()
        k = (d, where((float(x1) + float(x2)) / 2, (float(y1) + float(y2)) / 2))
        n[k] += 1
        tot[k] += int(cong)
        cap0[k] += cap == "0"
    print(f"{'direction':11} {'region':36} {'tiles':>6} {'sum overflow':>13} {'tiles cap=0':>12}")
    for k in sorted(n):
        print(f"{k[0]:11} {k[1]:36} {n[k]:6d} {tot[k]:13d} {cap0[k]:12d}")
    print(f"total overflow {sum(tot.values())}; in capacity-0 tiles {sum(1 for _ in ())}"
          if False else f"total overflow {sum(tot.values())} in {sum(n.values())} tiles")


if __name__ == "__main__":
    main(*sys.argv[1:4])
