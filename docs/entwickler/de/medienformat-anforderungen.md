<!-- SPDX-License-Identifier: MIT-0 -->
# Entwurf: Anforderungen von VC65 an ein Binärformat für Medien

Stand 2026-11-24, **Entwurf** auf Anfrage der Hauptsession (Zeitpunkt VintageCoder 0.3.1). Nur Anforderungen und Fragen; keine Implementierung, keine VCASM-Änderung. Nicht im Repository eingecheckt.

## 1 Ausgangslage und Entscheidungen
- VC65 hat **keine Medien-Editoren** und liest Medien nur. Der Export aus dem JSON-Original (JSON bleibt Quelle und Bearbeitungsformat) in ein kleines Binärformat genügt (einseitig).
- Heute gibt VC65 für ein `.include`/`#include` mit Medien-Endung den Fehler **E219** („in VC65 noch nicht unterstützt“). Die fertigen Daten der Beispiele liegen deshalb als `.byte`-Include-Dateien (`examples/`), erzeugt mit `vcc build` aus VintageCoder.
- Es gibt auf dem Gerät **keinen JSON-Leser** und keinen Platz dafür: die IDE-Abbildung hat rund 250 Byte Luft unter `$D000` (BASIC lädt nicht darüber); ein JSON-Parser (Zeichenketten, Verschachtelung, Hex-Farben `"#rrggbb"`) wäre allein größer als der freie Platz.

## 2 Welche Medienarten und in welcher Reihenfolge
VC65 braucht nur Medien, die ein MEGA65-Programm zur Laufzeit als Rohdaten benutzt (Ziel `mega65`, Profile `mega65.*`):

| Reihenfolge | Medium | Grund | Rohdaten (Beispiele aus `jumprun`/`pal_demo`/`music_demo`) |
|---|---|---|---|
| 1 | Palette `.vcpal` | einfachste Art, in jedem MEGA65-Beispiel mit Farben gebraucht | 3 × 256 Byte (R, G, B, Halbbytes vertauscht wie die Register), `pal65` |
| 2 | Zeichensatz `.vcchar` | Texte und Kacheln | 256 × 8 = 2048 Byte (`chars`), vollfarbig mehr |
| 3 | Sprite `.vcsprite` | Spiele | 898 Byte (`hero_base`), 386 Byte (`enemy_base`): 64-Byte-Blöcke |
| 4 | Bildschirm `.vcscreen` | Titelbilder | 2000 Byte Zeichen (plus 2000 Byte Farbe) (`title`) |
| 5 | Kacheln `.vctiles` | Level | 345 Byte je Level (`lv1`) |
| 6 | Lied `.vcsong` (Profil `mega65.sid4.song`) | Musik | 1574 Byte Daten + Spielroutine (`tune4`), 414 Byte (`jumprun/tune`) |

Nicht nötig für den Anfang: `.vcplay` (PLAY-Tracker), `.vcpmg` (Atari), Medien für andere Zielsysteme.

## 3 Wofür gelesen wird
1. **Einbinden in das übersetzte Programm** (Hauptzweck): der Assembler liefert die Bytes an der Include-Stelle, so wie es VCASM mit dem Medien-Include vorsieht (`.include "hero.vcsprite"` ergibt Assemblerdaten samt Marken, siehe unten).
2. **Vorlagen und Beispiele**: fertige Medien auf der Beispieldisk, damit Beispiele ohne Editor übersetzbar sind.
3. **Anzeige im Editor** (Vorschau, Größe, Art) ist ein späterer Wunsch, kein Muss.

## 4 Platz- und Speichergrenzen auf dem Gerät
- Programme laufen im MEGA65-Speicher; Quelltext, Include-Tabelle und Ausgabe liegen im **Attic** (28-Bit-Adressen, Quelltext `$0800_0000`, Dateitabelle `$0820_0000`, Ausgabe `$0850_0000`, je 1 MB reserviert). Die Include-Dateitabelle fasst mehrere Dateien; Größen sind 32 Bit.
- Praktische Obergrenze je Medium: **64 KB** (16-Bit-Länge genügt; ein Zeichensatz 2–4 KB, ein Bildschirm 4 KB, ein Lied unter 16 KB). Das Format sollte trotzdem 32-Bit-Längen führen.
- Die Ausgabe des Assemblers fasst 1 MB; `prallball` hat 54 KB Programm.
- **Speicher der Medien im Programm:** Bank 0 (Programm), Chip-RAM Bank 1 ab `$1_0000` (Zeichen/Sprites/Bildschirm laut Beispielen). Die Ablage regelt das Programm, nicht das Format.

## 5 Laden von Disk
- Quelle: **D81** (rund 800 KB, Dateinamen höchstens 16 Zeichen, keine Ordner), später SD-Karte. VC65 liest Dateien über die KERNAL-Dateiroutinen blockweise (256 Byte) in den Attic; das Format sollte daher **vorwärts lesbar** sein, ohne Suchen/Springen und ohne Gesamtlänge im Voraus zu kennen.
- Dateiart **PRG** mit zwei Bytes Ladeadresse am Anfang (so legt die Disk Dateien an); die Ladeadresse darf beliebig sein und wird vom Leser ignoriert (oder fest `$0000`).
- Aus dem Speicher (ohne Disk) ist heute kein Fall.

## 6 Kopf
Ein **einfacher Kopf genügt** (Vorschlag, little-endian wie die CPU):

