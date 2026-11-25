.target mega65
.org $2000
.var t = [10, 20, 30]
.byte t                          ; alle Elemente
.byte t[1], t[-1], len(t)
.byte t[1:3]
.byte [0] * 3 + [7]
.byte t[:2], t[2:], t[5:], t[-2:]
.var quadrate = []
.for n in range(5)
    quadrate += [n * n]
.next
tab:    .byte quadrate
.byte range(3), range(2, 6), range(10, 0, -4), len(range(7))
.var u = t + [40]
.byte len(t), len(u), u[3]
.for c in [2, 5, 7]
        .byte c * 2
.next
.for c in u
        .byte c + 1
.next
.var nested = [[1, 2], [3, [4, 5]], 6]
.byte nested, len(nested), nested[1][1][0]
.word t, [1000, 2000]
.byte 3 * [1, 2]
.var w = [1.5, 2.5]
.byte w[0] * 2, round(w[1])
.byte len([]), len([[]])
