.org $2000
BREITE = 40
HOEHE = BREITE / 2
ADR = $d000 + HOEHE * 2
        lda #BREITE
        lda #HOEHE
        lda ADR
        ldx #<ADR
        ldy #>ADR
        .byte BREITE, HOEHE, <ADR, >ADR
        lda #BREITE + 1 ; Kommentar
        lda *
        .word *
