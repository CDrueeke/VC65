#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prueft, dass sich Quelltexte (src/) gegenueber einem Git-Stand (Standard HEAD) nur in Kommentaren und Leerzeilen unterscheiden:
Kommentare (ab ';' ausserhalb von Zeichenketten und Zeichenliteralen), Leerzeilen und Einrueckung werden entfernt, der Rest muss
zeilengleich sein. Aufruf: tools/commentcheck.py [--rev HEAD] [Datei ...]   (ohne Dateien: alle geaenderten Dateien unter src/)"""
import subprocess, sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def strip(text):
    out = []
    for line in text.split("\n"):
        res, q = [], None
        i = 0
        while i < len(line):
            c = line[i]
            if q:
                res.append(c)
                if c == "\\" and i + 1 < len(line):
                    res.append(line[i + 1]); i += 1
                elif c == q: q = None
            elif c in "\"'":
                q = c; res.append(c)
            elif c == ";":
                break
            else:
                res.append(c)
            i += 1
        s = " ".join("".join(res).split())      # Einrueckung und Mehrfachleerzeichen vereinheitlichen
        if s: out.append(s)
    return out

def main():
    a = sys.argv[1:]
    rev = "HEAD"
    if a[:1] == ["--rev"]: rev, a = a[1], a[2:]
    files = a or subprocess.run(["git", "diff", "--name-only", rev, "--", "src"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    bad = 0
    for f in files:
        old = subprocess.run(["git", "show", f"{rev}:{f}"], cwd=ROOT, capture_output=True, text=True).stdout
        new = open(os.path.join(ROOT, f), encoding="utf-8").read()
        o, n = strip(old), strip(new)
        if o != n:
            bad += 1
            for i, (x, y) in enumerate(zip(o, n)):
                if x != y:
                    print(f"DIFF {f}: Codezeile {i + 1}: '{x}' -> '{y}'"); break
            else:
                print(f"DIFF {f}: Laenge {len(o)} -> {len(n)}")
        else:
            print("ok  ", f)
    sys.exit(1 if bad else 0)
main()
