<!-- SPDX-License-Identifier: MIT-0 -->
# 12 Glossar

Englische Fassung: [../en/12-glossary.md](../en/12-glossary.md). Zurück zur [Übersicht](README.md). Vorabversion 0.1.1-Alpha.

Begriffe, die im Handbuch vorkommen, in alphabetischer Reihenfolge.

| Begriff | Erklärung |
|---|---|
| **45GS02** | Die CPU des MEGA65. Sie versteht den Befehlssatz des 6502 und des 65CE02 und bringt zusätzliche Register (Z, B, Q) mit. |
| **Alpha** | Entwicklungsstand: Das Programm enthält mit Sicherheit noch Fehler und ist nicht vollständig geprüft. |
| **Anonyme Marke** | Marke ohne Namen: `-` und `+` (auch `--`, `++`). `bne -` springt zurück zur nächsten `-`-Marke, `beq +` vorwärts zur nächsten `+`-Marke. |
| **Assembler** | Programm, das Quelltext aus Befehlsnamen (Mnemoniks) in Maschinencode übersetzt. In VC65 mit **Strg+E**. |
| **B-Register** | Basisseitenregister des 45GS02. Beim Start von Programmen ist es 0; verändern Sie es nur bewusst. |
| **Bank** | Ein Speicherbereich von 64 KB. VC65 läuft in Bank 4; Ihr Testprogramm läuft in Bank 0. |
| **BASIC-Stub** | Eine BASIC-Zeile `10 SYS <Adresse>` am Programmanfang, erzeugt mit `.basicstub`, damit das Programm mit `RUN` startet. |
| **Boot-D81** | Die Diskette mit VC65, dem Debugger, den Werkzeugen und den Systemdateien (Laufwerk 8). |
| **Chip-Symbole** | Namen für die Chip-Register des MEGA65, zum Beispiel `vic2.border` für `$D020`. Sie stehen in `MEG.CHIPS`. |
| **CHROUT** | KERNAL-Routine bei `$FFD2`: gibt ein Zeichen aus. |
| **D81** | Abbild einer 3,5-Zoll-Diskette des MEGA65 (800 KB). |
| **Debugger** | Werkzeug zum schrittweisen Ablaufen eines Programms mit Anzeige von Registern, Speicher und Quelltextzeile (**Strg+D**). |
| **Direktive** | Befehl an den Assembler, der keinen Maschinenbefehl erzeugt: `.org`, `.byte`, `.if` usw. Sie beginnt mit einem Punkt. |
| **DMA** | Direct Memory Access: Der MEGA65 kann Speicher ohne die CPU kopieren oder füllen (DMAgic). |
| **E-/W-Code** | Kennung einer Assembler-Meldung: `E…` Fehler, `W…` Warnung ([Kapitel 11](11-fehlercodes.md)). |
| **Emulator (Xemu)** | Programm, das einen MEGA65 nachbildet. VC65 ist bisher nur dort getestet. |
| **Haltepunkt** | Stelle im Programm, an der der Debugger anhält (**Strg+G**). |
| **Hex** | Hexadezimale Zahlen mit `$`, zum Beispiel `$D020`. |
| **Include** | Einbinden einer weiteren Datei: `.include "datei"` (Projektlaufwerk) oder `#include <pfad>` (Systembibliothek). |
| **KERNAL** | Das Betriebssystem im ROM des MEGA65 mit festen Einsprungadressen (`CHROUT`, `GETIN`, …). |
| **Label / Marke** | Name für eine Adresse im Quelltext, zum Beispiel `loop:`. |
| **Makro** | Benannter Textbaustein, den der Assembler bei jedem Aufruf einsetzt (`.macro` … `.endmacro`). |
| **Mnemonik** | Kurzname eines Maschinenbefehls, zum Beispiel `lda`, `sta`, `jsr`. |
| **Notfalltaste** | Die **RESTORE-Taste**: unterbricht ein laufendes Programm und kehrt in die IDE zurück. |
| **Overlay** | Programmteil, der bei Bedarf von der Diskette in einen festen Speicherbereich geladen wird (`VC65D`, `VC65X`, `VC65T`). |
| **PRG** | Dateiformat mit zwei Bytes Ladeadresse, gefolgt vom Programm. |
| **Probleme-Leiste** | Zeilen unter dem Text mit den Meldungen des letzten Übersetzens. |
| **Projektlaufwerk** | Das Laufwerk (8 oder 9), von dem Quelltexte geladen und auf das sie gespeichert werden (**Strg+A**). |
| **Q-Register** | 32-Bit-Register des 45GS02 aus Z, Y, X und A; wird mit den Q-Befehlen (`ldq`, `stq`, `inq`, …) benutzt. |
| **Scope** | Ein Namensbereich in `{ … }`; Marken darin sind von außen nur mit dem Scope-Namen erreichbar. |
| **Segment** | Ein zusammenhängender Block der Ausgabe ab einer Adresse (`.org`, `.segment`). |
| **SID** | Der Soundchip des C64. Der MEGA65 hat vier davon. |
| **Statuszeile** | Zeile unten im Editor mit Meldungen und der Cursorposition (`L nnnn C nnnn`). |
| **Systemdisk** | Die Boot-D81 in Laufwerk 8, von der VC65 Bibliotheken und Overlays liest. |
| **Systembibliothek** | Fertige Include-Dateien mit Konstanten und Makros für den MEGA65 (`<mega65/…>`). |
| **VCASM** | Die Assemblersprache von VintageCoder; VC65 versteht sie für den MEGA65. Die Sprache ist frei nutzbar. |
| **vcc** | Der Assembler von VintageCoder in der Kommandozeile; VC65 liefert für MEGA65-Quelltexte dasselbe Ergebnis. |
| **VIC-IV** | Der Grafikchip des MEGA65 mit Paletten zu je 256 Farben, Vollfarbzeichen und weiteren Betriebsarten. |
| **Z-Register** | Zusätzliches Indexregister des 45GS02. Mit `sta [$40],z` wird ein 32-Bit-Zeiger benutzt. |
| **Zeropage** | Die ersten 256 Byte des Speichers (`$00` bis `$FF`) mit besonders schnellem Zugriff. |
