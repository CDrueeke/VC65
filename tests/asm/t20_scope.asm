.target mega65
.org $2000
init: {
        ldx #8
loop:   dex
        bne loop
        rts
}
main: {
loop:   jsr init
        jmp init.loop
}
.namespace farbe {
        schwarz = 0
        weiss   = 1
}
        lda #farbe.weiss
.repeat 2, n
{
lbl:    dex
        bne lbl
        .byte n
}
.endrepeat
outer: {
        a = 5
        inner: {
                lda #a
                b = a + 1
                .byte b
        }
        .byte a, inner.b
}
.var v = 1
{
        .var v = 2
        .byte v
        v += 1
        .byte v
}
.byte v
