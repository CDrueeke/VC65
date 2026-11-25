#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Loest `.include "datei"` und `#include "datei"` (relativ zur einbindenden Datei) rekursiv auf und schreibt den
Quelltext als eine einzige Datei. Aufruf: tools/flatten.py eingabe.asm ausgabe.asm
Wird fuer den Selbstuebersetzungstest gebraucht, solange der native Assembler .include noch nicht kennt (Etappe N6)."""
import os, re, sys

INC = re.compile(r'^\s*[.#]include\s+"([^"]+)"\s*(;.*)?$', re.I)


def flat(path, seen, out):
    path = os.path.abspath(path)
    if path in seen[-32:]:
        raise SystemExit(f"Include-Schleife bei {path}")
    seen.append(path)
    for line in open(path, encoding="utf-8").read().split("\n"):
        m = INC.match(line)
        if m:
            flat(os.path.join(os.path.dirname(path), m.group(1)), seen, out)
        else:
            out.append(line)
    seen.pop()


def main():
    out = []
    flat(sys.argv[1], [], out)
    open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"{len(out)} Zeilen -> {sys.argv[2]}")


if __name__ == "__main__":
    main()
