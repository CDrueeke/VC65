#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Debugger-Test in Xemu: ein kleines Programm wird im Editor uebersetzt (Strg+E) und im Debugger gestartet (Strg+D); Tastenfolgen
(Schritt, darueber, weiter, Haltepunkt per Strg+G) fuehren zu bekannten Haltestellen. Verglichen werden Adressen und Register aus dem
Bild des Debuggers (Zeile 0 und 1) und der Speicher nach dem Lauf. Aufruf: tools/dbgtest.py"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest, idetest as I

ROOT = asmtest.ROOT
PROG = """.org $2001
.basicstub start
start: lda #$11
       ldx #$22
       jsr sub
       ldy #$33
       sta $c500
       rts
sub:   inx
       rts
"""
NMIPROG = """.org $2001
.basicstub start
start: lda #$7f
       sta $dd0d
       lda $dd0d
       lda #<2000
       sta $dd04
       lda #>2000
       sta $dd05
       lda #$81
       sta $dd0d
       ldx #$22
       ldy #$33
       lda #$11
       sta $dd0e
loop:  jmp loop
"""
STEP, OVER, CONT, QUIT = 0x53, 0x4e, 0x43, 0x51        # s n c q (PETSCII)
ASM, DBG, BP, DOWN = 0x05, 0x04, 0x07, 0x11


def rows(n):
    sc = n["dscreen"]
    return [I.scr2txt(sc[r * 80:(r + 1) * 80]) for r in range(25)]


def lines():
    """Adresse je Quellzeile (nur Zeilen mit Ausgabe) aus der .vcdbg von vcc"""
    path = os.path.join(ROOT, "build", "dbg_prog.asm")
    open(path, "w").write(PROG)
    dbg = os.path.join(ROOT, "build", "dbg_prog.vcdbg")
    r = asmtest.run([asmtest.VCC, "asm", path, "--target", "mega65", "--data-dir", asmtest.DATA, "-o", os.path.join(ROOT, "build", "dbg_prog.prg"), "--debug", dbg])
    d = json.load(open(dbg))
    return {l["line"]: (l["addr"], l["len"]) for l in d["lines"] if l["len"] > 0}


def state(n):
    r = rows(n)
    m = re.search(r"A=(\w\w) X=(\w\w) Y=(\w\w) Z=(\w\w) B=(\w\w) SP=(\w\w) PC=(\w{4})", r[1])
    return r[0], (m.groups() if m else None)


