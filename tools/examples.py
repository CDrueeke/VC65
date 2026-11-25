#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Differenztest des nativen Assemblers gegen vcc mit den MEGA65-Beispielprojekten aus VintageCoder (nur gelesen, nie dort geaendert):
das Projekt wird nach build/ex/<name>/ kopiert, vcc uebersetzt die Hauptdatei (Rohformat), der native Assembler in Xemu ebenso; die
Include-Dateien des Projekts und die Systemdateien (data/sys) stehen als Dateitabelle im Attic.
Aufruf: tools/examples.py [Beispielname ...]   (ohne Namen: alle in examples/mega65)"""
import glob, json, os, shutil, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

ROOT = asmtest.ROOT
EX = os.path.expanduser("~/Documents/Development/Privat/VintageCoder-dev/examples/mega65")
TEXT = (".asm", ".inc", ".s", ".chars", ".sprites", ".txt")


def project_files(root):
    out = {}
    for dp, dn, fn in os.walk(root):
        for f in fn:
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, root).replace(os.sep, "/")
            if rel.startswith("tools/") or f.endswith((".vcprj", ".vctest", ".md", ".py")): continue
            out[rel] = open(p, "rb").read()
    return out


def sys_files():
    base = os.path.join(asmtest.DATA, "sys")
    out = {}
    for dp, dn, fn in os.walk(base):
        if "/en" in dp.replace(base, "", 1)[:4]: continue        # englische Spiegel (sys/en) nicht noetig
        for f in fn:
            if f.endswith(".asm") or f.endswith(".inc"):
                p = os.path.join(dp, f)
                out["sys/" + os.path.relpath(p, base).replace(os.sep, "/")] = open(p, "rb").read()
    out["sys/mega65/chips.asm"] = open(os.path.join(ROOT, "sys", "mega65", "chips.asm"), "rb").read()    # Chip-Symbole (tools/gen_chips.py)
    return out


def run_one(name):
    src = os.path.join(EX, name)
    dst = os.path.join(ROOT, "build", "ex", name)
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(src, dst)
    common = os.path.join(os.path.dirname(EX), "common")                  # ../../common/... aus den Beispielen
    if os.path.isdir(common):
        shutil.rmtree(os.path.join(ROOT, "build", "common"), ignore_errors=True)
        shutil.copytree(common, os.path.join(ROOT, "build", "common"))
    prj = json.load(open(os.path.join(dst, name + ".vcprj")))
    mains = [f for src in prj.get("sources", []) if src.get("kind") == "asm" for f in src.get("files", [])]
    if not mains:
        return "kein Quelltext (nur Medien)", 0
    subprocess.run([asmtest.VCC, "build"], cwd=dst, capture_output=True)    # erzeugt build/export/*.asm aus den Medien
    allf = project_files(dst)
    allf.update(sys_files())
    cdir = os.path.join(ROOT, "build", "common")
    for k, v in project_files(cdir).items():
        allf["common/" + k] = v          # native Pfadnormalisierung: ../../common/ wird zu common/
    res, size = [], 0
    for m in mains:                      # jede Hauptdatei des Projekts (tiles_demo hat fuenf)
        files = dict(allf)
        del files[m]
        r = asmtest.one("ex_" + name + "_" + m.replace("/", "_")[:-4], os.path.join(dst, m), files=files, vcc_may_fail=True)
        if r is not None: res.append(f"{m}: {r}")
        size += os.path.getsize(os.path.join(dst, m))
    return ("; ".join(res) or None), size


def main():
    names = sys.argv[1:] or sorted(d for d in os.listdir(EX) if os.path.isdir(os.path.join(EX, d)))
    bad = 0
    for n in names:
        r, size = run_one(n)
        if r == "kein Quelltext (nur Medien)": r = None            # Projekt ohne Quelltexte: nichts zu uebersetzen
        print(("ok    " if r is None else "DIFF  "), n, f"({size // 1024} KB)", "(keine Quelltexte, nur Medien)" if size == 0 and r is None else "" if r is None else str(r)[:300].replace("\n", " "))
        bad += 0 if r is None else 1
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
