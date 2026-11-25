#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Test der Meldung fuer Medien-Includes (VintageCoder D5): .include/#include mit Medien-Endung ergibt E219 (Code $15), jede andere
fehlende Datei weiter E212 (Code $14). Nur der native Assembler (vcc 222113b4 kennt Medien-Includes noch nicht).
Aufruf: tools/mediatest.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

ROOT = asmtest.ROOT
CASES = [
    ("m1", '.org $2000\n.include "graphics/hero.vcsprite"\n nop\n', [(0x15, 2)]),
    ("m2", '.org $2000\n#include "a/b.VCSONG"\n nop\n', [(0x15, 2)]),
    ("m3", '.org $2000\n.include "x.vcpal" as pal\n nop\n', [(0x15, 2)]),
    ("m4", '.org $2000\n.include "t.vcscreen"\n.include "t.vcchar"\n', [(0x15, 2), (0x15, 3)]),
    ("m5", '.org $2000\n.include "p.vctiles"\n.include "p.vcplay"\n.include "p.vcpmg"\n', [(0x15, 2), (0x15, 3), (0x15, 4)]),
    ("n1", '.org $2000\n.include "graphics/hero.vcspritex"\n nop\n', [(0x14, 2)]),
    ("n2", '.org $2000\n.include "build/export/hero.asm"\n nop\n', [(0x14, 2)]),
    ("n3", '.org $2000\n.include "vcsprite"\n nop\n', [(0x14, 2)]),
    ("n4", '.org $2000\n.include "a.vcspri"\n nop\n', [(0x14, 2)]),
]


def main():
    bad = 0
    for name, body, exp in CASES:
        asmtest.one_disk("media_" + name, body, {})          # leeres D81 (Dateitabelle ist initialisiert)
        got = [(c, line) for c, line, col in asmtest.LAST_ERRS]
        ok = got == exp
        print("ok   " if ok else "DIFF ", name, "" if ok else f"erwartet {exp} nativ {got}")
        bad += 0 if ok else 1
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
