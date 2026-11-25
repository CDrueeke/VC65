#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Baut aus dem Benutzerhandbuch (docs/benutzer/de und /en) je Sprache ein PDF und eine gebuendelte Markdown-Datei,
nach dem Vorbild von VintageCoder (tools/dokumentation_pdf.py): Deckblatt, Inhaltsverzeichnis, Lesezeichen, Seitenzahlen,
Bilder eingebettet (PDF) bzw. im Ordner bilder/ (Markdown).

Aufruf:  python3 tools/handbuch_pdf.py [Ausgabeordner]      (Standard: build/handbuch)
Braucht Python 3 mit dem Modul `markdown` (pip install markdown) und einen Chromium-Browser fuer den PDF-Druck
(Standard: Microsoft Edge auf macOS; anderer Browser ueber die Umgebungsvariable VC_PDF_BROWSER).
Ergebnis: VC65-Handbuch.pdf, VC65-Manual.pdf, markdown-handbuch/VC65-Handbuch.md, markdown-manual/VC65-Manual.md
(je mit bilder/) und die HTML-Zwischendateien. Kapitelreihenfolge steht in CHAPTERS."""
import base64, datetime, html, os, re, shutil, subprocess, sys
import markdown

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "handbuch")
EDGE = os.environ.get("VC_PDF_BROWSER", "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge")
VERSION = open(os.path.join(ROOT, "VERSION")).read().strip()
STAND = datetime.date.today().strftime("%d.%m.%Y")
LOGO = os.path.join(ROOT, "branding", "vc65-wortmarke.png")

# Kapitel je Sprache in Lesereihenfolge (Dateinamen ohne .md); README.md ist die Uebersicht und wird zum Inhaltsverzeichnis.
CHAPTERS = {
    "de": ["01-einstieg", "02-editor", "03-assembler", "04-bauen-und-starten", "05-debugger", "06-projekte-und-dateien", "07-referenz",
           "08-erstes-programm", "09-beispiele", "10-fehlersuche", "11-fehlercodes", "12-glossar"],
    "en": ["01-getting-started", "02-editor", "03-assembler", "04-build-and-run", "05-debugger", "06-projects-and-files", "07-reference",
           "08-first-program", "09-examples", "10-troubleshooting", "11-error-codes", "12-glossary"],
}
LANG = {
    "de": dict(file="VC65-Handbuch", mdir="markdown-handbuch", title="VC65 – Handbuch", sub="Benutzerhandbuch der Entwicklungsumgebung",
               meta=["Version {v}", "Stand {s}", "Editor, Assembler und Debugger für den MEGA65", "VCASM-kompatibel"], toc="Inhalt",
               alpha="<b>Alpha-Stadium.</b> VC65 befindet sich in Entwicklung und enthält mit Sicherheit noch Fehler. Alles ist bisher nur im Emulator Xemu getestet, nicht am echten MEGA65.",
               intro="Benutzerhandbuch von VC65. Version {v}, Stand {s}. Alpha-Stadium: Die Software enthält mit Sicherheit noch Fehler und ist nur im Emulator Xemu getestet.",
               drop=r"^Englische Fassung:", lic="Lizenz und freie Nutzung: siehe LICENSING.md im Paket."),
    "en": dict(file="VC65-Manual", mdir="markdown-manual", title="VC65 – Manual", sub="User guide of the development environment",
               meta=["Version {v}", "As of {s}", "Editor, assembler and debugger for the MEGA65", "VCASM compatible"], toc="Contents",
               alpha="<b>Alpha stage.</b> VC65 is under development and certainly still contains errors. Everything has so far been tested only in the Xemu emulator, not on a real MEGA65.",
               intro="User guide of VC65. Version {v}, as of {s}. Alpha stage: the software certainly still contains errors and is tested only in the Xemu emulator.",
               drop=r"^German version:", lic="License and free use: see LICENSING.md in the package."),
}

CSS = """
@page { size: A4; margin: 22mm 18mm 22mm 18mm;
  @bottom-center { content: counter(page); font: 9pt 'Helvetica Neue', Arial, sans-serif; color: #667; }
  @bottom-left { content: string(doctitle); font: 9pt 'Helvetica Neue', Arial, sans-serif; color: #889; }
}
@page :first { @bottom-center { content: none; } @bottom-left { content: none; } margin: 0; }
html { font: 10.2pt/1.5 'Helvetica Neue', Arial, sans-serif; color: #1b2230; }
body { margin: 0; }
.doctitle { string-set: doctitle content(); display: none; }
h1, h2, h3, h4 { font-family: 'Helvetica Neue', Arial, sans-serif; color: #0b3a66; line-height: 1.25; }
h1 { font-size: 22pt; margin: 0 0 6mm; padding-bottom: 2mm; border-bottom: 2px solid #0a63b5; }
h2 { font-size: 15pt; margin: 8mm 0 3mm; break-after: avoid; }
h3 { font-size: 12pt; margin: 6mm 0 2mm; break-after: avoid; }
h4 { font-size: 10.5pt; margin: 4mm 0 1mm; break-after: avoid; }
section.kap { break-before: page; }
p { margin: 0 0 3mm; orphans: 3; widows: 3; }
code { font: 9pt Menlo, 'SF Mono', Consolas, monospace; background: #eef2f8; padding: 0 2px; border-radius: 2px; }
pre { font: 8.4pt/1.4 Menlo, 'SF Mono', Consolas, monospace; background: #f3f5f9; border: 1px solid #d5dbe6; border-left: 3px solid #0a63b5;
  padding: 2.5mm 3mm; margin: 0 0 4mm; white-space: pre-wrap; word-break: break-word; break-inside: avoid; }
pre code { background: none; padding: 0; font: inherit; }
table { border-collapse: collapse; width: 100%; margin: 0 0 4mm; font-size: 9pt; break-inside: auto; }
th, td { border: 1px solid #ccd3e0; padding: 1.4mm 2mm; text-align: left; vertical-align: top; }
th { background: #e6eef8; color: #0b3a66; }
tr { break-inside: avoid; }
blockquote { margin: 0 0 4mm; padding: 2mm 4mm; background: #eef5fd; border-left: 4px solid #0a63b5; break-inside: avoid; }
blockquote p:last-child { margin-bottom: 0; }
blockquote.tipp { background: #e8f6ee; border-color: #0b7a43; }
blockquote.achtung { background: #fdf1dc; border-color: #c07a00; }
figure { margin: 0 0 5mm; text-align: center; break-inside: avoid; }
figure img { max-width: 100%; max-height: 120mm; border: 1px solid #ccd3e0; }
figcaption { font-size: 8.8pt; color: #566074; margin-top: 1.5mm; }
a { color: #0a63b5; text-decoration: none; }
ul, ol { margin: 0 0 3mm; padding-left: 6mm; }
li { margin-bottom: 1mm; }
.cover { height: 297mm; box-sizing: border-box; padding: 55mm 25mm 25mm; background: #0d1b2e; color: #fff; break-after: page; position: relative; }
.cover .logo { height: 34mm; margin-bottom: 14mm; }
.cover h1 { color: #fff; font-size: 34pt; border: 0; margin: 0 0 4mm; }
.cover .sub { font-size: 15pt; color: #9fc4ea; margin: 0 0 18mm; }
.cover .meta { font-size: 10.5pt; color: #c8d6e8; line-height: 1.7; }
.cover .alpha { position: absolute; left: 25mm; right: 25mm; bottom: 22mm; border: 1px solid #c07a00; background: #2a2110; color: #f5d28a; padding: 4mm 5mm; font-size: 9.5pt; }
.cover .bar { position: absolute; left: 0; right: 0; bottom: 0; height: 5mm; background: linear-gradient(90deg,#8b6cf0 0 40%,#ffffff 0 80%,#f5d000 0); }
.toc h1 { border: 0; }
.toc ol { list-style: none; padding: 0; counter-reset: x; }
.toc li { margin: 0 0 1.6mm; font-size: 10.5pt; }

.toc .grp { margin-top: 4mm; font-weight: bold; color: #0b3a66; }
.legal { font-size: 9pt; color: #566074; }
"""


def b64(path):
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def read_chapter(lang, stem):
    """Kapiteltext ohne SPDX-Kommentar und ohne den Verweis auf die andere Sprachfassung."""
    text = open(os.path.join(ROOT, "docs", "benutzer", lang, stem + ".md"), encoding="utf-8").read()
    text = re.sub(r"^<!--.*?-->\s*", "", text, flags=re.S)
    paras = text.split("\n\n")
    paras = [p for p in paras if not re.match(LANG[lang]["drop"], p.strip())]
    return "\n\n".join(paras)


def fix_links(text, lang, as_html):
    """Kapitelverweise (NN-name.md[#x]) -> Anker #k-NN-name, Uebersicht (README.md) -> #inhalt, Bilder ../../screenshots/x.png
    -> data-URI (PDF) bzw. bilder/x.png (Markdown). Verweise auf die andere Sprache und auf Dateien ausserhalb: nur der Text."""
    stems = set(CHAPTERS[lang])
    used = []

    def img(m):
        cap, path = m.group(1), m.group(2)
        p = os.path.normpath(os.path.join(ROOT, "docs", "benutzer", lang, path))
        if not os.path.exists(p):
            return ""
        used.append(p)
        if as_html:
            return f'\n\n<figure><img src="{b64(p)}" alt="{html.escape(cap)}"><figcaption>{html.escape(cap)}</figcaption></figure>\n\n'
        return f"![{cap}](bilder/{os.path.basename(p)})"
    text = re.sub(r"!\[([^\]]*)\]\(([^)]*screenshots/[^)]+\.png)\)", img, text)

    def link(m):
        t, target = m.group(1), m.group(2)
        base = target.split("#")[0]
        if base == "README.md": return f"[{t}](#inhalt)"
        if base.endswith(".md") and "/" not in base and base[:-3] in stems: return f"[{t}](#k-{base[:-3]})"
        if target.startswith("#") or target.startswith("http"): return m.group(0)
        return t
    text = re.sub(r"(?<!!)\[([^\]]+)\]\(([^)]+)\)", link, text)
    return text, used


def page(lang, parts):
    t = LANG[lang]["title"]
    return f"""<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><title>{html.escape(t)}</title>
<style>{CSS}</style></head><body><div class="doctitle">{html.escape(t)}</div>{''.join(parts)}</body></html>"""


def cover(lang):
    L = LANG[lang]
    meta = "<br>".join(x.format(v=VERSION, s=STAND) for x in L["meta"])
    return f"""<div class="cover"><img class="logo" src="{b64(LOGO)}"><h1>{html.escape(L['title'].split(' – ')[0])}</h1>
<p class="sub">{html.escape(L['sub'])}</p><p class="meta">{meta}</p>
<div class="alpha">{L['alpha']}</div><div class="bar"></div></div>"""


def title_of(body):
    return re.search(r"^# (.+)$", body, re.M).group(1)


def build_pdf(lang):
    L = LANG[lang]
    parts, entries, secs = [cover(lang)], [], []
    for stem in CHAPTERS[lang]:
        text, _ = fix_links(read_chapter(lang, stem), lang, True)
        entries.append((f"k-{stem}", title_of(text)))
        body = markdown.markdown(text, extensions=["tables", "fenced_code", "sane_lists"])
        body = re.sub(r'<blockquote>\s*<p><strong>(Tipp|Tip)', r'<blockquote class="tipp"><p><strong>\1', body)
        body = re.sub(r'<blockquote>\s*<p><strong>(Achtung|Warning|Hinweis|Note)', r'<blockquote class="achtung"><p><strong>\1', body)
        secs.append(f'<section class="kap" id="k-{stem}">{body}</section>')
    toc = [f'<section class="toc" id="inhalt"><h1>{L["toc"]}</h1><ol>']
    toc += [f'<li><a href="#{a}">{html.escape(t)}</a></li>' for a, t in entries]
    toc.append("</ol></section>")
    parts += ["".join(toc)] + secs
    parts.append(f'<section class="kap legal"><p>{html.escape(L["lic"])}</p></section>')
    return page(lang, parts)


def build_md(lang, outdir):
    L = LANG[lang]
    os.makedirs(os.path.join(outdir, "bilder"), exist_ok=True)
    items = []
    for stem in CHAPTERS[lang]:
        text, used = fix_links(read_chapter(lang, stem), lang, False)
        for p in used: shutil.copy(p, os.path.join(outdir, "bilder", os.path.basename(p)))
        items.append((f"k-{stem}", title_of(text), text))
    out = [f"# {L['title']}\n", L["intro"].format(v=VERSION, s=STAND) + "\n", f'<a id="inhalt"></a>\n\n## {L["toc"]}\n']
    out += [f"- [{t}](#{a})" for a, t, _ in items]
    for a, t, body in items:
        out.append(f'\n---\n\n<a id="{a}"></a>\n\n{body.strip()}\n')
    out.append(f"\n---\n\n{L['lic']}\n")
    open(os.path.join(outdir, L["file"] + ".md"), "w", encoding="utf-8").write("\n".join(out))


def pdf(htmlfile, pdffile):
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--no-sandbox", "--generate-pdf-document-outline",
                    f"--print-to-pdf={pdffile}", "file://" + htmlfile],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for lang, L in LANG.items():
        h = os.path.join(OUT, L["file"] + ".html")
        open(h, "w", encoding="utf-8").write(build_pdf(lang))
        pdf(h, os.path.join(OUT, L["file"] + ".pdf"))
        build_md(lang, os.path.join(OUT, L["mdir"]))
        print("fertig:", L["file"])
