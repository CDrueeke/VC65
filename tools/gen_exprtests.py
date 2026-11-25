#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt src/test/expr_cases.asm: Testfaelle fuer den Ausdrucksrechner (src/asm/expr.asm).
Erwartete Werte sind von Hand nach asm-expr.md (VintageCoder-Hilfe) bestimmt; Fehler als ('E', Code)."""
import os

E = lambda c: ("E", c)
CASES = [
    ("1+2", 3), ("2 + 3 * 4", 14), ("(2 + 3) * 4", 20), ("10 - 2 - 3", 5), ("7 / 2", 3), ("7 % 3", 1),
    ("-7 / 2", -3), ("-5 % 3", -2), ("7 / -2", -3), ("-7 / -2", 3), ("5 % -3", 2),
    ("1 << 3", 8), ("$ff & $0f", 15), ("1 ^ 3", 2), ("$30 | 1", 0x31),
    ("3 > 2", 1), ("3 == 4", 0), ("!0", 1), ("!7", 0), ("1 || 0 && 0", 1), ("6 & 3 == 2", 1),
    (">$1234", 0x12), ("<$1234", 0x34), (">$12ff + 1", 0x13), (">($12ff + 1)", 0x13), ("<($12ff + 1)", 0),
    ("%1010", 10), ("0x1f", 31), ("0X1F", 31), ("'a'", 97), ("255", 255), ("$D020", 0xD020), ("$d020", 0xD020),
    ("~0", -1), ("-3", -3), ("+5", 5), ("--4", 4), ("$80 >> 7", 1), ("-16 >> 2", -4), ("100*100*100", 1000000),
    ("$7fffffff", 0x7fffffff), ("1 << 31", -0x80000000), ("123456789 / 1000", 123456), ("123456789 % 1000", 789),
    ("-1 < 1", 1), ("1 < -1", 0), ("0 - 1 > 0", 0), ("5 >= 5", 1), ("5 <= 4", 0), ("5 != 5", 0), ("5 != 6", 1),
    ("2 + 3 > 4 == 1", 1), ("1 + 2 << 1", 6), ("2 * 3 % 4", 2), ("$ff00 | $00ff ^ $0ff0", 0xff00 | (0x00ff ^ 0x0ff0)),
    ("  7  *  6  ", 42), ("(((1)))", 1), ("-(2+3)*2", -10), ("!(1 == 1)", 0), ("~$f0 & $ff", 0x0f),
    ("100000 * 100000", (100000 * 100000) & 0xffffffff), ("$ffffffff", -1), ("2147483647 / 3", 715827882),
    ("1 / 0", E(2)), ("5 % 0", E(2)), ("(1 + 2", E(1)), ("$", E(1)), ("", E(1)), ("1 +", E(1)), ("%", E(1)),
    ("'ab'", E(1)), ("foo", E(2)), ("1 + foo", E(2)), ("2 * (3 + )", E(1)),
]


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    out = ["; SPDX-License-Identifier: GPL-3.0-or-later",
           "; ERZEUGT von tools/gen_exprtests.py - nicht von Hand aendern.",
           f"CASES_N = {len(CASES)}", "cases:"]
    for i, (expr, exp) in enumerate(CASES):
        if isinstance(exp, tuple):
            val, err = 0, exp[1]
        else:
            val, err = exp & 0xffffffff, 0
        out.append(f"        .word s{i}")
        out.append(f"        .dword ${val:08x}")
        out.append(f"        .byte {err}")
    out.append("")
    for i, (expr, exp) in enumerate(CASES):
        txt = expr.replace('"', '')
        bytes_ = ", ".join(str(ord(c)) for c in expr)
        out.append(f"s{i}:" + (f"     .byte {bytes_}, 0" if bytes_ else "     .byte 0"))
    with open(os.path.join(root, "src/test/expr_cases.asm"), "w") as f:
        f.write("\n".join(out) + "\n")
    print(len(CASES), "Faelle")


if __name__ == "__main__":
    main()
