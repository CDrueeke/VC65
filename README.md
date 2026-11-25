# VC65

Native Entwicklungsumgebung für den MEGA65: Vollbild-Editor, VCASM-kompatibler Assembler, Bauen und Starten, Debugger, Projekte auf der SD-Karte. Läuft **auf dem MEGA65 selbst**, ohne PC.

**Stand: Vorabversion 0.1.0-Alpha** (siehe [`docs/release/0.1.0-alpha.md`](docs/release/0.1.0-alpha.md)). Editor (80 × 50, Menü, Suchen/Ersetzen, Ausrichten, Marken), VCASM-kompatibler Assembler (übersetzt sich selbst byte-gleich zu `vcc`), Bauen und Starten, Debugger und Systembibliotheken von der Disk laufen **im Emulator Xemu**; am echten MEGA65 ist noch **nichts** geprüft (Handtestliste: [`docs/entwickler/de/handtest.md`](docs/entwickler/de/handtest.md)). Dieses Repository (`VC65-dev`, privat) ist aus dem Repository VintageCoder-dev ausgelöst worden. Das Repository `VC65` ist die öffentliche Fassung.

**English:** pre-release 0.1.0-alpha. Native editor, VCASM-compatible assembler and debugger for the MEGA65 (no PC needed). Tested in the Xemu emulator only, nothing verified on a real MEGA65 yet. Manual: [`docs/benutzer/en`](docs/benutzer/en/README.md), release notes: [`docs/release/0.1.0-alpha.md`](docs/release/0.1.0-alpha.md).

## Inhalt
- `docs/konzept/Konzept-VC65.md`: Konzept mit Architektur, Bankplan („eine Rolle je Bank“), Etappen und allen Entscheidungen (Abschnitt 19), Repository und Kompatibilität (Abschnitt 20), Lizenz (Abschnitt 21).
- `branding/`: Logo (Wortmarke „VC“ violett, „65“ weiß, gelber Punkt; Entwurf des Inhabers, SVG und PNG); als Verweis auf VC65 (Referenz) verwendbar, auch skaliert oder einfarbig, sonst nicht veränderbar (siehe `LICENSING.md`).
- `docs/mockups/`: Bildentwürfe (80×50 und 80×25), erzeugt mit `docs/mockups/render.sh` (Python und Edge headless).
- `docs/benutzer/`: Benutzerhandbuch (de/en, Kapitel 1–7).
- `docs/release/`: Hinweise zu den Vorabversionen.
- `examples/`: Beispiele für VC65 (hello, pal_demo, music_demo, prallball; MIT-0), fertig als Quelltext mit `.byte`-Includes.
- `src/` (Quellen in VCASM), `tools/` (Bau und Tests, `tools/release.py` baut die Boot-D81), `sys/`, `tests/`.
- `docs/entwickler/`: Entwicklerdokumentation (IDE, Editor, Assembler, Debugger, Handtest).
- `CHANGELOG.md`, `LICENSING.md`, `LICENSE`, `LICENSES/`, `THIRD-PARTY-NOTICES.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`: wie bei VintageCoder.

## Entscheidungen (Kurzfassung)
Name VC65 · Entwicklung in VCASM (Selbstübersetzung) · nur Vollbild-Editor · `.vcprj` der Desktop-Fassung lesen · Kompatibilitätsstufe 1 und 2 zum Start · Debugger zuerst mit Haltepunkten und Registern · 80×50 Standard, 80×25 nur als Editor · Deutsch und Englisch · eigene Release-Linie · Reset-Taste nach Absturz · eine Rolle je Bank, Quelltext im Attic.

## Beziehung zu VintageCoder
Eigenständig (keine laufende Abhängigkeit), aber dauerhaft möglichst kompatibel: gemeinsame Verträge (VCASM-Sprachversion, `.vcprj`-Versionsfeld, Konformitätsbeispiele), Abgleichsprüfung vor jedem Release. Einzelheiten im Konzept, Abschnitt 20.

**Vorgemerkt (2026-11-23, Entscheidung D5 in VintageCoder):** Medien-Includes zeigen künftig auf die Datei im Projekt (`.include "graphics/hero.vcsprite"`, im BASIC `#include`); der Assembler erkennt Medien an der Endung (`.vcsprite`, `.vcpmg`, `.vcchar`, `.vctiles`, `.vcscreen`, `.vcsong`, `.vcpal` …) und wandelt beim Bauen selbst um; alte Pfade `build/export/…` bleiben als Übergang gültig. VC65 unterstützt das später oder bewusst nicht; offene Frage an den Inhaber: Welche Rolle spielen Medien in VC65? Bis dahin wird nichts gebaut außer einer klaren Meldung: ein `.include`/`#include` mit Medien-Endung (`.vcsprite`, `.vcpmg`, `.vcchar`, `.vctiles`, `.vcscreen`, `.vcsong`, `.vcplay`, `.vcpal`) ergibt im VC65-Assembler den Fehler E219 („in VC65 noch nicht unterstützt“) statt „Datei nicht gefunden“. Die Sprachbeschreibung führt VintageCoder.

## Bekannte Grenzen (Auswahl)
Nur Ziel `mega65`; Makros höchstens 16 Parameter (E900); Umlaute nur in Kommentaren und in Zeichenketten für `.text`/`.petscii`/`.byte` (Labels, Konstanten, Zeichenliterale und `.screencode` verhalten sich anders als bei `vcc`); keine Medien-Includes (E219); keine Ordner und langen Dateinamen auf der Disk. Vollständig: Handbuch Kapitel 3 und `docs/release/0.1.0-alpha.md`.

## Lizenz
VC65 steht unter der **GNU General Public License, Version 3 oder später** ([LICENSE](LICENSE)), mit **denselben Zusagen wie VintageCoder**: Ausgaben, die Sprache VCASM und die Dateiformate sind frei nutzbar ([LICENSING.md](LICENSING.md)). Systemdateien, Vorlagen und Beispiele (sobald vorhanden) stehen unter MIT-0 ([LICENSES/MIT-0.txt](LICENSES/MIT-0.txt)). Die Software wird ohne jede Gewährleistung bereitgestellt. Fremdanteile: [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
