#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Erzeugt docs/entwickler/vcasm-status.json: maschinenlesbare Liste der VCASM-Eintraege (Direktiven, Befehle, Funktionen,
Operatoren, Systemdateien) mit dem Stand in VC65. status: "heute" | "geplant (Stufe 2|3)" | "nie". detail (optional) nennt
bekannte Abweichungen. Quellen: vendor/vintagecoder/help/*.md, data/cpus/45gs02.cpu.json, directives.json (VintageCoder, nur
gelesen; Pfad ueber --directives oder Umgebung VCASM_DIRECTIVES), und VC65-Quelltext (dirtab, optab, func.asm, mksysdisk.py).
Aufruf: tools/vcasm_status.py [--directives pfad] [ausgabe.json]"""
import json, os, re, sys, glob
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

def rd(p): return open(os.path.join(ROOT, p), encoding="utf-8").read()

def find_directives():
    a = sys.argv[1:]
    if "--directives" in a: return a[a.index("--directives") + 1]
    if os.environ.get("VCASM_DIRECTIVES"): return os.environ["VCASM_DIRECTIVES"]
    base = os.path.expanduser("~/Documents/Development/Privat/VintageCoder-dev")
    c = [base + "/data/asm/directives.json"] + sorted(glob.glob(base + "/.claude/worktrees/*/data/asm/directives.json"))
    for p in c:
        if os.path.exists(p): return p
    sys.exit("directives.json nicht gefunden (--directives pfad)")

# Gewollte Entscheidungen des Eigners: mega65-only
NIE = {".atascii": "Atari-only, in VC65 nicht gebraucht (E208)", ".cartridge": "beim MEGA65 vorerst nicht benoetigt (E208)"}
DETAIL = {
    ".bank": "nur Bank 0; andere Bank: E901 (Format-Unterschied, keine Bankausgabe)",
    ".segment": "Segmente; Ausgabe wie vcc, Besonderheiten siehe docs/entwickler/de/vcasm-konformitaet-luecken.md",
    ".target": "nur mega65; andere Ziele melden E207 (Entscheidung)",
    ".run": "wird gelesen, ohne Wirkung (W206 wie vcc fuer mega65)",
    ".cpu": "Optionen werden gelesen und ignoriert",
    ".include": "Systemdateien anderer Ziele fehlen (nur mega65, common, c64/hardware.asm)",
}
SPECIAL_OK = {"*=", "=", "{", "}", "#include"}  # im Scanner, nicht in dirtab

def out_status(ok, name, detail=None):
    e = {"name": name, "status": "heute" if ok else "nie"}
    if detail: e["detail"] = detail
    return e

def main():
    asm = rd("src/asm/asm.asm")
    dirtab = set(re.findall(r'"(\.[a-z0-9_]+)"', asm[asm.index("dirtab:"):asm.index("dirjmp:")]))
    dj = json.load(open(find_directives(), encoding="utf-8"))
    dirs, bad = [], []
    for d in dj:
        names = [d["name"]] + d.get("aliases", []) + ([d["end"]] if d.get("end") else []) + d.get("end_aliases", [])
        for n in names:
            if n in NIE: ok, det = False, NIE[n]
            else:
                ok = n in dirtab or n in SPECIAL_OK or n in (".endfor",)
                det = DETAIL.get(n)
                if not ok: bad.append(n)
            e = out_status(ok, n, det)
            if n != d["name"]: e["alias_of"] = d["name"]
            e["group"] = d.get("group")
            dirs.append(e)
    # Befehle
    cpu = json.load(open(os.path.join(ROOT, "vendor/vintagecoder/data/cpus/45gs02.cpu.json"), encoding="utf-8"))
    mn = sorted({o[0] for o in cpu["ops"]} | set(cpu["quadOps"]))
    opt = rd("src/asm/optab.asm")
    mnem = []
    for m in mn:
        ok = ("md_" + m + ":") in opt or ("md_" + m + ":") in opt.upper().replace("MD_", "md_")
        if not ok: bad.append(m)
        mnem.append(out_status(ok, m.lower()))
    # Funktionen
    ex = rd("vendor/vintagecoder/help/asm-expr.md")
    sec = ex[ex.index("## Eingebaute Funktionen"):ex.index("### Sinustabelle")]
    fn = sorted(set(re.findall(r'`([a-z0-9]+)\(', sec)))
    fsrc = rd("src/asm/func.asm")
    funcs = []
    for f in fn:
        ok = ('"' + f + '"') in fsrc
        if not ok: bad.append(f + "()")
        funcs.append(out_status(ok, f))
    # Operatoren
    ops = [out_status(True, o) for o in ["+", "-", "*", "/", "%", "<<", ">>", "&", "^", "|", "!", "~", "<", ">", "<=", ">=",
                                         "==", "!=", "&&", "||"]]
    # Systemdateien (Bibliothek)
    import mksysdisk
    have = set(mksysdisk.sys_list())
    lib = rd("vendor/vintagecoder/help/asm-library.md")
    paths = []
    for m in re.finditer(r'^\| (.*?) \|', lib, re.M):
        for p in re.findall(r'`([a-z0-9_]+/[a-z0-9_]+\.(?:asm|inc))`', m.group(1)):
            paths.append(p)
        m2 = re.match(r'`([a-z0-9]+)/([a-z0-9_]+\.asm)` `([a-z0-9_]+\.asm)`', m.group(1))
        if m2: paths.append(m2.group(1) + "/" + m2.group(3))
    libs = []
    for p in sorted(set(paths)):
        d, f = p.split("/")
        ok = (d[:3].upper() + "." + os.path.splitext(f)[0].upper()) in have
        libs.append(out_status(ok, p, None if ok else "Systemdatei eines anderen Ziels (mega65-only)"))
    # Nicht in der Hilfetabelle, aber vorhanden: Systemdatei vic4.asm (liegt auf der Systemdisk als MEG.VIC4)
    if "MEG.VIC4" in have: libs.append(out_status(True, "mega65/vic4.asm")); libs.sort(key=lambda e: e["name"])
    consts = [out_status("sym_pi:" in rd("src/asm/sym.asm"), "pi")]
    doc = {"_comment": "Erzeugt von tools/vcasm_status.py. status: heute | geplant (Stufe 2|3) | nie. Eintraege 'heute' koennen "
           "Abweichungen in 'detail' tragen; Stand der Pruefung: docs/entwickler/de/vcasm-konformitaet-luecken.md.",
           "vc65_version": rd("VERSION").strip(), "directives": dirs, "mnemonics": mnem, "functions": funcs,
           "constants": consts, "operators": ops, "libraries": libs}
    outp = [a for a in sys.argv[1:] if a.endswith(".json") and not a.endswith("directives.json")]
    outp = outp[0] if outp else os.path.join(ROOT, "docs/entwickler/vcasm-status.json")
    json.dump(doc, open(outp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    c = lambda l: {s: sum(1 for e in l if e["status"] == s) for s in ("heute", "nie")}
    for k in ("directives", "mnemonics", "functions", "constants", "operators", "libraries"): print(k, len(doc[k]), c(doc[k]))
    if bad: print("NICHT GEFUNDEN (als nie markiert):", bad)
    print("->", outp)

main()
