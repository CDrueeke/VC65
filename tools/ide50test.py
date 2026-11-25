#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Test des 50-Zeilen-Bildes der IDE (VIC-IV V400, Bildschirm $0004_D000) in Xemu. Das Pruefprogramm entsteht aus src/test/idetest.asm
(wie tools/idetest.py), jedoch mit IDE_ROWS = 50, ed_scr = $D000 und disp_init; am Ende des Tastenskripts haelt es an, und der Zustand wird
ueber den Xemu-Monitor gelesen (tools/xmon.py, ohne -prgexit). Geprueft werden:
  bild      Editorbild (Zeichen und Farben) gegen das Python-Modell (tools/edtest.py, 50 Zeilen) und die VIC-IV-Register
  blaettern wie bild, nach Bild-ab/Bild-auf und Cursortasten
  lauf      Strg+E, Strg+R: das Programm sieht den 25-Zeilen-Standard (V400 aus, DISPROWS 24, SCRNPTR $0800); danach ist das 50-Zeilen-Bild wieder da
  debugger  Strg+E, Strg+D: Debuggerbild 25 Zeilen ($0004_D200); nach 'c' (weiter) wieder 50 Zeilen
Aufruf: tools/ide50test.py [fall ...]      Umgebung wie tools/xmon.py"""
import os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import asmtest, edtest as E, disptest as D, build_ide, idetest as I
from xmon import Xemu

ROOT = asmtest.ROOT
SCR = 0x4d000                        # $0004_D000: Bildschirm im Bank-4-Fenster (CPU $D000)
CRAM = 0xff80000                     # Farb-RAM (COLPTR = 0)
DSCR, DCRAM = 0x4d200, 0xff81000     # Debuggerbild und -farben (DV_S, DV_COL)
MARK = 0x1c4ff                       # Bank 1: das Pruefprogramm schreibt hier $A5, wenn das Tastenskript zu Ende ist
MARK_CODE = """sk_stop: lda #$ff
        sta E2
        lda #$c4
        sta E2 + 1
        lda #$01
        sta E2 + 2
        lda #$00
        sta E2 + 3
        ldz #$00
        lda #$a5
        sta [E2],z
sk_h:   jmp sk_h
"""
ASM, DBG, RUN = 0x05, 0x04, 0x12
CONT = 0x43

TEXT = "".join("%s lda #%d   ; Zeile %d\n" % ("lab%d:" % i if i % 7 == 0 else "     ", i % 200, i) for i in range(1, 90)).encode()
PROG = b""".org $2001
.basicstub start
start: lda #$47
       sta $d02f
       lda #$53
       sta $d02f
       lda $d031
       sta $c500
       lda $d07b
       sta $c501
       lda $d060
       sta $c502
       lda $d061
       sta $c503
       lda $d062
       sta $c504
       rts
