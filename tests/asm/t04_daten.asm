.org $2000
        .byte 1, 2, 3
        .byte $ff, -1, 'a'
        .word $1234, 65535, -1
        .dword $12345678, -2
        .byte "HELLO", 0
        .byte 1+2*3, (1+2)*3
        .fill 4, $aa
        .fill 3
        .text "abc"
data:   .word data, data+1
        .byte <data, >data
