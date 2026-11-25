.target mega65
.org $2000
a:      .screencode "Hi@"
        .textnull "ab", "c"
        .textlen "ab", "c"
        .textshift "ab", "c"
        .retaddr a, $1234
        .addr $1234, a
        .lohitable 5, $0400 + 40 * i
        .relocate $0200
r1:     nop
        jmp r1
        .endrelocate
x:      .scope
y:      nop
        .endscope
.for i = 0, i < 3, i += 1
        lda #i
.endfor
        .dword $12345678
