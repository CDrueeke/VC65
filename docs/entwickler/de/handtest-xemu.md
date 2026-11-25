<!-- SPDX-License-Identifier: MIT-0 -->
# Handtest im Emulator Xemu

Vor der Vorabversion 0.1.0-Alpha prüft der Inhaber die IDE von Hand im Emulator Xemu (Mac). Das ersetzt **nicht** den Test am echten MEGA65 ([handtest.md](handtest.md)).

## Vorbereitung
```bash
python3 tools/handtest_xemu.py
```
Das Werkzeug baut die Boot-D81 (VC65, VC65D, VC65T, VC65X, Systembibliotheken) und eine Projektdisk mit den MEGA65-Beispielen aus VintageCoder und startet Xemu mit Laufwerk 8 = Boot-D81 und Laufwerk 9 = Projektdisk. Mit `--prg` startet VC65 sofort; ohne: in BASIC `DLOAD "VC65"` und `RUN`. Mit `--no-start` wird nur gebaut.

## Bedienung in Kürze
| Taste | Wirkung |
|---|---|
| Strg+A | Projektlaufwerk 8 ↔ 9 (für die Beispiele: 9) |
| Strg+O | Datei laden (Name eintippen, Return), zum Beispiel `hello` |
| Strg+E | übersetzen; Strg+R starten; Strg+F Programm speichern; Strg+K Quelltext speichern |
| HELP | Menü (Pfeile, Return, STOP) |
| STOP | IDE beenden (zurück nach BASIC) |

## Prüfpunkte
Ankreuzen oder Auffälligkeiten notieren; die Spalte „Gerät“ bleibt für den späteren Test am MEGA65.

| Nr | Prüfung | Erwartung | Xemu | Gerät |
|---|---|---|---|---|
| 1 | Start | 80×50-Bild mit Befehlsleiste, Dateizeile, Probleme-Leiste, Statuszeile | | |
| 2 | HELP-Taste | Menü öffnet; in Xemu hängt die Zuordnung der HELP-Taste an der Tastaturbelegung (Taste notieren, falls nichts passiert) | | |
| 3 | Strg+A, Strg+O `hello`, Strg+E, Strg+R | Meldung „OK … Byte“, Programm läuft, danach zurück in der IDE | | |
| 4 | `cputest`, `pal_demo`, `music_demo` laden, übersetzen, starten | laufen wie unter VintageCoder | | |
| 5 | `jumprun`, `3x2_ptr.asm` (Kacheln) | übersetzen ohne Fehler und laufen | | |
| 6 | Fehler einbauen (Befehl falsch schreiben), Zeile wechseln | Zeile rot, Eintrag in der Probleme-Leiste, kein Cursorsprung | | |
| 7 | Suchen (F1), Ersetzen (Menü Suchen), Marke setzen/anspringen, Label suchen | wie beschrieben | | |
| 8 | Bearb: Zeile/Alles ausrichten, Hex-Rechner `2000+3f`, Daten einfügen `2001 2008` | Spalten, `$203f = 8255`, `.byte`-Zeilen | | |
| 9 | Debugger: Strg+D, Einzelschritt (F1), Weiter (F5), Ende (F7) | Register und Disassemblierung stimmen | | |
| 10 | Endlosschleife, dann RESTORE (Notfalltaste) | IDE meldet „unterbrochen“ | | |
| 11 | Strg+F Programm speichern, Strg+K Quelltext speichern | Datei steht auf dem Projektlaufwerk | | |

## Bereits automatisch geprüft (Xemu)
`python3 tools/extest_ide.py --proof` lädt jedes MEGA65-Beispiel aus VintageCoder von einer Projektdisk in die IDE, übersetzt es, speichert das Programm und vergleicht mit `vcc` (alle Hauptdateien byte-gleich: cputest, hello, jumprun, music_demo, pal_demo, prallball, tiles_demo ×5); danach startet es das Programm mit Strg+R und prüft über den Xemu-Monitor, dass das Abbild im Speicher steht und das Programm läuft (cputest schreibt seine Ergebnisse in die Zeropage, music_demo verändert die SID-Register). Mit `--run` entstehen Bildschirmfotos in `build/extest/`. `play_demo` und `standard_charsets` haben keine Quelltexte.

## Xemu-Version
Geprüft mit Xemu vom **2026-01-29** (Mac, `xmega65`). Mit Xemu vom **2024-09** (Windows) zeigt `prallball` einen kaputten Hintergrund und reagiert nicht auf RESTORE (Befund der Windows-Session, Vermutung: zu alt für Vollfarbzeichen und Audio-DMA; noch nicht mit einer neueren Windows-Version gegengeprüft). Die Mindestversion steht erst fest, wenn eine neuere Windows-Version geprüft ist.

## Ergebnis Handtest alpha-9 (2026-11-25, Windows, Xemu 2024-09-26, Windows-Tastatur)
Alle fünf Punkte bestanden: (1) Start der IDE, Prüfsummen, kurze Wartezeit durch das Overlay VC65A unproblematisch; (2) Strg+E mit Funktionen, danach Debugger (q) und Menü Edit > Align line, erneut Strg+E: gleiches Ergebnis; (3) hello, prallball, paldemo, musicdemo: Übersetzen, Starten und RESTORE bringen die IDE sauber zurück (paldemo und musicdemo zeigen die im Quelltext erwartete blaue Fläche; **kein Ton in diesem Xemu**, Ton nicht geprüft); (4) cputest ohne Bildmüll, jumprun läuft (RESTORE greift dort bekanntlich nicht), Kachel 3x2ptr wie in alpha-6; 2x2ptr, 3x2smc, 3x2rle, 2x2smc nicht erneut geprüft; (5) absichtliche Fehler (`.org 70000`, `.byte 70000`): Fehlerzeile und Problems-Leiste erscheinen. Hinweis: prallball liegt nur auf der Beispiel-Disk (Laufwerk 9 tauschen). Am echten MEGA65 weiterhin ungeprüft.
Nachtrag (Windows, alpha-9): alle fünf Kachelvarianten (3x2ptr, 2x2ptr, 3x2smc, 3x2rle, 2x2smc) laufen sauber; E212 bei `.include "demo.inc"` kommt nur, wenn die Datei von Laufwerk 8 geladen wurde (Kopfzeile „Project drive 8“), nicht von der Projektdisk in Laufwerk 9 (erwartet). Ton von musicdemo am Handtest-Rechner nicht prüfbar (keine Lautsprecher). Ab dem nächsten Paket liegt prallball auf der Handtest-Projektdisk (tools/handtest_xemu.py).
Korrektur (alpha-10): prallball auf der Handtest-Projektdisk funktioniert **nicht**, weil das D81 flach ist und gleichnamige Include-Dateien von jumprun (`levels.inc`, `music.inc`, ...) vorgehen (E202, `level_count` fehlt). prallball bleibt auf der Beispiel-Disk der Auslieferung (dort eindeutige Namen); für den Handtest Laufwerk 9 mit dieser Disk bestücken.
