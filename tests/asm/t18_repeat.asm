.target mega65
.org $2000
.repeat 3
        nop
.endrepeat
.repeat 4, n
        .byte n * n
.endrepeat
.repeat 0
        .byte 99
.endrepeat
.repeat 2, a
.repeat 2, b
        .byte a * 10 + b
.endrepeat
.endrepeat
.for i = 0, i < 10, i += 3
        .byte i
.next
.for i in range(3)
        .byte i
.next
.for c in [2, 5, 7]
        .byte c * 2
.next
.for i in range(10)
        .if i == 2
        .continue
        .endif
        .if i == 5
        .break
        .endif
        .byte i
.next
.for i in range(5, 0, -2)
        .byte i
.next
.for i in range(2, 5)
        .byte i
.next
end:    rts
