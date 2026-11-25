#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt src/debug/dtab.asm (Dekodiertabellen des 45GS02 fuer Disassembler und Debugger) aus
vendor/vintagecoder/data/cpus/45gs02.cpu.json. Die Datei nicht von Hand aendern.
Tabellen (je 256 Byte, Index = Opcode): dt_len (Befehlslaenge), dt_mode (Adressierungsart M_*, wie optab.asm), dt_name (Index in
dt_names, 4 Zeichen klein, rechts mit 0 aufgefuellt), dt_qname (Name der Quad-Form nach Praefix $42 $42, $FF = keine)."""
import json, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MODES = ["imp", "acc", "imm", "imw", "zp", "zpx", "zpy", "abs", "abx", "aby", "ind", "iax",
         "izx", "izy", "izz", "isy", "rel", "rl", "zpr"]
QUAD_MODES = {"imp", "acc", "zp", "zpx", "abs", "abx", "izz"}


def main():
    d = json.load(open(os.path.join(ROOT, "vendor/vintagecoder/data/cpus/45gs02.cpu.json")))
    ln = [1] * 256
    mode = [0] * 256
    name = [""] * 256
    for m, md, op, n, cyc, fl, aff, grp in d["ops"]:
        o = int(op.lstrip("$"), 16)
        ln[o], mode[o], name[o] = n, MODES.index(md), m.lower()
    q_of = {base: q for q, base in d["quadOps"].items()}
    qn = [None] * 256
    for m, md, op, n, cyc, fl, aff, grp in d["ops"]:
        o = int(op.lstrip("$"), 16)
        if m in q_of and md in QUAD_MODES:
            qn[o] = q_of[m].lower()
    names = sorted({x for x in name} | {x for x in qn if x})
    idx = {n: i for i, n in enumerate(names)}
    out = ["; SPDX-License-Identifier: GPL-3.0-or-later",
           "; ERZEUGT von tools/gen_dtab.py aus vendor/vintagecoder/data/cpus/45gs02.cpu.json - nicht von Hand aendern.",
           "; Dekodiertabellen fuer Disassembler und Debugger (Aufbau siehe tools/gen_dtab.py).", ""]
    def tab(label, vals):
        out.append(label + ":")
        for i in range(0, 256, 16):
            out.append("        .byte " + ", ".join(str(v) for v in vals[i:i + 16]))
    tab("dt_len", ln)
    tab("dt_mode", mode)
    tab("dt_name", [idx[n] for n in name])
    tab("dt_qname", [idx[q] if q else 255 for q in qn])
    out.append("dt_names:")
    for n in names:
        out.append("        .byte " + ", ".join(str(ord(c)) for c in n.ljust(4, "\0")) + f"   ; {n}")
    with open(os.path.join(ROOT, "src/debug/dtab.asm"), "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"{len(names)} Namen, dtab.asm geschrieben")


if __name__ == "__main__":
    main()
