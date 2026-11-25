#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verbotsscan und Ausschlussliste fuer den Export ins oeffentliche Repository (Aufrufer: tools/export-public.sh und
tools/export-update.sh). Schlanke Fassung des Werkzeugs von VintageCoder (tools/export_check.py), ohne dessen Wortliste.

Unterbefehle:
  scan ORDNER          Verbotsscan ueber alle Dateien (Inhalt und Dateinamen) des Exportordners. Rueckgabewert 1 bei Funden.
  exclude ORDNER LISTE Dateien der Ausschlussliste (tools/export-exclude.txt) aus dem Exportordner loeschen (Dateien, Ordner, fnmatch-Muster).
  replace ORDNER LISTE Dateien ersetzen (tools/export-replace.txt, je Zeile `QUELLE ZIEL`): QUELLE wird nach ZIEL verschoben und ueberschreibt es.

Der Scan sucht nach: festen Pfaden (/Users/<Name>, /Volumes/<Name>, C:\\Users\\<Name>), dem privaten Namen des Inhabers ausserhalb
von GitHub-Adressen, E-Mail-Adressen (erlaubt: Sicherheitsadresse und noreply), internen IP-Adressen, Geheimnismustern, ROM-/Systemdateien
(*.rom, *.ROM), internen Ordnern (assets/, .claude/, build/, target/, __pycache__/), .DS_Store, zu grossen Dateien, nicht erlaubten
Binaerdateien und Co-Autor-Zeilen im Text. Hinweise (Namen von Entwicklungswerkzeugen) lassen den Rueckgabewert bei 0.
Aufruf: python3 -I tools/export_check.py scan /tmp/export     Nur Standardbibliothek."""
import fnmatch, os, re, shutil, sys

MAX_SIZE = 2 * 1024 * 1024
BINARY_EXT = {".png", ".d81"}                      # Bildschirmfotos, Logo; D81 nur falls Beispieldisketten je ins Repo kaemen (derzeit keine)
BAD_TOP_DIRS = {"assets", ".claude", "target", "build"}
BAD_ANY_DIRS = {"build", "target", ".claude", "__pycache__"}
BAD_NAME_RX = re.compile(r"\.rom$|^\.DS_Store$", re.I)
ALLOWED_EMAILS = {"vintagecoder@drueeke.de"}
ALLOWED_EMAIL_SUFFIXES = ("@users.noreply.github.com",)
ALLOWED_IPS = set()
ALLOWED_PRIVATE_NAME_RX = re.compile(r"github\.com/CDrueeke/|CDrueeke/VC65|CDrueeke/VintageCoder|\+CDrueeke@users\.noreply\.github\.com", re.I)
PRIVATE_NAME = "cdrueeke"
EMAIL_RX = re.compile(r"(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b")
IP_RX = re.compile(r"(?<![\d.])(192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(?![\d.]*\d)")
USER_PATH_RX = re.compile(r"(?:/Users/|/Volumes/|[A-Za-z]:[\\/]+Users[\\/]+|\\+Users\\+)([A-Za-z0-9._-]+)", re.I)
EXAMPLE_NAMES = {"anna", "ich", "a", "x", "bob", "chris", "name", "user", "demo"}
SECRET_RXS = [re.compile(r"""(?:password|passwd|token|secret|api[_-]?key)["']?\s*[:=]\s*["'][^"'\s]{4,}["']""", re.I),
              re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")]
COAUTHOR_RX = re.compile(r"Co-Authored", re.I)
HINT_WORDS = ["Claude", "Anthropic"]
# Dateien, die die gesuchten Muster selbst beschreiben: dort keine Funde fuer die Musterregeln
SELF_FILES = {"tools/export_check.py", "tools/export-public.sh", "tools/export-update.sh", "tools/export-exclude.txt", "tools/export-replace.txt"}


def user_path(text):
    for m in USER_PATH_RX.finditer(text):
        if m.group(1).lower().split(".")[0] not in EXAMPLE_NAMES:
            return m.group(0)
    return None


def short(s, n=90):
    s = s.strip()
    return s if len(s) <= n else s[:n - 1] + "…"


def read_list(path):
    out = []
    for line in open(path, encoding="utf-8"):
        line = line.split("#", 1)[0].strip()
        if line: out.append(line)
    return out


