#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Alle MEGA65-Beispiele aus VintageCoder (nur gelesen) durch die IDE: Projektdisk (D81, Laufwerk 9) mit den Dateien des Projekts unter
flachen Namen, in der IDE Strg+A (Laufwerk 9), Strg+O (Hauptdatei laden), Strg+E (uebersetzen), Strg+F (Programm als OUT speichern);
das gespeicherte PRG muss gleich der vcc-Ausgabe sein. Mit --run danach zusaetzlich Strg+R und ein Bildschirmfoto des laufenden
Programms (build/extest/<name>_<datei>.png). Hauptdateien mit Namen ueber 16 Zeichen werden auf der Disk als MAIN abgelegt.
Aufruf: tools/extest_ide.py [--run] [--proof] [Beispiel ...]   oder   --repo: die mitgelieferten Beispiele in examples/   (--proof: Xemu-Monitor prueft Abbild im Speicher und Wirkung)"""
import glob, json, os, re, shutil, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest, idetest as I, disptest as D, examples as X

ROOT = asmtest.ROOT
OUT = os.path.join(ROOT, "build", "extest")
CTRL_A, CTRL_O, CTRL_E, CTRL_F, CTRL_R, RET = 0x01, 0x0f, 0x05, 0x06, 0x12, 0x0d


def proj_disk(name, main, dst):
    """Projektdisk bauen: alle Dateien des Projekts (ohne Unterordner) unter ihrem Dateinamen, die Hauptdatei als MAIN."""
    d = os.path.join(OUT, name + "_files")
    shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    cmd = [asmtest.VCC, "disk", "d81", "-o", os.path.join(OUT, f"{name}.d81"), "--data-dir", asmtest.DATA, "--name", "PROJEKT", "--id", "01"]
    seen = {}
    allfiles = []
    for dp, dn, fn in os.walk(dst):
        rel = dp.replace(dst, "", 1)
        if rel.startswith("/tools") or (rel.startswith("/build") and not rel.startswith("/build/export")): continue      # Werkzeuge, Bauergebnisse
        for f in fn:
            if f.endswith((".vcprj", ".vctest", ".md", ".py", ".prg")): continue
            allfiles.append(os.path.join(dp, f))
    cdir = os.path.join(ROOT, "build", "common")                 # ../../common/... der Beispiele: nur der Dateiname zaehlt
    have = {os.path.basename(p).upper() for p in allfiles}
    for dp, dn, fn in os.walk(cdir):
        for f in fn:
            if f.upper() not in have and not f.endswith((".md", ".py", ".vcprj")):
                allfiles.append(os.path.join(dp, f)); have.add(f.upper())
    for p in allfiles:
        base = os.path.basename(p)
        if p == os.path.join(dst, main): continue
        nm = base.upper()
        if len(nm) > 16:
            print(f"      Hinweis {name}: {base} (mehr als 16 Zeichen) nicht auf die Disk gelegt"); continue
        if nm in seen:
            if open(seen[nm], "rb").read() != open(p, "rb").read(): print(f"      Hinweis {name}: Namenskollision {base} ({os.path.relpath(p, dst)}), erste Datei bleibt")
            continue
        seen[nm] = p
        cmd += ["--add", f"{p}:{nm}"]
    cmd += ["--add", f"{os.path.join(dst, main)}:MAIN"]
    r = asmtest.run(cmd)
    if r.returncode != 0: raise SystemExit("Projektdisk nicht gebaut: " + r.stdout + r.stderr)
    return os.path.join(OUT, f"{name}.d81")


def vcc_prg(dst, main):
    out = os.path.join(OUT, "exp.prg")
    if os.path.exists(out): os.remove(out)
    r = asmtest.run([asmtest.VCC, "asm", os.path.join(dst, main), "--target", "mega65", "--data-dir", asmtest.DATA, "-o", out], cwd=dst) if False else \
        subprocess.run([asmtest.VCC, "asm", main, "--target", "mega65", "--data-dir", asmtest.DATA, "-o", out], cwd=dst, capture_output=True, text=True)
    return open(out, "rb").read() if os.path.exists(out) else None


def check_run(x, tag, want):
    """Xemu-Monitor: das Programm steht nach Strg+R im Speicher (Bank 0 ab Ladeadresse) und laeuft."""
    img = want[2:]
    n = min(len(img), 16)                 # Anfang (BASIC-Starter): spaeter aendern Programme ihren Speicher selbst
    got = x.mem(want[0] | want[1] << 8, n)
    if got != img[:n]: return "FEHLER: Programmabbild im Speicher weicht von der vcc-Ausgabe ab"
    if tag.startswith("cputest"):         # Zeropage $60-$D4: Ergebnis der Befehlstests
        zp = x.mem(0x60, 0x75)
        if zp == bytes(0x75): return "FEHLER: cputest hat die Zeropage nicht beschrieben"
        return "ok (Abbild stimmt, cputest hat Ergebnisse in $60-$D4 geschrieben: " + zp[:12].hex() + "...)"
    if tag.startswith("music"):           # SID-Register 1-4 (OSC3/ENV3 sind lesbar): veraendern sich, wenn der Song spielt
        import time
        snap = lambda: b"".join(x.mem(0xFFD3400 + o, 32) for o in (0x00, 0x20, 0x40, 0x60))
        a = snap(); time.sleep(2); b = snap()
        return "ok (Abbild stimmt, SID-Register aendern sich)" if a != b else "FEHLER: SID-Register unveraendert"
    return "ok (Abbild stimmt, Programm gestartet)"


def repo_main():
    """Die mitgelieferten Beispiele (examples/, fertige .byte-Includes, flache Namen): eine Disk fuer alle, wie die Beispieldisk der Auslieferung."""
    run = "--run" in sys.argv
    proof = "--proof" in sys.argv
    import mksysdisk
    sysf = {n: open(p, "rb").read() for n, p in mksysdisk.sys_list().items()}
    base = os.path.join(ROOT, "examples")
    os.makedirs(OUT, exist_ok=True)
    disk = os.path.join(OUT, "beispiele.d81")
    cmd = [asmtest.VCC, "disk", "d81", "-o", disk, "--data-dir", asmtest.DATA, "--name", "BEISPIELE", "--id", "01"]
    seen = {}
    for d in sorted(os.listdir(base)):
        dd = os.path.join(base, d)
        if not os.path.isdir(dd): continue
        for f in sorted(os.listdir(dd)):
            if f.endswith(".md"): continue
            if f.upper() in seen: raise SystemExit(f"Namenskollision auf der Beispieldisk: {f}")
            seen[f.upper()] = 1
            if len(f) > 16: raise SystemExit(f"Dateiname zu lang: {f}")
            cmd += ["--add", f"{os.path.join(dd, f)}:{f.upper()}"]
    r = asmtest.run(cmd)
    if r.returncode != 0: raise SystemExit(r.stdout + r.stderr)
    bad = 0
    for d in sorted(os.listdir(base)):
        mn = d.replace("_", "") + ".asm"                # Hauptdatei ohne Unterstrich (siehe examples/README.md)
        mainf = os.path.join(base, d, mn)
        if not os.path.exists(mainf): continue
        want = vcc_prg(os.path.join(base, d), mn)
        if want is None: print("DIFF  ", d, "vcc uebersetzt nicht"); bad += 1; continue
        keys = [CTRL_A, CTRL_O] + D.pet(mn.encode()) + [RET, CTRL_E, CTRL_F] + D.pet(b"out") + [RET]
        big = os.path.getsize(mainf) > 100000
        n = I.run(b"", keys, sysf, chrome=True, d81b=disk, xt=150 if big else 60)
        got = D.d81_files(disk).get(b"OUT")
        ok = got == want
        print(("ok    " if ok else "DIFF  "), d, f"({len(want)} Byte)" if ok else f"Meldung '{n['msg']}', Datei OUT {'fehlt' if got is None else str(len(got)) + ' Byte'} statt {len(want)}")
        bad += 0 if ok else 1
        if proof and ok:
            res = I.run(b"", keys[:-5] + [CTRL_R], sysf, chrome=True, d81b=disk, xt=(150 if big else 60) + 20, monitor=lambda x: check_run(x, d, want))
            print("      Lauf:", res)
            bad += 0 if res.startswith("ok") else 1
    sys.exit(1 if bad else 0)


def main():
    if "--repo" in sys.argv: repo_main()
    run = "--run" in sys.argv
    proof = "--proof" in sys.argv
    names = [a for a in sys.argv[1:] if not a.startswith("--")] or sorted(d for d in os.listdir(X.EX) if os.path.isdir(os.path.join(X.EX, d)))
    os.makedirs(OUT, exist_ok=True)
    import mksysdisk
    sysf = {n: open(p, "rb").read() for n, p in mksysdisk.sys_list().items()}
    bad = 0
    for name in names:
        src = os.path.join(X.EX, name)
        dst = os.path.join(ROOT, "build", "ex", name)
        shutil.rmtree(dst, ignore_errors=True); shutil.copytree(src, dst)
        common = os.path.join(os.path.dirname(X.EX), "common")
        shutil.rmtree(os.path.join(ROOT, "build", "common"), ignore_errors=True)
        if os.path.isdir(common): shutil.copytree(common, os.path.join(ROOT, "build", "common"))
        prj = json.load(open(os.path.join(dst, name + ".vcprj")))
        mains = [f for s in prj.get("sources", []) if s.get("kind") == "asm" for f in s.get("files", [])]
        if not mains:
            print("ok    ", name, "(keine Quelltexte, nur Medien)"); continue
        subprocess.run([asmtest.VCC, "build"], cwd=dst, capture_output=True)       # Medien -> build/export/*.asm
        for m in mains:
            tag = f"{name}_{m[:-4].replace('/', '_')}"
            want = vcc_prg(dst, m)
            if want is None:
                print("DIFF  ", tag, "vcc uebersetzt nicht"); bad += 1; continue
            # common/ liegt ausserhalb des Projekts: ../../common/... wird zu common/... (Dateiname genuegt auf der Projektdisk)
            pdisk = proj_disk(tag, m, dst)
            keys = [CTRL_A, CTRL_O] + D.pet(b"main") + [RET, CTRL_E, CTRL_F] + D.pet(b"out") + [RET]
            big = os.path.getsize(os.path.join(dst, m)) > 100000
            n = I.run(b"", keys, sysf, chrome=True, d81b=pdisk, xt=150 if big else 60)
            got = D.d81_files(pdisk).get(b"OUT")
            ok = got == want
            print(("ok    " if ok else "DIFF  "), tag, f"({len(want)} Byte)" if ok else f"Meldung '{n['msg']}', Datei OUT {'fehlt' if got is None else str(len(got)) + ' Byte'} statt {len(want)}")
            bad += 0 if ok else 1
            if proof and ok:
                res = I.run(b"", keys[:-5] + [CTRL_R], sysf, chrome=True, d81b=pdisk, xt=(150 if big else 60) + 20, monitor=lambda x: check_run(x, tag, want))
                print("      Lauf:", res)
                bad += 0 if res.startswith("ok") else 1
            if run and ok:
                png = os.path.join(OUT, tag + ".png")
                if os.path.exists(png): os.remove(png)
                I.run(b"", keys[:-5] + [CTRL_R], sysf, shot=png, chrome=True, d81b=pdisk, xt=(150 if big else 60) + 20)
                print("      Bildschirmfoto", png if os.path.exists(png) else "FEHLT")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
