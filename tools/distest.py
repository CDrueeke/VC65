#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Differenztest des Disassemblers (src/debug/dis.asm) gegen `vcc dis`: zufaellige gueltige Befehlsfolgen (alle Opcodes, mit
Quad- und $EA-Praefix) werden von beiden zerlegt und Adresse, Laenge und Text verglichen. Aufruf: tools/distest.py [Anzahl] [Start]"""
import json, os, random, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest, edtest as E

ROOT = asmtest.ROOT
CPU = json.load(open(os.path.join(ROOT, "vendor/vintagecoder/data/cpus/45gs02.cpu.json")))
QUAD_MODES = {"imp", "acc", "zp", "zpx", "abs", "abx", "izz"}
OPS = [(m, md, int(op.lstrip("$"), 16), n) for m, md, op, n, *_ in CPU["ops"]]
QOPS = {m for m in CPU["quadOps"].values()}


def gen(seed, count):
    r = random.Random(seed)
    out = bytearray()
    for _ in range(count):
        m, md, op, n = r.choice(OPS)
        pre = b""
        if m in QOPS and md in QUAD_MODES and r.random() < 0.3:
            pre = b"\x42\x42"
        if md == "izz" and r.random() < 0.5:
            pre += b"\xea"
        out += pre + bytes([op]) + bytes(r.randrange(256) for _ in range(n - 1))
    return bytes(out)


def vcc_dis(data, addr):
    b = os.path.join(ROOT, "build")
    prg = os.path.join(b, "dis_ref.prg")
    open(prg, "wb").write(bytes([addr & 255, addr >> 8]) + data)
    r = asmtest.run([asmtest.VCC, "dis", prg, "--cpu", "45gs02", "--data-dir", asmtest.DATA])
    res = []
    for l in r.stdout.splitlines():
        m = re.match(r"^([0-9a-f]{4})  ((?:[0-9a-f]{2} )*[0-9a-f]{2})\s+(.*)$", l)
        if m:
            nb = len(m.group(2).split())
            res.append((int(m.group(1), 16), nb, m.group(3).strip()))
    return res


def native(data):
    tpl = open(os.path.join(ROOT, "src/test/distest.asm")).read()
    src = tpl.replace("{prog}", E.bytes_lit(data))
    b = os.path.join(ROOT, "build")
    asm = os.path.join(b, "dist.asm")
    open(asm, "w").write(src.replace('"../', '"../src/'))
    prg = os.path.join(b, "dist.prg")
    r = asmtest.run([asmtest.VCC, "asm", asm, "--target", "mega65", "--data-dir", asmtest.DATA, "-o", prg, "--labels", os.path.join(b, "dist.vs")])
    if r.returncode != 0:
        raise SystemExit("Pruefprogramm baut nicht\n" + r.stdout + r.stderr)
    lab = {}
    for l in open(os.path.join(b, "dist.vs")):
        m = re.match(r"al\s+C:([0-9a-fA-F]+)\s+\.?(\S+)", l)
        if m: lab[m.group(2)] = int(m.group(1), 16)
    r = asmtest.run([os.path.join(ROOT, "tools/xrun.sh"), prg, os.environ.get("XT", "60")], env=dict(os.environ))
    if r.returncode != 0:
        raise SystemExit(f"Xemu-Lauf fehlgeschlagen rc={r.returncode}")
    m = open(os.path.join(b, "xrun.mem"), "rb").read()
    res, p, addr = [], 0x40000, lab["prog"]
    while m[p] != 0:
        ln = m[p]; p += 1
        t = bytearray()
        while m[p] != 0: t.append(m[p]); p += 1
        p += 1
        res.append((addr, ln, t.decode()))
        addr += ln
    return lab["prog"], res


def main():
    cnt = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    start = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    bad = 0
    for s in range(start, start + cnt):
        data = gen(s, 60)
        # Ladeadresse des Abbilds fuer vcc: gleiche Adresse wie im Testprogramm (Beschriftung prog)
        addr0, nat = native(data)
        ref = vcc_dis(data, addr0)
        diffs = [(a, b) for a, b in zip(ref, nat) if a != b]
        ok = not diffs and len(ref) == len(nat)
        print("seed", s, "ok" if ok else f"ABWEICHUNG ({len(ref)} vs {len(nat)})")
        if not ok:
            bad += 1
            for a, b in diffs[:6]: print("   vcc", a, "nativ", b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
