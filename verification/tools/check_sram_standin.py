#!/usr/bin/env python3
"""Fail unless the SRAM stand-in differs from the pinned macro model only in documented ways.

    python3 -I verification/tools/check_sram_standin.py
    python3 -I verification/tools/check_sram_standin.py --pinned P --standin S --unpinned

`make -C verification soc-gate` simulates the synthesized netlist against
verification/models/sky130_sram_2kbyte_1rw1r_32x512_8_standin.v, not against the
pinned macro model, which does not elaborate in Icarus 13.0. This check is what
keeps that substitution honest: it fetches the pinned model (sha256 verified
against reuse.lock.json), normalises both files, applies the explicit list of
allowed edits in ALLOWED_EDITS to the pinned text, and requires the result to
equal the normalised stand-in exactly.

Nothing is inferred. Every difference is one named entry in ALLOWED_EDITS whose
`header` tag must also appear in the stand-in's own header comment, so an edit
cannot be allowed here without being documented there. Two failures, both exit 1:

  * an allowed edit that no longer matches the pinned text exactly once -- the pin
    moved, or the edit was mis-stated, and the stand-in must be re-derived;
  * any remaining difference between the edited pinned text and the stand-in -- a
    unified diff of the two normalised texts is printed.

Comment-only and whitespace-only differences are normalised away and pass.
Stdlib only.
"""
import argparse
import difflib
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = "efabless/sky130_sram_macros"
MACRO_V = "sky130_sram_2kbyte_1rw1r_32x512_8.v"
STANDIN = ROOT / "verification" / "models" / "sky130_sram_2kbyte_1rw1r_32x512_8_standin.v"
PINNED = ROOT / "build" / "sram_macro" / MACRO_V
FETCH = ROOT / "scripts" / "fetch-sram-macro.sh"
LOCK = ROOT / "reuse.lock.json"

# The complete set of allowed differences, as ordered edits to the NORMALISED pinned
# text. `header` is the tag that must appear in the stand-in's header comment; the
# reason each edit is allowed is written out there, next to that tag.
ALLOWED_EDITS = (
    {
        "name": "remove the USE_POWER_PINS port-list entries",
        "header": "removed `USE_POWER_PINS` blocks",
        "remove": ("`ifdef USE_POWER_PINS", "vccd1,", "vssd1,", "`endif"),
    },
    {
        "name": "remove the USE_POWER_PINS port declarations",
        "header": "removed `USE_POWER_PINS` blocks",
        "remove": ("`ifdef USE_POWER_PINS", "inout vccd1;", "inout vssd1;", "`endif"),
    },
    {
        "name": "remove the VERBOSE parameter",
        "header": "removed `VERBOSE`",
        "remove": ("parameter VERBOSE = 1 ;",),
    },
    {
        "name": "remove the VERBOSE-gated port-0 read and write traces",
        "header": "dropped `$display`",
        "remove": (
            "if ( !csb0_reg && web0_reg && VERBOSE )",
            '$display($time," Reading %m addr0=%b dout0=%b",addr0_reg,mem[addr0_reg]);',
            "if ( !csb0_reg && !web0_reg && VERBOSE )",
            '$display($time," Writing %m addr0=%b din0=%b wmask0=%b",addr0_reg,din0_reg,wmask0_reg);',
        ),
    },
    {
        "name": "remove the un-gated simultaneous-access WARNING",
        "header": "dropped the collision `WARNING`",
        "remove": (
            "if (!csb0 && !web0 && !csb1 && (addr0 == addr1))",
            '$display($time," WARNING: Writing and reading addr0=%b and addr1=%b simultaneously!",addr0,addr1);',
        ),
    },
    {
        "name": "remove the VERBOSE-gated port-1 read trace",
        "header": "dropped `$display`",
        "remove": (
            "if ( !csb1_reg && VERBOSE )",
            '$display($time," Reading %m addr1=%b dout1=%b",addr1_reg,mem[addr1_reg]);',
        ),
    },
    {
        "name": "take the mem declaration out of its place after the posedge clk1 block",
        "header": "`mem` declared first",
        "remove": ("reg [DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];",),
    },
    {
        "name": "declare mem before the first always, and zero it",
        "header": "`integer i;` and the zeroing `initial`",
        "before": ("reg csb0_reg;",),
        "insert": (
            "reg [DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];",
            "integer i;",
            "initial for (i = 0; i < RAM_DEPTH; i = i + 1) mem[i] = {DATA_WIDTH{1'b0}};",
        ),
    },
    {
        "name": "add the timescale directive",
        "header": "added `timescale`",
        "before": ("module sky130_sram_2kbyte_1rw1r_32x512_8(",),
        "insert": ("`timescale 1ns/1ps",),
    },
)


