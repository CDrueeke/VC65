; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; src.asm - Quelltext lesen ueber den 32-Bit-Zeiger SRC (Zeropage $60-$63). Das Zeichen 0 beendet den Quelltext.
; src_peek / src_peek1: Zeichen an SRC bzw. SRC+1 (A, Z veraendert). src_adv: SRC um 1 weiter (Register unveraendert).
; skipws: Leerzeichen und Tabulatoren ueberspringen.
; is_cmt2: erkennt den Zeilenkommentar `//` (wichtig, weil `/` auch der Divisionsoperator ist).
; Der Zeiger ist 32 Bit breit, weil der Quelltext im Chip-/Attic-RAM ausserhalb der ersten 64 KB liegen kann; gelesen wird deshalb
; mit dem 32-Bit-Zeiger-Befehl `lda [SRC],z` (Z = Versatz). Invarianten: SRC zeigt immer auf ein lesbares Zeichen, der Text endet
; mit Byte 0; kein Modul liest hinter dieses Byte. Zeichen werden nie veraendert (kein Gross-/Kleinwandeln hier).
; =====================================================================================================================
; src_peek: A = Zeichen an SRC (Z-Flag gemaess A). Veraendert A, Z; SRC bleibt.
src_peek:
        ldz #$00
        lda [SRC],z
        rts

; src_peek1: A = Zeichen an SRC+1 (Vorausschau um ein Zeichen, z. B. fuer `==`, `<<`, `//`). Veraendert A, Z.
src_peek1:
        ldz #$01
        lda [SRC],z
        rts

; src_adv: SRC um 1 erhoehen mit Uebertrag ueber alle vier Bytes; wichtig: `bne +` bricht ab, sobald ein Byte nicht
; auf 0 uebergelaufen ist (nur dann ist der Uebertrag ins naechste Byte noetig). Flags undefiniert.
src_adv:
        inc SRC
        bne +
        inc SRC + 1
        bne +
        inc SRC + 2
        bne +
        inc SRC + 3
+       rts

; skipws: Danach zeigt SRC auf das erste Zeichen, das weder Leerzeichen ($20) noch Tabulator ($09) ist; A = dieses Zeichen.
skipws: jsr src_peek
        cmp #$20
        beq sw1
        cmp #$09
        bne sw2
sw1:    jsr src_adv
        jmp skipws
sw2:    rts

; is_cmt2: Z gesetzt, wenn SRC auf `//` (Zeilenkommentar) steht
; Eingang SRC; Ausgang Z = 1 bei `//`. Veraendert A, Z. (Der Fall `/` allein oder anderes Zeichen liefert Z = 0 ueber `lda #1`.)
is_cmt2:
        jsr src_peek
        cmp #$2f
        bne ic2n
        jsr src_peek1
        cmp #$2f
        rts
ic2n:   lda #$01
        rts
