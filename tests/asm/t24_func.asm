.target mega65
.org $2000
.function lerp(a, b, t) = a + (b - a) * t / 255
.function bildschirm(zeile) = $0400 + 40 * zeile
.function quad(x) = x * x
.function summe(a, b) = quad(a) + quad(b)
        .byte lerp(0, 200, 128)
        .word bildschirm(3)
        .byte summe(3, 4), quad(quad(2))
.byte abs(-3), sign(-9), min(4, 2, 8), max(4, 2, 8)
.byte sqrt(16), pow(2, 5), sqrt(1000), pow(3, 0)
.byte int(7), round(5), floor(-2), ceil(9), sign(0), sign(12), abs(5)
 *= $2101
tabelle = next(256)
 .word tabelle, align(64)
.var v = 7
.byte quad(v), quad(v + 1), min(v, 9), max(v, 9)
.repeat 3, i
        .byte quad(i) + lerp(0, 255, i)
.endrepeat
max_label: nop
        lda #max_label & $ff
