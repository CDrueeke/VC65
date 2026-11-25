; SPDX-License-Identifier: MIT-0
; pal65: die 256-Farben-Palette aus dem Palettenfenster von VintageCoder, hier als fertige .byte-Tabellen (nicht von Hand ändern).
pal65_red:
        .byte $00,$ff,$18,$57,$e8,$65,$e2,$de
        .byte $e8,$55,$4c,$a4,$b7,$9a,$07,$2b
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$33,$33,$33,$33
        .byte $33,$33,$33,$33,$33,$33,$33,$33
        .byte $33,$33,$33,$33,$33,$33,$33,$33
        .byte $33,$33,$33,$33,$33,$33,$33,$33
        .byte $33,$33,$33,$33,$33,$33,$33,$33
        .byte $66,$66,$66,$66,$66,$66,$66,$66
        .byte $66,$66,$66,$66,$66,$66,$66,$66
        .byte $66,$66,$66,$66,$66,$66,$66,$66
        .byte $66,$66,$66,$66,$66,$66,$66,$66
        .byte $66,$66,$66,$66,$99,$99,$99,$99
        .byte $99,$99,$99,$99,$99,$99,$99,$99
        .byte $99,$99,$99,$99,$99,$99,$99,$99
        .byte $99,$99,$99,$99,$99,$99,$99,$99
        .byte $99,$99,$99,$99,$99,$99,$99,$99
        .byte $cc,$cc,$cc,$cc,$cc,$cc,$cc,$cc
        .byte $cc,$cc,$cc,$cc,$cc,$cc,$cc,$cc
        .byte $cc,$cc,$cc,$cc,$cc,$cc,$cc,$cc
        .byte $cc,$cc,$cc,$cc,$cc,$cc,$cc,$cc
        .byte $cc,$cc,$cc,$cc,$ff,$ff,$ff,$ff
        .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $80,$21,$c1,$62,$03,$a3,$44,$e4
        .byte $85,$26,$c6,$67,$08,$a8,$49,$e9
        .byte $8a,$2b,$cb,$6c,$0d,$ad,$4e,$ee
.const pal65_red_len = 256

; fertige Tabelle (nicht von Hand ändern)
pal65_green:
        .byte $00,$ff,$33,$ec,$c3,$ca,$c2,$1f
        .byte $05,$83,$c6,$a4,$b7,$ff,$d6,$2b
        .byte $00,$00,$00,$00,$00,$00,$33,$33
        .byte $33,$33,$33,$33,$66,$66,$66,$66
        .byte $66,$66,$99,$99,$99,$99,$99,$99
        .byte $cc,$cc,$cc,$cc,$cc,$cc,$ff,$ff
        .byte $ff,$ff,$ff,$ff,$00,$00,$00,$00
        .byte $00,$00,$33,$33,$33,$33,$33,$33
        .byte $66,$66,$66,$66,$66,$66,$99,$99
        .byte $99,$99,$99,$99,$cc,$cc,$cc,$cc
        .byte $cc,$cc,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $00,$00,$00,$00,$00,$00,$33,$33
        .byte $33,$33,$33,$33,$66,$66,$66,$66
        .byte $66,$66,$99,$99,$99,$99,$99,$99
        .byte $cc,$cc,$cc,$cc,$cc,$cc,$ff,$ff
        .byte $ff,$ff,$ff,$ff,$00,$00,$00,$00
        .byte $00,$00,$33,$33,$33,$33,$33,$33
        .byte $66,$66,$66,$66,$66,$66,$99,$99
        .byte $99,$99,$99,$99,$cc,$cc,$cc,$cc
        .byte $cc,$cc,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $00,$00,$00,$00,$00,$00,$33,$33
        .byte $33,$33,$33,$33,$66,$66,$66,$66
        .byte $66,$66,$99,$99,$99,$99,$99,$99
        .byte $cc,$cc,$cc,$cc,$cc,$cc,$ff,$ff
        .byte $ff,$ff,$ff,$ff,$00,$00,$00,$00
        .byte $00,$00,$33,$33,$33,$33,$33,$33
        .byte $66,$66,$66,$66,$66,$66,$99,$99
        .byte $99,$99,$99,$99,$cc,$cc,$cc,$cc
        .byte $cc,$cc,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $80,$21,$c1,$62,$03,$a3,$44,$e4
        .byte $85,$26,$c6,$67,$08,$a8,$49,$e9
        .byte $8a,$2b,$cb,$6c,$0d,$ad,$4e,$ee
.const pal65_green_len = 256

; fertige Tabelle (nicht von Hand ändern)
pal65_blue:
        .byte $00,$ff,$83,$8c,$79,$d4,$b9,$17
        .byte $92,$00,$17,$a4,$b7,$f9,$be,$2b
        .byte $00,$33,$66,$99,$cc,$ff,$00,$33
        .byte $66,$99,$cc,$ff,$00,$33,$66,$99
        .byte $cc,$ff,$00,$33,$66,$99,$cc,$ff
        .byte $00,$33,$66,$99,$cc,$ff,$00,$33
        .byte $66,$99,$cc,$ff,$00,$33,$66,$99
        .byte $cc,$ff,$00,$33,$66,$99,$cc,$ff
        .byte $00,$33,$66,$99,$cc,$ff,$00,$33
        .byte $66,$99,$cc,$ff,$00,$33,$66,$99
        .byte $cc,$ff,$00,$33,$66,$99,$cc,$ff
        .byte $00,$33,$66,$99,$cc,$ff,$00,$33
        .byte $66,$99,$cc,$ff,$00,$33,$66,$99
        .byte $cc,$ff,$00,$33,$66,$99,$cc,$ff
        .byte $00,$33,$66,$99,$cc,$ff,$00,$33
        .byte $66,$99,$cc,$ff,$00,$33,$66,$99
        .byte $cc,$ff,$00,$33,$66,$99,$cc,$ff
        .byte $00,$33,$66,$99,$cc,$ff,$00,$33
        .byte $66,$99,$cc,$ff,$00,$33,$66,$99
        .byte $cc,$ff,$00,$33,$66,$99,$cc,$ff
        .byte $00,$33,$66,$99,$cc,$ff,$00,$33
        .byte $66,$99,$cc,$ff,$00,$33,$66,$99
        .byte $cc,$ff,$00,$33,$66,$99,$cc,$ff
        .byte $00,$33,$66,$99,$cc,$ff,$00,$33
        .byte $66,$99,$cc,$ff,$00,$33,$66,$99
        .byte $cc,$ff,$00,$33,$66,$99,$cc,$ff
        .byte $00,$33,$66,$99,$cc,$ff,$00,$33
        .byte $66,$99,$cc,$ff,$00,$33,$66,$99
        .byte $cc,$ff,$00,$33,$66,$99,$cc,$ff
        .byte $80,$21,$c1,$62,$03,$a3,$44,$e4
        .byte $85,$26,$c6,$67,$08,$a8,$49,$e9
        .byte $8a,$2b,$cb,$6c,$0d,$ad,$4e,$ee
.const pal65_blue_len = 256

