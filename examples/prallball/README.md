<!-- SPDX-License-Identifier: MIT-0 -->
# PRALLBALL für den MEGA65 (Beispiel in VC65)

Ein Ball-und-Schläger-Spiel (C65-Modus, VIC-IV, vier SID-Chips, DMA-Audio, 40,5 MHz): der Ball prallt von Wänden, Schläger und Steinen ab; sind alle zerstörbaren Steine weg, beginnt das nächste Level (24 Levels). Das Beispiel zeigt, was ein größeres MEGA65-Programm in VCASM braucht: Vollfarbzeichen (FCM), 16-Farb-Sprites, Rasterinterrupt mit Farbverlauf, Audio-DMA, Datei auf dem Laufwerk (Bestenliste). Es stammt aus VintageCoder (MIT-0); hier liegt es fertig als Quelltext, ohne Editoren und Werkzeuge: alle Daten (Zeichen, Sprites, Levels, Musik) stehen als `.byte` in den Include-Dateien.

## Bedienung
Joystick in Port 2 (links/rechts, Feuer) **oder** Tastatur: Z = links, X = rechts, Leertaste = Feuer, R = Auflösung umschalten (320 × 200 / 640 × 400), RUN/STOP = Abbruch zum Titel. Feuer startet den Ball. Der Abprallwinkel hängt davon ab, wo der Ball den Schläger trifft.

## In VC65 übersetzen und starten
1. Die Beispieldisk (`VC65-Beispiele-….d81`) als zweites Laufwerk (9) einhängen; in VC65 **Strg+A** wählt das Projektlaufwerk 9.
2. **Strg+O**, Name `prallball.asm`, Return. Die Datei ist groß (rund 224 KB, 7500 Zeilen); der Editor fasst bis 768 KB.
3. **Strg+E** übersetzt (die Include-Dateien lädt VC65 von der Disk; Ergebnis rund 54 KB), **Strg+R** startet das Spiel. Zurück in die IDE: RESTORE-Taste (Notfalltaste).
4. Mit **Strg+F** lässt sich das Programm als Datei speichern (`.basicstub` erzeugt den BASIC-Starter, dann in BASIC `RUN`).

Die Bestenliste schreibt das Spiel in die Datei `PRALL.HS` auf Gerät 8.

## Aufbau
| Datei | Inhalt |
|---|---|
| `prallball.asm` | Hauptprogramm: Ablauf (Titel, Spiel, Spielende), Speicherplan, Physik, Steine, Extras, Anzeige; Kopfkommentar mit allen Abschnitten |
| `input.asm`, `rand.asm`, `sound.asm`, `hiscore.asm` | Eingabe, Zufall, Klang (4 SIDs, Musikspieler, DMA-Audio), Bestenliste |
| `gradient.inc`, `bricks.inc`, `sprites16.inc`, `sprites640.inc`, `gfx.inc.chars`, `gfx.inc.sprites`, `dirtable.inc`, `levels.inc`, `titelmusik.inc` | fertige Daten als `.byte` (Farbverläufe, Steine, Sprites, Zeichen, Abprallrichtungen, Levels, Titelmusik) |

Testfassungen: am Dateianfang vor den Includes eine Zeile `.const NAME = wert` einfügen (zum Beispiel `.const AUTOPLAY = 1`: der Rechner spielt selbst). Die Liste steht im Kopfkommentar von `prallball.asm`.

## Stand
Nur im Emulator Xemu getestet, **nicht** am echten MEGA65. Einzige bewusste Abweichung vom Original: Auf der Titelseite steht „ein demospiel von vc65“ statt „… von vintagecoder“.
