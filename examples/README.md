<!-- SPDX-License-Identifier: MIT-0 -->
# Beispiele für VC65

Deutsch · [English below](#english)

Vier kleine bis große MEGA65-Programme aus VintageCoder, fertig als Quelltext für VC65 (MIT-0). Alles, was dort mit Editoren entsteht (Palette, Tracker-Song, Sprites, Zeichen, Levels), steht hier als `.byte` in Include-Dateien; es braucht keine Werkzeuge außer VC65.

| Beispiel | Datei | Zeigt |
|---|---|---|
| `hello` | `hello.asm` | kleinstes Programm: roter Rahmen, VIC-IV freischalten, 32-Bit-Zeiger, Q-Befehle (63 Byte) |
| `pal_demo` | `paldemo.asm` (+ `vic4.inc`, `pal65.asm`) | 256-Farben-Palette in den VIC-IV laden (867 Byte) |
| `music_demo` | `musicdemo.asm` (+ `sidmusic.inc`, `tune4.asm`) | Tracker-Song auf vier SID-Chips, 12 Stimmen (2,4 KB) |
| `prallball` | `prallball.asm` (+ Include-Dateien) | vollständiges Spiel: Vollfarbzeichen, 16-Farb-Sprites, Raster, Audio-DMA (54 KB; Anleitung in `prallball/README.md`) |

## Benutzen
Der Unterstrich `_` lässt sich auf manchen Tastaturen (zum Beispiel einer Mac-Tastatur im Emulator) nicht tippen; deshalb heißen die Hauptdateien ohne Unterstrich (`paldemo.asm`, `musicdemo.asm`). Beim Laden (Strg+O) gehört die Endung dazu: `hello.asm`, nicht `hello`.

Die Dateien liegen auf der Beispieldisk (`VC65-Beispiele-….d81`) ohne Unterordner. In VC65: Disk als Laufwerk 9 einhängen, **Strg+A** (Projektlaufwerk 9), **Strg+O** und den Namen der Hauptdatei, **Strg+E** übersetzen, **Strg+R** starten. Die Include-Dateien werden bei jedem Übersetzen von derselben Disk gelesen. Zurück in die IDE: RESTORE-Taste (Notfalltaste).

In den Verzeichnissen dieses Repositorys liegen dieselben Dateien nach Beispielen geordnet; auf der Disk gibt es keine Ordner, daher haben alle Dateien eindeutige Namen.

**Stand:** übersetzen in VC65 byte-gleich zu `vcc` und starten sind nur in Xemu geprüft, nicht am echten MEGA65 (`tools/extest_ide.py --repo --proof`).

<a id="english"></a>
# Examples for VC65

Four small to large MEGA65 programs from VintageCoder, ready as source for VC65 (MIT-0). Everything that is made with editors there (palette, tracker song, sprites, characters, levels) is included here as `.byte` in include files; nothing but VC65 is needed.

| Example | File | Shows |
|---|---|---|
| `hello` | `hello.asm` | smallest program: red border, unlock VIC-IV, 32-bit pointer, Q instructions (63 bytes) |
| `pal_demo` | `paldemo.asm` (+ `vic4.inc`, `pal65.asm`) | load a 256-colour palette into the VIC-IV (867 bytes) |
| `music_demo` | `musicdemo.asm` (+ `sidmusic.inc`, `tune4.asm`) | tracker song on four SID chips, 12 voices (2.4 KB) |
| `prallball` | `prallball.asm` (+ include files) | complete game: full-colour characters, 16-colour sprites, raster, audio DMA (54 KB; guide in `prallball/README.md`, German) |

## Use
The underscore `_` cannot be typed on some keyboards (for example a Mac keyboard in the emulator); the main files are therefore named without it (`paldemo.asm`, `musicdemo.asm`). When loading (Ctrl+O) the extension is part of the name: `hello.asm`, not `hello`.

The files are on the examples disk (`VC65-Beispiele-….d81`) without folders. In VC65: mount the disk as drive 9, **Ctrl+A** (project drive 9), **Ctrl+O** and the name of the main file, **Ctrl+E** to assemble, **Ctrl+R** to run. The include files are read from the same disk at every assembly. Back to the IDE: RESTORE key (emergency key).

In this repository the same files are sorted by example; the disk has no folders, so all file names are unique.

**Status:** assembling in VC65 byte-identical to `vcc` and running were checked in Xemu only, not on a real MEGA65 (`tools/extest_ide.py --repo --proof`).
