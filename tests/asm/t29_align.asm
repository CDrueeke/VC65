.target mega65
.org $2000
        nop
.align 4, $ea
        nop
.align 4
        nop
.align 8, skip
        nop
.align 4, 1 + 2
        nop
.align 16, -1
        rts
.align 2, $ff
