.target mega65
.org $2000
.var x = 0
x = x + 1
x += 2
.byte x
x <<= 2
x -= 1
.byte x
.var y = 7
y *= 3
y %= 5
.byte y, x + y
.set y = 200
.byte y
