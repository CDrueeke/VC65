<!-- SPDX-License-Identifier: MIT-0 -->
# Editor (N1): Kern und Anzeige

Englische Fassung: [../en/n1-editor.md](../en/n1-editor.md). Quelle: `src/editor/ed.asm`.

## Aufbau
- **Lückenpuffer im Attic** (`$0830_0000`, 768 KB): Text mit LF als Zeilenende, 32-Bit-Positionen, Byte 0 kommt im Text nicht vor.
- **Eingabe und Ausgabe getrennt**: `ed_key` nimmt einen Tastencode, `ed_view` zeichnet in einen Bildpuffer (`ed_scr`, Farben `ed_attr`). Tastatur und VIC-IV-Anbindung folgen später.
- **Bild**: 80 Spalten, 25 oder 50 Zeilen, 5 Spalten Zeilennummern, letzte Zeile = Statuszeile. Färbung durch einen Lexer (Kommentar, Text, Zahl, Direktive, Label, Mnemonik über `mn_find`).
- **Tasten**: Zeichen, Return (mit Einrückung), Tab (auf Vielfache von 4), Rückschritt, Entf, Pfeile, Pos1/Ende, Bild auf/ab, `$1A` Rückgängig, `$19` Wiederholen.

## Rückgängig / Wiederholen
Jede Änderung (ein Byte einfügen oder löschen) wird im Verlauf (`$083C_0000`, 16 Byte je Eintrag: Art, Byte, Gruppe, Stelle, Cursor vorher, Cursor nachher) notiert. Tasten gleicher Art hintereinander (Zeichen/Tab, Return, Rückschritt, Entf) bilden eine **Gruppe**; jede andere Taste beginnt eine neue. Rückgängig macht die ganze letzte Gruppe zurück, Wiederholen spielt sie vor. Eine neue Änderung verwirft die Wiederholungsstufen. `ed_load` schreibt nicht mit und leert den Verlauf. Nach Undo/Redo wird die Zeilennummer neu gezählt (`ed_recount`).

## Suchen und Gehe-zu
Beides sind Routinen für die spätere Eingabezeile (die Bedienung folgt mit der Anzeigeschicht), noch keine Tasten.
- `ed_find_next` / `ed_find_prev`: Muster in `ed_pat` (bis 32 Byte), Länge in `ed_patn`. Gesucht wird hinter (vor) dem Cursor und umbrechend über Textende (Textanfang); Groß-/Kleinschreibung zählt nicht. Treffer: Carry gesetzt, Cursor auf dem Treffer; sonst Carry gelöscht und Cursor unverändert. Ein leeres Muster oder leerer Text findet nichts.
- `ed_goto`: Zeilennummer in `ed_garg`; 0 gilt als 1, hinter der letzten Zeile landet der Cursor am Anfang der letzten Zeile.
- Beide beenden die laufende Undo-Gruppe (wie eine Taste ohne Änderung) und zählen die Zeilennummer neu.
- Test: der Differenztest nutzt Befehle im Tastenskript (`$FE` + `g lo hi`, `f n Muster`, `n`, `p`).

## Auswahl und Zwischenablage
- **Auswahl** = Bereich zwischen Anker (`ed_anc`) und Cursor, solange `ed_sel` gesetzt ist. `$02` (Strg+B) setzt den Anker auf den Cursor bzw. hebt die Auswahl auf; Bewegungstasten ziehen sie auf. Ausgewählte Zeichen bekommen im Farbbyte das Bit `SELF` (`$20`, Umkehrdarstellung).
- **Zwischenablage** im Attic (`$0870_0000`, höchstens 64 KB, Länge `ed_cblen`): `$03` kopieren (hebt die Auswahl auf), `$18` ausschneiden, `$16` einfügen (eine aktive Auswahl wird dabei ersetzt). Ist die Auswahl zu groß oder der Puffer voll, passiert nichts.
- Rückschritt/Entf löschen eine aktive Auswahl; Zeichen, Return, Tab, Rückgängig und Wiederholen heben sie auf. Ausschneiden, Einfügen und das Löschen einer Auswahl sind je **eine** Undo-Gruppe.
- Die Zwischenablage bleibt beim Laden eines neuen Textes erhalten (Einfügen zwischen Dateien).

