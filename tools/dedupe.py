#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Benennt Labels um, die in zwei Quelltextgruppen doppelt definiert sind (vcc meldet E204), damit man Module zusammenbinden kann.
Aufruf: tools/dedupe.py PRAEFIX --rename DATEI... --against DATEI... [--also DATEI...] [--dry-run]
  --rename   Dateien, deren Labels umbenannt werden (die Namen, die auch in --against definiert sind, bekommen den Praefix)
  --against  Dateien, deren Labels unveraendert bleiben (Vergleichsmenge)
  --also     weitere Dateien, in denen die umbenannten Namen ersetzt werden, deren eigene Labels aber nicht verglichen werden
             (zum Beispiel Testprogramme, die die umbenannten Namen benutzen)
Als Label gilt ein Name am Zeilenanfang, gefolgt von ':' oder '=' (auch Konstanten). Ersetzt wird nur das ganze Wort. Namen, die
absichtlich von beiden Gruppen gemeinsam benutzt werden (zum Beispiel Zeropage-Zellen), gehoeren nicht in --rename-Dateien als
Definition; vorher mit --dry-run pruefen. Beispiel (Editor gegen Assembler):
  tools/dedupe.py ez_ --rename src/editor/ed.asm src/editor/disp.asm --against src/asm/*.asm --also src/test/edtest.asm"""
import re, sys

DEF = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*[: =]", re.M)


def labels(path):
    return set(DEF.findall(open(path).read()))


def main(argv):
    if len(argv) < 2 or argv[0].startswith("-"):
        sys.exit(__doc__)
    prefix, groups, cur, dry = argv[0], {"--rename": [], "--against": [], "--also": []}, None, False
    for a in argv[1:]:
        if a == "--dry-run": dry = True
        elif a in groups: cur = a
        elif cur: groups[cur].append(a)
        else: sys.exit(__doc__)
    ren, against = set(), set()
    for f in groups["--rename"]: ren |= labels(f)
    for f in groups["--against"]: against |= labels(f)
    clash = sorted(ren & against)
    print(f"{len(clash)} doppelte Namen: {' '.join(clash)}")
    if dry or not clash: return
    for f in groups["--rename"] + groups["--also"]:
        s = open(f).read()
        for c in clash:
            s = re.sub(r"\b" + re.escape(c) + r"\b", prefix + c, s)
        open(f, "w").write(s)
    print("umbenannt in", len(groups["--rename"]) + len(groups["--also"]), "Dateien")


if __name__ == "__main__":
    main(sys.argv[1:])
