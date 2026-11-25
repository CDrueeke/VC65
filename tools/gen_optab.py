#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt src/asm/optab.asm (Opcode-Tabelle des 45GS02 fuer den nativen Assembler) aus
vendor/vintagecoder/data/cpus/45gs02.cpu.json. Die Datei nicht von Hand aendern.

Tabelle: MN_TABLE, je Mnemonik 7 Byte, alphabetisch (binaere Suche): 4 Zeichen (rechts mit 0 aufgefuellt), Flags
(Bit 0: Quad-Befehl, Praefix $42 $42), Adresse der Modenliste (Wort). Modenliste: Anzahl, dann je (Mode, Opcode).
Quad-Befehle (LDQ ...) tragen die Opcodes ihres Grundbefehls, erlaubt sind nur imp, acc, zp, zpx, abs, abx, izz
(wie in vcc: E206 sonst). Das 32-Bit-Zeigerpraefix $EA vor izz wird vom Assembler bei Syntax [zp],z gesetzt."""
import json, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MODES = ["imp", "acc", "imm", "imw", "zp", "zpx", "zpy", "abs", "abx", "aby", "ind", "iax",
         "izx", "izy", "izz", "isy", "rel", "rl", "zpr"]
QUAD_MODES = {"imp", "acc", "zp", "zpx", "abs", "abx", "izz"}


def main():
    d = json.load(open(os.path.join(ROOT, "vendor/vintagecoder/data/cpus/45gs02.cpu.json")))
    by = {}
    for m, mode, op, n, cyc, fl, aff, grp in d["ops"]:
        assert mode in MODES, mode
        by.setdefault(m, []).append((MODES.index(mode), int(op.lstrip("$"), 16)))
    entries = {m: (0, v) for m, v in by.items()}
    for q, base in d["quadOps"].items():
        entries[q] = (1, [(mo, op) for mo, op in by[base] if MODES[mo] in QUAD_MODES])
    names = sorted(entries)
    out = ["; SPDX-License-Identifier: GPL-3.0-or-later",
           "; ERZEUGT von tools/gen_optab.py aus vendor/vintagecoder/data/cpus/45gs02.cpu.json - nicht von Hand aendern.",
           "; Aufbau: siehe tools/gen_optab.py (Mnemonik-Tabelle, binaere Suche, Modenlisten).", ""]
    for i, m in enumerate(MODES):
        out.append(f"M_{m.upper()} = {i}")
    out += ["", f"MN_COUNT = {len(names)}", "MN_SIZE = 7", "", "mn_table:"]
    for n in names:
        fl, _ = entries[n]
        chars = ", ".join(str(ord(c)) for c in n.ljust(4, "\0"))
        out.append(f"        .byte {chars}, {fl}")
        out.append(f"        .word md_{n}")
    out += ["", "md_data:"]
    for n in names:
        fl, lst = entries[n]
        out.append(f"md_{n}:  .byte {len(lst)}" + "".join(f", {mo}, ${op:02x}" for mo, op in lst))
    base = [0] * 256
    worst = [0] * 256
    for m, mode, op, n, cyc, fl, aff, grp in d["ops"]:
        o = int(op.lstrip("$"), 16)
        base[o] = cyc
        worst[o] = cyc + (2 if "b" in fl else 0) + (1 if "p" in fl else 0)
    out += ["", "; Zyklen je Opcode: Grundzahl und ungünstigster Fall (Sprung genommen +2, Seitenüberschreitung +1)"]
    for nm, tab in (("cyc_base", base), ("cyc_worst", worst)):
        out.append(nm + ":")
        for i in range(0, 256, 16):
            out.append("        .byte " + ", ".join(str(x) for x in tab[i:i + 16]))
    with open(os.path.join(ROOT, "src/asm/optab.asm"), "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"{len(names)} Mnemoniken, optab.asm geschrieben")


if __name__ == "__main__":
    main()
