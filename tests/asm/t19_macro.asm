.target mega65
.org $2000
.macro wait(n)
        ldx #n
@schleife:
        dex
        bne @schleife
.endmacro
        wait 10
        wait(20)
.macro lade(wert)
        lda wert
.endmacro
        lade #5
        lade $1234
.macro doppelt(a)
        .byte (a) * 2
.endmacro
        doppelt 1 + 2
.macro rahmen(farbe=0, takte=1)
        lda #farbe
        sta $d020
        .repeat takte
        nop
        .endrepeat
.endmacro
        rahmen
        rahmen 5
        rahmen 5, 2
.macro clear(adr, anzahl)
        ldx #anzahl
        lda #0
@loop:  sta adr - 1,x
        dex
        bne @loop
.endmacro
        clear $0400, 8
        clear $0500, 4
.macro w(n, reg=1)
        ldx #n
        .if reg == 0
        .exitmacro
        .endif
        nop
.endmacro
        w 1
        w 2, 0
start:  vor 3
.macro vor(k)
        .byte k, k + 1
.endmacro
        rts
