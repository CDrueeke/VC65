<!-- SPDX-License-Identifier: MIT-0 -->
# Offene Punkte für das nächste Release (nach 0.1.0-alpha)

Stand 2026-11-25. Befunde der Prüfung der veröffentlichten Release-D81 (Windows/Xemu, echtes Xemu, echte Tastatur). Beschlossen: erst im nächsten Release beheben, das veröffentlichte nicht anfassen.

## 1 About/Startbild: Quelltext schimmert durch das Logo
- **Befund:** Mit geladener Datei (zum Beispiel `hello.asm`) wird das Logo ohne Hintergrund über den Quelltext gezeichnet; Zeilen des Quelltexts kreuzen das Logo. Mit leerem Editor sauber. Die Testbilder (leerer Editor) haben es nicht gezeigt.
- **Ursache:** `xo_logo` (`src/editor/xtools.asm`) ruft `ed_view` und zeichnet das Logo darüber; der Textbereich bleibt sichtbar.
- **Fix (ungetestet):** Branch `naechstes-release` (lokal), Commit „WIP“: Textbereich (Zeile 1 bis `ed_rows`-2) vor dem Logo mit Leerzeichen und Normalfarbe füllen. Zu prüfen: About mit geladener Datei (Bild), Startbild, Menü danach sauber, Overlay-Größe.
- **Website-Bild:** `vc65-about.png` wurde ersatzweise mit leerem Editor aufgenommen.

## 2 Debugger: Haltepunkt zeigt `brk` / hält nicht (Verdacht, nicht bestätigt)
- **Befund Windows (Release-D81):** `hello.asm`, Haltepunkt Zeile 35, Strg+E, Strg+D, F5: hält bei `$2019`, aber die Disassemblierung zeigt dort `brk` und danach falsch dekodierte Befehle; ein weiterer Schritt führt in `$1fc2`, das Programm entgleist. Mit `greet.asm` (Haltepunkt auf `jsr CHROUT`) hält F5 gar nicht, das Programm läuft durch. Ohne Haltepunkt laufen die Schritte sauber. Bei alpha-11 (Quelltext gleich) hielt `greet.asm` richtig.
- **Nicht nachgestellt** in der Testumgebung (Xemu auf dem Mac, gleiche Quelle): `hello.asm` Zeile 34 und 35 halten korrekt, Anzeige ist das Original.
- **Verdacht:** Zustand aus einer früheren Debugger-Sitzung. `dbg_ins` (`src/debug/dbg.asm`) überspringt Einträge mit gesetztem Bit 7 („schon eingefügt"), `dbg_rem` stellt nur diese Einträge zurück. Wird eine Sitzung mit F7/`q` (Ende) beendet, ohne dass `dbg_rem` lief, bleiben die Einträge als „eingefügt" markiert: in der nächsten Sitzung wird dort kein BRK eingefügt (Haltepunkt wird übersehen), und beim nächsten Halt schreibt `dbg_rem` ein veraltetes „Original" zurück. Zu prüfen: Zustand der Haltepunkttabelle `dbg_bp` bei Sitzungsende (Ende, Programmende, Fehler) und beim Start (`ide_debug`: „Zustand löschen"?).
- **Nachstellversuch (offen):** Skripte im Scratchpad der Sitzung (`dbg_seq.py`): Variante A: Sitzung ohne Haltepunkt mit F1 x3 und Ende, danach Haltepunkt Zeile 35, E, D, F5. Variante B: `hello.asm` Haltepunkt 35, F5, Ende; dann `greet.asm` Haltepunkt Zeile 11, E, D, F5. Bei Bestätigung: Fehlertest in `tools/dbgtest.py` ergänzen.
- **Frage an die Windows-Session (offen):** genaue Tastenfolge vor dem fehlerhaften Lauf (frühere Debugger-Sitzungen, Programmläufe, Textänderungen).

## Entscheidungen des Eigners (2026-11-25)
1. **About-Logo:** Statt den Textbereich mit Leerzeichen zu überschreiben: Hintergrund (Quelltext) abdunkeln, dann das Logo darüberlegen. Der WIP-Fix auf `naechstes-release` ist entsprechend umzubauen und zu testen.
2. **Debugger-Haltepunkt:** Zuerst bei Windows nach der genauen Tastenfolge vor dem Fehler fragen; bis zur Antwort nichts ändern.
3. **Bilder:** Handbuch und Release-Anhänge bekommen im nächsten Release die echten Xemu-Aufnahmen (aus `austausch-vc65/screenshots-release`, auf 640x400 zugeschnitten wie auf der Website). Neues About-Bild erst nach dem Logo-Fix.
4. **PR-Vorlage:** `.github/pull_request_template.md` nach dem Muster von VintageCoder anlegen, an VC65 anpassen und in die Export-Skripte aufnehmen.

## 2 Debugger: Nachgestellt (2026-11-25, Mac/Xemu)
Windows und Eigner kennen die Tastenfolge nicht mehr; der Fehler ist nun selbst nachgestellt (`tools/dbg_repro_haltepunkt.py`): zwei Haltepunkte (Zeile 4, 7), Sitzung bis „Program ended" (F5 dreimal), dann in Zeile 4 eine Zeile `nop` einfügen, Strg+E, Strg+D, drei Schritte. Ergebnis: Debugger hält bei `$ff8b` mit lauter `brk` (Referenz ohne erste Sitzung: sauber bei `$201a`).
- **Ursache:** Endet das Programm regulär (`ds_fin` in `src/debug/dsess.asm`), läuft `dbg_rem` nicht; im Eintrag in `dbg_bp` bleibt Bit 7 („eingefügt") samt altem Original. Nach der Textänderung schreibt `dbg_rem` beim ersten Halt das alte Original an die alte Adresse in den neuen Code, und `dbg_ins` fügt für den markierten Eintrag nichts ein. Zusätzlich findet `ib_tog` (`src/ide/ide.asm`) einen markierten Eintrag nicht (Vergleich mit `#$01`).
- **Fix-Vorschlag (noch nicht umgesetzt):** in `ds_fin` (und beim Start in `ide_debug` vor `dbg_ins`) die Markierungen löschen: Bit 7 aller Einträge zurücksetzen, Zwischenhaltepunkte freigeben, ohne Speicher zu schreiben. Danach Test in `tools/dbgtest.py` aufnehmen.

**Umgesetzt (2026-11-25, lokal auf `naechstes-release`, Wort des Eigners):** (a) `ide_asm` löscht alle Haltepunkte des Benutzers, wenn sich der Text seit dem letzten Übersetzen geändert hat (sie sind Adressen und lagen sonst mitten in Befehlen: eigentliche Ursache des Entgleisens, in der Nachstellung allein dafür verantwortlich); (b) `ds_fin` ruft `dbg_rem` (Programmende: Markierungen Bit 7 weg, Originale zurück). Regressionstest „reste nach programmende" in `tools/dbgtest.py` (schlug vorher mit `$ff8b`/`brk` fehl). `dbgtest.py` und `idetest.py` vollständig grün. Der Fix (b) allein genügte nicht. Folge für Anwender: Haltepunkte gelten nur für den Stand des Textes, der zuletzt übersetzt wurde.
