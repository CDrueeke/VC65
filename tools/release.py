#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Baut die Vorabversion (Version aus VERSION): Boot-D81 mit VC65, VC65D, VC65T, VC65X und den Systemdateien und die Beispieldisk (examples/) nach build/release/,
dazu das Handbuch je Sprache (tools/handbuch_pdf.py, braucht das Modul markdown und einen Chromium-Browser) als Doku-Anhaenge in doku-anhaenge/ (PDF und Markdown-ZIP je Sprache, eigene Summendatei SHA256SUMS-doku.txt, wie bei VintageCoder), das ZIP-Paket VC65-<version>.zip (beide D81, Handbuch, Lizenzdateien, LIESMICH.txt; feste Zeitstempel im ZIP; die PDFs tragen aber ihr Erzeugungsdatum, die Pruefsumme der PDFs und des ZIP ist daher je Bau neu) und SHA256SUMS (wie bei VintageCoder, ohne Endung). Prueft vorher, dass die Arbeitskopie sauber ist (git status) und bricht sonst ab (Ausnahme: --dirty).
Veroeffentlicht nichts (kein Tag, kein Push). Aufruf: tools/release.py [--dirty]"""
import hashlib, os, shutil, subprocess, sys, zipfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

ROOT = asmtest.ROOT


ZIP_ROOT_FILES = ["LICENSE", "LICENSING.md", "THIRD-PARTY-NOTICES.md", "README.md", "CHANGELOG.md"]
READ_ME = """VC65 {ver} (Vorabversion, nur im Emulator Xemu getestet)
=======================================================
Inhalt:
  VC65-{ver}.d81            Boot-Diskette (Laufwerk 8): VC65, Debugger, Werkzeuge, Systemdateien
  VC65-Beispiele-{ver}.d81  Beispiele (Laufwerk 9)
  Handbuch/VC65-Handbuch.pdf, Handbuch/markdown-handbuch/   Handbuch (Deutsch) als PDF und als Markdown mit Bildern
  Handbuch/VC65-Manual.pdf,   Handbuch/markdown-manual/     Manual (English) as PDF and as Markdown with images
  LICENSE, LICENSING.md, THIRD-PARTY-NOTICES.md   Lizenzen (VC65: GPL-3.0-or-later; Systemdateien, Vorlagen, Beispiele: MIT-0)