## Anzeigeschicht (`src/editor/disp.asm`)
Verbindet den Kern mit dem MEGA65: Bildpuffer auf den Bildschirm, Tastatur, Eingabezeile. Der Aufrufer legt `ed_scr`/`ed_attr` (je 2000 Byte, Bank 0) fest, ruft `ed_init` (25 Zeilen) und `ed_load`, dann `ed_run` (kehrt bei STOP zurück).
- **Bildschirm**: Standard-Textmodus 80×25; Bildschirmcodes nach `$0800`, Farb-RAM über den 32-Bit-Zeiger `$0FF8_0000` (Lehre aus Spike N0). `disp_init` setzt Rahmen/Hintergrund schwarz und den Attributmodus (`$D031` Bit 5). Das Bit `SELF` (`$20`) wirkt als Umkehrdarstellung (in Xemu mit Bildschirmfotos geprüft: `$20` kehrt um, `$40` blinkt/färbt, `$10` blendet aus). In der IDE-Abbildung ist die Ein-/Ausgabe ausgeblendet; `disp_init` ruft darum die Brückenroutine `kvic` (Rahmen, Hintergrund, `$D031`) und schaltet mit PETSCII `$0E` über das KERNAL auf den Zeichensatz Groß-/Kleinschreibung (Statuszeile: `Z`/`S` als Großbuchstaben `$5A`/`$53`). Der Textcursor ist dasselbe Bit auf seiner Zelle, umgeschaltet, damit er in einer Auswahl sichtbar bleibt.
- **Tastatur**: KERNAL-GETIN (PETSCII), wartend, mit Basisseite 0 und nur dann freigegebenen Interrupts; über den Zeiger `disp_keyv` austauschbar (die Tests speisen ein Tastenskript ein). Buchstaben werden PETSCII→ASCII umgesetzt.
- **Belegung** (Tabelle `kmap_in`/`kmap_out`): F1 Suchen (Eingabezeile), F2 weitersuchen, F3 Gehe zu (Eingabezeile), F4 rückwärts suchen, F5 Markieren, F6 Kopieren, F7 Ausschneiden, F8 Einfügen, `$10`/`$15` Rückgängig/Wiederholen, `$16`/`$17` Bild auf/ab, CLR Zeilenende, Umschalt+DEL Entfernen vorwärts, STOP Ende; Cursortasten, Pos1, Return, Tab, DEL und druckbare Zeichen gehen unverändert an den Kern.
- **Eingabezeile**: ersetzt die Statuszeile (`Suche: …` bzw. `Zeile: …`), Return übernimmt, STOP bricht ab, DEL löscht ein Zeichen; Suchen bearbeitet das letzte Muster (bis 32 Zeichen), Gehe-zu nimmt höchstens 4 Ziffern.
- **50 Zeilen**: in der IDE angeschlossen (VIC-IV V400, Bildschirm `$0004_D000`), siehe [n1-ide.md](n1-ide.md). **Noch nicht**: Fehlermeldungen („nicht gefunden“), Laden/Speichern, Menü. Die Hardwarebelegung (F-Tasten-Codes, Umkehrbit) ist in Xemu nicht prüfbar und gehört in den Handtest.
- **Test**: `tools/disptest.py [Anzahl] [Start]` (`src/test/disptest.asm`) spielt PETSCII-Tastenskripte ab und vergleicht Bildschirmcodes und Farb-RAM des letzten Bildes (auch mit offener Eingabezeile) sowie den Kernzustand mit einem Python-Modell. Stand: Samen 1–40 und 200–239 identisch.

**Direkt zeichnen:** Der Kern schreibt Zeichencodes nach `ed_scr` und Farben über den 32-Bit-Zeiger `ED_ATTR32` (`dw_attrptr`); mit `DISP_DIRECT = 1` (IDE) ist `ed_scr` der Bildschirm und `ED_ATTR32` das Farb-RAM, die Anzeigeschicht kopiert dann nichts mehr. Die Tests setzen `DISP_DIRECT = 0` und einen Puffer in Bank 0.

