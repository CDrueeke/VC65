.org $2000
start:  lda #$00
loop:   inx
        bne loop
        beq done
        jmp start
        jsr sub
done:   rts
sub:    lda #$01
        bra sub
        lbra sub
        lbne done
        bsr sub
        bsr after
after:  nop
