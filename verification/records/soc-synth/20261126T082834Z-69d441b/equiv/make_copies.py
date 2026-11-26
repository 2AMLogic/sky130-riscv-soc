#!/usr/bin/env python3
"""Derive the equivalence-check copies of rtl/obi_xbar.sv (record evidence).

    python3 -I make_copies.py BASELINE_SV WORKTREE_SV OUT_DIR [--mutate-new]

BASELINE_SV is rtl/obi_xbar.sv before the rom_addr_o narrowing (the parent
commit of the one this record names), WORKTREE_SV the file after it. Stdlib
only. Writes into OUT_DIR:

- xbar_old.sv: the baseline file with the module renamed obi_xbar_old, its
  32-bit rom_addr_o output made an internal wire rom_addr_o_wide, and a new
  internal wire rom_addr_o_narrow = rom_addr_o_wide[11:2].
- xbar_new.sv: the narrowed file with the module renamed obi_xbar_new and its
  10-bit rom_addr_o output renamed rom_addr_o_narrow.
- xbar_old_aw10.sv / xbar_new_aw10.sv: the same two with the parameter
  defaults ISRAM_AW / DSRAM_AW 11 -> 10 (1024-word SRAMs).
- with --mutate-new, xbar_new_mut.sv: xbar_new.sv with bit 2 of the
  instruction manager's ROM address forced to 0 -- a negative control the
  check must reject.

Every edit asserts that it hit exactly one line, so a drifted source fails
here instead of silently proving the wrong thing.
"""
import pathlib
import sys


def sub_once(text, old, new):
    assert text.count(old) == 1, (old, text.count(old))
    return text.replace(old, new)


def old_copy(src):
    t = pathlib.Path(src).read_text()
    t = sub_once(t, "module obi_xbar #(", "module obi_xbar_old #(")
    t = sub_once(t, "    output logic [31:0] rom_addr_o,\n", "")
    t = sub_once(t, "  assign rom_addr_o = i_to_rom ? i_addr_i : d_addr_i;\n",
                 "  logic [31:0] rom_addr_o_wide;\n"
                 "  assign rom_addr_o_wide = i_to_rom ? i_addr_i : d_addr_i;\n")
    assert t.rstrip().endswith("endmodule")
    t = t.rstrip()[:-len("endmodule")] + (
        "  logic [11:2] rom_addr_o_narrow;\n"
        "  assign rom_addr_o_narrow = rom_addr_o_wide[11:2];\n"
        "endmodule\n")
    return t


def new_copy(src):
    t = pathlib.Path(src).read_text()
    t = sub_once(t, "module obi_xbar #(", "module obi_xbar_new #(")
    t = sub_once(t, "    output logic [11:2] rom_addr_o,\n",
                 "    output logic [11:2] rom_addr_o_narrow,\n")
    t = sub_once(t, "  assign rom_addr_o = i_to_rom ? i_addr_i[11:2] : d_addr_i[11:2];\n",
                 "  assign rom_addr_o_narrow = i_to_rom ? i_addr_i[11:2] : d_addr_i[11:2];\n")
    return t


def aw10(t):
    t = sub_once(t, "    parameter int ISRAM_AW = 11,\n", "    parameter int ISRAM_AW = 10,\n")
    t = sub_once(t, "    parameter int DSRAM_AW = 11\n", "    parameter int DSRAM_AW = 10\n")
    return t


def mutate(t):
    return sub_once(
        t,
        "  assign rom_addr_o_narrow = i_to_rom ? i_addr_i[11:2] : d_addr_i[11:2];\n",
        "  assign rom_addr_o_narrow = i_to_rom ? {i_addr_i[11:3], 1'b0} : d_addr_i[11:2];\n")


def main(argv):
    mutate_new = "--mutate-new" in argv[3:]
    args = [a for a in argv[1:] if a != "--mutate-new"]
    if len(args) != 3:
        sys.exit(__doc__)
    base, work, out = args
    out = pathlib.Path(out)
    o, n = old_copy(base), new_copy(work)
    (out / "xbar_old.sv").write_text(o)
    (out / "xbar_new.sv").write_text(n)
    (out / "xbar_old_aw10.sv").write_text(aw10(o))
    (out / "xbar_new_aw10.sv").write_text(aw10(n))
    if mutate_new:
        (out / "xbar_new_mut.sv").write_text(mutate(n))
    print("ok", out)


if __name__ == "__main__":
    main(sys.argv)