## Laden und Speichern (`src/editor/file.asm`)
Über die KERNAL-Dateiroutinen (Laufwerk `ed_fdev`, Vorgabe 8: SD-Karte oder D81), nur Dateinamen ohne Ordner (Ordner und lange Namen folgen mit dem Hyppo-Direktzugriff, wie beim Dateilader des Assemblers). Name in `ed_fname` (höchstens 16 Zeichen, Länge `ed_fnl`); Kleinbuchstaben werden für das Laufwerk groß.
- `ed_fload`: ersetzt den Text (`ed_clear`: Text, Verlauf, Auswahl, Ansicht; Zwischenablage und Suchmuster bleiben). Zeilenenden CR, CRLF und LF werden zu LF, Nullbytes entfallen. Schlägt das Öffnen oder das erste Lesen fehl (Datei fehlt), bleibt der Text unverändert. Rückgabe: Carry gelöscht = gut, sonst `A` = 1 Fehler, 2 Text zu groß (Anfang geladen), 3 Lesefehler mitten in der Datei (Teiltext). Eine **leere Datei** meldet das Laufwerk als Lesefehler: sie lässt sich nicht laden.
- `ed_fsave`: schreibt den Text unverändert (LF) als PRG-Datei und ersetzt eine vorhandene (`@0:NAME,P,W`). Im Test scheiterte das Ersetzen einer von `vcc disk` angelegten PRG-Datei mit Typ `S`, mit `P` klappt es; eine bestehende SEQ-Datei ist ungeprüft.
- **Bedienung** (Anzeigeschicht): Strg+O (`$0F`) lädt, Strg+K (`$0B`) speichert. Beide öffnen die Eingabezeile `Datei: …` mit dem letzten Namen zum Bearbeiten; Return führt aus, STOP bricht ab. Danach erscheint in der Statuszeile ab Spalte 20 bis zur nächsten Taste „Gespeichert“, „Fehler beim Laden“ oder „Fehler beim Speichern“. Die Tastencodes sind vorläufig und am Gerät ungeprüft.
- **Test**: `tools/disptest.py files [Anzahl] [Start]` bildet das Laufwerk als D81 in Xemu nach, spielt Tastenskripte mit Laden und Speichern (CR/CRLF/LF, Nullbytes, fehlende Dateien, Überschreiben, mehrere Blöcke) ab und prüft Bild, Kernzustand und die danach aus dem D81-Abbild gelesenen Dateien gegen das Python-Modell. Stand: Samen 1–8 und 10–39 identisch.

## Eine Datei (keine Reiter, Stand 2026-11-24)
- Der Editor arbeitet mit **einer** Datei; mehrere Reiter gibt es nicht mehr (`src/editor/tabs.asm` ist entfernt, das spart Platz). Der Textpuffer liegt im Attic bei `$0830_0000` (768 KB Text), der Verlauf bei `$083C_0000`.
- Die frühere Tastenbelegung Strg+N/L/J ist frei. `.include`/`#include` lesen immer von der Platte (Projektlaufwerk, Systemdisk); die Dateitabelle bei `$0820_0000` bleibt leer.
- **Test:** `tools/disptest.py` (Python-Modell, Zufallsfolgen mit Datei- und Eingabetasten, auch Laden/Speichern).

## Ersetzen und Ausrichten (Menü, Stand 2026-11-24)
- **Ersetzen** (Menü Suchen > Ersetzen, `SP_REPL`): Eingabezeilen „Suche:“ und „Ersatz:“, danach werden alle Treffer **ab dem Cursor bis zum Textende** ersetzt (ohne Umbruch, Groß-/Kleinschreibung egal, `ed_repl_all`); Meldung „n ersetzt“. Je Treffer löscht der Kern das Muster mit Rückschritt und fügt den Ersatz wie Tasten ein, Rückgängig geht also Schritt für Schritt.
- **Ausrichten** (Menü Bearb > Zeile ausrichten / Alles ausrichten, `ed_fmt_line` / `ed_fmt_all`, Anregung vom Turbo Macro Pro): Marke Spalte 0, Befehl Spalte 8, Operand bei 8 + max(4, Befehlslänge + 1), Kommentar Spalte 32 (oder ein Leerzeichen hinter dem Operanden, wenn der Platz fehlt). Unverändert bleiben Kommentarzeilen, Zeilen mit `.` oder `#` in Spalte 0 und Konstanten mit `=`; Leerraum am Zeilenende fällt weg; Zeilen ab 100 Zeichen bleiben unberührt; Anführungszeichen schützen `;` im Operanden.
- **Marken und Label-Sprung** (Menü Suchen, Anregung vom Turbo Macro Pro): *Marke setzen* und *Marke anspringen* fragen eine Ziffer 1–9 ab (Marke = Zeilennummer der Cursorzeile; sie wandert nicht mit, wenn Zeilen davor eingefügt werden), *Label suchen* fragt einen Namen ab und springt zur Zeile, die mit dem Namen beginnt und dann Doppelpunkt, Leerraum oder Zeilenende hat (`ed_find_label`, Groß-/Kleinschreibung egal, überschreibt das Suchmuster). Tests: `tools/edtest.py` (Zufallsfolgen und „label suchen feste Beispiele“ gegen `Ed.find_label`), `tools/idetest.py` (`marke`, `marke_leer`, `label`).
- **Test:** `tools/edtest.py` (Zufallsfolgen mit Ersetzen und Ausrichten gegen das Python-Modell `Ed.fmt`/`replace_all`, feste Beispiele „format feste Beispiele“), `tools/idetest.py` (`ersetzen`, `ausrichten` über das Menü).

## Test
`tools/edtest.py [Anzahl] [Start]` vergleicht den Kern in Xemu (`src/test/edtest.asm`) mit einem Python-Referenzeditor (Text, Cursor, Ausschnitt, Bild, Farben) auf Zufallsskripten inklusive Undo/Redo. Stand: Samen 1–30 und 100–129 identisch.
