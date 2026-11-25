#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt src/asm/mathtab.asm: Konstanten fuer die Festkomma-Mathematik (32.32) des Assemblers: Arkustangens-Tabelle
fuer CORDIC, CORDIC-Verstaerkung, pi, ln 2 usw. Aufruf: tools/gen_mathtab.py"""
import math, os
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
N = 32


def fx(v):                      # 32.32: 8 Byte, Nachkomma 4 Byte tief, dann Ganzzahlteil 4 Byte
    n = int(round(v * (1 << 32))) & ((1 << 64) - 1)
    return n.to_bytes(8, "little")


def row(name, b, comment=""):
    return f"{name}: .byte " + ", ".join(f"${x:02x}" for x in b) + (f"  ; {comment}" if comment else "")


out = ["; SPDX-License-Identifier: GPL-3.0-or-later",
       "; ERZEUGT von tools/gen_mathtab.py - nicht von Hand aendern. Werte im Festkomma-Format 32.32 (8 Byte, tief zuerst).",
       f"CORDIC_N = {N}", "atab:"]
for i in range(N):
    out.append("        .byte " + ", ".join(f"${x:02x}" for x in fx(math.atan(2.0 ** -i))) + f"  ; atan(2^-{i})")
k = 1.0
for i in range(N):
    k *= 1.0 / math.sqrt(1 + 2.0 ** (-2 * i))
out.append(row("c_k", fx(k), "CORDIC-Verstaerkung"))
out.append(row("c_pi", fx(math.pi), "pi"))
out.append(row("c_2pi", fx(2 * math.pi), "2 pi"))
out.append(row("c_hpi", fx(math.pi / 2), "pi / 2"))
out.append(row("c_ln2", fx(math.log(2)), "ln 2"))
out.append(row("c_lg2", fx(math.log10(2)), "log10(2)"))
out.append(row("c_one", fx(1.0), "1"))
out.append(row("c_half", fx(0.5), "0,5"))
open(os.path.join(ROOT, "src/asm/mathtab.asm"), "w").write("\n".join(out) + "\n")
print("mathtab.asm geschrieben")
