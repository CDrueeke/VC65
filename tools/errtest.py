#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fehlerlistentest: vergleicht die Fehler (Code, Zeile) von vcc und vom nativen Assembler (Xemu) fuer eigene Faelle und fuer
die Fehlerbeispiele der VCASM-Hilfe (```asm fehler). Native Codes: 1 = Syntaxfehler (passt zu jedem vcc-Code).
Aufruf: tools/errtest.py"""
import os, re, subprocess, sys, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

ROOT = asmtest.ROOT
MAP = {2: "E202", 3: "E203", 4: "E204", 5: "E205", 6: "E206", 7: "E207", 8: "E208", 0x0a: "E210", 0x0b: "E211", 0x0c: "E216", 0x0d: "E213", 0x0e: "E209", 0x0f: "E207", 0x11: "E214", 0x12: "E218", 0x13: "E215"}

CASES = {
    "mehrere": " lda #256\n foo\n lda nowhere\n nop\n .byte 1/0\n bne -\n lda #1\n",
    "makro": ".macro m(a)\n lda a\n.endmacro\n m 1, 2\n lda zzz\n m 300\n",
    "schleife": ".repeat 2\n lda unbekannt\n.endrepeat\n nop\n",
    "endcycles": " nop\n.endcycles\n nop\n",
    "cycles_offen": " nop\n.cycles x\n nop\n",
    "scope": "a: {\n nop\n}\n}\n nop\n",
}


def vcc_errors(path):
    r = asmtest.run([asmtest.VCC, "asm", path, "--target", "mega65", "--format", "bin", "--data-dir", asmtest.DATA, "-o", "/tmp/errt.bin"])
    out = r.stdout + r.stderr
    res = []
    for m in re.finditer(r"error\[(E\d+)\][^\n]*\n\s*--> [^\n]*:(\d+)", out):
        res.append((m.group(1), int(m.group(2))))
    return res


def native_errors(name, path):
    r = asmtest.one(name, path, vcc_may_fail=True)
    return [(MAP.get(c, "SYN" if c == 1 else f"?{c}"), line) for c, line, col in asmtest.LAST_ERRS]


def harvest():
    out = []
    for f in sorted(glob.glob(os.path.join(ROOT, "vendor/vintagecoder/help/*.md"))):
        t = open(f).read()
        for i, m in enumerate(re.finditer(r"```asm fehler[^\n]*\n(.*?)```", t, re.S)):
            out.append((os.path.basename(f)[:-3] + f"_{i:02d}", m.group(1)))
    return out


def limits():
    """Makro-Parametergrenze von VC65 (MAXPAR = 16; vcc kennt keine): 16 Parameter wie vcc, 17 melden E900 (Code $17)."""
    bad = 0
    for n, k, want in (("par16", 16, None), ("par17", 17, 0x17)):
        names = ", ".join(f"p{i}" for i in range(k))
        args = ", ".join(str(i) for i in range(k))
        src = f".org $2000\n.macro m({names})\n lda #p0\n.endmacro\n m {args}\n rts\n"
        path = os.path.join(ROOT, "build", f"err_{n}.asm")
        open(path, "w").write(src)
        r = asmtest.one("e_" + n, path, vcc_may_fail=True)
        got = [c for c, line, col in asmtest.LAST_ERRS]
        ok = (r is None) if want is None else (want in got)
        print("ok    " if ok else "DIFF  ", n, "" if ok else f"erwartet {'identisch' if want is None else hex(want)}, erhalten {r if r else got}")
        bad += 0 if ok else 1
    return bad


def main():
    cases = [(k, v) for k, v in CASES.items()] + harvest()
    bad = 0
    for name, body in cases:
        src = ".target mega65\n.org $2000\n" + body if ".org" not in body and "*=" not in body else ".target mega65\n" + body
        path = os.path.join(ROOT, "build", f"err_{name}.asm")
        open(path, "w").write(src)
        exp = vcc_errors(path)
        if not exp:
            continue                                        # vcc meldet in diesem Beispiel keinen Fehler (Warnungen u. a.)
        got = native_errors("e_" + name, path)
        ok = len(exp) == len(got) and all(g[1] == e[1] and (g[0] in (e[0], "SYN")) for g, e in zip(got, exp))
        print(("ok    " if ok else "DIFF  "), name, "" if ok else f"vcc {exp} nativ {got}")
        bad += 0 if ok else 1
    bad += limits()
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
