<!-- SPDX-License-Identifier: MIT-0 -->
# 9 Die Beispielprogramme

Englische Fassung: [../en/09-examples.md](../en/09-examples.md). Zurück zur [Übersicht](README.md). Vorabversion 0.1.1-Alpha.

Die Beispiel-D81 (`VC65-Beispiele-0.1.1-alpha.d81`) enthält vier MEGA65-Programme aus VintageCoder als Quelltext. Sie stehen unter der Lizenz MIT-0: Sie dürfen sie ohne Auflagen verwenden, ändern und weitergeben. Jede Hauptdatei beginnt mit einem ausführlichen Kopfkommentar (Was das Programm zeigt, Bedienung, Hardware, Speicher). Lesen Sie ihn zuerst.

> **Hinweis:** Übersetzen in VC65 liefert dieselben Bytes wie `vcc`; das Starten ist nur im Emulator Xemu geprüft, nicht am echten MEGA65.

## So laden Sie ein Beispiel

1. Beispiel-D81 als **Laufwerk 9** einhängen.
2. In VC65 **Strg+A** drücken (`Project drive 9`).
3. **Strg+O**, den Namen der Hauptdatei tippen (zum Beispiel `hello.asm`), Return.
4. **Strg+E** übersetzt, **Strg+R** startet.
5. Programme ohne Rückkehr (Endlosschleife) beenden Sie mit der **RESTORE-Taste**.

Auf der Diskette gibt es keine Ordner, deshalb haben alle Dateien eindeutige Namen. Der Unterstrich `_` lässt sich auf manchen Tastaturen im Emulator nicht tippen; die Hauptdateien heißen darum `paldemo.asm` und `musicdemo.asm`.

## hello.asm: das kleinste Programm

| | |
|---|---|
| Größe | 63 Byte |
| Zeigt | roter Rahmen, VIC-IV freischalten, 32-Bit-Zeiger, Q-Befehle |
| Start | BASIC-Zeile (`.basicstub`), aus der IDE mit Strg+R |

Das Programm schaltet den **VIC-IV** frei (zuerst `$47`, dann `$53` nach `$D02F`; ohne diesen Handgriff sind die erweiterten Register ab `$D030` nicht erreichbar) und färbt den Rahmen rot (`vic2.border`, Farbe 2). Dann schreibt es ein Byte über einen **32-Bit-Zeiger** (`sta [$40],z`) in das Chip-RAM der Bank 1 (`$0001_0000`), das die CPU mit 16-Bit-Adressen nicht erreicht, und erhöht den Zeiger als ganzes 32-Bit-Wort mit den **Q-Befehlen** `ldq`, `inq`, `stq`. Am Ende steht eine Endlosschleife: Zurück in die IDE geht es mit RESTORE.

Gut zum Lernen: die Besonderheiten des 45GS02 (Z-Register, 32-Bit-Zeiger, Q-Register) in wenigen Zeilen.

## paldemo.asm: eine 256-Farben-Palette

| | |
|---|---|
| Dateien | `paldemo.asm` (Hauptdatei), `vic4.inc`, `pal65.asm` |
| Größe | 867 Byte, Ladeadresse `$2000` (ohne BASIC-Starter) |
| Zeigt | die Palette des VIC-IV: vier Bänke zu je 256 Farben mit 8 Bit Rot, Grün und Blau |

Der VIC-IV kennt statt der 16 festen Farben des C64 **vier Paletten zu je 256 Einträgen**. Das Programm lädt die Palette `pal65` (Einträge 0 bis 15: die C64-Farben, danach Verläufe) in Palettenbank 1 und wählt sie für Text und Bitmap. Auf dem Bildschirm ist kaum etwas zu sehen; das Ergebnis prüft man im Monitor des Emulators durch Lesen der Registerfenster `$D100` bis `$D3FF`. Auch dieses Programm endet in einer Endlosschleife.

Gut zum Lernen: Include-Dateien mit Makros (`vic4.inc`), Tabellen als `.byte`, Zugriff auf die Farbregister.

