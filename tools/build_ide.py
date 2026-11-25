#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Baut VC65 (src/ide/vc65.asm) und das Debugger-Overlay VC65D (src/debug/overlay.asm) und legt beides auf ein D81.
Ablauf: Hauptprogramm uebersetzen (--labels) -> build/ovsyms.asm (alle Namen des Hauptprogramms als Konstanten) -> Overlay als Rohdatei
-> VC65D = Ladeadresse $E000 (2 Byte) + Rohdatei. Aufruf: tools/build_ide.py [Ausgabeordner]; Testprogramme rufen build_overlay() auf."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest, mksysdisk

ROOT = asmtest.ROOT


def write_syms(vs, out, exclude=()):
    lines = []
    for l in open(vs):
        m = re.match(r"al\s+C:([0-9a-fA-F]+)\s+\.?(\S+)", l)
        if m and re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", m.group(2)) and m.group(2) not in exclude:
            lines.append(f"{m.group(2)} = ${int(m.group(1), 16):04x}")
    open(out, "w").write("; ERZEUGT von tools/build_ide.py aus der Labeldatei des Hauptprogramms\n" + "\n".join(lines) + "\n")


def build_tables(outdir):
    """Tabellendatei VC65T (src/ide/tdata.asm) bauen und build/optabsyms.asm (Namen als Konstanten fuer das Hauptprogramm) schreiben;
    liefert den Pfad der Datei VC65T. Muss vor dem Hauptprogramm laufen."""
    b = os.path.join(ROOT, "build")
    os.makedirs(outdir, exist_ok=True)
    raw = os.path.join(outdir, "vc65t.bin")
    vs = os.path.join(outdir, "vc65t.vs")
    r = asmtest.run([asmtest.VCC, "asm", os.path.join(ROOT, "src/ide/tdata.asm"), "--target", "mega65", "--format", "bin",
                     "--data-dir", asmtest.DATA, "-o", raw, "--labels", vs])
    if r.returncode != 0:
        raise SystemExit("Tabellen (VC65T) bauen nicht\n" + r.stdout + r.stderr)
    data = open(raw, "rb").read()
    if 0xf500 + len(data) > 0xfff9:   # $FFFA-$FFFF: Vektoren
        raise SystemExit(f"VC65T zu gross: {len(data)} Byte")
    write_syms(vs, os.path.join(b, "optabsyms.asm"))
    path = os.path.join(outdir, "VC65T")
    open(path, "wb").write(bytes([0x00, 0xf5]) + data)
    return path


def build_overlay(vs, outdir):
    """Aus der Labeldatei vs das Overlay bauen; liefert den Pfad der Datei VC65D."""
    b = os.path.join(ROOT, "build")
    write_syms(vs, os.path.join(b, "ovsyms.asm"))
    raw = os.path.join(outdir, "vc65d.bin")
    r = asmtest.run([asmtest.VCC, "asm", os.path.join(ROOT, "src/debug/overlay.asm"), "--target", "mega65", "--format", "bin",
                     "--data-dir", asmtest.DATA, "-o", raw])
    if r.returncode != 0:
        raise SystemExit("Overlay baut nicht\n" + r.stdout + r.stderr)
    data = open(raw, "rb").read()
    if 0xe000 + len(data) > 0xf500:   # ab $F500 liegen die Tabellen (VC65T)
        raise SystemExit(f"Overlay zu gross: {len(data)} Byte")
    path = os.path.join(outdir, "VC65D")
    open(path, "wb").write(bytes([0x00, 0xe0]) + data)
    return path


def build_xoverlay(outdir):
    """Werkzeug-Overlay VC65X (src/ide/xoverlay.asm) bauen; build/ovsyms.asm muss von build_overlay stammen (gleiche Labeldatei)."""
    raw = os.path.join(outdir, "vc65x.bin")
    r = asmtest.run([asmtest.VCC, "asm", os.path.join(ROOT, "src/ide/xoverlay.asm"), "--target", "mega65", "--format", "bin",
                     "--data-dir", asmtest.DATA, "-o", raw])
    if r.returncode != 0:
        raise SystemExit("Werkzeug-Overlay baut nicht\n" + r.stdout + r.stderr)
    data = open(raw, "rb").read()
    if 0xe000 + len(data) > 0xf500:   # ab $F500 liegen die Tabellen (VC65T)
        raise SystemExit(f"Werkzeug-Overlay zu gross: {len(data)} Byte")
    path = os.path.join(outdir, "VC65X")
    open(path, "wb").write(bytes([0x00, 0xe0]) + data)
    return path


