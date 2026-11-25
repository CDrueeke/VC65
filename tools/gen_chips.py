#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt sys/mega65/chips.asm aus den Chip-Beschreibungen von vcc (data/chips/*.chip.json, Chips des Ziels mega65): je Chip ein Namensraum
mit den Registeradressen (vic2.border usw.). Der native Assembler bindet die Datei bei jedem Durchlauf selbst ein (inc.asm, chips_enter)."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

D = asmtest.DATA
tgt = json.load(open(os.path.join(D, "targets", "mega65.target.json")))["target"]
out = ["// SPDX-License-Identifier: MIT-0", "// MEGA65: Registernamen der Chips (vic2.border usw.), erzeugt von tools/gen_chips.py aus vcc data/chips - nicht von Hand aendern"]
for cid in tgt["chips"]:
    c = json.load(open(os.path.join(D, "chips", cid + ".chip.json")))
    out.append(".namespace %s {" % cid)
    for r in c["regs"]:
        out.append(".const %s = %s" % (r["name"], r["addr"]))
    out.append("}")
p = os.path.join(asmtest.ROOT, "sys", "mega65", "chips.asm")
open(p, "w").write("\n".join(out) + "\n")
print(p, len(out), "Zeilen")
