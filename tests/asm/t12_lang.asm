.branchlong auto
.org $2000
start:  bne far
        beq far
        bra far
        .fill 200, $ea
far:    rts
back:   nop
        .fill 200, $ea
        bne back
        bra back
        bsr back