Start: Boot-D81 in Laufwerk 8 einlegen (am MEGA65 oder in Xemu), Beispiel-D81 in Laufwerk 9, dann starten. Details: Handbuch, Kapitel 1.
ROMs des MEGA65 sind nicht enthalten.
"""


def make_zip(path, ver, d81s):
    """ZIP mit festen Zeitstempeln (1980-01-01) und sortierter Reihenfolge (gleiche Dateien ergeben dasselbe ZIP; die PDFs aendern sich je Bau)."""
    files = {os.path.basename(p): p for p in d81s}
    for f in ZIP_ROOT_FILES: files[f] = os.path.join(ROOT, f)
    hb = os.path.join(os.path.dirname(path), "handbuch")        # Ergebnis von tools/handbuch_pdf.py
    for dp, dn, fn in os.walk(hb):
        for f in fn:
            if f.endswith(".html") or f == ".DS_Store": continue     # HTML-Zwischendateien gehoeren nicht ins Paket
            full = os.path.join(dp, f)
            files["Handbuch/" + os.path.relpath(full, hb)] = full
    top = f"VC65-{ver}/"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        def add(name, data):
            zi = zipfile.ZipInfo(top + name, (1980, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = 0o644 << 16
            z.writestr(zi, data)
        add("LIESMICH.txt", READ_ME.format(ver=ver).encode("utf-8"))
        for name in sorted(files): add(name, open(files[name], "rb").read())


def make_doc_assets(out, ver):
    """Doku-Anhaenge nach dem Muster von VintageCoder (Ordner doku-anhaenge/): je Sprache PDF und Markdown-ZIP
    (VC65-<ver>-Handbuch.pdf, VC65-<ver>-Handbuch-Markdown.zip, VC65-<ver>-Manual.pdf, VC65-<ver>-Manual-Markdown.zip)."""
    dd = os.path.join(out, "doku-anhaenge"); os.makedirs(dd, exist_ok=True)
    res = []
    for stem, mdir in (("Handbuch", "markdown-handbuch"), ("Manual", "markdown-manual")):
        pdf = os.path.join(dd, f"VC65-{ver}-{stem}.pdf")
        shutil.copy(os.path.join(out, "handbuch", f"VC65-{stem}.pdf"), pdf)
        zp = os.path.join(dd, f"VC65-{ver}-{stem}-Markdown.zip")
        base = os.path.join(out, "handbuch", mdir)
        with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
            for dp, dn, fn in sorted(os.walk(base)):
                for f in sorted(fn):
                    full = os.path.join(dp, f)
                    zi = zipfile.ZipInfo(os.path.relpath(full, os.path.dirname(base)), (1980, 1, 1, 0, 0, 0))
                    zi.compress_type = zipfile.ZIP_DEFLATED; zi.external_attr = 0o644 << 16
                    z.writestr(zi, open(full, "rb").read())
        res += [pdf, zp]
    return res


def main():
    ver = open(os.path.join(ROOT, "VERSION")).read().strip()
    if "--dirty" not in sys.argv:
        st = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
        if st:
            raise SystemExit("Arbeitskopie nicht sauber (git status), erst committen oder --dirty:\n" + st)
    out = os.path.join(ROOT, "build", "release")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    env = dict(os.environ, VC65_DISKNAME=("VC65 " + ver).upper()[:16])
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build_ide.py"), os.path.join(out, "work")], env=env, capture_output=True, text=True)
    print(r.stdout.strip())
    if r.returncode != 0:
        raise SystemExit(r.stderr)
    d81 = os.path.join(out, f"VC65-{ver}.d81")
    shutil.copy(os.path.join(out, "work", "vc65.d81"), d81)
    ex = os.path.join(out, f"VC65-Beispiele-{ver}.d81")        # Beispieldisk: examples/ ohne Ordner (flache Namen, siehe examples/README.md)
    cmd = [asmtest.VCC, "disk", "d81", "-o", ex, "--data-dir", asmtest.DATA, "--name", "BEISPIELE", "--id", "01"]
    seen = set()
    for d in sorted(os.listdir(os.path.join(ROOT, "examples"))):
        dd = os.path.join(ROOT, "examples", d)
        if not os.path.isdir(dd): continue
        for f in sorted(os.listdir(dd)):
            if f.endswith(".md"): continue
            if f.upper() in seen or len(f) > 16: raise SystemExit(f"Beispieldisk: Name doppelt oder zu lang: {f}")
            seen.add(f.upper())
            cmd += ["--add", f"{os.path.join(dd, f)}:{f.upper()}"]
    r = asmtest.run(cmd)
    if r.returncode != 0: raise SystemExit(r.stdout + r.stderr)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "handbuch_pdf.py"), os.path.join(out, "handbuch")], capture_output=True, text=True)
    if r.returncode != 0: raise SystemExit("Handbuch (PDF/Markdown) nicht gebaut:\n" + r.stdout + r.stderr)
    docs = make_doc_assets(out, ver)
    zp = os.path.join(out, f"VC65-{ver}.zip")
    make_zip(zp, ver, [d81, ex])
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    with open(os.path.join(out, "SHA256SUMS"), "w") as f:
        for p in (d81, ex, zp): f.write(f"{hashlib.sha256(open(p, 'rb').read()).hexdigest()}  {os.path.basename(p)}\n")
    with open(os.path.join(out, "doku-anhaenge", "SHA256SUMS-doku.txt"), "w") as f:      # eigene Summendatei fuer die Doku-Anhaenge, wie bei VintageCoder
        for p in docs: f.write(f"{hashlib.sha256(open(p, 'rb').read()).hexdigest()}  {os.path.basename(p)}\n")
    open(os.path.join(out, "BUILD.txt"), "w").write(f"VC65 {ver}\nQuelle: Commit {commit}\nNur im Emulator Xemu getestet, am echten MEGA65 ungeprueft.\n")
    print(f"Fertig: {d81} und {ex} (Commit {commit})")


if __name__ == "__main__":
    main()
