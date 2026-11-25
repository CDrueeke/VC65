#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Differenztest: uebersetzt jeden Quelltext tests/asm/*.asm mit vcc (Rohbytes, --format bin) und mit dem nativen
Assembler von VC65 in Xemu (Mac), vergleicht die Bytes. Aufruf: tools/asmtest.py [namen...]
Je Test entsteht ein Pruefprogramm build/asmt_<name>.asm, das den Quelltext einbettet (.binary), asm_run aufruft und
die Ausgabe (ab $0005_8000) samt Laenge ($C200/$C201) und Fehlercode ($C202) im Speicher hinterlaesst."""
import os, subprocess, sys, glob

LAST_TIME = 0.0
LAST_ERRS = []
LAST_ERR_FILES = []                  # Dateinummer je Fehler (0 = Hauptdatei, sonst Reihenfolge der Includes)
LAST_WARNS = []
LAST_CYC = []
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
VCC = os.environ.get("VCC", os.path.expanduser("~/Development/vcc-bin/2caec744/vcc"))
DATA = os.environ.get("VCC_DATA", os.path.join(os.path.dirname(VCC), "data"))

HARNESS = """; ERZEUGT von tools/asmtest.py
.target mega65
.cpu 45gs02 {{ illegals = deny }}
.branchlong auto
.org $2001
.basicstub start
start:  sei
        lda #$02
        tab                         ; Basisseite $0200 (Interrupts sind gesperrt)
        lda #$00                    ; Quelltext liegt im Hauptspeicher (Bank 0)
        sta SRCBASE
        sta SRCBASE + 3
        sta OUTBASE
        sta OUTBASE + 3
        {srcbase}
        lda #$00
        sta OUTBASE + 0
        lda #$00
        sta OUTBASE + 1
        lda #$05
        sta OUTBASE + 2             ; Ausgabe ab $0005_0000 (64 KB)
        sei                         ; Zeitmessung: CIA1 Timer A und B (32 Bit, 1 MHz) frei laufen lassen
        lda #$7f
        sta $dc0d
        lda #$00
        sta $dc0e
        sta $dc0f
        lda #$ff
        sta $dc04
        sta $dc05
        sta $dc06
        sta $dc07
        lda #$11
        sta $dc0e
        lda #$51
        sta $dc0f
        {pre}
        jsr asm_run
        php
        pha
        lda #$00                    ; Zeit anhalten und lesen
        sta $dc0e
        sta $dc0f
        lda $dc04
        sta $c208
        lda $dc05
        sta $c209
        lda $dc06
        sta $c20a
        lda $dc07
        sta $c20b
        cli
        pla
        sec                         ; Laenge = OUTP - OUTBASE (16 Bit)
        lda OUTP
        sbc OUTBASE
        sta $c200
        lda OUTP + 1
        sbc OUTBASE + 1
        sta $c201
        lda ERR
        sta $c202
        lda PASS
        sta $c203
        lda SRC
        sta $c204
        lda SRC + 1
        sta $c205
        lda #<(source)
        sta $c206
        lda #>(source)
        sta $c207
        lda ercnt                    ; Fehlerliste: Anzahl, dann je Fehler Code, Zeile, Spalte
        sta $c210
        ldy #$00
el_h:   cpy ercnt
        beq el_hd
        cpy #$10
        beq el_hd
        tya
        pha
        jsr err_linecol
        pla
        pha
        asl
        asl
        asl
        tax
        pla
        pha
        tay
        jsr err_ptr
        ldz #$00
        lda [P6],z
        sta $c220,x
        ldz #$01
        lda [P6],z                  ; Dateinummer des Fehlers
        sta $c225,x
        lda eline
        sta $c221,x
        lda eline + 1
        sta $c222,x
        lda ecol
        sta $c223,x
        lda ecol + 1
        sta $c224,x
        pla
        tay
        iny
        jmp el_h
el_hd:  lda #$01                    ; Warnungen (Liste 1): Anzahl $C2F0, Eintraege ab $C300 (Code, Zeile, Spalte)
        sta lsel
        lda wcnt
        sta $c2f0
        ldy #$00
wl_h:   cpy wcnt
        beq wl_hd
        cpy #$08
        beq wl_hd
        tya
        pha
        jsr err_linecol
        pla
        pha
        asl
        asl
        asl
        tax
        pla
        pha
        tay
        jsr err_ptr
        ldz #$00
        lda [P6],z
        sta $c300,x
        lda eline
        sta $c301,x
        lda eline + 1
        sta $c302,x
        lda ecol
        sta $c303,x
        lda ecol + 1
        sta $c304,x
        pla
        tay
        iny
        jmp wl_h
wl_hd:  lda #$00
        sta lsel
        lda cyrepn                  ; Zyklenberichte: Anzahl $C2F1, Daten ab $C380
        sta $c2f1
        ldx #$7f
