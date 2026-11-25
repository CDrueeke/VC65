; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; reset.asm - Spike N0, Pruefpunkt 3: Loescht ein Reset das Attic-RAM?
; Ablauf: 1. RUN: schreibt die Kennung "VC65" und Zaehler 1 nach $0800_0000 (Attic) und meldet das.
;         2. Reset ausloesen (Reset-Taste oder Xemu-Reset), danach das Programm erneut laden und RUN.
;         3. Ist die Kennung noch da, meldet das Programm "ATTIC ERHALTEN" und zaehlt hoch.
; Ausgabe ueber CHROUT ($FFD2), nur Grossbuchstaben und Ziffern.
; Zeropage: $40-$43 = 32-Bit-Zeiger auf $0800_0000, Z = Index.
; =====================================================================================================================
.target mega65
.cpu 45gs02 { illegals = deny }

.org $2001
.basicstub start

start:  lda #$00
        sta $40
        sta $41
        sta $42
        lda #$08
        sta $43                     ; Zeiger = $0800_0000 (Attic, Anfang)
        ldz #$00
        lda [$40],z
        cmp #$56                    ; 'V'
        bne fresh
        inz
        lda [$40],z
        cmp #$43                    ; 'C'
        bne fresh
        inz
        lda [$40],z
        cmp #$36                    ; '6'
        bne fresh
        inz
        lda [$40],z
        cmp #$35                    ; '5'
        bne fresh
        inz                         ; Z = 4: Zaehler
        lda [$40],z
        clc
        adc #$01
        sta [$40],z
        pha
        ldx #$00
        jsr print
        pla
        clc
        adc #$30                    ; Zaehler als Ziffer (bis 9)
        jsr $ffd2
        lda #$0d
        jsr $ffd2
        rts

fresh:  ldz #$00
        lda #$56
        sta [$40],z
        inz
        lda #$43
        sta [$40],z
        inz
        lda #$36
        sta [$40],z
        inz
        lda #$35
        sta [$40],z
        inz
        lda #$01
        sta [$40],z                 ; Zaehler = 1
        ldx #msg2-msg1
        jsr print
        rts

; print: gibt ab Offset X (relativ zu msg1) eine nullterminierte Zeichenkette aus
print:  lda msg1,x
        beq pdone
        jsr $ffd2
        inx
        bne print
pdone:  rts

msg1:   .text "ATTIC ERHALTEN, LAUF NR "
        .byte 0
msg2:   .text "KENNUNG GESCHRIEBEN. JETZT RESET, DANN ERNEUT LADEN UND RUN"
        .byte 0
