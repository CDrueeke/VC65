#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Konformitaetsbericht: nimmt die Beispielbloecke der VCASM-Hilfe (vendor/vintagecoder/help/*.md, Bloecke ```asm mit
Zeilen `;= ..` fuer die erwarteten Bytes) und prueft, ob der native Assembler dieselben Bytes wie vcc erzeugt.
Aufruf: tools/conform.py [--list] [datei.md ...]   Ergebnis: build/conform/bericht.txt"""
import os, re, sys, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

ROOT = asmtest.ROOT


def blocks(path):
    t = open(path).read()
    out = []
    for m in re.finditer(r"```(asm[^\n]*)\n(.*?)```", t, re.S):
        info, body = m.group(1), m.group(2)
        if ";=" not in body or "fehler" in info or "warnung" in info:
            continue
        if re.search(r"target=|fmt=|D=", info):
            continue                      # andere Ziele und Formate: nicht Sache von VC65
        out.append((info, body))
    return out


def main():
    files = [a for a in sys.argv[1:] if not a.startswith("--")] or sorted(glob.glob(os.path.join(ROOT, "vendor/vintagecoder/help/asm-*.md")) + [os.path.join(ROOT, "vendor/vintagecoder/help/assembler.md")])
    d = os.path.join(ROOT, "build/conform")
    os.makedirs(d, exist_ok=True)
    res = {"ok": 0, "native": [], "diff": [], "vcc": []}
    n = 0
    for f in files:
        base = os.path.basename(f)[:-3]
        for i, (info, body) in enumerate(blocks(f)):
            n += 1
            code = "\n".join(l for l in body.split("\n") if not l.strip().startswith(";="))
            if not re.search(r"^\s*(\.org|\*\s*=)", code, re.M):
                code = ".org $2000\n" + code
            name = f"{base}_{i:02d}"
            src = os.path.join(d, name + ".asm")
            open(src, "w").write(code + "\n")
            if "--list" in sys.argv:
                print(name)
                continue
            r = asmtest.one(name, src)
            if r is None:
                res["ok"] += 1
                print("ok    ", name)
            elif "vcc-Fehler" in r:
                res["vcc"].append(name)
                print("vcc   ", name)
            elif "ABWEICHUNG" in r:
                res["diff"].append((name, r))
                print("DIFF  ", name)
            else:
                res["native"].append((name, r))
                print("nativ ", name, r.split(":", 1)[1].strip()[:90])
    print(f"\n{res['ok']} von {n} identisch, {len(res['diff'])} abweichend, {len(res['native'])} nativer Fehler (Funktion fehlt), {len(res['vcc'])} von vcc nicht uebersetzbar")
    with open(os.path.join(d, "bericht.txt"), "w") as f:
        f.write(f"{res['ok']} von {n} identisch\n")
        for nm, r in res["diff"]:
            f.write("DIFF " + nm + "\n" + r + "\n")
        for nm, r in res["native"]:
            f.write("NATIV " + nm + " " + r.split(":", 1)[1].strip() + "\n")
        for nm in res["vcc"]:
            f.write("VCC " + nm + "\n")


if __name__ == "__main__":
    main()