def main():
    L = lines()
    addr = {k: v[0] for k, v in L.items()}
    # Zeilen: 3 basicstub? Zeilennummern in PROG: 1 .org, 2 .basicstub, 3 lda, 4 ldx, 5 jsr, 6 ldy, 7 sta, 8 rts, 9 inx, 10 rts
    bad = 0
    def check(name, keys, expect_pc, regs=None, extra=None):
        nonlocal bad
        n = I.run(PROG.encode(), [ASM, DBG] + keys)
        title, st = state(n)
        problems = []
        if expect_pc is not None:
            if f"${expect_pc:04x}" not in title: problems.append(f"Titel {title!r}")
            if not st or int(st[6], 16) != expect_pc: problems.append(f"PC {st}")
        for k, v in (regs or {}).items():
            idx = "AXYZ".index(k)
            if not st or int(st[idx], 16) != v: problems.append(f"{k}={st[idx] if st else '?'} statt {v:02x}")
        if extra: problems += extra(n)
        print("ok   " if not problems else "DIFF ", name, "; ".join(problems))
        bad += 1 if problems else 0
    check("start", [], addr[3])
    check("schritt", [STEP], addr[4], {"A": 0x11})
    check("schritt2", [STEP, STEP], addr[5], {"A": 0x11, "X": 0x22})
    check("hinein", [STEP, STEP, STEP], addr[9], {"X": 0x22})
    check("darueber", [STEP, STEP, OVER], addr[6], {"X": 0x23, "A": 0x11})
    check("ruecksprung", [STEP, STEP, STEP, STEP, STEP], addr[6], {"X": 0x23})
    def fin(n):
        out = []
        if n["mark"] != 0x11: out.append(f"Marke {n['mark']:#x}")
        if n["msg"] != "Program ended": out.append("Meldung " + n["msg"])
        return out
    check("weiter", [CONT], None, extra=fin)
    # Haltepunkt in Zeile 7 (sta): Cursor 6 Zeilen nach unten, Strg+G, dann im Debugger weiter
    n = I.run(PROG.encode(), [ASM] + [DOWN] * 6 + [BP, DBG, CONT])
    title, st = state(n)
    ok = f"${addr[7]:04x}" in title and st and int(st[2], 16) == 0x33
    print("ok   " if ok else "DIFF ", "haltepunkt", title, st)
    bad += 0 if ok else 1
    # Notfalltaste: ein NMI (CIA-2-Zeitgeber) unterbricht eine Endlosschleife; der Debugger zeigt die unterbrochene Stelle
    path = os.path.join(ROOT, "build", "dbg_nmi.asm")
    open(path, "w").write(NMIPROG)
    dbgj = os.path.join(ROOT, "build", "dbg_nmi.vcdbg")
    asmtest.run([asmtest.VCC, "asm", path, "--target", "mega65", "--data-dir", asmtest.DATA, "-o", os.path.join(ROOT, "build", "dbg_nmi.prg"), "--debug", dbgj])
    LOOPLINE = NMIPROG.split("\n").index("loop:  jmp loop") + 1
    loop = [l["addr"] for l in json.load(open(dbgj))["lines"] if l["line"] == LOOPLINE][0]
    n = I.run(NMIPROG.encode(), [ASM, DBG, CONT])
    title, st = state(n)
    ok = "interrupted" in title and f"${loop:04x}" in title and st and (int(st[0], 16), int(st[1], 16), int(st[2], 16)) == (0x11, 0x22, 0x33)
    print("ok   " if ok else "DIFF ", "notfalltaste", title, st)
    bad += 0 if ok else 1
    # Notfalltaste bei ausgeblendetem KERNAL ($01 = $35, wie prallball): der NMI geht ueber den RAM-Vektor $FFFA (knmir in der Bruecke)
    prog = NMIPROG.replace("start: lda #$7f", "start: sei\n       lda #$35\n       sta $01\n       lda #$7f", 1)
    n = I.run(prog.encode(), [ASM, DBG, CONT])
    title, st = state(n)
    LOOP2 = prog.split("\n").index("loop:  jmp loop") + 1
    ok = "interrupted" in title and st and (int(st[0], 16), int(st[1], 16), int(st[2], 16)) == (0x11, 0x22, 0x33)
    print("ok   " if ok else "DIFF ", "notfalltaste ohne KERNAL", title, st)
    bad += 0 if ok else 1
    # nach der Notfalltaste ein Schritt: das Programm laeuft korrekt weiter (Rueckkehr aus dem NMI-Rahmen) und haelt am Folgebefehl
    n = I.run(NMIPROG.encode(), [ASM, DBG, CONT, STEP])
    title, st = state(n)
    ok = "stopped" in title and f"${loop:04x}" in title and st and (int(st[0], 16), int(st[1], 16), int(st[2], 16)) == (0x11, 0x22, 0x33)
    print("ok   " if ok else "DIFF ", "notfalltaste+schritt", title, st)
    bad += 0 if ok else 1
    # und weiter: der Zeitgeber unterbricht das Programm erneut
    n = I.run(NMIPROG.encode(), [ASM, DBG, CONT, CONT])
    title, st = state(n)
    ok = "interrupted" in title and f"${loop:04x}" in title
    print("ok   " if ok else "DIFF ", "notfalltaste+weiter", title)
    bad += 0 if ok else 1
    # Programmbild: der Debugger hat einen eigenen Bildschirm (VIC-IV-Zeiger), mit V zeigt er das unberuehrte Bild des Programms
    VPROG = (".org $2001\n.basicstub start\nstart: lda #$93\n jsr $ffd2\n ldx #$00\nl1: lda txt,x\n beq done\n jsr $ffd2\n inx\n bne l1\n"
             "done: brk\n .byte 0\n rts\ntxt: .byte \"HALLO\", 13, \"ZWEITE ZEILE\", 13, 0\n")
    os.environ["XT"] = "22"
    for name, keys, want, deny in (("debuggerbild", [ASM, DBG, CONT], "VC65 Debugger", "zweite zeile"),
                                  ("programmbild", [ASM, DBG, CONT, 0x56], "zweite zeile", "VC65 Debugger")):
        I.run(VPROG.encode(), keys, shot=os.path.join(ROOT, "build", "dbg_v.png"))
        dump = open(os.path.join(ROOT, "build", "xrun.screen")).read()
        ok = want in dump and deny not in dump
        print("ok   " if ok else "DIFF ", name, "" if ok else dump[:200].replace("\n", " | "))
        bad += 0 if ok else 1
    os.environ["XT"] = "30"
    # Notfalltaste ohne Debugger: Strg+R, das Programm haengt in der Schleife, der NMI bringt die IDE zurueck
    n = I.run(NMIPROG.encode(), [ASM, 0x12])
    ok = n["msg"] == "Program interrupted (emergency key)"
    print("ok   " if ok else "DIFF ", "notfalltaste ohne debugger", repr(n["msg"]))
    bad += 0 if ok else 1
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
