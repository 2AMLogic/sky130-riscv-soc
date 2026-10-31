"""Freshness check for the synthesized soc_top netlist (T1 item 1).

    python3 -I scripts/check-soc-netlist.py

Re-hashes every file listed in flow/soc/synth.sha256 (the RTL, pins, scripts,
synthesis request, boot image and the netlist, as recorded by scripts/synth-soc.sh)
and exits 1 if any differs or is missing. It runs no synthesis: it proves the
committed netlist and its inputs are the ones recorded together, so an edit to an
RTL source without re-running scripts/synth-soc.sh fails here.
"""
import hashlib
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parent.parent
bad = []
for line in (root / "flow/soc/synth.sha256").read_text().splitlines():
    want, _, rel = line.partition("  ")
    p = root / rel
    got = hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "missing"
    if got != want:
        bad.append(f"{rel}: recorded {want[:12]}, now {got[:12]}")
if bad:
    sys.exit("netlist stale (re-run scripts/synth-soc.sh):\n  " + "\n  ".join(bad))
print("ok    netlist and inputs match flow/soc/synth.sha256")
