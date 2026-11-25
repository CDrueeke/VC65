#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt echte Bildschirmfotos der IDE aus Xemu (Xemu speichert mit -screenshot beim Beenden ein PNG) fuer Dokumentation und Website.
Szenen: Editor, Uebersetzen, Fehlersprung, Debugger, Projekt. Ausgabe: docs/screenshots/*.png (800 x 625, MEGA65 80 x 25).
Aufruf: tools/screens.py [Ausgabeordner]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("XT", "40")
import asmtest, idetest as I, disptest as D, ide50test as I50

ROOT = asmtest.ROOT
SRC = (b"; Cycle the border colour\n.org $2001\n.basicstub start\n\nBORDER = $d020\n\n"
       b"start:  ldx #0\nloop:   stx BORDER        ; set colour\n        inx\n        bne loop\n        rts\n")
ASM, DBG, BP, DOWN, MARK, RIGHT = 0x05, 0x04, 0x07, 0x11, 0x02, 0x1d
STEP, LOAD, SAVE = 0x53, 0x0f, 0x0b
HELP, RIGHT_, DOWN_ = 0x84, 0x1d, 0x11
NAME = [SAVE] + D.pet(b"border.asm") + [0x0d]      # Reiter benennen (Strg+K), damit die Reiterleiste einen Namen zeigt

def _projekt():
    """erste 46 Zeilen des MEGA65-Beispiels jumprun (nur gelesen, aus VintageCoder-dev) fuer das volle 50-Zeilen-Bild"""
    f = os.path.expanduser("~/Documents/Development/Privat/VintageCoder-dev/examples/mega65/jumprun/jumprun.asm")
    if not os.path.exists(f): return None
    return b"".join(open(f, "rb").read().split(b"\n")[i] + b"\n" for i in range(46))


SCENES = {
    "editor": (SRC, NAME + [DOWN] * 8, "Editor: Quelltext mit Faerbung, Zeilennummern, Statuszeile"),
    "uebersetzen": (SRC, NAME + [ASM], "Uebersetzen mit Strg+E: Meldung in der Statuszeile"),
    "fehler": (SRC.replace(b"inx", b"inxx"), NAME + [ASM], "Fehler: Meldung mit Code, Zeile und Spalte, Cursor springt in die Zeile"),
    "menue": (SRC, NAME + [HELP, RIGHT_, DOWN_, DOWN_], "Menue (HELP): Aufklappfeld Bearb, dritter Eintrag gewaehlt"),
    "about": (SRC, [HELP, DOWN_, DOWN_, DOWN_, DOWN_, 0x0d], "About (Menue File): Logo, Version und Hinweis"),
    "debugger": (SRC, NAME + [ASM, DBG, STEP, STEP, STEP], "Debugger: Register, Disassemblierung, Quelltextzeile, Stapel, Speicher"),
}
if _projekt(): SCENES["projekt"] = (_projekt(), [DOWN] * 30, "Voller Bildschirm: 50 Zeilen mit Quelltext (jumprun)")


def run50(text, keys, shot):
    """50-Zeilen-Bild (VIC-IV V400, wie die echte IDE): Pruefprogramm aus ide50test, am Ende des Tastenskripts Endlosschleife,
    Xemu speichert beim Beenden das Bildschirmfoto."""
    I50.MARK_CODE = "sk_stop: jmp sk_stop\n"
    I50.CHROME = True
    prg, extra = I50.build(text, keys)
    env = dict(os.environ)
    env["XEMU_ARGS"] = " ".join(extra) + f" -screenshot {shot}"
    asmtest.run([os.path.join(ROOT, "tools/xrun.sh"), prg, os.environ.get("XT", "300")], env=env)


def main():
    args = [a for a in sys.argv[1:] if a != "--50"]
    rows50 = "--50" in sys.argv
    out = args[0] if args else os.path.join(ROOT, "docs", "screenshots")
    os.makedirs(out, exist_ok=True)
    only = os.environ.get("SCENES")
    for name, (text, keys, what) in SCENES.items():
        if only and name not in only.split(","): continue
        path = os.path.join(out, f"vc65-{name}.png")
        if os.path.exists(path): os.remove(path)
        (run50(text, keys, path) if rows50 else I.run(text, keys, shot=path))
        print(("ok   " if os.path.exists(path) else "FEHLT"), path, "-", what)


if __name__ == "__main__":
    main()
