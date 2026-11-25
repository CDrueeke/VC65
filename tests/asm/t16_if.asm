.org $2000
MODUS = 2
BREITE = 80
.if MODUS == 1
        lda #1
.elseif MODUS == 2
        lda #2
.else
        lda #3
.endif
.if BREITE > 40
        ldx #$50
.else
        ldx #$28
.endif
.if 0
        nop
        .if 1
                brk
        .endif
.endif
.ifdef BREITE
        ldy #1
.endif
.ifndef BREITE
        ldy #2
.endif
.ifdef NIX
        ldy #3
.else
        ldy #4
.endif
        rts
