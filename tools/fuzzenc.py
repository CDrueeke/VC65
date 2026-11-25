#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Kodierungstest ueber alle Mnemoniken und Adressierungsarten des 45GS02: erzeugt aus
vendor/vintagecoder/data/cpus/45gs02.cpu.json je Mnemonik und Modus eine Zeile, behaelt die Zeilen, die vcc
uebersetzt, und vergleicht die Bytes des nativen Assemblers (Xemu) mit denen von vcc. Aufruf: tools/fuzzenc.py"""
import json, os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

ROOT = asmtest.ROOT
OPERAND = {"imp": "", "acc": " a", "imm": " #$12", "imw": " #$1234", "zp": " $12", "zpx": " $12,x", "zpy": " $12,y",
           "abs": " $1234", "abx": " $1234,x", "aby": " $1234,y", "ind": " ($1234)", "iax": " ($1234,x)", "izx": " ($12,x)",
           "izy": " ($12),y", "izz": " ($12),z", "isy": " ($12,sp),y", "rel": " L", "rl": " L", "zpr": " $12, L"}


def lines():
    d = json.load(open(os.path.join(ROOT, "vendor/vintagecoder/data/cpus/45gs02.cpu.json")))
    out = []
    mm = {}
    for m, mode, *_ in d["ops"]:
        mm.setdefault(m, []).append(mode)
    for q, base in d["quadOps"].items():
        mm[q] = mm[base]
    for m in sorted(mm):
        for mode in mm[m]:
            out.append((m, mode, m + OPERAND[mode]))
            if mode == "izz":
                out.append((m, "izz32", m + " [$12],z"))
            if mode == "abs":
                out.append((m, "abs-z", m + " $0012"))
    return out


def main():
    b = os.path.join(ROOT, "build")
    os.makedirs(b, exist_ok=True)
    good = []
    rejected = []
    for i, (m, mode, text) in enumerate(lines()):
        src = text.replace(" L", " L0")
        f = os.path.join(b, "fz_one.asm")
        open(f, "w").write(f".target mega65\n.org $2000\nL0: {src}\n")
        r = subprocess.run([asmtest.VCC, "asm", f, "--target", "mega65", "--format", "bin", "--data-dir", asmtest.DATA, "-o", os.path.join(b, "fz_one.bin")], capture_output=True, text=True)
        if r.returncode == 0:
            good.append(text)
        else:
            rejected.append((text, (r.stdout + r.stderr).split("\n")[0]))
    print(len(good), "Zeilen von vcc akzeptiert")
    bad = 0
    chunk = 90
    for k in range(0, len(good), chunk):
        part = good[k:k + chunk]
        body = ".target mega65\n.org $2000\n"
        for j, t in enumerate(part):
            body += f"L{j}: {t.replace(' L', f' L{j}')}\n"
        name = f"fz{k // chunk:02d}"
        path = os.path.join(ROOT, "tests", "asm", name + ".asm")
        open(path, "w").write(body)
        res = asmtest.one(name)
        os.remove(path)
        if res:
            bad += 1
            print("FEHLER", res)
        else:
            print("ok    ", name, len(part), "Zeilen")
    for text, why in rejected:                       # was vcc ablehnt, muss auch der native Assembler ablehnen (gleicher Fehlercode)
        code = why.split("]")[0].split("[")[-1]
        name = "fzr"
        path = os.path.join(ROOT, "tests", "asm", name + ".asm")
        open(path, "w").write(f".target mega65\n.org $2000\nL0: {text.replace(' L', ' L0')}\n")
        os.makedirs(b, exist_ok=True)
        res = asmtest.one(name, path, vcc_may_fail=True)
        os.remove(path)
        want = {"E206": "ERR=6"}.get(code)
        if res and want and want in res:
            continue
        bad += 1
        print("FEHLER abgelehnte Zeile", text, "vcc:", why[:60], "nativ:", (res or "uebersetzt")[:90])
    print("alle identisch" if not bad else f"{bad} Abweichung(en)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
