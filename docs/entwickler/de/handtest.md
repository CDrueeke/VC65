<!-- SPDX-License-Identifier: MIT-0 -->
# Handtest Spike N0 am echten MEGA65

Englische Fassung: [../en/handtest.md](../en/handtest.md). Zweck: die Punkte prüfen, die Xemu nicht aussagekräftig zeigt (Attic-Geschwindigkeit, Reset-Verhalten, Logo-Farben, `BRK`). Die Ergebnisse bitte in diese Tabelle oder an die VC65-Sitzung melden.

## Vorbereitung

1. Paket bauen (Mac, im Repository): `tools/handtest.sh` erzeugt `build/VC65TEST.D81` (alle Programme) und `build/VC65AUTO.D81` (Reset-Test als Autoboot).
2. Beide Dateien auf die SD-Karte des MEGA65 kopieren (z. B. in einen Ordner `VC65`).
3. Im MEGA65: `VC65TEST.D81` einhängen (Taste MEGA-Taste + Menü bzw. Disk-Menü), Laufwerk 8. Das Original-ROM wird vorausgesetzt.
4. Laden und starten mit `LOAD "NAME",8` und `RUN` (oder `DLOAD "NAME"`, dann `RUN`).

## Prüfungen

| Nr | Programm | Erwartete Ausgabe | Ergebnis |
|---|---|---|---|
| 1 | `SPEED` | Vier Zeilen mit Takten (`HAUPT SCHREIB`, `HAUPT LESEN`, `ATTIC SCHREIB`, `ATTIC LESEN`) und `FEHLER: 00`. **Die vier Werte abschreiben.** Sind die Attic-Zeilen deutlich größer als die Hauptspeicherzeilen, ist der Attic langsamer. Entscheidung N-E11 | |
| 2 | `RUN` | `START UND RUECKKEHR OK` | |
| 3 | `RUNDMA` | `DMA, START UND RUECKKEHR OK` | |
| 4 | `BRK` | `BRK-RUECKKEHR OK` (hängt der Rechner oder landet er im Monitor, bitte vermerken) | |
| 5 | `SD` | `DATEI GESCHRIEBEN UND GELESEN: OK`; danach steht die Datei `VC65TEST` im Verzeichnis (`DIRECTORY`) | |
| 6 | `LOGO` | Logo „VC65.“ aus 7 Zeilen, hellblaue Blöcke, gelber Punkt, schwarzer Grund; **Farben und Schärfe beurteilen**. Taste beendet | |
| 7 | Reset | `VC65AUTO.D81` einhängen und Rechner neu starten (Autoboot startet `RESET`: `KENNUNG GESCHRIEBEN`). **Reset-Taste drücken**: meldet der Autoboot danach `ATTIC ERHALTEN, LAUF NR 2`, überlebt der Attic die Reset-Taste. Danach **Kaltstart** (Ausschalten und Einschalten): `NR` sollte wieder 1 sein, sonst vermerken. Entscheidung N-E10 | |

Hinweise: `SPEED` und `LOGO` benötigen den normalen Start aus BASIC 65. Bricht ein Programm ab, ohne etwas auszugeben, Reset-Taste drücken und das Programm erneut laden. Die Programme schreiben nur in Bank 0 ab `$4000`, in das Attic (ab `$8000000`, Bänke 1, 8) und auf Laufwerk 8; sie berühren die SD-Karte nur über die eingehängte D81.

## Noch ungeprüft am Gerät (IDE, Stand 2026-11-24)

Alles Folgende läuft in Xemu, ist aber **nicht** am echten MEGA65 geprüft und gilt nicht als fertig:

| Nr | Punkt | Erwartung | Ergebnis |
|---|---|---|---|
| A | HELP-Taste (Code `$84`) öffnet das Menü | Aufklappfeld erscheint; Pfeile, Return, STOP wie beschrieben | |
| B | Alle Menüpunkte (Datei, Bearb, Suchen, Bauen, Debug, Ersetzen, Ausrichten) | führen den Befehl aus wie die Tastenkürzel | |
| C | 50-Zeilen-Bild, Kopfzeilen, Probleme-Leiste, Farben (hellblaue Leiste, graue Leisten, rote Fehlerzeilen) | lesbar, richtige Farben, keine Reste nach Rückkehr aus Programm/Debugger | |
| D | Laden der Datei `VC65T` (Befehlstabelle) beim Start von der Disk | IDE startet; fehlt die Datei, kehrt VC65 zu BASIC zurück | |
| E | Automatische Prüfung bei Zeilenwechsel | Geschwindigkeit bei jedem Zeilenwechsel, Texte bis 16 KB, kein spürbares Stocken, kein Cursorsprung | |
| F | Zwei D81 (Systemdisk und Projektlaufwerk), Strg+A schaltet 8/9 | Bibliotheken und Projektdateien werden gefunden | |
| G | Menüpunkte Suchen: Marke setzen / anspringen, Label suchen; Ersetzen; Ausrichten | wirken wie beschrieben | |
| H | Menü Bearb: Hex-Rechner, Daten einfügen (Datei `VC65X`, Laden beim ersten Gebrauch) | Rechnung und eingefügte `.byte`-Zeilen stimmen | |
