.org $2000
        nop
        lda #$12
        lda $12
        lda $1234
        lda $12,x
        lda $1234,x
        lda $1234,y
        lda ($12,x)
        lda ($12),y
        lda ($12),z
        lda ($12,sp),y
        ldx $12,y
        ldx #$ff
        ldy #-1
        sta $d020
        stz $12
        stz $1234,x
        jmp $1234
        jmp ($1234)
        jmp ($1234,x)
        jsr $c000
        asl
        asl a
        asl $12
        lsr $1234,x
        inc
        inc $12
        dex
        inw $12
        phw #$1234
        phw $1234
        rts
