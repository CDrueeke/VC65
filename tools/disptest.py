#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Differenztest der Anzeigeschicht (src/editor/disp.asm) gegen ein Python-Modell: Tasten (PETSCII-Ebene) einschliesslich
Eingabezeile fuer Suchen und Gehe-zu; verglichen werden Bildschirmcodes und Farb-RAM des letzten Bildes sowie Kernzustand.
Aufruf: tools/disptest.py [Anzahl] [Start]"""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest
import edtest as E

ROOT = E.ROOT
SP_QUIT, SP_FIND, SP_NEXT, SP_GOTO, SP_PREV, SP_LOAD, SP_SAVE, SP_ASM, SP_PRG, SP_RUN, SP_DBG, SP_BP = 0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa, 0xfb
KMAP = {0x03: SP_QUIT, 0x85: SP_FIND, 0x89: SP_NEXT, 0x86: SP_GOTO, 0x8a: SP_PREV, 0x87: E.K_MARK, 0x8b: E.K_COPY,
        0x88: E.K_CUT, 0x8c: E.K_PASTE, 0x10: E.K_UNDO, 0x15: E.K_REDO, 0x16: E.K_PGUP, 0x17: E.K_PGDN, 0x93: E.K_END, 0x94: E.K_DEL, 0x0f: SP_LOAD, 0x0b: SP_SAVE, 0x05: SP_ASM, 0x06: SP_PRG, 0x12: SP_RUN, 0x04: SP_DBG, 0x07: SP_BP}
KPASS = (E.K_RET, E.K_TAB, E.K_BS, E.K_UP, E.K_DOWN, E.K_LEFT, E.K_RIGHT, E.K_HOME)


def dmap(k):
    if k in KMAP: return KMAP[k]
    if 0x41 <= k < 0x5b: k |= 0x20
    elif 0xc1 <= k < 0xdb: k &= 0x7f
    if 0x20 <= k < 0x7f: return k
    return k if k in KPASS else 0


class Disp:
    def __init__(self, text, files=None):
        self.e = E.Ed(25, text)
        self.e.view()
        self.pat = b""
        self.fs = {k.upper().encode(): v for k, v in (files or {}).items()}
        self.fname = b""
        self.oname = b""
        self.msg = 0
        self.prompt = None           # None | (kind, bytearray)

    def key(self, k):
        m = dmap(k)
        if m == 0: return
        self.msg = 0
        if self.prompt is not None:
            kind, buf = self.prompt
            if m == SP_QUIT: self.prompt = None
            elif m == E.K_RET:
                self.prompt = None
                if kind == 0:
                    self.pat = bytes(buf); self.e.find(self.pat, True)
                elif kind == 1:
                    if buf: self.e.goto(int(bytes(buf)))
                elif kind == 4:
                    if buf: self.oname = bytes(buf)
                elif buf:
                    self.fname = bytes(buf); self.fileop(kind)
            elif m == E.K_BS:
                if buf: buf.pop()
            elif 0x20 <= m < 0x7f:
                if kind == 0:
                    if len(buf) < 32: buf.append(m)
                elif kind == 1:
                    if 0x30 <= m <= 0x39 and len(buf) < 4: buf.append(m)
                elif len(buf) < 16: buf.append(m)
            return
        if m == SP_QUIT: return
        if m == SP_FIND: self.prompt = (0, bytearray(self.pat))
        elif m == SP_GOTO: self.prompt = (1, bytearray())
        elif m == SP_LOAD: self.prompt = (2, bytearray(self.fname))
        elif m == SP_SAVE: self.prompt = (3, bytearray(self.fname))
        elif m == SP_PRG: self.prompt = (4, bytearray(self.oname))
        elif m in (SP_ASM, SP_RUN, SP_DBG, SP_BP): pass
        elif m == SP_NEXT: self.e.find(self.pat, True)
        elif m == SP_PREV: self.e.find(self.pat, False)
        else: self.e.key(m)

    def fileop(self, kind):
        nm = bytes(c & 0xdf if 0x61 <= c < 0x7b else c for c in self.fname)
        if kind == 2:
            data = self.fs.get(nm)
            if not data: self.msg = 2; return
            out = bytearray(); cr = False
            for c in data:
                if c == 0: continue
                if c == 0x0d: out.append(10); cr = True
                elif c == 0x0a:
                    if cr: cr = False
                    else: out.append(10)
                else: cr = False; out.append(c)
            e = self.e
            e.t = out; e.cur = 0; e.top = 0; e.topline = 1; e.left = 0; e.want = None
            e.sel = False; e.log = []; e.hp = 0
            e.view()
        else:
            self.fs[nm] = bytes(self.e.t) or b"\r"; self.msg = 1      # das Laufwerk legt eine leere Datei als ein CR an

    def frame(self):
        e = self.e
        scr, attr = bytearray(e.screen2()[0]), bytearray(e.screen2()[1])
        if self.prompt is None and self.msg:
            t = {1: b"Saved", 2: b"Error loading", 3: b"Error saving"}[self.msg]
            for i, c in enumerate(t): scr[24 * 80 + 20 + i] = E.asc2scr(c)
        if self.prompt is None:
            row = e.curline() - e.topline
            off = row * 80 + (e.col() - e.left) + E.GUTTER
        else:
            kind, buf = self.prompt
            base = 24 * 80
            scr[base:base + 80] = bytes([0x20]) * 80
            attr[base:base + 80] = bytes([E.COL_TEXT]) * 80
            lab = (b"Find:  " if kind == 0 else b"Line:  " if kind == 1 else b"File:  ") + bytes(buf)
            for i, c in enumerate(lab): scr[base + i] = E.asc2scr(c)
            off = base + 7 + len(buf)
        attr[off] ^= E.SELF
        return bytes(scr), bytes(attr)


def d81_files(path):
    m = open(path, "rb").read()
    sec = lambda t, s: m[((t - 1) * 40 + s) * 256:((t - 1) * 40 + s) * 256 + 256]
    files = {}
    t, s = 40, 3
    seen = set()
    while t and (t, s) not in seen:
        seen.add((t, s))
        d = sec(t, s)
        for i in range(8):
            ent = d[i * 32:(i + 1) * 32]
            if ent[2] & 7 == 0: continue
            name = bytes(ent[5:21]).rstrip(b"\xa0")
            data = bytearray(); ft, fs = ent[3], ent[4]
            while ft:
                b = sec(ft, fs)
                if b[0]: data += b[2:]
                else: data += b[2:b[1] + 1]
                ft, fs = b[0], b[1]
            files[name] = bytes(data)
        t, s = d[0], d[1]
    return files


def run_native(text, keys, files=None):
    tpl = open(os.path.join(ROOT, "src/test/disptest.asm")).read()
    src = tpl.replace("{text}", E.bytes_lit(text) if text else "").replace("{keys}", E.bytes_lit(list(keys) + [0]))
    b = os.path.join(ROOT, "build")
    asm = os.path.join(b, "dpt.asm")
    open(asm, "w").write(src.replace('"../', '"../src/'))
    prg = os.path.join(b, "dpt.prg")
    r = asmtest.run([asmtest.VCC, "asm", asm, "--target", "mega65", "--data-dir", asmtest.DATA, "-o", prg])
    if r.returncode != 0:
        raise SystemExit("Pruefprogramm baut nicht\n" + r.stdout + r.stderr)
    env = dict(os.environ)
    d81 = None
    if files is not None:
        d = os.path.join(b, "dpt_disk")
        import shutil
        shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
        d81 = os.path.join(d, "p.d81")
        cmd = [asmtest.VCC, "disk", "d81", "-o", d81, "--data-dir", asmtest.DATA]
        for fn, data in files.items():
            open(os.path.join(d, fn), "wb").write(data)
            cmd += ["--add", f"{os.path.join(d, fn)}:{fn.upper()}"]
        r = asmtest.run(cmd)
        if r.returncode != 0: raise SystemExit("D81 nicht gebaut " + r.stdout + r.stderr)
        env["XEMU_ARGS"] = f"-8 {d81}"
    r = asmtest.run([os.path.join(ROOT, "tools/xrun.sh"), prg, "90"], env=env)
    if r.returncode != 0:
        raise SystemExit(f"Xemu-Lauf fehlgeschlagen rc={r.returncode}")
    m = open(os.path.join(b, "xrun.mem"), "rb").read()
    u32 = lambda a: m[a] | m[a + 1] << 8 | m[a + 2] << 16 | m[a + 3] << 24
    st = dict(cur=u32(0xc400), top=u32(0xc404), length=u32(0xc408), curline=m[0xc40c] | m[0xc40d] << 8,
              topline=m[0xc40e] | m[0xc40f] << 8, left=m[0xc410] | m[0xc411] << 8, patn=m[0xc412])
    st["text"] = bytes(m[0xc600:0xc600 + st["length"]])
    st["screen"] = bytes(m[0xa000:0xa000 + 2000])
    st["attr"] = bytes(m[0x9000:0x9000 + 2000])
    if d81: st["disk"] = d81_files(d81)
    return st


def gen(seed):
    r = random.Random(seed)
    text = b"\n".join(E.gen_line(r)[:60] for _ in range(r.randrange(0, 12)))
    keys = []
    FK = [0x85, 0x89, 0x86, 0x8a, 0x87, 0x8b, 0x88, 0x8c, 0x10, 0x15, 0x16, 0x17, 0x93, 0x94]
    for _ in range(r.randrange(10, 80)):
        k = r.random()
        if k < 0.25: keys.append(r.choice(b"abcxyz ;09,."))
        elif k < 0.32: keys.append(r.choice([0x41, 0x42, 0x58, 0xc1, 0xc2, 0xd8]))   # PETSCII-Buchstaben
        elif k < 0.40: keys.append(r.choice([0x0d, 0x09, 0x14]))
        elif k < 0.50: keys.append(r.choice([0x91, 0x11, 0x9d, 0x1d, 0x13]))
        elif k < 0.55: keys.append(r.choice([0xfe, 0xa0, 0x01, 0x80]))              # ignorierte Tasten
        elif k < 0.70: keys.append(r.choice(FK))
        elif k < 0.80:
            keys += [0x85] + list(r.choice([b"a", b"xy", b"B", b"l", b";"]) + b"") + [0x0d]  # Suchen
        elif k < 0.87:
            keys += [0x86] + list(str(r.randrange(0, 30)).encode()) + [0x0d]                  # Gehe zu
        elif k < 0.90: keys += [0x85, 0x03]
        elif k < 0.96: keys.append(r.choice([0x0e, 0x0e, 0x0c, 0x0c, 0x0a]))
        else: keys += [0x89, 0x8a]
    return text, keys


def pet(name):
    return [c - 0x20 if 0x61 <= c <= 0x7a else c + 0x80 if 0x41 <= c <= 0x5a else c for c in name]


def gen_files(seed):
    r = random.Random(seed)
    text, keys = gen(seed)
    keys = [k for k in keys if k not in (0x0f, 0x0b)][:30]
    def content():
        kind = r.randrange(5)
        base = b"\n".join(E.gen_line(r)[:50] for _ in range(r.randrange(1, 40)))
        if kind == 0: return base or b"x"
        if kind == 1: return base.replace(b"\n", b"\r\n") or b"x"
        if kind == 2: return base.replace(b"\n", b"\r") or b"x"
        if kind == 3: return (base + b"\n\x00\n" + base)[:700] or b"x"
        return bytes(r.choice(b"abc\n\r ") for _ in range(r.randrange(1, 600)))
    files = {"IN": content(), "AB": content()}
    ops = []
    for _ in range(r.randrange(2, 7)):
        k = r.random()
        nm = r.choice([b"IN", b"AB", b"out", b"Out2", b"NOPE", b"in"])
        if k < 0.45: ops.append([0x0f] + pet(nm) + [0x0d])
        elif k < 0.85: ops.append([0x0b] + pet(nm) + [0x0d])
        else: ops.append([0x0f, 0x03])
        ops.append(r.choice([[0x61, 0x62], [0x0d, 0x91], [0x13, 0x41], [0x11, 0x11, 0x1d]]))
    for o in ops: keys += o
    return text[:300], keys, files


def main_files(cnt, start):
    bad = 0
    for sd in range(start, start + cnt):
        text, keys, files = gen_files(sd)
        d = Disp(text, files)
        for k in keys: d.key(k)
        scr, attr = d.frame()
        n = run_native(text, keys, files)
        e = d.e
        exp = dict(cur=e.cur, top=e.top, length=len(e.t), curline=e.curline(), topline=e.topline, left=e.left,
                   patn=len(d.pat), text=bytes(e.t), screen=scr, attr=attr)
        diff = [k for k in exp if exp[k] != n[k]]
        for nm, data in d.fs.items():
            if n["disk"].get(nm) != data: diff.append("disk:" + nm.decode())
        print("files seed", sd, "ok" if not diff else f"ABWEICHUNG {diff}")
        if diff:
            bad += 1
            for k in diff:
                if k in n and k not in ("text", "screen", "attr"): print("   ", k, "erwartet", exp[k], "nativ", n[k])
    sys.exit(1 if bad else 0)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "files":
        return main_files(int(sys.argv[2]) if len(sys.argv) > 2 else 6, int(sys.argv[3]) if len(sys.argv) > 3 else 1)
    cnt = int(sys.argv[1]) if len(sys.argv) > 1 else 6
    start = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    bad = 0
    for s in range(start, start + cnt):
        text, keys = gen(s)
        d = Disp(text)
        for k in keys: d.key(k)
        scr, attr = d.frame()
        n = run_native(text, keys)
        e = d.e
        exp = dict(cur=e.cur, top=e.top, length=len(e.t), curline=e.curline(), topline=e.topline, left=e.left,
                   patn=len(d.pat), text=bytes(e.t), screen=scr, attr=attr)
        diff = [k for k in exp if exp[k] != n[k]]
        print("seed", s, "ok" if not diff else f"ABWEICHUNG {diff}")
        if diff:
            bad += 1
            for k in diff:
                if k not in ("text", "screen", "attr"): print("   ", k, "erwartet", exp[k], "nativ", n[k])
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
