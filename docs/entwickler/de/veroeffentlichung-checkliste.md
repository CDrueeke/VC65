# Veröffentlichung: Prüfstand und Checkliste (Stand 2026-11-25)

Nur Vorbereitung. **Nichts davon ist ausgeführt:** kein Push nach `public`, kein Tag, kein GitHub-Release, keine Website-Veröffentlichung. Jeden Schritt unter „Wort des Eigners“ gibt nur der Eigner frei.

## 1 Geprüft (ohne Befund)

| Punkt | Ergebnis |
|---|---|
| Binärdateien, ROMs, Disketten im Repo und in der Historie | keine (das ungenutzte `py65`-Wheel wurde am 2026-11-25 entfernt; es bleibt nur in der Historie) |
| Zugangsdaten, Schlüssel, Tokens im Quelltext | keine Treffer |
| Persönliche Pfade (`/Users/…`) in Dateien | keine; nur die Sicherheitsadresse `vintagecoder@drueeke.de` in `SECURITY.md` (gewollt, wie VintageCoder) |
| SPDX-Kopfzeile in `src/` und `tools/` | vollständig (außer `tools/vcc.version`, eine Versionsnummer) |
| Systemdatei `sys/mega65/chips.asm` | trug keine Lizenzzeile; jetzt `MIT-0` (Quelle `tools/gen_chips.py`), Tests laufen |
| Lizenzdateien | `LICENSE` (GPL-3.0-or-later), `LICENSES/MIT-0.txt`, `LICENSING.md`, `THIRD-PARTY-NOTICES.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md` vorhanden |
| Externe Links in Benutzerdokumentation und README | keine |
| Tests | voller Lauf sauber, Paket alpha-11 auf Windows/Xemu abgenommen (inkl. Ton) |

## 2 Vorschläge zum Aufräumen (Eigner entscheidet)

1. ~~`py65`-Wheel entfernen~~ erledigt (2026-11-25, Entscheidung des Eigners).
2. ~~`vendor/vintagecoder/VERSION` ergänzen~~ erledigt (2026-11-25): Prüfsummen aller neun kopierten Dateien.
3. ~~Historie~~ entschieden (2026-11-25): keine Umschreibung; die öffentliche Fassung entsteht wie bei VintageCoder als Kopie aus `VC65-dev`, die Autorenadresse `<test>` spielt dort keine Rolle.
4. ~~Inhalt der öffentlichen Fassung~~ entschieden (2026-11-25): `docs/mockups/` und `docs/konzept/` bleiben privat (`tools/export-exclude.txt`), `docs/entwickler/` geht mit.

## 3 Wort des Eigners nötig

- ~~Anwaltliche Durchsicht der Lizenzseite und der Erklärung des Rechteinhabers (`LICENSING.md`, Abschnitt 3)~~ erledigt, ohne Beanstandung (Mitteilung des Eigners, 2026-11-25).
- ~~Markenrecherche „VC65“~~ erledigt, ohne Beanstandung (Mitteilung des Eigners, 2026-11-25).
- Freigabe von: Push nach `origin` (VC65-dev), Push nach `public` (VC65), Tag `v0.1.0-alpha`, GitHub-Release mit den D81-Dateien, Veröffentlichung auf der Website.
- Freigabe, die D81-Abbilder öffentlich zu verteilen (enthalten nur VC65 und eigene Beispiele, keine ROMs; vor der Freigabe `THIRD-PARTY-NOTICES.md` gegen den Disketteninhalt prüfen).

## 4 Ablauf wie bei VintageCoder (Auskunft der Hauptsession, 2026-11-25; Entscheidung des Eigners: genauso hier)

**Zwei Repositories.** Arbeitsrepo privat `CDrueeke/VC65-dev` (Remote `origin`), öffentlich `CDrueeke/VC65` (Remote `public`). Die öffentliche Fassung ist kein Spiegel, sondern ein **Export** eines Commits ohne Historie:

- `tools/export-public.sh AUSGABEORDNER` (einmalig, ein Einstiegs-Commit) und `tools/export-update.sh AUSGABEORDNER` (jedes weitere Release: klont den öffentlichen Stand, ersetzt den Dateibaum, legt **einen** neuen Commit an). Beide pushen nie und setzen keinen Tag. Optionen: `--commit REF`, `--verify` (baut und testet aus dem Export), `--message`.
- Export = `git archive` der getrackten Dateien ohne `tools/export-exclude.txt`, mit den Ersetzungen aus `tools/export-replace.txt` (`release/CHANGELOG.public.md` wird zu `CHANGELOG.md`, das Entwicklungstagebuch bleibt privat) und dem Verbotsscan `tools/export_check.py` (feste Pfade, privater Name, E-Mail, IP, Geheimnisse, ROM-Dateien, interne Ordner, Binärdateien, `.DS_Store`).
- Autor und Committer des Export-Commits: `Christian Drüeke <165030641+CDrueeke@users.noreply.github.com>`, ohne Mitautor-Zeile.

**Ablauf (jeder Schritt nur auf ausdrückliches Wort):**
1. Version und „Alpha“-Etikett setzt der Eigner (`VERSION`).
2. Alle Vorab-Prüfungen: voller Testlauf, Export mit `--verify`, Handtest auf Windows/Xemu, Paketprüfung (Prüfsummen).
3. Privat nach `origin/main` (Fast-Forward) pushen („Du darfst pushen“).
4. `tools/export-update.sh` (beim ersten Mal `export-public.sh`), im Export-Ordner `git tag -a v0.1.0-alpha -m "VC65 0.1.0-alpha"`, `git push origin main v0.1.0-alpha` (dort ist `origin` das öffentliche Repo). Lehre aus VintageCoder 0.2.0: Builds und Handprüfung **vor** dem öffentlichen Push, den Tag erst danach (dort wurde er dreimal neu gesetzt).
5. GitHub-Release als **Pre-release** (kein Entwurf; „Du darfst veröffentlichen“), Text aus `docs/release/0.1.0-alpha.md`; Anhänge: beide D81, das ZIP, `SHA256SUMS`; Doku-Anhänge `VC65-<Version>-Handbuch.pdf`, `…-Manual.pdf`, `…-Handbuch-Markdown.zip`, `…-Manual-Markdown.zip` mit eigener Summendatei `SHA256SUMS-doku.txt` (`python3 tools/release.py` legt alles in `build/release/` und `build/release/doku-anhaenge/`). Danach Download nachprüfen (Prüfsumme gegen `SHA256SUMS`).
6. Website (Website-Session, nur auf Wort): Version, Datum, Dateiliste, Prüfsummen, `CHANGELOG.md` (öffentliche Fassung), Handbuch/Doku, Lizenzseite, Bilder. Reihenfolge bei VintageCoder 0.2.0: GitHub-Release zuerst, dann Update-Feed (bei VC65 derzeit nicht vorgesehen), dann Website, dann privates `origin/main`.

**Freigabestufen** (jedes Ja gilt nur für den genannten Schritt): (a) Version/Etikett; (b) Merge nach `main`; (c) Export, Tag und Push ins öffentliche Repo; (d) GitHub-Release veröffentlichen; (e) Website und privates `origin/main` je eigenes Wort.

**Nicht übernommen:** Update-Feed, Installer und Linux-Pakete (VC65 liefert Disketten-Abbilder); Paketprüfskripte und Linux-VM (entfallen). Das ZIP mit beiden D81, Lizenzdateien und Handbuch ist eine Ergänzung gegenüber VintageCoder (Eignerwunsch).