def scan_name(rel):
    out = []
    parts = rel.split("/")
    if parts[0] in BAD_TOP_DIRS: out.append((rel, 0, "verbotener-ordner", "Ordner '%s/' gehoert nicht in den Export" % parts[0]))
    for d in parts[1:-1]:
        if d in BAD_ANY_DIRS and parts[0] not in BAD_TOP_DIRS:
            out.append((rel, 0, "verbotener-ordner", "Ordner '%s/' gehoert nicht in den Export" % d)); break
    if BAD_NAME_RX.search(parts[-1]): out.append((rel, 0, "datei-name", "ROM-Datei oder .DS_Store"))
    if user_path(rel): out.append((rel, 0, "fester-pfad", "Dateiname enthaelt festen Pfad"))
    if PRIVATE_NAME in rel.lower(): out.append((rel, 0, "privater-name", "Dateiname enthaelt '%s'" % PRIVATE_NAME))
    return out


def scan_line(rel, n, line):
    out = []
    if rel not in SELF_FILES:
        p = user_path(line)
        if p: out.append((rel, n, "fester-pfad", "%s in: %s" % (p, short(line))))
        stripped = ALLOWED_PRIVATE_NAME_RX.sub("", line)
        if PRIVATE_NAME in stripped.lower(): out.append((rel, n, "privater-name", short(line)))
        for rx in SECRET_RXS:
            if rx.search(line): out.append((rel, n, "geheimnis", short(line)))
        for m in IP_RX.finditer(line):
            if m.group(0) not in ALLOWED_IPS: out.append((rel, n, "ip-adresse", m.group(0)))
        for m in EMAIL_RX.finditer(line):
            a = m.group(0)
            if a.lower() not in ALLOWED_EMAILS and not a.lower().endswith(ALLOWED_EMAIL_SUFFIXES):
                out.append((rel, n, "email", a))
        if COAUTHOR_RX.search(line): out.append((rel, n, "co-autor", short(line)))
    return out


def scan(root):
    findings, hints = [], []
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d != ".git"]
        for f in fn:
            full = os.path.join(dp, f); rel = os.path.relpath(full, root).replace(os.sep, "/")
            findings += scan_name(rel)
            size = os.path.getsize(full)
            ext = os.path.splitext(f)[1].lower()
            if size > MAX_SIZE: findings.append((rel, 0, "zu-gross", "%d KiB" % (size // 1024)))
            head = open(full, "rb").read(8192)
            if b"\0" in head:
                if ext not in BINARY_EXT: findings.append((rel, 0, "binaer", "Binaerdatei, nicht erlaubt"))
                continue
            try: text = open(full, encoding="utf-8").read()
            except UnicodeDecodeError: text = open(full, encoding="latin-1").read()
            for n, line in enumerate(text.splitlines(), 1):
                findings += scan_line(rel, n, line)
                if rel not in SELF_FILES and any(w in line for w in HINT_WORDS): hints.append((rel, n, "Hinweis", short(line)))
    for r, n, rule, txt in findings: print("%s%s: [%s] %s" % (r, ":%d" % n if n else "", rule, txt))
    for r, n, rule, txt in hints[:20]: print("%s:%d: [%s] %s" % (r, n, rule, txt))
    if hints[20:]: print("... und %d weitere Hinweise" % len(hints[20:]))
    print("Verbotsscan: %d Fund(e), %d Hinweis(e)" % (len(findings), len(hints)))
    return 1 if findings else 0


def exclude(root, listfile):
    n = 0
    for pat in read_list(listfile):
        hits = [os.path.join(dp, f) for dp, dn, fn in os.walk(root) for f in fn + dn
                if fnmatch.fnmatch(os.path.relpath(os.path.join(dp, f), root).replace(os.sep, "/"), pat.rstrip("/"))]
        direct = os.path.join(root, pat.rstrip("/"))
        if os.path.exists(direct) and direct not in hits: hits.append(direct)
        for h in hits:
            if os.path.isdir(h): shutil.rmtree(h, ignore_errors=True); n += 1
            elif os.path.exists(h): os.remove(h); n += 1
    print("Ausschlussliste: %d Eintraege entfernt" % n)


def replace(root, listfile):
    for line in read_list(listfile):
        src, dst = line.split()
        s, d = os.path.join(root, src), os.path.join(root, dst)
        if not os.path.exists(s): sys.exit("replace: Quelle fehlt: " + src)
        os.makedirs(os.path.dirname(d), exist_ok=True); shutil.move(s, d)
    print("Ersetzungen: erledigt")


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("scan", "exclude", "replace"): sys.exit(__doc__)
    if sys.argv[1] == "scan": sys.exit(scan(sys.argv[2]))
    if len(sys.argv) < 4: sys.exit(__doc__)
    (exclude if sys.argv[1] == "exclude" else replace)(sys.argv[2], sys.argv[3])
