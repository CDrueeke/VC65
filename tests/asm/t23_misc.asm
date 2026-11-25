.target mega65
.org $2000   // Kommentar mit Schraegstrichen
tab:    .db 1, 2, 3   // noch einer
        .dw tab
        .long $12345678
        .dbyt $1234
        .assert * - tab <= 256, "passt in eine Seite"
        .assert 1
        .warning "noch nicht fertig"
.macro m(a)   // Makro
        .byte a   // ok
.endmacro
        m 5   // Aufruf
        lda #10 / 2   // geteilt
.var q = 8
.repeat 2, n   // Schleife
        .byte n + q / 4
.endrepeat
