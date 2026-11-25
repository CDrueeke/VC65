#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Konformitaetskorpus: Quelltext-Schnipsel aus den Tests von vc-asm (crates/vc-asm/tests/*.rs und src/lib.rs, nur gelesen) werden mit
vcc (Gegenprobe, Ziel mega65) und mit dem nativen Assembler in Xemu uebersetzt; verglichen werden Bytes, Fehlercodes mit Zeile und
Warncodes. Ergebnis: build/corpus/ergebnis.jsonl (je Schnipsel eine Zeile) und eine Zusammenfassung.
Aufruf: tools/vcasm_corpus.py extract|run [Anzahl]|bericht     Umgebung: VCASM_SRC (Arbeitskopie von VintageCoder, Standard tauri-ui)"""
import glob, json, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asmtest

ROOT = asmtest.ROOT
OUT = os.path.join(ROOT, "build", "corpus")
W = os.environ.get("VCASM_SRC", os.path.expanduser("~/Documents/Development/Privat/VintageCoder-dev/.claude/worktrees/tauri-ui-723e95"))
ENUM = [0, 201, 202, 203, 204, 205, 206, 207, 208, 0, 210, 211, 216, 213, 209, 207, 212, 214, 218, 215, 212, 219, 300, 900, 301, 901]    # ide.asm enum_t
WENUM = {0x20: "W200", 0x21: "W201", 0x22: "W202", 0x23: "W203", 0x24: "W204", 0x26: "W206"}


def rust_strings(src):
    out = []
    for m in re.finditer(r'r(#+)"(.*?)"\1', src, re.S): out.append(m.group(2))
    for m in re.finditer(r'(?<![#\w])r"(.*?)"', src, re.S): out.append(m.group(1))
    for m in re.finditer(r'(?<![\w#])"((?:[^"\\\n]|\\.)*)"', src):
        try: out.append(bytes(m.group(1), "utf-8").decode("unicode_escape").encode("latin1").decode("utf-8"))
        except Exception: pass
    return out


def extract():
    os.makedirs(OUT, exist_ok=True)
    seen, items = set(), []
    for f in sorted(glob.glob(W + "/crates/vc-asm/tests/*.rs")) + [W + "/crates/vc-asm/src/lib.rs"]:
        for s in rust_strings(open(f, encoding="utf-8").read()):
            t = s.strip("\\n")
            if not 4 <= len(t) <= 4000 or s in seen: continue
            if not re.search(r"^\s*(\.|[a-z_]\w*:|[a-z]{3}\b)", t, re.M | re.I): continue
            if "\n" not in s and not re.match(r"\s*(\.\w+|[a-z]{3}\s)", s): continue
            if re.search(r"(fn |let |assert|\{\}|\{:)", t): continue
            seen.add(s); items.append({"id": len(items), "file": os.path.basename(f), "src": s if s.endswith("\n") else s + "\n"})
    json.dump(items, open(os.path.join(OUT, "korpus.json"), "w"), ensure_ascii=False)
    print(len(items), "Schnipsel")


def vcc(path):
    exp = path + ".bin"
    if os.path.exists(exp): os.remove(exp)
    r = subprocess.run([asmtest.VCC, "asm", path, "--target", "mega65", "--format", "bin", "--data-dir", asmtest.DATA, "-o", exp], capture_output=True, text=True, timeout=60)
    out = r.stdout + r.stderr
    errs = [(m.group(1), int(m.group(2))) for m in re.finditer(r"error\[(E\d+)\][^\n]*\n\s*--> [^\n]*:(\d+)", out)]
    warns = sorted({m.group(1) for m in re.finditer(r"warning\[(W\d+)\]", out)})
    if r.returncode != 0 and not errs and "keine Ausgabe" in out:       # vcc meldet "keine Ausgabe" bei fehlerfreier Quelle ohne Bytes: erwartet wird die leere Ausgabe
        return b"", errs, warns
    return (open(exp, "rb").read() if r.returncode == 0 and os.path.exists(exp) else None), errs, warns


def run(limit=None):
    items = json.load(open(os.path.join(OUT, "korpus.json")))
    resf = os.path.join(OUT, "ergebnis.jsonl")
    done = {json.loads(l)["id"] for l in open(resf)} if os.path.exists(resf) else set()
    n = 0
    for it in items:
        if it["id"] in done: continue
        if limit and n >= limit: break
        n += 1
        path = os.path.join(OUT, f"s{it['id']:04d}.asm")
        open(path, "w", encoding="utf-8").write(it["src"])
        try: want, werrs, wwarn = vcc(path)
        except Exception as e: want, werrs, wwarn = None, [("??", 0)], []
        res = dict(id=it["id"], file=it["file"], vcc_ok=want is not None, vcc_errs=werrs, vcc_warn=wwarn, vcc_len=None if want is None else len(want))
        try:
            r = asmtest.one(f"corp{it['id']}", path, vcc_may_fail=True)
            got = asmtest.LAST_ERRS
            gerrs = [(ENUM[c] if c < len(ENUM) and ENUM[c] else ("SYN" if c == 1 else f"?{c}"), line) for c, line, col in got]
            res.update(native_errs=gerrs, native_warn=sorted({WENUM.get(c, f"W?{c}") for c, l in asmtest.LAST_WARNS}), native_msg=(r or "")[:300])
        except SystemExit as e:
            res.update(native_errs=[("XEMU", 0)], native_warn=[], native_msg=str(e)[:300])
        open(resf, "a").write(json.dumps(res, ensure_ascii=False) + "\n")
        print(it["id"], flush=True)


def classify(r):
    """identisch | bytes_abweichung | nativ_lehnt_ab (vcc ok, nativ Fehler) | nativ_nimmt_an (vcc Fehler, nativ ok) |
    fehler_gleich (alle vcc-Fehler mit Code und Zeile auch nativ) | fehler_gleich_syn (nativ nur allgemeiner Syntaxfehler) |
    fehler_erster_gleich (erster Fehler gleich, Rest weicht ab) | fehlercode_abweichung"""
    ne = [("SYN" if c in (1, 201) else "E%s" % c if isinstance(c, int) else c, l) for c, l in r["native_errs"]]       # 1 = Syntaxfehler, die IDE zeigt ihn als E201
    if r["vcc_ok"]:
        if not ne:
            return "bytes_abweichung" if "ABWEICHUNG" in r["native_msg"] else "identisch"
        return "nativ_lehnt_ab"
    if not ne: return "nativ_nimmt_an"
    ve = [(c, l) for c, l in r["vcc_errs"]]
    if not ve: return "fehlercode_abweichung"
    if all((c, l) in ne for c, l in ve) and len(set(ne)) == len(set(ve)): return "fehler_gleich"
    if all(any(c == vc and l == vl for c, l in ne) for vc, vl in ve): return "fehler_gleich_plus"        # nativ meldet zusaetzlich weitere
    if all(any((c == vc or c == "SYN") and l == vl for c, l in ne) for vc, vl in ve): return "fehler_gleich_syn"
    if set(ne) <= set(ve): return "fehler_teilmenge"                     # nativ meldet nur einen Teil der vcc-Fehler (gleiche Codes)
    if ne[0] == ve[0]: return "fehler_erster_gleich"
    if ne[0][1] == ve[0][1]: return "fehlercode_abweichung_gleiche_zeile"
    return "fehlercode_abweichung"


# Gewollte Ausnahmen (Inhaber, 2026-11-25): VC65 uebersetzt nur fuer den MEGA65; ATASCII und Systemdateien anderer Ziele entfallen
AUSNAHME = re.compile(r"\.atascii|\.cartridge|#include\s*<(c128|atari8bit|vic20|plus4)/|#include\s*<c64/(?!hardware)|\.target\s+(c64|atari|c128|vic20)", re.I)


def bericht():
    rows = [json.loads(l) for l in open(os.path.join(OUT, "ergebnis.jsonl"))]
    texts = {it["id"]: it["src"] for it in json.load(open(os.path.join(OUT, "korpus.json")))}
    cnt = {}
    for r in rows:
        r["klasse"] = classify(r)
        if r["klasse"] not in ("identisch", "fehler_gleich") and AUSNAHME.search(texts.get(r["id"], "")):
            r["klasse"] = "gewollte_ausnahme"       # Entscheidung des Inhabers: VC65 ist MEGA65-only, kein ATASCII/andere Ziele
        cnt[r["klasse"]] = cnt.get(r["klasse"], 0) + 1
    print(len(rows), "Schnipsel:", json.dumps(cnt, ensure_ascii=False))
    wd = [r["id"] for r in rows if set(r["vcc_warn"]) != set(r["native_warn"]) and r["klasse"] != "gewollte_ausnahme"]
    print("Warnungen: Abweichung bei", len(wd), "Schnipseln", wd[:20])
    json.dump(rows, open(os.path.join(OUT, "ergebnis_klassifiziert.json"), "w"), ensure_ascii=False)


if __name__ == "__main__":
    a = sys.argv[1] if len(sys.argv) > 1 else ""
    if a == "extract": extract()
    elif a == "run": run(int(sys.argv[2]) if len(sys.argv) > 2 else None)
    elif a == "bericht": bericht()
    else: print(__doc__)
