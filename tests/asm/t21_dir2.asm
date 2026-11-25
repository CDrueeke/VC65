.target mega65
.org $2000
        nop
        .page
tab:    .byte 7
        .word tab
        .page 64
        .byte 1
.fill 3, $ea
.fill 4, i * 2               ; 0, 2, 4, 6
.fill 3, k + 10, k
zeilen:  .lohifill 5, $0400 + 40 * i
        lda zeilen,x
image:
        .pseudopc $0200
lauf:   inc $d020
        jmp lauf
        .endpseudopc
image_end:
        .byte <image_end, >image_end
tabelle: .rta eins, zwei
eins:   nop
zwei:   nop
.enum Farbe
    schwarz
    weiss
    rot = 5
    gruen, blau
.endenum
        lda #Farbe.rot
        ldx #Farbe.blau
.struct Punkt
    x      .byte
    y      .byte
.endstruct
.struct Sprite
    x      .byte
    y      .byte
    ptr    .word
    anim   .byte 4
    pos    Punkt
    trail  Punkt 3
.endstruct
spieler: .fill Sprite.size, 0
        lda spieler + Sprite.y
        ldx #Sprite.size
        .byte Sprite.pos.x, Sprite.pos.y, Sprite.trail.y
