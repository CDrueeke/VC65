; SPDX-License-Identifier: GPL-3.0-or-later
; ERZEUGT von tools/gen_mathtab.py - nicht von Hand aendern. Werte im Festkomma-Format 32.32 (8 Byte, tief zuerst).
; Zahlenformat 32.32: Wert = Ganzzahlanteil (Byte 4-7, vorzeichenbehaftet) + Bruchteil (Byte 0-3) / 2^32; die acht Bytes stehen
; tief zuerst (Little Endian). Beispiel c_one: Bytes 4-7 = 1. Die Tabellen dienen den CORDIC- und Reihenroutinen in math.asm
; (Erzeugung: tools/gen_mathtab.py; hier nie von Hand aendern, sonst weichen Tabelle und Generator voneinander ab).
CORDIC_N = 32                       ; Anzahl der CORDIC-Schritte = Eintraege in atab (32 Bruchbits)
; atab: arctan(2^-i) fuer i = 0..31 (Radiant, 32.32) = Drehwinkel je CORDIC-Schritt. Ab i = 11 ist arctan(x) im Rahmen der
; 32 Bruchbits gleich x = 2^-i, daher dort nur noch ein einzelnes gesetztes Bit.
atab:
        .byte $a2, $da, $0f, $c9, $00, $00, $00, $00  ; atan(2^-0)
        .byte $16, $9c, $b1, $76, $00, $00, $00, $00  ; atan(2^-1)
        .byte $f2, $eb, $b6, $3e, $00, $00, $00, $00  ; atan(2^-2)
        .byte $9b, $ba, $d5, $1f, $00, $00, $00, $00  ; atan(2^-3)
        .byte $dc, $ad, $fa, $0f, $00, $00, $00, $00  ; atan(2^-4)
        .byte $6f, $55, $ff, $07, $00, $00, $00, $00  ; atan(2^-5)
        .byte $ab, $ea, $ff, $03, $00, $00, $00, $00  ; atan(2^-6)
        .byte $55, $fd, $ff, $01, $00, $00, $00, $00  ; atan(2^-7)
        .byte $ab, $ff, $ff, $00, $00, $00, $00, $00  ; atan(2^-8)
        .byte $f5, $ff, $7f, $00, $00, $00, $00, $00  ; atan(2^-9)
        .byte $ff, $ff, $3f, $00, $00, $00, $00, $00  ; atan(2^-10)
        .byte $00, $00, $20, $00, $00, $00, $00, $00  ; atan(2^-11)
        .byte $00, $00, $10, $00, $00, $00, $00, $00  ; atan(2^-12)
        .byte $00, $00, $08, $00, $00, $00, $00, $00  ; atan(2^-13)
        .byte $00, $00, $04, $00, $00, $00, $00, $00  ; atan(2^-14)
        .byte $00, $00, $02, $00, $00, $00, $00, $00  ; atan(2^-15)
        .byte $00, $00, $01, $00, $00, $00, $00, $00  ; atan(2^-16)
        .byte $00, $80, $00, $00, $00, $00, $00, $00  ; atan(2^-17)
        .byte $00, $40, $00, $00, $00, $00, $00, $00  ; atan(2^-18)
        .byte $00, $20, $00, $00, $00, $00, $00, $00  ; atan(2^-19)
        .byte $00, $10, $00, $00, $00, $00, $00, $00  ; atan(2^-20)
        .byte $00, $08, $00, $00, $00, $00, $00, $00  ; atan(2^-21)
        .byte $00, $04, $00, $00, $00, $00, $00, $00  ; atan(2^-22)
        .byte $00, $02, $00, $00, $00, $00, $00, $00  ; atan(2^-23)
        .byte $00, $01, $00, $00, $00, $00, $00, $00  ; atan(2^-24)
        .byte $80, $00, $00, $00, $00, $00, $00, $00  ; atan(2^-25)
        .byte $40, $00, $00, $00, $00, $00, $00, $00  ; atan(2^-26)
        .byte $20, $00, $00, $00, $00, $00, $00, $00  ; atan(2^-27)
        .byte $10, $00, $00, $00, $00, $00, $00, $00  ; atan(2^-28)
        .byte $08, $00, $00, $00, $00, $00, $00, $00  ; atan(2^-29)
        .byte $04, $00, $00, $00, $00, $00, $00, $00  ; atan(2^-30)
        .byte $02, $00, $00, $00, $00, $00, $00, $00  ; atan(2^-31)
; Konstanten: c_k = 1/K = 0,607252935 (Kehrwert der CORDIC-Verstaerkung K = 1,6467..., Startwert der x-Koordinate)
c_k: .byte $a8, $ed, $74, $9b, $00, $00, $00, $00  ; CORDIC-Verstaerkung
c_pi: .byte $89, $6a, $3f, $24, $03, $00, $00, $00  ; pi
c_2pi: .byte $11, $d5, $7e, $48, $06, $00, $00, $00  ; 2 pi
c_hpi: .byte $44, $b5, $1f, $92, $01, $00, $00, $00  ; pi / 2
c_ln2: .byte $f8, $17, $72, $b1, $00, $00, $00, $00  ; ln 2
c_lg2: .byte $42, $4d, $10, $4d, $00, $00, $00, $00  ; log10(2)
c_one: .byte $00, $00, $00, $00, $01, $00, $00, $00  ; 1
c_half: .byte $00, $00, $00, $80, $00, $00, $00, $00  ; 0,5
