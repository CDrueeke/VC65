#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Selbstuebersetzungstest: Der native Assembler (in Xemu) uebersetzt den eigenen Quelltext (Pruefprogramm samt allen
Modulen aus src/asm, per tools/flatten.py zu einer Datei zusammengefasst, aus dem Attic gelesen) und muss dieselben
Bytes liefern wie vcc. Aufruf: tools/selfhost.py"""
import os, sys, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

ROOT = asmtest.ROOT


def main():
    b = os.path.join(ROOT, "build")
    os.makedirs(b, exist_ok=True)
    main_src = os.path.join(b, "shsrc_main.asm")
    # Pruefprogramm mit leerem Quelltext als zu uebersetzendes Programm
    open(main_src, "w").write(asmtest.HARNESS.format(srcbase="lda #$00\n        sta SRCBASE\n        sta SRCBASE + 1\n        sta SRCBASE + 2",
                                                    srcdata="source: .byte 0\n", pre=""))
    flat = os.path.join(b, "selfhost_flat.asm")
    subprocess.run([sys.executable, os.path.join(ROOT, "tools/flatten.py"), main_src, flat], check=True)
    res = asmtest.one("selfhost", flat, attic=True)
    if res:
        print("FEHLER", res)
        sys.exit(1)
    print("ok: der native Assembler uebersetzt sich selbst, Bytes identisch zu vcc")
    lines = len(open(flat).read().split("\n"))
    print(f"Zeit in Xemu (40 MHz): {asmtest.LAST_TIME:.1f} s fuer {lines} Zeilen")


if __name__ == "__main__":
    main()
