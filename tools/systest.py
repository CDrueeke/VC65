#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Test der Systemdisk (tools/mksysdisk.py): Bibliotheken <mega65/...> kommen von einer D81 in Laufwerk 8, die Projektdateien (Include
des Anwenders) von einer zweiten D81 in Laufwerk 9; Ergebnis byte-identisch zu vcc (das die Bibliotheken eingebaut hat)."""
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest, mksysdisk

B = os.path.join(asmtest.ROOT, "build")


def proj_disk(path, files):
    d = B                                  # vcc findet die Include-Dateien neben dem Quelltext
    cmd = [asmtest.VCC, "disk", "d81", "-o", path, "--data-dir", asmtest.DATA]
    for fn, data in files.items():
        open(os.path.join(d, fn), "w").write(data)
        cmd += ["--add", f"{os.path.join(d, fn)}:{fn.upper()}"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


def t(name, body, d81b=None):
    p = os.path.join(B, "systest.asm")
    open(p, "w").write(body)
    r = asmtest.one(name, p, attic=True, vcc_may_fail=True, d81=os.path.join(B, "sysdisk.d81"), d81b=d81b)
    print(("ok    " if r is None else "DIFF  ") + name, "" if r is None else str(r)[:200].replace("\n", " "), flush=True)
    return r is None


def main():
    os.makedirs(B, exist_ok=True)
    mksysdisk.build(os.path.join(B, "sysdisk.d81"))
    ok = True
    ok &= t("sys_chips", "#include <mega65/gs4502.asm>\n.org $2001\n mega65_enable_vic4\n lda #2\n sta vic2.border\n rts\n")
    ok &= t("sys_mehrere", "#include <mega65/vic4.asm>\n#include <common/types.asm>\n#include <mega65/tiles.asm>\n#include <common/math.asm>\n"
            ".org $2001\n lda #2\n sta vic2.border\n rts\n")
    pd = os.path.join(B, "proj.d81")
    proj_disk(pd, {"mein.inc": ".const MEINE = 7\n"})
    ok &= t("sys_projekt9", "#include <mega65/gs4502.asm>\n.include \"mein.inc\"\n.org $2001\n mega65_enable_vic4\n lda #MEINE\n sta vic2.border\n rts\n", d81b=pd)
    sys.exit(0 if ok else 1)


main()
