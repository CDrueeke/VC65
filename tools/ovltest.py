#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Overlay-Test: Quelltexte mit Funktionen (func/math, Overlay A) werden in der IDE uebersetzt und mit der Ausgabe von vcc verglichen;
ausserdem Wechsel der Overlays (Debugger/Werkzeug ersetzen das Overlay A, danach laedt es sich aus dem Attic nach).
Aufruf: tools/ovltest.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest, idetest as I

ROOT = asmtest.ROOT
ASM, DBG, CONT, HELP, RIGHT, DOWN, RET = 0x05, 0x04, 0x43, 0x84, 0x1d, 0x11, 0x0d


def vcc(path):
    exp = os.path.join(ROOT, "build", "ovl_exp.bin")
    if os.path.exists(exp): os.remove(exp)
    r = asmtest.run([asmtest.VCC, "asm", path, "--target", "mega65", "--format", "bin", "--data-dir", asmtest.DATA, "-o", exp])
    return open(exp, "rb").read() if r.returncode == 0 else None


def main():
    bad = 0
    for name in ("t24_func", "t26_math", "t27_list"):
        src = os.path.join(ROOT, "tests", "asm", name + ".asm")
        want = vcc(src)
        text = open(src, "rb").read()
        cases = (("direkt", [ASM]),
                 ("nach Debugger", [ASM, DBG, 0x51, ASM]),              # Strg+E, Strg+D, q (Ende), Strg+E: Overlay A kommt aus dem Attic
                 ("nach Werkzeug", [ASM, HELP, RIGHT] + [DOWN] * 6 + [RET, ASM]))   # Align line ersetzt das Overlay, dann wieder Strg+E
        for label, keys in cases:
            n = I.run(text, keys, chrome=True, xt=200)
            ok = want is not None and n["out"] == want
            print("ok   " if ok else "DIFF ", name, label, "" if ok else f"Meldung '{n['msg']}' Bytes {len(n['out'])} statt {len(want) if want else None}")
            bad += 0 if ok else 1
    sys.exit(1 if bad else 0)


main()
