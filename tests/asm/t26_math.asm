.target mega65
.org $2000
.byte int(7 / 2.0), round(2.5), floor(-2.5), ceil(2.1)
.byte abs(-3), sign(-9), min(4, 2, 8), max(4, 2, 8)
.byte sqrt(16), pow(2, 5), log2(8), log10(1000)
.byte int(sin(pi / 2)), int(cos(0)), round(atan2(1, 1) * 4)
.word round(sqrt(2) * 100), round(exp(1) * 100), round(log(10) * 100)
.word round(sin(1) * 100), round(cos(1) * 100), round(tan(1) * 100)
.word round(atan(2) * 100), round(asin(0.5) * 100), round(acos(0.5) * 100)
.word round(pow(2, 0.5) * 100), round(pow(2, -2) * 100), round(pow(10, 2.5))
.byte round(abs(-2.5) * 2), sign(-0.5), sign(0.0), round(min(2.5, 3) * 2), max(2.5, 3) * 2
.word round(sin(-1) * 100), round(cos(3) * 100), round(sin(10) * 100)
sinus:
    .repeat 32, i
        .byte round(128 + 127 * sin(i * 2 * pi / 32))
    .endrepeat