cy_c:   lda cyrep,x
        sta $c380,x
        dex
        bpl cy_c
        lda lt_cnt                  ; Zeilentabelle: Anzahl $C2F8/9, Eintraege (hoechstens 256) aus dem Attic nach $0004_0000
        sta $c2f8
        lda lt_cnt + 1
        sta $c2f9
        lda #$00
        sta P6
        sta P6 + 1
        sta P7
        sta P7 + 1
        sta P7 + 3
        lda #LT_B2
        sta P6 + 2
        lda #LT_B3
        sta P6 + 3
        lda #$04
        sta P7 + 2
        ldx #$08
lt_pg:  ldz #$00
lt_b:   lda [P6],z
        sta [P7],z
        inz
        bne lt_b
        inc P6 + 1
        inc P7 + 1
        dex
        bne lt_pg
        lda #$00
        tab
        plp
        bcs bad
        ldx #$00
p1:     lda ok,x
        beq pd
        jsr $ffd2
        inx
        bne p1
pd:     rts
bad:    ldx #$00
p2:     lda er,x
        beq pd
        jsr $ffd2
        inx
        bne p2
ok:     .byte 'O','K',13,0
er:     .byte 'F','E','H','L','E','R',13,0
.include "../src/asm/zp.asm"
.include "../src/asm/src.asm"
.include "../src/asm/optab.asm"
.include "../src/asm/mnfind.asm"
.include "../src/asm/sym.asm"
.include "../src/asm/expr.asm"
.include "../src/asm/enc.asm"
.include "../src/asm/numx.asm"
.include "../src/asm/math.asm"
.include "../src/asm/mathtab.asm"
.include "../src/asm/stage2.asm"
.include "../src/asm/dir2.asm"
.include "../src/asm/text2.asm"
.include "../src/asm/func.asm"
.include "../src/asm/list.asm"
.include "../src/asm/charnames.asm"
.include "../src/asm/err.asm"
.include "../src/asm/inc.asm"
.include "../src/asm/cyc.asm"
.include "../src/asm/loader.asm"
.include "../src/asm/asm.asm"
{srcdata}"""


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def one(name, src=None, attic=False, vcc_may_fail=False, files=None, d81=None, d81b=None):
    src = src or os.path.abspath(os.path.join(ROOT, "tests/asm", name + ".asm"))
    b = os.path.join(ROOT, "build")
    os.makedirs(b, exist_ok=True)
    exp = os.path.join(b, f"asmt_{name}.exp")
    r = run([VCC, "asm", src, "--target", "mega65", "--format", "bin", "--data-dir", DATA, "-o", exp])
    if r.returncode != 0 and not vcc_may_fail:
        return f"{name}: vcc-Fehler\\n{r.stdout}{r.stderr}"
    expected = open(exp, "rb").read() if r.returncode == 0 else None
    h = os.path.join(b, f"asmt_{name}.asm")
    attic = True                       # das Programm ist so gross, dass ein Quelltext dahinter in den Code laufen kann
    if attic:
        srcbase = "lda #$00\n        sta SRCBASE\n        sta SRCBASE + 1\n        sta SRCBASE + 2\n        lda #$08\n        sta SRCBASE + 3"
        srcdata = "source: .byte 0\n"
        srcpath = os.path.join(b, f"asmt_{name}.attic")
        img = open(src, "rb").read() + b"\x00"
        if True:                       # Dateitabelle (immer, auch leer, der Assembler sucht in jedem Durchlauf darin die Chipdatei); vorher: files or d81 - (bei der D81 leer: nur das Tabellenende) bei $0820_0000 (Attic-Versatz $200000)
            tab = b""
            for fn, data in (files or {}).items():
                nb = fn.encode()
                tab += bytes([len(nb)]) + nb + len(data).to_bytes(4, "little") + data + b"\x00"
            tab += b"\x00"
            img = img + b"\x00" * (0x200000 - len(img)) + tab
        open(srcpath, "wb").write(img)
    else:
        srcbase = "lda #<(source)\n        sta SRCBASE\n        lda #>(source)\n        sta SRCBASE + 1\n        lda #$00\n        sta SRCBASE + 2"
        srcdata = f'source: .incbin "{src}"\n        .byte 0\n'
    open(h, "w").write(HARNESS.format(srcbase=srcbase, srcdata=srcdata, pre=("lda #$01\n        sta ldon" if d81 else "") + ("\n        lda #$09\n        sta lddev" if d81b else "")))
    prg = os.path.join(b, f"asmt_{name}.prg")
    r = run([VCC, "asm", h, "--target", "mega65", "--data-dir", DATA, "-o", prg])
    if r.returncode != 0:
        return f"{name}: Pruefprogramm baut nicht\\n{r.stdout}{r.stderr}"
    env = dict(os.environ)
    if attic:
        env["XEMU_ARGS"] = f"-initattic {srcpath}" + (f" -8 {d81}" if d81 else "") + (f" -9 {d81b}" if d81b else "")
    r = run([os.path.join(ROOT, "tools/xrun.sh"), prg, "600" if attic else "90"], env=env)
    if r.returncode != 0:
        return f"{name}: Xemu-Lauf fehlgeschlagen (rc={r.returncode})"
    mem = open(os.path.join(b, "xrun.mem"), "rb").read()
    n = mem[0xc200] | (mem[0xc201] << 8)
    err = mem[0xc202]
    passes = mem[0xc203]
    global LAST_TIME
    ta = mem[0xc208] | (mem[0xc209] << 8)
    tb = mem[0xc20a] | (mem[0xc20b] << 8)
    LAST_TIME = (((0xFFFF - tb) << 16) + (0xFFFF - ta)) / 1e6      # Sekunden bei 1 MHz Zaehlertakt
    LAST_PASSES = passes
    got = mem[0x50000:0x50000 + n]
    nerr = mem[0xc210]
    errs = [(mem[0xc220 + 8 * i], mem[0xc221 + 8 * i] | (mem[0xc222 + 8 * i] << 8), mem[0xc223 + 8 * i] | (mem[0xc224 + 8 * i] << 8)) for i in range(min(nerr, 16))]
    global LAST_ERRS, LAST_WARNS, LAST_CYC, LAST_ERR_FILES
    LAST_ERRS = errs
    LAST_ERR_FILES = [mem[0xc225 + 8 * i] for i in range(min(nerr, 16))]
    nw = mem[0xc2f0]
    LAST_WARNS = [(mem[0xc300 + 8 * i], mem[0xc301 + 8 * i] | (mem[0xc302 + 8 * i] << 8)) for i in range(min(nw, 8))]
    LAST_CYC = []
    for i in range(min(mem[0xc2f1], 16)):
        e = mem[0xc380 + 8 * i: 0xc388 + 8 * i]
        LAST_CYC.append((e[0] | e[1] << 8, e[2] | e[3] << 8, (e[4] | e[5] << 8) if e[6] else None))
    if err != 0:
        pos = (mem[0xc204] | (mem[0xc205] << 8)) - (mem[0xc206] | (mem[0xc207] << 8))
        text = open(src, "rb").read()
        line = text[:pos].count(b"\n") + 1
        return f"{name}: native Fehler ERR={err} (Durchlauf {passes}) bei Zeile {line}, Zeichen {pos}: {text[max(0,pos-12):pos+12]!r}"
    if expected is None:
        return f"{name}: nativ ohne Fehler uebersetzt, vcc lehnt ab"
    if got != expected and len(expected) > 200:
        k = next((i for i in range(min(len(got), len(expected))) if got[i] != expected[i]), min(len(got), len(expected)))
        return (f"{name}: ABWEICHUNG erwartet {len(expected)} Byte, erhalten {len(got)} Byte; erste Abweichung bei Offset {k} "
                f"(${0x2001 + k:04x}): erwartet {expected[k:k+12].hex(' ')} erhalten {got[k:k+12].hex(' ')}")
    if got != expected:
        return f"{name}: ABWEICHUNG\\n  erwartet ({len(expected)}): {expected.hex(' ')}\\n  erhalten ({len(got)}): {got.hex(' ')}"
    return None


def main():
    names = sys.argv[1:] or sorted(os.path.basename(p)[:-4] for p in glob.glob(os.path.join(ROOT, "tests/asm/*.asm")))
    bad = 0
    for n in names:
        res = one(n)
        if res:
            bad += 1
            print("FEHLER", res)
        else:
            print("ok    ", n)
    print(f"{len(names) - bad} von {len(names)} bestanden")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()


def one_inc(name, main, files):
    """Projekt mit Hauptdatei und Include-Dateien (dict Pfad -> Text/Bytes): vcc uebersetzt im Projektordner, der native
    Assembler bekommt die Dateien als Tabelle im Attic."""
    d = os.path.join(ROOT, "build", "inc_" + name)
    import shutil
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    fb = {}
    for fn, data in files.items():
        data = data.encode() if isinstance(data, str) else data
        fb[fn] = data
        os.makedirs(os.path.dirname(os.path.join(d, fn)) or d, exist_ok=True)
        open(os.path.join(d, fn), "wb").write(data)
    mp = os.path.join(d, "main.asm")
    open(mp, "w").write(main)
    return one(name, mp, attic=True, vcc_may_fail=True, files=fb)


def one_disk(name, main, files):
    """Wie one_inc, aber die Include-Dateien liegen auf einer D81 (Laufwerk 8) und der Dateilader holt sie."""
    d = os.path.join(ROOT, "build", "disk_" + name)
    import shutil
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    cmd = [VCC, "disk", "d81", "-o", os.path.join(d, "p.d81"), "--data-dir", DATA]
    for fn, data in files.items():
        data = data.encode() if isinstance(data, str) else data
        os.makedirs(os.path.dirname(os.path.join(d, fn)) or d, exist_ok=True)
        open(os.path.join(d, fn), "wb").write(data)
        cmd += ["--add", f"{os.path.join(d, fn)}:{os.path.basename(fn).upper()}"]
    r = run(cmd)
    if r.returncode != 0:
        return f"{name}: D81 nicht gebaut {r.stdout}{r.stderr}"
    mp = os.path.join(d, "main.asm")
    open(mp, "w").write(main)
    return one(name, mp, attic=True, vcc_may_fail=True, d81=os.path.join(d, "p.d81"))
