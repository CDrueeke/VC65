#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Nachstellung (Befund nach 0.1.0-alpha): Sitzung bis Programmende mit zwei Haltepunkten, Textaenderung, zweite Sitzung. Aufruf: XT=70 tools/dbg_repro_haltepunkt.py
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dbgtest as T, idetest as I, disptest as D
A, B, UP = T.ASM, T.DBG, 0x91
bp = [T.DOWN]*3 + [T.BP] + [T.DOWN]*3 + [T.BP]
s1 = [A] + bp + [B, T.CONT, T.CONT, T.CONT]            # Sitzung 1 bis Programmende, Haltepunkt Zeile 4 bleibt eingefuegt
edit = [UP]*3 + D.pet(b"nop") + [0x0d]                  # Zeile 4: nop einfuegen, Code dahinter rueckt um 1 Byte
tail = [A, B, T.STEP, T.STEP, T.STEP]
for name, keys in (("ref: nur Textaenderung", [A] + [T.DOWN]*3 + edit + tail), ("S1, Textaenderung, S2", s1 + edit + tail)):
    n = I.run(T.PROG.encode(), keys)
    rws = T.rows(n)
    title, st = T.state(n)
    print(name, "|", title, st, "| Meldung:", n["msg"])
    for r in rws[3:12]: print("    ", r.rstrip())
