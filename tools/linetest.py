#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Test der Zeilentabelle des nativen Assemblers (Debugger) gegen die Zeilenabbildung in der .vcdbg von vcc (`vcc asm --debug`):
je Quelltext Adresse, Laenge und Zeilennummer der Zeilen, die Bytes ausgeben. Aufruf: tools/linetest.py [Dateien...]"""
import json, os, sys, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

ROOT = asmtest.ROOT
KNOWN = {"t19_macro", "t23_misc"}   # vcc ordnet Makrobytes den Zeilen des Makrorumpfs zu, VC65 der Aufrufzeile


def vcc_lines(path):
    dbg = os.path.join(ROOT, "build", "lt_ref.vcdbg")
    prg = os.path.join(ROOT, "build", "lt_ref.prg")
    r = asmtest.run([asmtest.VCC, "asm", path, "--target", "mega65", "--data-dir", asmtest.DATA, "-o", prg, "--debug", dbg])
    if r.returncode != 0: return None
    d = json.load(open(dbg))
    base = os.path.basename(path)
    return sorted((l["line"], l["addr"], l["len"]) for l in d["lines"] if l["file"].endswith(base) and l["len"] > 0)


def native_lines(name, path):
    r = asmtest.one(name, path, vcc_may_fail=True)
    mem = open(os.path.join(ROOT, "build", "xrun.mem"), "rb").read()
    n = mem[0xc2f8] | mem[0xc2f9] << 8
    src = open(path, "rb").read()
    starts = [0]
    for i, c in enumerate(src):
        if c == 10: starts.append(i + 1)
    res = []
    for i in range(min(n, 256)):
        e = mem[0x40000 + i * 8:0x40000 + i * 8 + 8]
        pos = (e[0] | e[1] << 8 | e[2] << 16 | e[3] << 24) & 0xFFFFF   # ohne Attic-Basis $0800_0000
        line = max(k for k, st in enumerate(starts) if st <= pos) + 1
        res.append((line, e[4] | e[5] << 8, e[6] | e[7] << 8))
    return sorted(res)


def main():
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, "tests/asm/t*.asm")))
    bad = 0
    for f in files:
        name = os.path.basename(f)[:-4]
        ref = vcc_lines(f)
        if ref is None: continue
        got = native_lines("lt_" + name, f)
        ok = ref == got
        known = name in KNOWN and not ok
        print("ok   " if ok else "bek. " if known else "DIFF ", name, "" if ok or known else f"vcc {ref[:6]}... nativ {got[:6]}...")
        bad += 0 if ok or known else 1
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