"""


CHROME = False                       # True: mit Rahmen der IDE (Kopfzeilen, Probleme-Leiste, src/ide/chrome.asm), wie vc65.asm


def build(text, keys):
    tpl = open(os.path.join(ROOT, "src/test/idetest.asm")).read()
    src = tpl.replace("{tlen}", str(len(text))).replace("{keys}", E.bytes_lit(list(keys) + [0]))
    for old, new in (("ed_scr  = $0800", "IDE_ROWS = 50\ned_scr  = $d000\nED_SCRPHYS = $0004d000"),
                     ("        lda #25\n        jsr ed_init\n", "        lda #50\n        jsr ed_init\n        jsr disp_init\n"),
                     ("sk_stop: lda snapd", MARK_CODE + "sk_stop2: lda snapd")):
        assert old in src, old
        src = src.replace(old, new, 1)
    if CHROME:
        src = src.replace("        jsr ed_init\n        jsr disp_init\n", "        jsr ed_init\n        jsr chrome_init\n        jsr disp_init\n", 1)
        src = src.replace('.include "../ide/ide.asm"', '.include "../ide/ide.asm"\n.include "../ide/chrome.asm"', 1)
        assert "chrome_init" in src and "chrome.asm" in src
    b = os.path.join(ROOT, "build")
    os.makedirs(b, exist_ok=True)
    tab = build_ide.build_tables(os.path.join(b, "i50disk"))      # VC65T (Befehlstabelle) und build/optabsyms.asm
    asm = os.path.join(b, "i50.asm")
    open(asm, "w").write(src.replace('"../', '"../src/'))
    prg = os.path.join(b, "i50.prg")
    vs = os.path.join(b, "i50.vs")
    r = asmtest.run([asmtest.VCC, "asm", asm, "--target", "mega65", "--data-dir", asmtest.DATA, "-o", prg, "--labels", vs])
    if r.returncode != 0:
        raise SystemExit("Pruefprogramm baut nicht\n" + r.stdout + r.stderr)
    d = os.path.join(b, "i50disk")
    os.makedirs(d, exist_ok=True)
    ov = build_ide.build_overlay(vs, d)
    d81 = os.path.join(b, "i50.d81")
    # relativer Pfad: "C:" im Pfad stoert die Angabe Datei:NAME unter Windows
    r = asmtest.run([asmtest.VCC, "disk", "d81", "-o", d81, "--data-dir", asmtest.DATA, "--add", f"{os.path.relpath(ov)}:VC65D", "--add", f"{os.path.relpath(tab)}:VC65T", "--add", f"{os.path.relpath(build_ide.build_xoverlay(d))}:VC65X", "--add", f"{os.path.relpath(build_ide.build_aoverlay(vs, d))}:VC65A"])
    if r.returncode != 0:
        raise SystemExit("D81 nicht gebaut " + r.stdout + r.stderr)
    ia = os.path.join(b, "i50_src.bin")
    open(ia, "wb").write(text)
    return prg, ["-initattic", ia, "-8", d81]


def regs(x):
    d031 = x.vic(0x31)[0]
    d07b = x.vic(0x7b)[0]
    sp = x.vic(0x60, 3)
    return d031, d07b, sp[0] | sp[1] << 8 | sp[2] << 16


def state(text, keys, wait, mem=()):
    prg, extra = build(text, keys)
    with Xemu(prg, 5, extra) as x:
        t_end = time.time() + wait
        while x.mem(MARK, 1)[0] != 0xa5:       # warten, bis das Tastenskript abgearbeitet ist
            if time.time() > t_end:
                raise SystemExit("Zeitueberschreitung: Tastenskript nicht beendet")
            time.sleep(3)
        r = regs(x)
        out = {"regs": r}
        for name, a, n in mem:
            out[name] = x.mem(a, n)
    return out


def check_regs(r, rows, scr, problems):
    d031, d07b, sp = r
    want_v400 = rows == 50
    if bool(d031 & 8) != want_v400:
        problems.append("V400 %s statt %s ($D031=%02X)" % (bool(d031 & 8), want_v400, d031))
    if d07b != rows - 1:
        problems.append("DISPROWS %d statt %d" % (d07b, rows - 1))
    if sp != scr:
        problems.append("SCRNPTR %06X statt %06X" % (sp, scr))


def show_diff(got, exp, w=80):
    rows = sorted({i // w for i in range(min(len(got), len(exp))) if got[i] != exp[i]})
    return "Zeilen %s" % rows[:10]


def case_bild(keys, name, wait=240):
    e = E.Ed(50, TEXT)
    e.view()
    E.play(e, [])
    mk = [D.KMAP.get(k, k) for k in keys]
    for k in mk:
        e.key(k)
    ex_s, ex_a = e.screen2()
    st = state(TEXT, keys, wait, (("scr", SCR, 4000), ("cram", CRAM, 4000)))
    problems = []
    check_regs(st["regs"], 50, 0x04d000, problems)
    if st["scr"] != ex_s:
        problems.append("Zeichen: " + show_diff(st["scr"], ex_s))
    # Farben ohne das Auswahl-/Cursorbit ($20 kehrt um) vergleichen (der Cursor ist in der Anzeige ein umgeschaltetes Bit)
    ca = bytes(v & 0x1f for v in st["cram"]); ea = bytes(v & 0x1f for v in ex_a)
    if ca != ea:
        problems.append("Farben: " + show_diff(ca, ea))
    print("ok   " if not problems else "DIFF ", name, "; ".join(problems))
    return not problems


def case_lauf(wait=240):
    open(os.path.join(ROOT, "build", "i50prog.asm"), "wb").write(PROG)
    st = state(PROG, [ASM, RUN], wait, (("prog", 0xc500, 5), ("scr", SCR, 1920)))
    problems = []
    check_regs(st["regs"], 50, 0x04d000, problems)
    p = st["prog"]
    if p[0] & 8: problems.append("Programm sah V400 ein ($D031=%02X)" % p[0])
    if p[1] != 24: problems.append("Programm sah DISPROWS %d" % p[1])
    if p[2] | p[3] << 8 | p[4] << 16 != 0x0800: problems.append("Programm sah SCRNPTR %02X%02X%02X" % (p[4], p[3], p[2]))
    print("ok   " if not problems else "DIFF ", "lauf", "; ".join(problems), "(Programm: D031=%02X D07B=%02X SCRNPTR=%02X%02X%02X)" % (p[0], p[1], p[4], p[3], p[2]))
    return not problems


def case_debugger(wait=240):
    prog = b".org $2001\n.basicstub start\nstart: lda #$11\n       ldx #$22\n       sta $c500\n       rts\n"
    problems = []
    st = state(prog, [ASM, DBG], wait, (("dscr", DSCR, 2000),))
    check_regs(st["regs"], 25, 0x04d200, problems)
    title = I.scr2txt(st["dscr"][:80])
    if "Debugger" not in title: problems.append("Debuggerbild: %r" % title.strip())
    print("ok   " if not problems else "DIFF ", "debugger (angehalten)", "; ".join(problems))
    ok = not problems
    problems = []
    st = state(prog, [ASM, DBG, CONT], wait, (("scr", SCR, 80),))
    check_regs(st["regs"], 50, 0x04d000, problems)
    print("ok   " if not problems else "DIFF ", "debugger (zurueck in die IDE)", "; ".join(problems))
    return ok and not problems


def main():
    want = sys.argv[1:] or ["bild", "blaettern", "lauf", "debugger"]
    ok = True
    if "bild" in want: ok &= case_bild([], "bild")
    if "blaettern" in want: ok &= case_bild([0x17, 0x17, 0x11, 0x11, 0x11, 0x16], "blaettern")
    if "lauf" in want: ok &= case_lauf()
    if "debugger" in want: ok &= case_debugger()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
