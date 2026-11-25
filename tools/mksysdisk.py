#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Systemdisk fuer den Dateilader (loader.asm): die MEGA65-Systemdateien aus vcc data/sys (mega65/*, c64/hardware.asm, common/*) und
sys/mega65/chips.asm als D81 mit flachen Namen "ORD.NAME" (3 Zeichen des Ordners, Name ohne Endung, Grossbuchstaben), z. B.
<mega65/vic4.asm> -> MEG.VIC4. Dieselbe Abbildung steht im Lader (ld_load). Aufruf: tools/mksysdisk.py [ziel.d81] [weitere Dateien name=pfad ...]"""
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

SYS = os.path.join(asmtest.DATA, "sys")
SETS = {"mega65": None, "common": None, "c64": ("hardware.asm",)}


def flat(d, f):
    return d[:3].upper() + "." + os.path.splitext(f)[0].upper()


def sys_list():
    out = {}
    for d, only in SETS.items():
        for f in sorted(os.listdir(os.path.join(SYS, d))):
            if not f.endswith((".asm", ".inc")): continue
            if only and f not in only: continue
            n = flat(d, f)
            assert n not in out and len(n) <= 16, n
            out[n] = os.path.join(SYS, d, f)
    out[flat("mega65", "chips.asm")] = os.path.join(asmtest.ROOT, "sys", "mega65", "chips.asm")
    return out


def build(target, extra=None):
    cmd = [asmtest.VCC, "disk", "d81", "-o", target, "--data-dir", asmtest.DATA]
    files = sys_list()
    files.update(extra or {})
    for n, p in files.items():
        cmd += ["--add", f"{p}:{n}"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(r.stdout + r.stderr)
    return files


if __name__ == "__main__":
    t = sys.argv[1] if len(sys.argv) > 1 else os.path.join(asmtest.ROOT, "build", "sysdisk.d81")
    os.makedirs(os.path.dirname(t), exist_ok=True)
    f = build(t)
    print(t, len(f), "Dateien:", " ".join(sorted(f)))
