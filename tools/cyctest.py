#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Zyklentest: .cycles/.endcycles. vcc liefert ueber --debug die Bloecke (min, max, Budget) und die Warnung W201; der native
Assembler muss dieselben Zahlen und Warnungen (Zeile) liefern. Aufruf: tools/cyctest.py"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

H = ".target mega65\n.org $2000\n"
CASES = {
    "irq": ".cycles irq max=24\n inc $d020\n lda $d012\n sta $d021\n rts\n.endcycles\n",
    "langsam": ".cycles langsam max=10\n lda $d020\n sta $d021\n jsr $ffd2\n.endcycles\n",
    "schleife": ".cycles s max=20\n .repeat 3\n nop\n .endrepeat\n lda $1234,x\n beq weiter\n nop\nweiter: nop\n.endcycles\n",
    "verschachtelt": ".cycles aussen\n nop\n.cycles innen max=3\n lda #1\n nop\n.endcycles\n rts\n.endcycles\n",
    "ohne_namen": ".cycles\n ldx #5\nl: dex\n bne l\n.endcycles\n",
    "quad": ".cycles q\n ldq $10\n stq [$20],z\n inq\n.endcycles\n",
    "lang": ".branchlong auto\n.cycles lb\n bne far\n .fill 300, $ea\nfar: nop\n.endcycles\n",
    "if": ".cycles c\n .if 0\n nop\n .else\n lda #1\n .endif\n.endcycles\n",
}


def main():
    bad = 0
    for name, body in CASES.items():
        path = os.path.join(asmtest.ROOT, "build", f"cyc_{name}.asm")
        open(path, "w").write(H + body)
        dbg = path + ".vcdbg"
        r = asmtest.run([asmtest.VCC, "asm", path, "--target", "mega65", "--format", "bin", "--data-dir", asmtest.DATA, "-o", "/tmp/cyc.bin", "--debug", dbg])
        out = r.stdout + r.stderr
        warn = sorted(int(m.group(1)) for m in re.finditer(r"warning\[W201\][^\n]*\n\s*--> [^\n]*:(\d+)", out))
        exp = []
        if os.path.exists(dbg):
            exp = [(c["min"], c["max"], c.get("budget")) for c in json.load(open(dbg)).get("cycleBlocks", [])]
        res = asmtest.one("c_" + name, path, vcc_may_fail=True)
        got = sorted(asmtest.LAST_CYC)
        gw = sorted(l for c, l in asmtest.LAST_WARNS if c == 0x21)
        ok = sorted(exp, key=str) == sorted(got, key=str) and warn == gw
        print("ok    " if ok else "DIFF  ", name, "" if ok else f"vcc {exp} {warn} nativ {got} {gw}")
        bad += 0 if ok else 1
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
