.org $2000
        lda foo
        lda bar
        sta foo
        lda foo,x
        ldx foo,y
        jmp end
        nop
bar:    nop
foo = $10
end:    rts
