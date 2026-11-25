#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Test der Warnungen W204 (.basicstub nicht bei $2001) und W206 (.run ohne Wirkung) gegen vcc: Zeile und Anzahl je Quelltext.
Aufruf: tools/warntest.py"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

ROOT = asmtest.ROOT
MAP = {0x24: "W204", 0x26: "W206"}
CASES = {
    "w1": ".target mega65\n.org $2001\n.basicstub start\nstart: nop\n",
    "w2": ".target mega65\n.org $3000\n.basicstub start\nstart: nop\n",
    "w3": ".target mega65\n.org $2001\n.run start\nstart: nop\n",
    "w4": ".target mega65\n.org $3000\n.basicstub start\n.org $3100\nstart: nop\n.run start\n",
}


def vcc_warns(path):
    r = asmtest.run([asmtest.VCC, "asm", path, "--target", "mega65", "--format", "bin", "--data-dir", asmtest.DATA, "-o", "/tmp/warnt.bin"])
    out = r.stdout + r.stderr
    return [(m.group(1), int(m.group(2))) for m in re.finditer(r"warning\[(W20[4-7])\][^\n]*\n\s*--> [^\n]*:(\d+)", out)]


def main():
    bad = 0
    for name, body in CASES.items():
        path = os.path.join(ROOT, "build", f"warn_{name}.asm")
        open(path, "w").write(body)
        exp = vcc_warns(path)
        asmtest.one_disk("warn_" + name, body, {})
        got = [(MAP.get(c, f"?{c}"), line) for c, line, *_ in asmtest.LAST_WARNS]
        ok = exp == got
        print("ok   " if ok else "DIFF ", name, "" if ok else f"vcc {exp} nativ {got}")
        bad += 0 if ok else 1
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
