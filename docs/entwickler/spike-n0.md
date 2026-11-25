<!-- SPDX-License-Identifier: MIT-0 -->
# Spike N0: Zwischenergebnisse

Stand: 2026-11-22. Gemessen von der Windows-Sitzung in Xemu (40,5 MHz), gebaut mit `vcc` 0.2.1 (Release, SHA-256 `154dba43cfe19a69e1a6e45fa0e366746c0e831304e54a0e02e1eec8c4b04131`). Die Testquellen liegen nur im Scratchpad der Windows-Sitzung, nicht im Repository.

**Grenze der Aussage:** Xemu hat keine Wartezustände für das Attic-RAM. Alle Zeitvergleiche Attic gegen Hauptspeicher sind in Xemu **nicht aussagekräftig**; maßgeblich ist nur der Handtest am echten MEGA65.

| Nr | Prüfpunkt | Ergebnis in Xemu | Gilt für echte Hardware |
|---|---|---|---|
| 1 | 64 KB füllen und prüfen mit `[zp],Z` (Hauptspeicher Bank 4/5, Attic A0/A1) | je 0 Fehler; Schreiben 32384, Lesen 37216 CIA-Takte, in allen Bänken gleich | Funktion bestätigt (32-Bit-Zeiger ohne `MAP`-Wechsel). Geschwindigkeit **offen** |
| 2 | DMA 32 KB (Enhanced, Optionen `$80`/`$81`, Auslösen `$D705`): Haupt→Attic, Attic→Attic, Attic→Haupt, Haupt→Haupt | je 0 Fehler, je 1664 µs (≈ 19,7 MB/s); Füllen 32 KB Attic 864 µs | Funktion bestätigt. Geschwindigkeit **offen** |
| 3 | Reset löscht den Attic nicht (`src/spike/reset.asm`, als `AUTOBOOT.C65` auf D81 in Laufwerk 8; Reset per Schreiben von `$42` nach `$D6CF`, Bestätigung „FPGA reconfiguration request“ mit Yes) | Kennung `56 43 36 35` und Zähler überstehen den Xemu-Reset: nach dem Neustart meldet Autoboot „ATTIC ERHALTEN, LAUF NR 2“. Der UART-Monitor nimmt nach dem Reset keine Verbindung mehr an | Reset-Taste, Kaltstart und HyperRAM **nur am echten MEGA65 sicher** (N-E10) |
| 4 | SD über Hyppo (lesen, schreiben, Ordner, lange Namen) | Teil 1 (`src/spike/sd.asm`, sequentielle Datei `VC65TEST` mit 10 Byte schreiben und zurücklesen über KERNAL, Laufwerk 8): bestanden, sowohl mit frischer D81 (`-8`; Datei steht danach im D81-Verzeichnis, 1 Block) als auch mit einer Kopie des Standard-SD-Abbilds (`-sdimg`). Nicht geprüft: Ordner, lange Namen, Überschreiben, Löschen, Fehlerfälle (Datei existiert, voll), Zielort der Datei auf dem SD-Abbild. Teil 2 (Hyppo direkt, Ordner, lange Namen): nicht begonnen | offen |
| 5 | Programm per DMA nach Bank 0, starten, zurückkehren (`RTS`, `BRK`) | `RTS`: bestanden. `src/spike/run.asm` (CPU-Kopie nach `$4000`, `JSR`, `RTS`) und `src/spike/rundma.asm` (DMA Haupt → Attic A8 → Bank 0, `JSR`, `RTS`) meldeten „OK“ (Xemu, `-fastboot -prg`, 40,5 MHz PAL). `BRK`: nicht begonnen | am echten MEGA65 prüfen |

Folgerung für N-E11: Mit den Xemu-Werten ist nicht zu entscheiden, ob der Quelltext im Attic bleiben kann. Entscheidung nach Messung am echten MEGA65.

## Logo auf dem MEGA65 (`src/spike/logo.asm`)

