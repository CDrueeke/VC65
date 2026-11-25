#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Test der IDE (src/ide/ide.asm, Editor + Assembler in einem Programm) in Xemu: Quelltext im Editor, Strg+E uebersetzt;
verglichen werden Ausgabebytes bzw. Fehlercode/-zeile mit vcc, der Cursor (springt in die Fehlerzeile) und die Meldung in der
Statuszeile; Strg+F speichert das Programm auf ein D81, das danach gelesen wird. Aufruf: tools/idetest.py"""
import os, re, sys, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest, disptest as D, edtest as E, build_ide, mksysdisk

ROOT = asmtest.ROOT
MAPN = {1: 201, 2: 202, 3: 203, 4: 204, 5: 205, 6: 206, 7: 207, 8: 208, 0x0a: 210, 0x0b: 211, 0x0c: 216, 0x0d: 213, 0x0e: 209, 0x0f: 207, 0x10: 212, 0x11: 214, 0x12: 218, 0x13: 215, 0x14: 212}


def scr2txt(b):
    out = ""
    for c in b:
        if 1 <= c <= 26: out += chr(0x60 + c)
        elif c == 0: out += "@"
        else: out += chr(c)
    return out.rstrip()


def vcc_result(path):
    prg = os.path.join(ROOT, "build", "ide_exp.prg")
    if os.path.exists(prg): os.remove(prg)
    r = asmtest.run([asmtest.VCC, "asm", path, "--target", "mega65", "--data-dir", asmtest.DATA, "-o", prg])
    out = r.stdout + r.stderr
    errs = [(m.group(1), int(m.group(2))) for m in re.finditer(r"error\[(E\d+)\][^\n]*\n\s*--> [^\n]*:(\d+)", out)]
    if errs: return None, errs
    return open(prg, "rb").read(), []


def run(text, keys, files=None, shot=None, chrome=False, d81b=None, xt=None, monitor=None):
    """shot: Pfad einer PNG-Datei: das Skript haelt am Ende an (Bild bleibt stehen), Xemu speichert beim Beenden einen Bildschirmfoto."""
    st = D.run_native(text, keys, files) if False else None
    tpl = open(os.path.join(ROOT, "src/test/idetest.asm")).read()
    src = tpl.replace("{tlen}", str(len(text))).replace("{keys}", E.bytes_lit(list(keys) + [0]))
    if chrome:      # IDE-Rahmen (Menue usw., src/ide/chrome.asm) wie in vc65.asm
        src = src.replace("        jsr ed_init\n", "        jsr ed_init\n        jsr chrome_init\n", 1)
        src = src.replace('.include "../ide/ide.asm"', '.include "../ide/ide.asm"\n.include "../ide/chrome.asm"', 1)
    if shot or monitor:
        src = src.replace("sk_stop: lda snapd", "sk_stop: jmp sk_stop\nsk_stop2: lda snapd", 1)
        src = src.replace("        jsr ide_init\n", "        jsr ide_init\n        jsr disp_init\n", 1)
    b = os.path.join(ROOT, "build")
    tab = build_ide.build_tables(os.path.join(b, "ide_tab"))      # VC65T (Befehlstabelle) und build/optabsyms.asm
    asm = os.path.join(b, "idt.asm")
    open(asm, "w").write(src.replace('"../', '"../src/'))
    prg = os.path.join(b, "idt.prg")
    r = asmtest.run([asmtest.VCC, "asm", asm, "--target", "mega65", "--data-dir", asmtest.DATA, "-o", prg, "--labels", os.path.join(b, "idt.vs")])
    if r.returncode != 0: raise SystemExit("IDE-Testprogramm baut nicht\n" + r.stdout + r.stderr)
    env = dict(os.environ)
    d81 = os.path.join(b, "ide_disk.d81")
    d = os.path.join(b, "ide_disk"); os.makedirs(d, exist_ok=True)
    cmd = [asmtest.VCC, "disk", "d81", "-o", d81, "--data-dir", asmtest.DATA]
    for fn, data in (files or {"DUMMY": b"x"}).items():
        open(os.path.join(d, fn), "wb").write(data if isinstance(data, bytes) else data.encode())
        cmd += ["--add", f"{os.path.join(d, fn)}:{fn.upper()}"]
    ov = build_ide.build_overlay(os.path.join(b, "idt.vs"), d)   # Debugger-Overlay VC65D auf das D81
    if not os.environ.get("NOOV"): cmd += ["--add", f"{ov}:VC65D"]
    cmd += ["--add", f"{tab}:VC65T", "--add", f"{build_ide.build_xoverlay(d)}:VC65X", "--add", f"{build_ide.build_aoverlay(os.path.join(b, 'idt.vs'), d)}:VC65A"]
    r = asmtest.run(cmd)
    if r.returncode != 0: raise SystemExit("D81 nicht gebaut " + r.stdout + r.stderr)
    ia = os.path.join(b, "ide_src.bin")
    open(ia, "wb").write(text)
    env["XEMU_ARGS"] = f"-initattic {ia} -8 {d81}" + (f" -9 {d81b}" if d81b else "") + (f" -screenshot {shot}" if shot else "")
    if monitor:      # Xemu mit UART-Monitor: monitor(x) liest den Speicher, waehrend das Programm laeuft (tools/xmon.py)
        from xmon import Xemu
        with Xemu(prg, xt or 60, ["-initattic", ia, "-8", d81] + (["-9", d81b] if d81b else [])) as x:
            return monitor(x)
    r = asmtest.run([os.path.join(ROOT, "tools/xrun.sh"), prg, str(xt or os.environ.get("XT", "300"))], env=env)
    if shot: return None
    if r.returncode != 0: raise SystemExit(f"Xemu-Lauf fehlgeschlagen rc={r.returncode}")
    m = open(os.path.join(b, "xrun.mem"), "rb").read()
    u32 = lambda a: m[a] | m[a + 1] << 8 | m[a + 2] << 16 | m[a + 3] << 24
    R = 0x1c400
    olen = u32(R + 4)
    return dict(cur=u32(R), curline=m[R + 8] | m[R + 9] << 8, olen=olen, out=bytes(m[0x40000:0x40000 + olen]),
                msg=scr2txt(m[R + 0x20 + 20:R + 0x20 + 80]), disk=D.d81_files(d81), mark=m[0xc500], mem=m, screen=bytes(m[0x41000:0x41000 + 2000]), dscreen=bytes(m[0x41800:0x41800 + 2000]))


CASES = {
    "ok1": ".org $2000\n lda #1\n sta $d020\n rts\n",
    "ok2": ".target mega65\n.org $2000\nstart: ldx #0\nl: inx\n bne l\n jmp start\n",
    "fehler1": ".org $2000\n nop\n foo\n nop\n",
    "fehler2": ".org $2000\n lda #1\n nop\n lda nowhere\n rts\n",
    "fehler3": ".org $2000\n nop\n nop\n .byte 1/0\n",
    "e300_code": " nop\n.org $2000\n rts\n",
    "e300_marke": "lb:\n.org $2000\n rts\n",
}


def main():
    bad = 0
    srcs = dict(CASES)
    for f in sorted(glob.glob(os.path.join(ROOT, "tests/asm/t0[0-3]*.asm")))[:4]:
        srcs[os.path.basename(f)[:-4]] = open(f).read()
    incfiles = {"INCL.ASM": " nop\n lda #7\n"}
    srcs["include"] = ".org $2000\n.include \"INCL.ASM\"\n rts\n"
    for fn, data in incfiles.items(): open(os.path.join(ROOT, "build", fn), "w").write(data)
    for name, body in srcs.items():
        text = body.encode()
        if len(text) > 1800: continue
        path = os.path.join(ROOT, "build", f"ide_{name}.asm")
        open(path, "w").write(body)
        prg, errs = vcc_result(path)
        keys = [0x05]
        if prg is not None: keys += [0x06] + D.pet(b"OUT") + [0x0d]
        n = run(text, keys, dict(incfiles) if name == "include" else None)
        problems = []
        if prg is not None:
            if n["out"] != prg[2:]: problems.append(f"Bytes {len(n['out'])} statt {len(prg) - 2}")
            if n["disk"].get(b"OUT") != prg: problems.append("Datei OUT")
            if n["msg"] != "Program saved": problems.append("Meldung " + n["msg"])
        else:
            m = re.match(r"E(\d+) line (\d+)", n["msg"])
            if not m: problems.append("Meldung " + n["msg"])
            else:
                if int(m.group(2)) != errs[0][1]: problems.append(f"Zeile {m.group(2)} statt {errs[0][1]}")
                if "E" + m.group(1) != errs[0][0] and m.group(1) != "201": problems.append(f"Code E{m.group(1)} statt {errs[0][0]}")
                if n["curline"] != errs[0][1]: problems.append(f"Cursorzeile {n['curline']}")
        print("ok   " if not problems else "DIFF ", name, "; ".join(problems))
        bad += 1 if problems else 0
    # Menue (HELP-Taste): Bauen > Uebersetzen per Menue; Abbruch mit STOP; Wirkung wie bei Strg+E
    HELP, RIGHT, DOWN, RET, STOP = 0x84, 0x1d, 0x11, 0x0d, 0x03
    body = ".org $2000\n lda #1\n sta $d020\n rts\n"
    mp = os.path.join(ROOT, "build", "ide_menu.asm")
    open(mp, "w").write(body)
    prg, errs = vcc_result(mp)
    ESC = 0x1b
    for name, keys, want in (("menue_esc", [ESC, RIGHT, RIGHT, RIGHT, RET], True), ("menue_bauen", [HELP, RIGHT, RIGHT, RIGHT, RET], True), ("menue_abbruch", [HELP, RIGHT, RIGHT, RIGHT, STOP], False),
                             ("menue_zyklus", [HELP, RIGHT, RIGHT, RIGHT, RIGHT, RIGHT, RIGHT, RIGHT, RIGHT, DOWN, DOWN, STOP, 0x05], True)):
        n = run(body.encode(), keys, chrome=True)
        problems = []
        if want and (prg is None or n["out"] != prg[2:]): problems.append(f"Bytes {n['out'].hex()}")
        if not want and n["olen"] != 0: problems.append("Ausgabe trotz Abbruch")
        print("ok   " if not problems else "DIFF ", name, "; ".join(problems))
        bad += 1 if problems else 0
    # Ersetzen ueber das Menue (Suchen > Ersetzen): alles ab dem Cursor; danach uebersetzen
    body = ".org $2000\n lda #1\n sta $d020\n LDA #2\n rts\n"
    exp_body = body.replace("lda", "ldx").replace("LDA", "ldx")
    mp = os.path.join(ROOT, "build", "ide_repl.asm")
    open(mp, "w").write(exp_body)
    prg, errs = vcc_result(mp)
    keys = [HELP, RIGHT, RIGHT] + [DOWN] * 4 + [RET] + D.pet(b"lda") + [RET] + D.pet(b"ldx") + [RET, 0x05]
    n = run(body.encode(), keys, chrome=True)
    problems = []
    if prg is None or n["out"] != prg[2:]: problems.append(f"Bytes {n['out'].hex()} statt {prg[2:].hex() if prg else None}")
    print("ok   " if not problems else "DIFF ", "ersetzen", "; ".join(problems))
    bad += 1 if problems else 0
    # Ausrichten ueber das Menue (Bearb > Alles ausrichten): der Text bleibt uebersetzbar mit gleichem Ergebnis
    body = ".org $2000\nstart:ldx #0\nloop:   stx   $d020 ; Farbe  \n  inx\n\tbne loop   \n  rts  \n"
    mp = os.path.join(ROOT, "build", "ide_fmt.asm")
    open(mp, "w").write(body)
    prg, errs = vcc_result(mp)
    keys = [HELP, RIGHT, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, RET, 0x05]
    n = run(body.encode(), keys, chrome=True)
    problems = []
    if prg is None or n["out"] != prg[2:]: problems.append(f"Bytes {n['out'].hex()} statt {prg[2:].hex() if prg else None}")
    print("ok   " if not problems else "DIFF ", "ausrichten", "; ".join(problems))
    bad += 1 if problems else 0
    # automatische Pruefung bei Zeilenwechsel nach einer Aenderung (Leerzeichen tippen, Pfeil ab): uebersetzt still, kein Cursorsprung
    for name, body, ok in (("auto_ok", ".org $2000\n nop\n rts\n", True), ("auto_fehler", ".org $2000\n nop\n foo\n rts\n", False)):
        mp = os.path.join(ROOT, "build", "ide_" + name + ".asm")
        open(mp, "w").write(body)
        prg, errs = vcc_result(mp)
        n = run(body.encode(), [0x20, DOWN], chrome=True)
        problems = []
        if ok and (prg is None or n["out"] != prg[2:]): problems.append(f"Bytes {n['out'].hex()}")
        if not ok and n["olen"] != 0: problems.append("Ausgabe trotz Fehler")
        en = [int(m.group(1), 16) for m in (re.match(r"al\s+C:([0-9a-fA-F]+)\s+\.ed_en\s*$", l.strip()) for l in open(os.path.join(ROOT, "build", "idt.vs"))) if m]
        cnt = n["mem"][0x40000 + en[0]]            # Zahl der roten Fehlerzeilen (ed_en, Bank 4)
        if cnt != (0 if ok else 1): problems.append(f"Fehlerzeilen {cnt}")
        if n["curline"] != 2: problems.append(f"Cursorzeile {n['curline']} (Sprung?)")
        print("ok   " if not problems else "DIFF ", name, "; ".join(problems))
        bad += 1 if problems else 0
    # Marken und Label-Sprung ueber das Menue (Suchen: Label suchen / Marke setzen / Marke anspringen)
    UP = 0x91
    body = ".org $2000\nstart:\n nop\nloop: nop\n bne loop\n rts\n"
    pr = lambda *k: list(k)
    mset = [HELP, RIGHT, RIGHT] + [DOWN] * 6 + [RET] + D.pet(b"1") + [RET]
    mgo = [HELP, RIGHT, RIGHT] + [DOWN] * 7 + [RET] + D.pet(b"1") + [RET]
    lab = [HELP, RIGHT, RIGHT] + [DOWN] * 5 + [RET] + D.pet(b"LOOP") + [RET]
    for name, keys, want in (("marke", [DOWN, DOWN] + mset + [UP, UP] + mgo, 3), ("marke_leer", mgo, 1), ("label", lab, 4)):
        n = run(body.encode(), keys, chrome=True)
        problems = []
        if n["curline"] != want: problems.append(f"Cursorzeile {n['curline']} statt {want}")
        print("ok   " if not problems else "DIFF ", name, "; ".join(problems))
        bad += 1 if problems else 0
    # Hex-Rechner und Daten einfuegen (Menue Bearb, Werkzeug-Overlay VC65X)
    body = ".org $2000\n nop\n rts\n"
    calc = [HELP, RIGHT] + [DOWN] * 8 + [RET]
    for name, txt, want in (("rechner_add", b"2000+3f", "$203f = 8255"), ("rechner_sub", b"$d020-$d000", "$0020 = 32"), ("rechner_null", b"10-10", "$0000 = 0"), ("rechner_fehler", b"xyz", "Input?")):
        n = run(body.encode(), calc + D.pet(txt) + [RET], chrome=True)
        problems = [] if n["msg"].startswith(want) else [f"Meldung '{n['msg']}' statt '{want}'"]
        print("ok   " if not problems else "DIFF ", name, "; ".join(problems))
        bad += 1 if problems else 0
    data = [HELP, RIGHT] + [DOWN] * 9 + [RET]
    n = run(body.encode(), [DOWN] + data + D.pet(b"2001 2008") + [RET, 0x05], chrome=True)
    want = bytes(n["mem"][0x2001:0x2009]) + b"\xea\x60"        # Speicher des Testprogramms (Bank 0) $2001-$2008 nach dem Lauf
    if want[:8] == bytes(8): print("WARNUNG daten_einfuegen: Bereich leer")
    problems = [] if n["out"] == want else [f"Bytes {n['out'].hex()} statt {want.hex()}"]
    print("ok   " if not problems else "DIFF ", "daten_einfuegen", "; ".join(problems))
    bad += 1 if problems else 0
    # Bibliotheken von der Systemdisk (Boot-D81): <mega65/...> und Chip-Symbole; Ergebnis wie vcc
    body = "#include <mega65/gs4502.asm>\n.org $2000\n mega65_enable_vic4\n lda #2\n sta vic2.border\n rts\n"
    sp = os.path.join(ROOT, "build", "ide_sys.asm")
    open(sp, "w").write(body)
    prg, errs = vcc_result(sp)
    sysf = {n: open(p, "rb").read() for n, p in mksysdisk.sys_list().items()}
    n = run(body.encode(), [0x05], sysf)
    problems = []
    if prg is None or n["out"] != prg[2:]: problems.append(f"Bytes {n['out'].hex()} statt {prg[2:].hex() if prg else None}")
    if not n["msg"].startswith("OK"): problems.append("Meldung " + n["msg"])
    print("ok   " if not problems else "DIFF ", "systemdisk", "; ".join(problems))
    bad += 1 if problems else 0
    # Programm starten (Strg+R): das Testprogramm schreibt $42 nach $C500 (Bank 0) und kehrt zurueck
    body = ".org $2001\n.basicstub start\nstart: lda #$42\n sta $c500\n rts\n"
    n = run(body.encode(), [0x05, 0x12])
    problems = []
    if n["mark"] != 0x42: problems.append(f"Marke {n['mark']:#x}")
    if n["msg"] != "Program ended": problems.append("Meldung " + n["msg"])
    print("ok   " if not problems else "DIFF ", "start", "; ".join(problems))
    bad += 1 if problems else 0
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