| Feld | Größe | Inhalt |
|---|---|---|
| Kennung | 4 | z. B. `VCM` + `$00` |
| Version | 1 | Formatversion |
| Art | 1 | Palette, Zeichensatz, Sprite, Bildschirm, Kacheln, Lied |
| Profil | 1 | z. B. `mega65.sid4.song`, `mega65.palette` (Nummer statt Text) |
| Flags | 1 | Bit 0 = RLE-gepackt |
| Länge Nutzdaten | 4 | 32 Bit |
| Name | 16 | ASCII, für Marken (siehe 8) |

Danach die Nutzdaten **genau in der Registerreihenfolge der Hardware** (Palette Halbbytes vertauscht, Sprites in 64-Byte-Blöcken, Zeichen in 8-Byte-Gruppen). Bei zusammengesetzten Medien (Bildschirm: Zeichen + Farbe; Lied: Reihenfolge, Muster, Instrumente) eine kleine Liste von **Abschnitten** (Kennung, Länge, Daten) statt eines festen Aufbaus.

## 7 Wünsche zu Kompression und Byte-Reihenfolge
- **Byte-Reihenfolge:** little-endian für alle Zahlen im Kopf; Nutzdaten wie sie die Hardware erwartet.
- **Kompression:** optional und **ausgeschaltet als Standard** (der Assembler sollte nichts entpacken müssen). Nützlich ist ein einfaches **RLE** (Wert, Anzahl) für Bildschirme (viele gleiche Zeichen) und Kachelkarten; die Entpackroutine gehört dann ins Programm (wenige Dutzend Byte, Beispiel: `tiles_demo`-Variante `rle`). Kein LZ-Verfahren, weil Platz und Zeit auf dem Gerät knapp sind.
- Prüfsumme (CRC) ist nicht nötig; Länge und Kennung genügen.

## 8 Verwendung im Assembler-Include
Ja: das Format sollte dafür verwendbar sein. Heute liefert `.include "x.vcsprite"` in VintageCoder **Assemblerdaten mit Marken und Konstanten** (zum Beispiel `tune4_order`, `tune4_patterns`, `tune4_ins`, `tune4_speed`, `tune4_rows`, `tune4_patsize`; bei Paletten `pal65_red/_green/_blue`). Damit Quelltexte zwischen VintageCoder und VC65 austauschbar bleiben, braucht VC65 dieselben Namen und Werte:
- entweder trägt das Binärformat die Marken und Konstanten (Namen mit Versatz) selbst, und der Assembler legt sie beim Einbinden an,
- oder die Art/Profil legen die Namen fest (fester Namensplan aus dem Medien-Namen, zum Beispiel `<name>_red`), und das Format trägt nur Längen.
Ich empfehle die zweite Form (kleiner, keine Namenstabelle im Format), sofern der Namensplan je Profil in VintageCoder festgeschrieben ist.

## 9 Was heute an JSON auf dem MEGA65 nicht lesbar oder zu groß ist
| Datei (Beispiel) | JSON | Nutzdaten | Faktor |
|---|---|---|---|
| `jumprun/graphics/chars.vcchar` | 31 403 Byte | 2048 Byte | 15 × |
| `standard_charsets/…/vc-mega65-upper.vcchar` | 43 868 Byte | einige KB | über 10 × |
| `jumprun/graphics/title.vcscreen` | 13 075 Byte | 2000 Byte | 6,5 × |
| `jumprun/graphics/hero_over.vcsprite` | 10 192 Byte | 898 Byte | 11 × |
| `music_demo/music/tune4.vcsong` | 8375 Byte | 1574 Byte | 5 × |
| `pal_demo/graphics/pal65.vcpal` | 2665 Byte | 768 Byte | 3,5 × |
| `jumprun/graphics/lv1.vctiles` | 4115 Byte | 345 Byte | 12 × |

Der heutige Ausweg (Export als `.asm` mit `.byte`) ist ebenfalls groß: `chars.asm` 11,9 KB Text für 2048 Byte, `title.asm` 11,8 KB für 2000 Byte, `pal65.asm` 4,7 KB für 768 Byte; jede Datei muss bei jedem Übersetzen von der Disk gelesen und zeilenweise übersetzt werden.

## 10 Fragen an VintageCoder
1. Gibt es je Profil einen festen **Namensplan** der Marken und Konstanten des Medien-Includes (damit das Binärformat nur Längen trägt)?
2. Welche **Profile** für `mega65` sind nötig (Palette, Zeichensatz einfarbig/Mehrfarb/Vollfarb, Sprite 8-Bit/16-Farb, Lied `mega65.sid4.song`)?
3. Wie sieht ein **Bildschirm** mit Farb-RAM und mit 16-Bit-Zeichennummern (Super-Extended-Attribute-Mode) aus, ein oder zwei Abschnitte?
4. Soll der Export ein **eigener Befehl** sein (`vcc media export --format bin`) und welche **Dateiendung** bekommt die Binärdatei? Sie muss auf der D81 mit höchstens 16 Zeichen Namen ablegbar sein (Vorschlag: Endung weglassen, Art im Kopf).
5. Wie wird die **Versionierung** gehandhabt (Mindestversion, Verhalten bei unbekannter Version: ablehnen)?
6. Gilt für `.incbin` eine Zuordnung (Binärdatei einbinden ohne Marken) als Zwischenlösung, bis der Medien-Include fertig ist?