Standard-Textmodus 80 × 25: Bildschirmcode `$A0` (voller Block), Farbe 14 (Block) und 7 (Punkt) im Farb-RAM. In Xemu sauber (7 Zeilen, 25 Spalten ab Zeile 8, Spalte 27). **Lehre:** Das Farb-RAM bei `$D800` deckt nur 1000 Zellen ab, darüber liegt bei `$DC00` die CIA; im 80×25-Modus ist das Farb-RAM über einen 32-Bit-Zeiger bei `$0FF8_0000` anzusprechen. Die Kantenschattierung des Logos braucht den Vollfarb-Zeichenmodus, ist noch nicht gebaut. Farben der Standardpalette am echten MEGA65 ungeprüft.

## Werkzeuge

D81 bauen: `vcc disk d81 … --add reset.prg:AUTOBOOT.C65`. Xemu mit `-8 <d81>` startet Autoboot von selbst und nimmt jeden Reset mit.

## Geschwindigkeit und BRK (Xemu, Stand 33ea766)

- `src/spike/speed.asm`: bestanden. Hauptspeicher Bank 5 und Attic A1 je Schreiben `$7E80` (32384) und Lesen `$9140` (37184) CIA-Takte, 0 Fehler. In Xemu ohne Attic-Wartezustände, **keine Aussage zur Hardware**; maßgeblich bleibt der Handtest.
- `src/spike/brk.asm` (erste Fassung): Behandler über `$0316` wird erreicht (Marke `$42` in `$4100`), die Rückkehr scheitert (kein Rücksprung hinter das `BRK`). Vorgabewerte in Xemu: `$0316/$0317` = `$CE4A`, `$0314/$0315` = `$F974`. Vermutung: Das MEGA65-KERNAL legt beim BRK-Eintritt mehr als A, X, Y auf den Stapel (z. B. Z). **Konsequenz für den Debugger:** Die Rückkehr darf sich nicht auf die Anzahl der KERNAL-Pushes verlassen.
- `src/spike/brk.asm` (Fassung 2): merkt den Stapelzeiger vor dem `JSR` und setzt ihn im Behandler auf SP − 5 (JSR 2 Byte, BRK 3 Byte). **Bestanden** (Xemu auf dem Mac, ROM BASIC 65 V920395): „BRK-RUECKKEHR OK“, Vektor `$0316` wieder `$CE4A`. Stapelabzug: SP vor dem `JSR` `$EF`, Eintritts-SP im Behandler `$E5`, also legt das KERNAL **5 Byte** über dem BRK-Rahmen ab (`$01E6` bis `$01EA` = `00 00 00 EF 60`; darüber P `B1`, PC `$4002`, dann die JSR-Rückkehr `$203C`). Für den Debugger: Rahmen über die Differenz zum bekannten SP ansprechen, die fünf KERNAL-Bytes nicht annehmen, sondern beim ersten Lauf auf dem Gerät erneut messen.

## Stand der Läufe (2026-11-22)

- Handtest-Paket: `tools/handtest.sh`, Anleitung [de](de/handtest.md) und [en](en/handtest.md).
- `src/test/mnfind_test.asm` (N2): Mnemonik-Suche, in Xemu (Mac) bestanden („MNFIND: OK“, Ergebnisbyte `$4200` = 1).

## Testen auf dem Mac

Xemu (`/Applications/xmega65.app`) läuft auf dem Mac mit dem ROM im Xemu-Ordner (nie im Repository). Beispiel (headless, Bildschirm und Speicher sichern):

`xmega65 -headless -sleepless -fastboot -besure -rom <MEGA65.ROM> -prg build/x.prg -prgexit -dumpscreen s.txt -dumpmem m.bin`

`m.bin` enthält die 384 KB Hauptspeicher; Ergebnisbytes der Tests liegen bei `$4200` (Mnemonik-Test) bzw. `$4100`/`$4200` ff. (BRK-Test).

## Weiterführend

Der Spike N0 ist in Xemu bis auf Hyppo-Direktzugriff (Ordner, lange Namen) und die Messungen am echten MEGA65 abgeschlossen. Danach hat Etappe N2 begonnen: [n2-assembler.md](de/n2-assembler.md).