## musicdemo.asm: Tracker-Song auf vier SID-Chips

| | |
|---|---|
| Dateien | `musicdemo.asm`, `sidmusic.inc` (Spielroutine), `tune4.asm` (Songdaten) |
| Größe | 2402 Byte, Ladeadresse `$2000` |
| Zeigt | 12 Stimmen auf vier SID-Chips, Takt über die Rasterzeile |

Der MEGA65 hat **vier SID-Chips** (bei `$D400`, `$D420`, `$D440`, `$D460`), jeder mit drei Stimmen, zusammen zwölf Stimmen. Das Programm spielt den im Tracker von VintageCoder komponierten Song `tune4` endlos. Die Hauptschleife wartet auf Rasterzeile `$FF` und ruft einmal je Bild die Routine `music_play` auf; ein Aufruf ist ein Takt, der Song hat sechs Takte je Zeile. Für NTSC-Maschinen fügen Sie vor dem Include `.const NTSC = 1` ein (andere Frequenztabelle). Zu hören ist die Musik, auf dem Bildschirm ändert sich nichts. Die Wiedergabe ist am Windows-Rechner mit Xemu bestätigt, am echten MEGA65 ungeprüft.

Gut zum Lernen: Songdaten und Spielroutine einbinden, Rasterzeile als Zeitgeber, Konstanten vor dem Include setzen.

## prallball.asm: ein vollständiges Spiel

| | |
|---|---|
| Dateien | `prallball.asm` und die Dateien `input.asm`, `rand.asm`, `sound.asm`, `hiscore.asm` sowie viele `.inc`-Datendateien |
| Größe | Quelltext rund 224 KB (7500 Zeilen), übersetzt rund 54 KB |
| Zeigt | Vollfarbzeichen, 16-Farb-Sprites, Rasterinterrupt, vier SIDs, DMA-Audio |

Ein Ball-und-Schläger-Spiel mit 24 Levels: Der Ball prallt von Wänden, Schläger und Steinen ab; sind alle zerstörbaren Steine weg, beginnt das nächste Level. Steuerung: Joystick in Port 2 **oder** Tastatur (Z links, X rechts, Leertaste Feuer, R schaltet die Auflösung zwischen 320 × 200 und 640 × 400 um, RUN/STOP bricht zum Titel ab). Die Bestenliste schreibt das Spiel in die Datei `PRALL.HS` auf Gerät 8.

Das Beispiel zeigt, wie ein größeres Programm aus mehreren Dateien aufgebaut ist: Der Kopfkommentar von `prallball.asm` beschreibt jeden Abschnitt. Die Datei ist groß; der Editor fasst bis 768 KB. Beim Übersetzen liest VC65 die Include-Dateien von der Diskette. Für Testfassungen fügen Sie am Dateianfang vor den Includes eine Zeile `.const NAME = wert` ein (zum Beispiel `.const AUTOPLAY = 1`, dann spielt der Rechner selbst); die Namen stehen im Kopfkommentar.

> Auf der Titelseite steht „ein demospiel von vc65“; das ist die einzige bewusste Abweichung vom Original aus VintageCoder.

## Eigene Programme daraus entwickeln

- Beginnen Sie mit `hello.asm`, ändern Sie eine Zeile, übersetzen Sie, starten Sie. So lernen Sie den Ablauf Editor → Übersetzen → Starten.
- Setzen Sie im Debugger ([Kapitel 5](05-debugger.md)) einen Haltepunkt auf die erste Zeile und gehen Sie `hello.asm` im Einzelschritt durch. Es sind nur wenige Zeilen.
- Lesen Sie die Kommentare am Dateianfang von `musicdemo.asm` und `paldemo.asm`: Sie erklären die Register und den Speicherplan.
- Speichern Sie Änderungen nie auf der ausgelieferten Beispieldisk, sondern auf Ihrer eigenen D81 ([Kapitel 6](06-projekte-und-dateien.md)).
