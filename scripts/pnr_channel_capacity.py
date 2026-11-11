#!/usr/bin/env python3
"""Channel-capacity analysis for the soc_top macro arrangement (issue #37).

Reads the macro placement in a klt place-and-route request and the macro LEF,
and for each vertical gap between stacked macros of one column reports the
signal pins facing the gap and the pins per micron of gap height.  A pin faces
a gap when its LEF side (after the placement orientation) points into it.
Power pins are excluded.  This is an estimate of demand placement, not a
router result; the router result is in each verification/records/soc-pnr/ run.

    python3 -I scripts/pnr_channel_capacity.py flow/soc/pnr_request.json build/sram_macro/<macro>.lef
"""
import collections
import json
import re
import sys

# LEF side -> side after orientation (only N/S matter for vertical gaps).
FLIP_Y = {"MX", "R180"}


def lef_sides(path):
    text = open(path).read()
    w, h = map(float, re.search(r"SIZE ([\d.]+) BY ([\d.]+)", text).groups())
    sides = collections.Counter()
    for name, body in re.findall(r"PIN (\S+)\n(.*?)END \1\n", text, re.S):
        if name.startswith(("vccd", "vssd")):
            continue
        x1, y1, x2, y2 = map(float, re.search(r"RECT\s+([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+)", body).groups())
        cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
        sides["W" if cx < 3 else "E" if cx > w - 3 else "S" if cy < 3 else "N" if cy > h - 3 else "int"] += 1
    return w, h, sides


def main(req_path, lef):
    w, h, sides = lef_sides(lef)
    macros = json.load(open(req_path))["macros"]
    print(f"macro {w} x {h} um; signal pins by LEF side: {dict(sides)}")
    cols = collections.defaultdict(list)
    for m in macros:
        cols[round(m["x_um"])].append(m)
    for x, col in sorted(cols.items()):
        col.sort(key=lambda m: m["y_um"])
        print(f"column x={x}")
        for lo, hi in zip(col, col[1:]):
            gap = hi["y_um"] - (lo["y_um"] + h)
            top_of_lo = "S" if lo["orientation"] in FLIP_Y else "N"
            bot_of_hi = "N" if hi["orientation"] in FLIP_Y else "S"
            pins = sides[top_of_lo] + sides[bot_of_hi]
            print(f"  gap {gap:7.2f} um  facing {top_of_lo}+{bot_of_hi} = {pins:3d} pins  {pins / gap:5.2f} pins/um")


if __name__ == "__main__":
    main(*sys.argv[1:3])
