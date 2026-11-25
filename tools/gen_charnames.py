#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt src/asm/charnames.asm (Namen der PETSCII-Steuerzeichen fuer {name} in Zeichenketten) aus
vendor/vintagecoder/data/chars/petscii.json. Aufruf: tools/gen_charnames.py"""
import json, os
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
d = json.load(open(os.path.join(ROOT, "vendor/vintagecoder/data/chars/petscii.json"), encoding="utf-8"))
rows = []
for e in d["entries"]:
    code = int(e["code"].lstrip("$"), 16)
    for n in [e["name"]] + ([e["basic"]] if "basic" in e else []) + e.get("aliases", []):
        n = n.lower().replace("_", " ").replace("-", " ")
        if (n, code) not in rows:
            rows.append((n, code))
out = ["; SPDX-License-Identifier: GPL-3.0-or-later",
       "; ERZEUGT von tools/gen_charnames.py aus vendor/vintagecoder/data/chars/petscii.json - nicht von Hand aendern.",
       "; Eintrag: Laenge, Name (klein, Leerzeichen), Code. Ende: Laenge 0.",
       "charnames:"]
for n, c in rows:
    out.append(f'        .byte {len(n)}, "{n}", ${c:02x}')
out.append("        .byte 0")
open(os.path.join(ROOT, "src/asm/charnames.asm"), "w").write("\n".join(out) + "\n")
print(len(rows), "Namen")
