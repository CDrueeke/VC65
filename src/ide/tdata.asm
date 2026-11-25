; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; tdata.asm - Datentabellen der IDE (Datei VC65T): die Befehlstabelle des Assemblers (optab.asm, rund 2,3 KB) und einige Puffer (tbss.asm) liegen nicht im
; Hauptprogramm, denn BASIC kann das Hauptprogramm nur bis $CFFF laden. VC65 laedt VC65T beim Start (ide_ldtab) nach $0004_F500 (CPU $F500
; in Block 7). tools/build_ide.py uebersetzt diese Datei zuerst und macht aus der Labeldatei build/optabsyms.asm (alle Namen als
; Konstanten), die das Hauptprogramm statt optab.asm einbindet.
; Aufbau der Datei: $F500 beginnt mit der Befehlstabelle (optab.asm), dahinter folgen die Puffer aus tbss.asm (nur Nullen). Die Adressen
; aller Eintraege sind fest (.org TDATA), das Hauptprogramm kennt sie ueber optabsyms.asm; wer optab.asm oder tbss.asm aendert,
; muss Hauptprogramm und VC65T gemeinsam neu bauen. Der Bereich darf nicht bis zu den Vektoren bei $FFFA reichen.
; Als PRG hat die Datei zwei Byte Ladeadresse; ide_ldtab/ov_get verwirft sie und schreibt den Rest nach $0004_F500.
; =====================================================================================================================
.target mega65
TDATA = $f500                       ; Ladeadresse (CPU-Sicht; Block 7 = Bank 4 in der IDE-Abbildung)
.org TDATA
.include "../asm/optab.asm"
.include "../asm/charnames.asm"          ; PETSCII-Namen fuer {name} in Zeichenketten (aus dem Hauptprogramm ausgelagert)
.include "tbss.asm"
