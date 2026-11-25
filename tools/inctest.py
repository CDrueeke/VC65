#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Include-Test: .include, #include, as name, .incbin, verschachtelte Pfade, Makros aus Include-Dateien, Fehler in
Include-Dateien; vcc und der native Assembler (Dateitabelle im Attic) muessen dieselben Bytes bzw. Fehler liefern."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

H = ".target mega65\n.org $2000\n"
F = {
    "lib.inc": "SPEED = 3\nspiele: lda #SPEED\n        rts\n",
    "sub/x.inc": '.include "../y.inc"\nxlab: nop\n',
    "y.inc": ".macro wait(n)\n  ldx #n\n.endmacro\n.byte $99\n",
    "once.inc": "ONCE = 5\n.byte ONCE\n",
    "uses.inc": '#include "once.inc"\n.byte ONCE + 1\n',
    "bad.inc": " nop\n lda nowhere\n foo\n",
    "data.bin": bytes([1, 2, 3, 4, 5]),
    "big.bin": bytes(i % 251 for i in range(700)),
    "b512.bin": bytes((i * 7) % 256 for i in range(512)),
}
CASES = {
    "basis": H + '.include "lib.inc"\n jsr spiele\n .byte SPEED\n',
    "as": H + '.include "lib.inc" as m1\n.include "lib.inc" as m2\n jsr m1.spiele\n jsr m2.spiele\n lda #m2.SPEED\n',
    "pfad": H + '.include "sub/x.inc"\n wait 3\n jmp xlab\n',
    "makro_vorher": H + ' wait 4\n.include "y.inc"\n',
    "incbin": H + '.incbin "data.bin"\n.incbin "data.bin", 2\n.incbin "data.bin", 1, 2\n',
    "gross": H + '.incbin "big.bin"\n.incbin "b512.bin"\n.incbin "big.bin", 600, 50\n',
    "once": H + '#include "once.inc"\n#include "uses.inc"\n#include "uses.inc"\n',
    "schleife": H + '.repeat 2, n\n.include "once.inc"\n.endrepeat\n',
}
ERRCASES = {
    "fehler_in_include": H + ' nop\n.include "bad.inc"\n lda nowhere2\n',
    "fehlt": H + ' nop\n.include "gibts-nicht.inc"\n nop\n',
}


def main():
    bad = 0
    for name, main_src in CASES.items():
        for tag, fn in (("", asmtest.one_inc), ("_disk", asmtest.one_disk)):
            r = fn(name + tag, main_src, F)
            print(("ok    " if not r else "FEHLER"), name + tag, r or "")
            bad += 1 if r else 0
    for name, main_src in [(k + t, v) for k, v in ERRCASES.items() for t in ("", "_disk")]:
        disk = name.endswith("_disk")
        d = os.path.join(asmtest.ROOT, "build", ("disk_" if disk else "inc_") + name)
        r = (asmtest.one_disk if disk else asmtest.one_inc)(name, main_src, F)
        out = asmtest.run([asmtest.VCC, "asm", os.path.join(d, "main.asm"), "--target", "mega65", "--format", "bin", "--data-dir", asmtest.DATA, "-o", "/tmp/inc.bin"])
        exp = [(m.group(1), int(m.group(2))) for m in re.finditer(r"error\[(E\d+)\][^\n]*\n\s*--> [^\n]*:(\d+)", out.stdout + out.stderr)]
        got = [(("E212" if c == 0x14 else "E202" if c == 2 else "E205" if c == 5 else f"?{c}"), l) for c, l, col in asmtest.LAST_ERRS]
        ok = [e for e in exp] == got
        print(("ok    " if ok else "DIFF  "), name, "" if ok else f"vcc {exp} nativ {got}")
        bad += 0 if ok else 1
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
