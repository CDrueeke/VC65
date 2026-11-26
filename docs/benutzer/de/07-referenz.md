<!-- SPDX-License-Identifier: MIT-0 -->
# 7 Referenz

Englische Fassung: [../en/07-reference.md](../en/07-reference.md). Zurück zur [Übersicht](README.md). Vorabversion 0.1.1-Alpha.

> **Hinweis:** Alle Tastencodes sind vorläufig und am echten MEGA65 ungeprüft; die HELP-Taste (`$84`), ESC, die Funktionstasten (VC65 schaltet die Funktionstasten-Belegung des KERNAL beim Start ab) und das Menü sind nur im Emulator Xemu getestet.

## Tasten im Editor

| Taste | Tastencode | Wirkung |
|---|---|---|
| STOP | `$03` | VC65 beenden (in Eingabezeilen und im Menü: abbrechen) |
| F1 | `$85` | Suchen (Eingabezeile) |
| F2 | `$89` | weitersuchen |
| F3 | `$86` | Gehe zu Zeile (Eingabezeile) |
| F4 | `$8A` | rückwärts suchen |
| F5 | `$87` | Markieren |
| F6 | `$8B` | Kopieren |
| F7 | `$88` | Ausschneiden |
| F8 | `$8C` | Einfügen |
| Strg+P | `$10` | Rückgängig |
| Strg+U | `$15` | Wiederholen |
| Strg+V | `$16` | Seite zurück |
| Strg+W | `$17` | Seite vor |
| CLR | `$93` | Zeilenende |
| Umschalt+DEL | `$94` | Zeichen unter dem Cursor löschen |
| Strg+O | `$0F` | Datei laden |
| Strg+K | `$0B` | Datei speichern |
| Strg+E | `$05` | übersetzen |
| Strg+F | `$06` | Programm speichern (PRG) |
| Strg+R | `$12` | Programm starten |
| Strg+D | `$04` | Programm im Debugger starten |
| Strg+G | `$07` | Haltepunkt in der Cursorzeile umschalten |
| Strg+A | `$01` | Projektlaufwerk 8 / 9 |
| ESC, HELP | `$1B`, `$84` | Menü öffnen (ESC schließt es auch) |
| Return, Tab, DEL, Cursortasten, Pos1, druckbare Zeichen | – | wie in Kapitel 2 |
| RESTORE | – | Notfalltaste (NMI) |

Die Tastencodes in der Spalte „Tastencode“ sind die Werte, die der KERNAL liefert (PETSCII); ein Strg+Buchstabe hat den Code des Buchstabens minus `$40`.

## Tasten im Debugger

| Taste | Wirkung |
|---|---|
| F1 oder `s` | Einzelschritt |
| F3 oder `n` | darüber (`JSR` läuft durch) |
| F5 oder `c` | weiter bis zum nächsten Haltepunkt |
| V (oder Strg+P, `$10`) | Programmbild bis zur nächsten Taste |
| Pfeil ab / auf | Speicher um 32 Byte blättern |
| F7, `q` oder STOP | Sitzung beenden |

## Tasten im Menü

| Taste | Wirkung |
|---|---|
| Links / rechts | Feld wechseln |
| Auf / ab | Eintrag wählen |
| Return | Eintrag ausführen |
| STOP, ESC oder HELP | Menü schließen |

## Menü

Die Befehlsleiste zeigt `VC65  File  Edit  Search  Build  Debug    ESC or HELP: Menu`. Die Menütexte sind englisch.

| Feld | Eintrag | Taste |
|---|---|---|
| File | Load | Strg+O |
| | Save | Strg+K |
| | Save program | Strg+F |
| | Drive | Strg+A |
| | About VC65 | |
| | Quit | STOP |
| Edit | Undo | Strg+P |
| | Redo | Strg+U |
| | Mark | F5 |
| | Copy | F6 |
| | Cut | F7 |
| | Paste | F8 |
| | Align line | nur Menü |
| | Align all | nur Menü |
| | Hex calculator | nur Menü |
| | Insert data | nur Menü |
| Search | Find | F1 |
| | Find next | F2 |
| | Find previous | F4 |
| | Go to line | F3 |
| | Replace | nur Menü |
| | Find label | nur Menü |
| | Set mark | nur Menü |
| | Go to mark | nur Menü |
| Build | Assemble | Strg+E |
| | Run | Strg+R |
| Debug | Debugger | Strg+D |
| | Breakpoint | Strg+G |

## Meldungen der Statuszeile

Die Meldungen sind englisch. Rechts in der Statuszeile steht die Cursorposition `L nnnn C nnnn` (L = Zeile, C = Spalte).

| Meldung | Bedeutung |
|---|---|
| OK n bytes | Übersetzen erfolgreich, Ausgabe n Byte |
| Ennn line z col s | erster Fehler beim Übersetzen; bei Include-Dateien `in file n` statt Spalte |
| Assemble first | keine aktuelle Ausgabe vorhanden (Strg+F, Strg+R, Strg+G) |
| Program saved | Strg+F erfolgreich |
| Error saving | Speichern fehlgeschlagen |
| Error loading | Laden fehlgeschlagen |
| Saved | Strg+K erfolgreich |
| Program ended | das Programm ist mit `RTS` zurückgekehrt |
| Program interrupted (emergency key) | mit RESTORE unterbrochen |
| Load address below $2000 | Programm kann nicht gestartet werden |
| File VC65D missing | der Debugger kann nicht geladen werden |
| File VC65X missing | das Werkzeug-Overlay (Ausrichten, Hex-Rechner, Daten einfügen) kann nicht geladen werden |
| No output here | Haltepunkt in einer Zeile ohne Ausgabe |
| Breakpoint set / removed | Strg+G |
| Too many breakpoints | Grenze der Haltepunkte erreicht |
| Project drive n | Strg+A |
| n replaced | Ersetzen: Anzahl der Ersetzungen |
| Mark set / Mark not set | Marken |
| Label not found | Label suchen ohne Treffer |
| No problems | Probleme-Leiste ohne Einträge |

## Fehler- und Warnungscodes

Der Assembler meldet Fehler als `Ennn` und Warnungen als `Wnnn`, jeweils mit Zeile und Spalte; Fehler stehen in der Probleme-Leiste rot, Warnungen gelb. Alle Codes mit Bedeutung und typischer Ursache stehen in [Kapitel 11](11-fehlercodes.md).
