#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Differenztest des Editorkerns (src/editor/ed.asm): ein Python-Referenzeditor und der native Kern in Xemu muessen nach
demselben Tastenskript denselben Text, Cursor, Bildausschnitt und dasselbe Bild haben. Aufruf: tools/edtest.py [anzahl] [startwert]"""
import os, random, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

ROOT = asmtest.ROOT
K_RET, K_TAB, K_BS, K_DEL, K_UP, K_DOWN, K_LEFT, K_RIGHT, K_HOME, K_END, K_PGUP, K_PGDN = 0x0d, 0x09, 0x14, 0xc3, 0x91, 0x11, 0x9d, 0x1d, 0x13, 0xc0, 0xc1, 0xc2
K_UNDO, K_REDO = 0x1a, 0x19
K_MARK, K_COPY, K_CUT, K_PASTE = 0x02, 0x03, 0x18, 0x16
SELF = 0x20
SCRW, GUTTER = 80, 5
COL_TEXT, COL_GUTTER, COL_COMMENT, COL_STRING, COL_NUM, COL_DIR, COL_LABEL, COL_MNEM = 1, 11, 12, 5, 7, 3, 14, 13


def _mnemonics():
    import json
    d = json.load(open(os.path.join(ROOT, "vendor/vintagecoder/data/cpus/45gs02.cpu.json")))
    m = {o[0] for o in d["ops"]} | set(d["quadOps"]) | {"NOP"}
    return {x for x in m if len(x) <= 4}


MNEM = _mnemonics()


def line_colours(t):
    """Farbe je Zeichen einer Zeile (Spiegel des Lexers in ed.asm)."""
    n = len(t)
    col = [COL_TEXT] * n
    isid = lambda c: c == 0x5f or 0x41 <= c <= 0x5a or 0x61 <= c <= 0x7a
    isdig = lambda c: 0x30 <= c <= 0x39
    ishex = lambda c: isdig(c) or 0x61 <= (c | 0x20) <= 0x66
    at = lambda i: t[i] if i < n else 0
    first = True
    i = 0
    state = 0
    while i < n:
        c = t[i]
        if state == 1:
            col[i] = COL_COMMENT; i += 1; continue
        if state == 2:
            col[i] = COL_STRING
            if c == 0x22: state = 0
            i += 1; continue
        if c == 0x3b or (c == 0x2f and at(i + 1) == 0x2f):
            state = 1; col[i] = COL_COMMENT; i += 1; continue
        if c == 0x22:
            state = 2; col[i] = COL_STRING; i += 1; continue
        k = None; tok = COL_TEXT; fn = None
        if c == 0x2e and isid(at(i + 1)):
            j = i + 1
            while isid(at(j)) or isdig(at(j)): j += 1
            ln = j - i; tok = COL_DIR; fn = "id"
        elif isdig(c):
            j = i
            while isid(at(j)) or isdig(at(j)): j += 1
            for q in range(i, j): col[q] = COL_NUM
            first = False; i = j; continue
        elif c == 0x24 and ishex(at(i + 1)):
            j = i + 1
            while ishex(at(j)) or at(j) == 0x5f: j += 1
            for q in range(i, j): col[q] = COL_NUM
            first = False; i = j; continue
        elif c == 0x25 and at(i + 1) in (0x30, 0x31):
            j = i + 1
            while at(j) in (0x30, 0x31, 0x5f): j += 1
            for q in range(i, j): col[q] = COL_NUM
            first = False; i = j; continue
        elif isid(c):
            j = i
            while isid(at(j)) or isdig(at(j)): j += 1
            ln = j - i; fn = "id"
        else:
            i += 1; continue
        # Bezeichner oder Direktive ab i, Laenge ln
        if i == 0 and at(i + ln) == 0x3a:
            for q in range(i, i + ln + 1): col[q] = COL_LABEL
            i += ln + 1; continue
        if tok != COL_DIR and first and ln <= 4 and bytes(t[i:i + ln]).upper().decode("latin1") in MNEM:
            tok = COL_MNEM
        for q in range(i, i + ln): col[q] = tok
        first = False
        i += ln
    return col


def asc2scr(c):
    if c < 0x20 or c >= 0x7f: return 0x2e
    if c < 0x40: return c
    if c == 0x40: return 0
    if c < 0x5b: return c
    if c < 0x60: return c - 0x40
    if c == 0x60: return 0x2e
    if c < 0x7b: return c - 0x60
    return 0x2e


class Ed:
    def __init__(self, rows, text=b""):
        self.rows = rows
        self.t = bytearray(text)
        self.cur = 0
        self.top = 0
        self.topline = 1
        self.left = 0
        self.want = None
        self.sel = False; self.anc = 0; self.clip = b""
        self.log = []; self.hp = 0; self.grp = 0; self.lastkind = 0

    def ins(self, b):
        cb = self.cur
        self.t.insert(self.cur, b); self.cur += 1
        del self.log[self.hp:]
        self.log.append((1, b, self.grp, cb, cb, self.cur)); self.hp += 1

    def dele_at(self, pos, cb):
        b = self.t[pos]; del self.t[pos]
        del self.log[self.hp:]
        self.log.append((2, b, self.grp, pos, cb, pos)); self.hp += 1

    def kind(self, k):
        if k == K_RET: kd = 2
        elif k == K_BS: kd = 3
        elif k == K_DEL: kd = 4
        elif k == K_TAB or 0x20 <= k < 0x7f: kd = 1
        else: kd = 0
        if kd == 0 or kd != self.lastkind: self.grp = (self.grp + 1) & 0xffff
        self.lastkind = kd

    def apply(self, e, rev):
        ty, b, g, pos, cb, ca = e
        self.cur = pos
        if (ty == 1) != rev:
            self.t.insert(pos, b); self.cur = pos + 1
        else:
            del self.t[pos]

    def undo(self):
        if self.hp == 0: return
        g = self.log[self.hp - 1][2]; last = None
        while self.hp > 0 and self.log[self.hp - 1][2] == g:
            e = self.log[self.hp - 1]; self.apply(e, True); last = e[4]; self.hp -= 1
        self.cur = last

    def redo(self):
        if self.hp == len(self.log): return
        g = self.log[self.hp][2]; last = None
        while self.hp < len(self.log) and self.log[self.hp][2] == g:
            e = self.log[self.hp]; self.apply(e, False); last = e[5]; self.hp += 1
        self.cur = last

    def find(self, pat, fwd):
        self.kind(0)
        n = len(self.t)
        if n == 0 or not pat:
            self.view(); return
        low = lambda b: bytes(c | 0x20 if 0x41 <= c < 0x5b else c for c in b)
        pat = low(pat)
        p = self.cur + 1 if fwd else (self.cur - 1 if self.cur > 0 else n - 1)
        if fwd and p >= n: p = 0
        for _ in range(n):
            if low(bytes(self.t[p:p + len(pat)])) == pat:
                self.cur = p; self.want = None; break
            if fwd:
                p += 1
                if p >= n: p = 0
            else:
                p = p - 1 if p > 0 else n - 1
        self.view()

    def replace_all(self, pat, rep):
        """wie ed_repl_all: ab dem Cursor bis zum Ende, ohne Umbruch; je Treffer Rueckschritte und Zeichen wie Tasten"""
        self.kind(0)
        self.sel = False
        if not self.t or not pat:
            self.view(); return
        low = lambda b: bytes(c | 0x20 if 0x41 <= c < 0x5b else c for c in b)
        pat = low(pat)
        p = self.cur
        while p + len(pat) <= len(self.t):
            if low(bytes(self.t[p:p + len(pat)])) == pat:
                self.cur = p + len(pat)
                for _ in pat: self.key(K_BS)
                for c in rep: self.key(c)
                p = self.cur
            else: p += 1
        self.want = None
        self.view()

    @staticmethod
    def fmt(line):
        """wie fm_conv: Zeile in Spalten ausrichten (Marke 0, Befehl 8, Operand 8 + max(4, Laenge + 1), Kommentar 32)"""
        ws = b" \t"
        n = len(line)
        i = 0
        while i < n and line[i] in ws: i += 1
        if i == n: return b""
        raw = lambda: bytes(line).rstrip(ws)
        iscm = lambda k: line[k] == 0x3b or (line[k] == 0x2f and k + 1 < n and line[k + 1] == 0x2f)
        c = line[i]
        if c in (0x3b, 0x2f): return raw()
        out = bytearray()
        lbl = 0
        if i == 0:
            if c in (0x2e, 0x23): return raw()
            while i < n and line[i] not in ws:
                out.append(line[i]); i += 1
                if out[-1] == 0x3a: break
            lbl = len(out)
            while i < n and line[i] in ws: i += 1
            if i == n: return bytes(out)
        rt = lambda: [out.pop() for _ in iter(lambda: bool(out) and out[-1] in ws, False)]
        if not iscm(i):
            if line[i] == 0x3d: return raw()
            if lbl and len(out) >= 8: out.append(0x20)
            else: out += b" " * (8 - len(out)) if len(out) < 8 else b""
            ms = len(out)
            while i < n and line[i] not in ws: out.append(line[i]); i += 1
            mn = len(out) - ms
            while i < n and line[i] in ws: i += 1
            q = 0
            st = False
            while i < n:
                if q == 0:
                    if iscm(i): break
                    if line[i] in (0x22, 0x27): q = line[i]
                elif line[i] == q: q = 0
                if not st:
                    st = True
                    col = 8 + max(4, mn + 1)
                    out.append(0x20)
                    out += b" " * max(0, col - len(out))
                out.append(line[i]); i += 1
            while out and out[-1] in ws: out.pop()
            if i >= n: return bytes(out)
        while out and out[-1] in ws: out.pop()
        if len(out) < 31: out += b" " * (32 - len(out))
        else: out.append(0x20)
        out += bytes(line[i:])
        while out and out[-1] in ws: out.pop()
        return bytes(out)

    def fmt_line(self):
        self.sel = False
        s = self.ls(self.cur)
        e = self.le(self.cur)
        line = bytes(self.t[s:e])
        if len(line) < 100:
            out = Ed.fmt(line)
            if out != line:
                self.cur = e
                for _ in line: self.key(K_BS)
                for c in out: self.key(c)
                return
        self.cur = e

    def fmt_all(self):
        ol = self.curline()
        self.sel = False
        self.cur = 0
        while True:
            self.fmt_line()
            if self.cur >= len(self.t): break
            self.cur += 1
        self.goto(ol)

    def find_label(self, pat):
        """wie ed_find_label"""
        self.kind(0)
        n = len(self.t)
        if n == 0 or not pat:
            self.view(); return
        low = lambda b: bytes(c | 0x20 if 0x41 <= c < 0x5b else c for c in b)
        pat = low(pat)
        p = 0
        while p + len(pat) <= n:
            if low(bytes(self.t[p:p + len(pat)])) == pat:
                q = p + len(pat)
                if q >= n or self.t[q] in (0x3a, 0x20, 0x09, 0x0a):
                    self.cur = p; self.want = None; break
            e = self.le(p)
            if e >= n: break
            p = e + 1
        self.view()

    def goto(self, ln):
        self.kind(0)
        p, l = 0, 1
        while l < ln:
            e = self.le(p)
            if e >= len(self.t): break
            p = e + 1; l += 1
        self.cur = p; self.want = None
        self.view()

    def srange(self):
        return min(self.anc, self.cur), max(self.anc, self.cur)

    def sel_del(self):
        s0, e0 = self.srange()
        self.cur = s0; self.sel = False
        for _ in range(e0 - s0): self.dele_at(s0, s0)

    def copy(self):
        if not self.sel: return False
        s0, e0 = self.srange()
        if e0 - s0 > 0x10000: return False
        self.clip = bytes(self.t[s0:e0]); self.sel = False
        return True

    def paste(self):
        if not self.clip or len(self.t) + len(self.clip) >= 0x30000: return
        if self.sel: self.sel_del()
        for b in self.clip: self.ins(b)

    def ls(self, p):
        while p > 0 and self.t[p - 1] != 10: p -= 1
        return p

    def le(self, p):
        while p < len(self.t) and self.t[p] != 10: p += 1
        return p

    def curline(self):
        return 1 + self.t[:self.cur].count(10)

    def col(self):
        return self.cur - self.ls(self.cur)

    def up(self):
        if self.want is None: self.want = self.col()
        s = self.ls(self.cur)
        if s == 0: return
        ps = self.ls(s - 1)
        self.cur = ps + min(self.want, self.le(ps) - ps)

    def down(self):
        if self.want is None: self.want = self.col()
        e = self.le(self.cur)
        if e >= len(self.t): return
        ns = e + 1
        self.cur = ns + min(self.want, self.le(ns) - ns)

    def key(self, k):
        self.kind(k)
        if self.sel:
            if k in (K_BS, K_DEL):
                self.want = None; self.sel_del(); self.view(); return
            if k in (K_UNDO, K_REDO) or self.lastkind != 0: self.sel = False
        if k == K_MARK:
            self.want = None; self.sel = not self.sel; self.anc = self.cur
        elif k == K_COPY: self.want = None; self.copy()
        elif k == K_CUT:
            self.want = None
            if self.copy(): self.sel_del()
        elif k == K_PASTE: self.want = None; self.paste()
        elif k == K_UNDO: self.want = None; self.undo()
        elif k == K_REDO: self.want = None; self.redo()
        elif k == K_UP: self.up()
        elif k == K_DOWN: self.down()
        elif k in (K_PGUP, K_PGDN):
            for _ in range(self.rows - 2): (self.up if k == K_PGUP else self.down)()
        else:
            self.want = None
            if k == K_LEFT and self.cur > 0: self.cur -= 1
            elif k == K_RIGHT and self.cur < len(self.t): self.cur += 1
            elif k == K_HOME: self.cur = self.ls(self.cur)
            elif k == K_END: self.cur = self.le(self.cur)
            elif k == K_BS and self.cur > 0:
                cb = self.cur; self.cur -= 1; self.dele_at(self.cur, cb)
            elif k == K_DEL and self.cur < len(self.t):
                self.dele_at(self.cur, self.cur)
            elif k == K_RET:
                self.ins(10)
                ps = self.ls(self.cur - 1)
                n = 0
                while ps + n < len(self.t) and self.t[ps + n] == 0x20: n += 1
                for _ in range(n):
                    self.ins(0x20)
            elif k == K_TAB:
                while True:
                    self.ins(0x20)
                    if self.col() % 4 == 0: break
            elif 0x20 <= k < 0x7f:
                self.ins(k)
        self.view()

    def top_next(self):
        e = self.le(self.top)
        if e < len(self.t):
            self.top = e + 1; self.topline += 1

    def view(self):
        cl = self.curline()
        if cl < self.topline:
            self.top = self.ls(self.cur); self.topline = cl
        else:
            lim = self.topline + self.rows - 1
            while cl >= lim:
                self.top_next(); lim += 1
        col = self.col()
        tw = SCRW - GUTTER
        if col < self.left: self.left = col
        elif col >= self.left + tw: self.left = col - tw + 1

    def screen(self):
        out, attr = self.screen2()
        return out

    def screen2(self):
        attr = bytearray([COL_TEXT]) * (self.rows * SCRW)
        out = bytearray([0x20]) * (self.rows * SCRW)
        p, ln, exist = self.top, self.topline, True
        for r in range(self.rows - 1):
            if not exist: break
            num = f"{ln:4d}" if ln < 10000 else "####"
            row = bytearray([0x20]) * SCRW
            row[0:4] = num.encode()
            arow = bytearray([COL_TEXT]) * SCRW
            arow[0:5] = bytes([COL_GUTTER]) * 5
            e = self.le(p)
            cc = line_colours(self.t[p:e])
            if self.sel: ss, se = self.srange()
            for i, c in enumerate(self.t[p:e]):
                d = i - self.left
                if 0 <= d < tw_():
                    row[GUTTER + d] = asc2scr(c)
                    arow[GUTTER + d] = cc[i] | (SELF if self.sel and ss <= p + i < se else 0)
            out[r * SCRW:(r + 1) * SCRW] = row
            attr[r * SCRW:(r + 1) * SCRW] = arow
            if e >= len(self.t): exist = False
            else: p = e + 1; ln += 1
        r = (self.rows - 1) * SCRW
        out[r] = 0x4c
        out[r + 2:r + 6] = f"{self.curline():4d}".encode()
        out[r + 9] = 0x43
        out[r + 11:r + 15] = f"{self.col() + 1:4d}".encode()
        return bytes(out), bytes(attr)


def tw_(): return SCRW - GUTTER


def bytes_lit(b):
    b = list(b)
    if not b: return ".byte 0"
    return "\n".join(".byte " + ", ".join(str(x) for x in b[i:i + 16]) for i in range(0, len(b), 16))


def run_native(rows, text, keys, hdr=0, ftr=0, deco=0):
    tpl = open(os.path.join(ROOT, "src/test/edtest.asm")).read()
    src = tpl.replace("{deco}", str(deco)).replace("{hdr}", str(hdr)).replace("{ftr}", str(ftr)).replace("{rows}", str(rows)).replace("{text}", bytes_lit(text) if text else "").replace("{keys}", bytes_lit(list(keys) + [0]))
    b = os.path.join(ROOT, "build")
    asm = os.path.join(b, "edt.asm")
    open(asm, "w").write(src.replace('"../', '"../src/'))
    prg = os.path.join(b, "edt.prg")
    r = asmtest.run([asmtest.VCC, "asm", asm, "--target", "mega65", "--data-dir", asmtest.DATA, "-o", prg])
    if r.returncode != 0:
        raise SystemExit("Pruefprogramm baut nicht\n" + r.stdout + r.stderr)
    env = dict(os.environ)
    r = asmtest.run([os.path.join(ROOT, "tools/xrun.sh"), prg, "90"], env=env)
    if r.returncode != 0:
        raise SystemExit(f"Xemu-Lauf fehlgeschlagen rc={r.returncode}")
    m = open(os.path.join(b, "xrun.mem"), "rb").read()
    u32 = lambda a: m[a] | m[a + 1] << 8 | m[a + 2] << 16 | m[a + 3] << 24
    st = dict(cur=u32(0xc400), top=u32(0xc404), length=u32(0xc408), curline=m[0xc40c] | m[0xc40d] << 8,
              topline=m[0xc40e] | m[0xc40f] << 8, left=m[0xc410] | m[0xc411] << 8)
    st["text"] = bytes(m[0xc600:0xc600 + st["length"]])
    st["screen"] = bytes(m[0xb000:0xb000 + rows * SCRW])
    st["attr"] = bytes(m[0x8000:0x8000 + rows * SCRW])
    return st


def play(e, keys):
    i = 0
    pat = b""
    while i < len(keys):
        k = keys[i]; i += 1
        if k != 0xfe: e.key(k); continue
        c = keys[i]; i += 1
        if c == 0x67: e.goto(keys[i] | keys[i + 1] << 8); i += 2
        elif c == 0x66: n = keys[i]; pat = bytes(keys[i + 1:i + 1 + n]); i += 1 + n
        elif c == 0x6e: e.find(pat, True)
        elif c == 0x70: e.find(pat, False)
        elif c == 0x6c:
            n = keys[i]; pt = bytes(keys[i + 1:i + 1 + n]); i += 1 + n
            pat = pt; e.find_label(pt)
        elif c == 0x46: e.fmt_all()
        elif c == 0x4c: e.fmt_line()
        elif c == 0x72:
            n = keys[i]; pt = bytes(keys[i + 1:i + 1 + n]); i += 1 + n
            m = keys[i]; rp = bytes(keys[i + 1:i + 1 + m]); i += 1 + m
            pat = pt; e.replace_all(pt, rp)


def compare(rows, text, keys):
    e = Ed(rows, text)
    e.view()
    play(e, keys)
    n = run_native(rows, text, keys)
    exp = dict(cur=e.cur, top=e.top, length=len(e.t), curline=e.curline(), topline=e.topline, left=e.left, text=bytes(e.t), screen=e.screen2()[0], attr=e.screen2()[1])
    bad = [k for k in exp if exp[k] != n[k]]
    return bad, exp, n


def compare_layout(rows, hdr, ftr, text, keys, deco=0):
    """Kopf-/Fusszeilen (ed_layout, IDE-Rahmen): Zustand und Textzeilen wie ein Editor mit rows - hdr - ftr Zeilen; Kopf und Fuss bleiben unberuehrt"""
    vr = rows - hdr - ftr
    e = Ed(vr, text)
    e.view()
    play(e, keys)
    n = run_native(rows, text, keys, hdr, ftr, deco)
    es, ea = bytearray(e.screen2()[0]), bytearray(e.screen2()[1])
    if deco:      # Schmuck (ed_deco): Strich hinter der Zeilennummer, Cursorzeile mit > und heller Nummer (COL_CURNUM = 7), Statusleiste umgekehrt (12 + SELF)
        for r in range(vr - 1):
            if es[r * SCRW:r * SCRW + 4].strip() == b"": continue
            es[r * SCRW + 4] = 0x5d
            if e.topline + r == e.curline():
                es[r * SCRW + 4] = 0x3e
                ea[r * SCRW:r * SCRW + 5] = bytes([7]) * 5
        ea[(vr - 1) * SCRW:vr * SCRW] = bytes([12 | SELF]) * SCRW
    exp = dict(cur=e.cur, top=e.top, length=len(e.t), curline=e.curline(), topline=e.topline, left=e.left, text=bytes(e.t))
    bad = [k for k in exp if exp[k] != n[k]]
    ts = (vr - 1) * SCRW
    if n["screen"][hdr * SCRW:hdr * SCRW + ts] != es[:ts]: bad.append("textzeilen")
    if n["screen"][hdr * SCRW:hdr * SCRW + ts] == es[:ts] and n["attr"][hdr * SCRW:hdr * SCRW + ts] != ea[:ts]: bad.append("textfarben")
    if n["screen"][(rows - 1) * SCRW:rows * SCRW] != es[ts:ts + SCRW]: bad.append("statuszeile")
    if deco and n["attr"][(rows - 1) * SCRW:rows * SCRW] != ea[ts:ts + SCRW]: bad.append("statusfarben")
    return bad, exp, n


def gen_line(r):
    kind = r.random()
    if kind < 0.5:                       # Quelltext-aehnlich
        parts = []
        if r.random() < 0.4: parts.append(r.choice([b"loop:", b"start", b".loc:", b"x"]))
        parts.append(r.choice([b" lda ", b"  nop", b" JSR ", b" ldq ", b".byte ", b" foo ", b"\tbne "]))
        parts.append(r.choice([b"#$1f", b"label", b"%1010", b"\"txt\"", b"12,x", b"0x1f", b"$zz", b"a;b", b".word 5 ; c", b"x // y"]))
        return b"".join(parts)
    return bytes(r.choice(b"abcxyz ABC09;:.,#$%\"/") for _ in range(r.choice([0, 1, 3, 10, 30, 70, 90, 120])))


def gen(seed, rows):
    r = random.Random(seed)
    lines = []
    for _ in range(r.randrange(0, 40)):
        lines.append(gen_line(r))
    text = b"\n".join(lines)
    keys = []
    for _ in range(r.randrange(10, 120)):
        k = r.random()
        if k < 0.35: keys.append(r.choice(b"abc xyz;09,."))
        elif k < 0.40: keys.append(K_RET)
        elif k < 0.42: keys.append(K_TAB)
        elif k < 0.48: keys.append(K_BS)
        elif k < 0.51: keys.append(K_DEL)
        elif k < 0.55: keys.append(K_UNDO)
        elif k < 0.58: keys.append(K_REDO)
        elif k < 0.60:
            keys += [0xfe, 0x67, r.randrange(0, 60), 0]
        elif k < 0.63:
            if r.random() < 0.5 and len(text) > 3:
                a = r.randrange(0, len(text) - 2)
                pt = bytes(c for c in text[a:a + r.randrange(1, 5)] if c != 10) or b"a"
            else:
                pt = bytes(r.choice(b"abcxyzABC;. ") for _ in range(r.randrange(1, 4)))
            keys += [0xfe, 0x66, len(pt)] + list(pt)
        elif k < 0.68: keys += [0xfe, 0x6e]
        elif k < 0.71: keys += [0xfe, 0x70]
        elif k < 0.74: keys.append(K_MARK)
        elif k < 0.76: keys.append(K_COPY)
        elif k < 0.77: keys.append(K_CUT)
        elif k < 0.775: keys.append(K_PASTE)
        elif k < 0.785: keys += [0xfe, r.choice([0x46, 0x4c, 0x4c])]      # Formatieren (alles / Zeile)
        elif k < 0.792:                                  # Label suchen
            if len(text) > 3:
                a = r.randrange(0, len(text) - 2)
                pt = bytes(c for c in text[a:a + r.randrange(1, 5)] if c not in (10, 32)) or b"a"
            else: pt = b"a"
            keys += [0xfe, 0x6c, len(pt)] + list(pt)
        elif k < 0.80:                                   # Ersetzen: Muster aus dem Text, Ersatz kurz oder leer
            if len(text) > 3:
                a = r.randrange(0, len(text) - 2)
                pt = bytes(c for c in text[a:a + r.randrange(1, 4)] if c != 10) or b"a"
            else: pt = b"a"
            rp = bytes(r.choice(b"xyZ09 ;") for _ in range(r.choice([0, 1, 2, 5])))
            keys += [0xfe, 0x72, len(pt)] + list(pt) + [len(rp)] + list(rp)
        else: keys.append(r.choice([K_UP, K_DOWN, K_LEFT, K_RIGHT, K_HOME, K_END, K_PGUP, K_PGDN, K_UP, K_DOWN, K_RIGHT]))
    return text, keys


def main():
    cnt = int(sys.argv[1]) if len(sys.argv) > 1 else 6
    start = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    bad = 0
    for s in range(start, start + cnt):
        rows = 25 if s % 2 else 50
        text, keys = gen(s, rows)
        diff, exp, n = compare(rows, text, keys)
        print("seed", s, "rows", rows, "ok" if not diff else f"ABWEICHUNG {diff}")
        if diff:
            bad += 1
            for k in diff:
                if k not in ("text", "screen", "attr"): print("   ", k, "erwartet", exp[k], "nativ", n[k])
    messy = (b"; Demo\n.org $2001\nBORDER = $d020\nstart:ldx #0\nloop:   stx   BORDER ; Farbe  \n  inx\n\tbne loop   \n        lda #';'   // x\n"
             b"verylonglabel_here lda #1\n   .byte 1,2,3 ;daten\n  rts  \nende:\n")
    diff, exp, n = compare(50, messy, [0xfe, 0x46])
    want = (b"; Demo\n.org $2001\nBORDER = $d020\nstart:  ldx #0\nloop:   stx BORDER              ; Farbe\n        inx\n        bne loop\n"
            b"        lda #';'                // x\nverylonglabel_here lda #1\n        .byte 1,2,3             ;daten\n        rts\nende:\n")
    ok = not diff and n["text"] == want
    print("format feste Beispiele", "ok" if ok else f"ABWEICHUNG {diff} {n['text']!r}")
    bad += 0 if ok else 1
    lt = b".org $2000\nstart:\n nop\nloop: nop\n bne loop\nlooper: nop\n"
    diff, exp, n = compare(50, lt, [0xfe, 0x6c, 4] + list(b"LOOP"))
    ok = not diff and n["cur"] == lt.index(b"loop:")
    print("label suchen feste Beispiele", "ok" if ok else f"ABWEICHUNG {diff} cur={n['cur']}")
    bad += 0 if ok else 1
    for s, (rows, hdr, ftr, deco) in enumerate(((50, 2, 4, 0), (25, 2, 0, 0), (50, 2, 4, 1), (25, 2, 0, 1)), 100):      # IDE-Rahmen
        text, keys = gen(s, rows - hdr - ftr)
        diff, exp, n = compare_layout(rows, hdr, ftr, text, keys, deco)
        print("seed", s, "rows", rows, "kopf", hdr, "fuss", ftr, "schmuck", deco, "ok" if not diff else f"ABWEICHUNG {diff}")
        if diff:
            bad += 1
            for k in diff:
                if k in exp and k != "text": print("   ", k, "erwartet", exp[k], "nativ", n[k])
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
