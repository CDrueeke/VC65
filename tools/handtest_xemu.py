#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Handtest der IDE im Emulator Xemu (Mac): baut die Boot-D81 (VC65, VC65D, VC65T, VC65X, Systemdateien) und eine Projektdisk mit den
MEGA65-Beispielen aus VintageCoder (nur gelesen; Hauptdateien unter ihrem Namen, z. B. HELLO, CPUTEST, JUMPRUN, PRALLBALL) und startet
Xemu mit Laufwerk 8 = Boot-D81, Laufwerk 9 = Projektdisk. Danach in BASIC:  DLOAD"VC65"  und  RUN  (oder mit --prg: VC65 startet sofort).
In VC65: Strg+A (Projektlaufwerk 9), Strg+O und Dateiname (zum Beispiel hello), Strg+E uebersetzen, Strg+R starten, HELP-Taste fuer das
Menue. Anleitung: docs/entwickler/de/handtest-xemu.md.  Aufruf: tools/handtest_xemu.py [--prg] [--no-start]"""
import os, shutil, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest, examples as X

ROOT = asmtest.ROOT
OUT = os.path.join(ROOT, "build", "handtest")
XEMU = os.environ.get("XEMU", "/Applications/xmega65.app/Contents/MacOS/xmega65")
ROM = os.environ.get("XEMU_ROM", os.path.expanduser("~/Library/Application Support/xemu-lgb/mega65/MEGA65.ROM"))


def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build_ide.py"), os.path.join(OUT, "boot")], capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit(r.stdout + r.stderr)
    boot = os.path.join(OUT, "boot", "vc65.d81")
    # Projektdisk: Beispiele (Dateien ohne Unterordner, Namen hoechstens 16 Zeichen); gleichnamige Dateien verschiedener Beispiele: das erste gilt
    cmd = [asmtest.VCC, "disk", "d81", "-o", os.path.join(OUT, "projekt.d81"), "--data-dir", asmtest.DATA, "--name", "BEISPIELE", "--id", "01"]
    seen = set()
    for ex in ("hello", "cputest", "pal_demo", "music_demo", "jumprun", "tiles_demo"):
        src = os.path.join(X.EX, ex)
        dst = os.path.join(OUT, ex)
        shutil.copytree(src, dst)
        subprocess.run([asmtest.VCC, "build"], cwd=dst, capture_output=True)
        for dp, dn, fn in os.walk(dst):
            rel = dp.replace(dst, "", 1)
            if rel.startswith("/tools") or (rel.startswith("/build") and not rel.startswith("/build/export")): continue
            for f in fn:
                if f.endswith((".vcprj", ".vctest", ".md", ".py", ".prg")): continue
                nm = f.upper()
                if f in ("%s.asm" % ex,) or f.startswith(ex + "_"):          # Hauptdateien ohne Unterstrich (der Unterstrich laesst sich nicht ueberall tippen)
                    nm = f.replace(ex + "_", "").replace("_", "").upper() if f.startswith(ex + "_") else f.replace("_", "").upper()
                if len(nm) > 16:                              # zu lang fuer die Disk: Projektname vorne weglassen (tiles_demo_3x2_ptr.asm -> 3X2_PTR.ASM)
                    nm = f.replace(ex + "_", "").upper()
                    if len(nm) > 16: continue
                if nm in seen: continue
                seen.add(nm)
                cmd += ["--add", f"{os.path.join(dp, f)}:{nm}"]
    common = os.path.join(os.path.dirname(X.EX), "common")
    for dp, dn, fn in os.walk(common):
        for f in fn:
            nm = f.upper()
            if nm not in seen and not f.endswith((".md", ".py", ".vcprj")) and len(f) <= 16:
                seen.add(nm); cmd += ["--add", f"{os.path.join(dp, f)}:{nm}"]
    r = asmtest.run(cmd)
    if r.returncode != 0: raise SystemExit(r.stdout + r.stderr)
    print("Boot-D81:   ", boot)
    print("Projektdisk:", os.path.join(OUT, "projekt.d81"), "(Beispiele: HELLO, CPUTEST, PAL_DEMO, MUSIC_DEMO, JUMPRUN, 3X2_PTR.ASM, usw.; prallball liegt auf der Beispiel-Disk der Auslieferung: dort heissen die Dateien eindeutig, auf dieser Projektdisk kollidieren die Namen mit jumprun, flaches D81)")
    args = [XEMU, "-rom", ROM, "-8", boot, "-9", os.path.join(OUT, "projekt.d81"), "-fastboot"]
    if "--prg" in sys.argv: args += ["-prg", os.path.join(OUT, "boot", "VC65")]
    print("Start:", " ".join(args))
    if "--no-start" not in sys.argv:
        subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


if __name__ == "__main__":
    main()