def normalise(text):
    """Comment-free, whitespace-collapsed, blank-free lines."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    lines = []
    for raw in text.splitlines():
        line = " ".join(re.sub(r"//.*", "", raw).split())
        if line:
            lines.append(line)
    return lines


def header_comment(text):
    """The leading `//` comment block of a Verilog file."""
    out = []
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped:
            continue
        if not stripped.startswith("//"):
            break
        out.append(stripped[2:].strip())
    return " ".join(out)


def locate(lines, block, what, errs):
    """The single index where `block` occurs in `lines`, or None with an error recorded."""
    hits = [i for i in range(len(lines) - len(block) + 1) if lines[i:i + len(block)] == list(block)]
    if len(hits) != 1:
        errs.append(
            f"allowed edit {what!r} no longer applies: expected exactly one match in the "
            f"pinned model, found {len(hits)}. The pin moved or the edit is mis-stated; "
            f"re-derive the stand-in. Block:\n"
            + "\n".join(f"    | {line}" for line in block)
        )
        return None
    return hits[0]


def apply_edits(pinned, errs):
    lines = list(pinned)
    for edit in ALLOWED_EDITS:
        if "remove" in edit:
            at = locate(lines, edit["remove"], edit["name"], errs)
            if at is not None:
                del lines[at:at + len(edit["remove"])]
        else:
            at = locate(lines, edit["before"], edit["name"], errs)
            if at is not None:
                lines[at:at] = list(edit["insert"])
    return lines


def check_undocumented_edits(standin_text, errs):
    header = header_comment(standin_text)
    for edit in ALLOWED_EDITS:
        if edit["header"] not in header:
            errs.append(
                f"allowed edit {edit['name']!r} is not documented in the stand-in header: "
                f"it must mention {edit['header']!r} with the reason"
            )


def verify_pin(path, errs):
    try:
        lock = json.loads(LOCK.read_text())
        entry = next(i for i in lock["imports"] if i["from"] == UPSTREAM)
        want = next(f["sha256"] for f in entry["files"] if f["upstream"].endswith("/" + MACRO_V))
    except (OSError, ValueError, KeyError, StopIteration) as e:
        errs.append(f"cannot read the {MACRO_V} pin from {LOCK}: {e}")
        return
    got = hashlib.sha256(path.read_bytes()).hexdigest()
    if got != want:
        errs.append(f"{path}: sha256 {got}, {LOCK.name} pins {want}")


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--pinned", type=Path, default=PINNED,
                    help=f"the pinned macro Verilog (default: {PINNED}, fetched if absent)")
    ap.add_argument("--standin", type=Path, default=STANDIN, help=f"default: {STANDIN}")
    ap.add_argument("--unpinned", action="store_true",
                    help="skip the sha256 pin check (for the fixture test only)")
    args = ap.parse_args(argv[1:])

    if not args.pinned.exists():
        if args.pinned != PINNED:
            print(f"error: {args.pinned} does not exist", file=sys.stderr)
            return 1
        print(f"fetching the pinned macro views: {FETCH}", file=sys.stderr)
        if subprocess.run([str(FETCH)], cwd=ROOT).returncode != 0:
            print(f"error: {FETCH.name} failed", file=sys.stderr)
            return 1

    errs = []
    if args.unpinned:
        print("warn: sha256 pin check skipped (--unpinned)", file=sys.stderr)
    else:
        verify_pin(args.pinned, errs)

    try:
        pinned_text = args.pinned.read_text()
        standin_text = args.standin.read_text()
    except OSError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    check_undocumented_edits(standin_text, errs)
    pinned, standin = normalise(pinned_text), normalise(standin_text)
    edited = apply_edits(pinned, errs)

    if edited != standin:
        diff = difflib.unified_diff(edited, standin, fromfile="pinned model + allowed edits",
                                    tofile=str(args.standin), lineterm="", n=3)
        errs.append("the stand-in differs from the pinned model in ways that are not in "
                    "ALLOWED_EDITS:\n" + "\n".join(diff))

    for e in errs:
        print(e, file=sys.stderr)
    if errs:
        print(f"FAIL  {args.standin.name}: {len(errs)} problem(s)", file=sys.stderr)
        return 1
    print(f"ok    {args.standin.name} matches {args.pinned.name} under "
          f"{len(ALLOWED_EDITS)} documented edits")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