A_STUBS = ("ex_call", "argpush", "arg_get", "f_pass", "d_function", "asp", "fnargs", "fi")     # Namen, die das Overlay A selbst definiert (src/asm/funcres.asm)


def build_aoverlay(vs, outdir):
    """Overlay A (src/ide/aoverlay.asm: func, math, mathtab) bauen; liefert den Pfad der Datei VC65A."""
    b = os.path.join(ROOT, "build")
    write_syms(vs, os.path.join(b, "ovsyms_a.asm"), A_STUBS)
    raw = os.path.join(outdir, "vc65a.bin")
    r = asmtest.run([asmtest.VCC, "asm", os.path.join(ROOT, "src/ide/aoverlay.asm"), "--target", "mega65", "--format", "bin",
                     "--data-dir", asmtest.DATA, "-o", raw])
    if r.returncode != 0:
        raise SystemExit("Overlay A baut nicht\n" + r.stdout + r.stderr)
    data = open(raw, "rb").read()
    if 0xe000 + len(data) > 0xf300:   # funcres.asm kopiert OA_PAGES = 19 Seiten ($E000-$F2FF); ab $F500 liegen die Tabellen (VC65T)
        raise SystemExit(f"Overlay A zu gross: {len(data)} Byte")
    path = os.path.join(outdir, "VC65A")
    open(path, "wb").write(bytes([0x00, 0xe0]) + data)
    return path


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "ide")
    os.makedirs(out, exist_ok=True)
    prg = os.path.join(out, "VC65")
    vs = os.path.join(out, "vc65.vs")
    tab = build_tables(out)
    r = asmtest.run([asmtest.VCC, "asm", os.path.join(ROOT, "src/ide/vc65.asm"), "--target", "mega65", "--data-dir", asmtest.DATA,
                     "-o", prg, "--labels", vs])
    if r.returncode != 0:
        raise SystemExit("VC65 baut nicht\n" + r.stdout + r.stderr)
    end = 0x2001 + os.path.getsize(prg) - 2
    if end > 0xd000:      # BASIC kann das PRG nur bis $CFFF laden (darueber ist die Ein-/Ausgabe sichtbar); ab $D000 liegt das 50-Zeilen-Bild
        raise SystemExit(f"VC65 zu gross: endet bei ${end:04x}, Grenze $D000")
    ov = build_overlay(vs, out)
    xo = build_xoverlay(out)
    ao = build_aoverlay(vs, out)
    d81 = os.path.join(out, "vc65.d81")
    cmd = [asmtest.VCC, "disk", "d81", "-o", d81, "--data-dir", asmtest.DATA, "--name", os.environ.get("VC65_DISKNAME", "VC65"), "--id", "65", "--add", f"{prg}:VC65", "--add", f"{ov}:VC65D", "--add", f"{tab}:VC65T", "--add", f"{xo}:VC65X", "--add", f"{ao}:VC65A"]
    for n, p in mksysdisk.sys_list().items():          # Systemdateien (<mega65/...> usw.) auf dieselbe Disk, siehe mksysdisk.py
        cmd += ["--add", f"{p}:{n}"]
    r = asmtest.run(cmd)
    if r.returncode != 0:
        raise SystemExit("D81 nicht gebaut\n" + r.stdout + r.stderr)
    print(f"VC65 {os.path.getsize(prg)} Byte, VC65D {os.path.getsize(ov)} Byte, VC65X {os.path.getsize(xo)} Byte, {len(mksysdisk.sys_list())} Systemdateien, {d81}")


if __name__ == "__main__":
    main()
