#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Zufallstest fuer lange Spruenge (.branchlong auto) und Zeropage-/absolut-Wahl ueber mehrere Durchlaeufe:
erzeugt Programme mit vielen Vorwaerts- und Rueckwaertssprungen und spaet definierten Konstanten, vergleicht vcc und den
nativen Assembler. Aufruf: tools/fuzzbr.py [anzahl] [startwert]"""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

ROOT = asmtest.ROOT


def gen(seed, n=260, org=0x2000):
    r = random.Random(seed)
    nl = n // 6
    lines = [".target mega65", ".branchlong auto", f".org ${org:04x}"]
    nz = 40
    for i in range(n):
        if i % 6 == 0:
            lines.append(f"L{i // 6}:")
        k = r.random()
        if k < 0.35:
            lines.append(f"        b{r.choice(['ne','eq','cc','cs','mi','pl'])} L{r.randrange(nl)}")
        elif k < 0.55:
            lines.append(f"        lda Z{r.randrange(nz)}")
        elif k < 0.65:
            lines.append(f"        sta Z{r.randrange(nz)},x")
        elif k < 0.72:
            lines.append(f"        lda L{r.randrange(nl)}")
        elif k < 0.80:
            lines.append(f"        jmp L{r.randrange(nl)}")
        elif k < 0.86:
            lines.append(f"        .fill {r.randrange(1, 9)}, 0")
        else:
            lines.append("        nop")
    lines.append("        rts")
    for z in range(nz):
        lines.append(f"Z{z} = ${10 + z * 5:02x}")
    return "\n".join(lines) + "\n"


def main():
    cnt = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    start = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 260
    org = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x2000
    bad = 0
    for s in range(start, start + cnt):
        name = "fzb"
        path = os.path.join(ROOT, "tests", "asm", name + ".asm")
        open(path, "w").write(gen(s, size, org))
        res = asmtest.one(name, attic=(size > 400))
        os.remove(path)
        if res:
            bad += 1
            print("seed", s, res[:150])
            open(os.path.join(ROOT, "build", f"fzb_seed{s}.asm"), "w").write(gen(s, size, org))
        else:
            print("seed", s, "ok")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
