; SPDX-License-Identifier: GPL-3.0-or-later
; Spike M (MAP): Programm laeuft aus Bank 4. Der Lader kopiert das Abbild ($2001..) nach Bank 4 ($0004_2001..), blendet mit MAP
; die CPU-Adressen $2000-$BFFF auf Bank 4 ($42000-$4BFFF) und laeuft dort weiter. KERNAL-Aufrufe gehen ueber das Bruecken-
; stueck bei $1700 (Bank 0, immer sichtbar): Standardabbildung ($00,$00,$00,$83) herstellen, rufen, IDE-Abbildung zurueck.
.target mega65
.cpu 45gs02 { illegals = deny }
.branchlong auto
.org $2001
.basicstub start
BR      = $1700
MAPX    = $e4                       ; Blocks 1-3 ($2000-$7FFF) -> +$40000
MAPZ    = $34                       ; Blocks 4-5 ($8000-$BFFF) -> +$40000
start:  sei
        ldx #bridge_end - bridge_src - 1   ; Bruecke nach $1700 kopieren
cb:     lda bridge_src,x
        sta BR,x
        dex
        bpl cb
        lda #$00                    ; Abbild $2000-$BFFF (physisch Bank 0) nach $0004_2000 kopieren, beides ueber 32-Bit-Zeiger
        sta $f8
        sta $fc
        lda #$20
        sta $f9
        sta $fd
        lda #$00
        sta $fa
        sta $fb
        lda #$04
        sta $fe
        lda #$00
        sta $ff
        ldx #$a0                    ; 160 Seiten
cpg:    ldz #$00
cpb:    lda [$f8],z
        sta [$fc],z
        inz
        bne cpb
        inc $f9
        inc $fd
        dex
        bne cpg
        lda #$11                    ; Marke 1: Kopie fertig (Bank 5)
        jsr mark
        lda #$00
        ldx #MAPX
        ldy #$00
        ldz #MAPZ
        map
        eom
        lda #$22
        jsr mark
        ; ab hier lesen und schreiben wir Bank 4
        lda #$4d
        sta $2fff                   ; landet in Bank 4 ($42FFF)
        lda #'A'
        jsr kchrout                 ; Zeichen ueber die Bruecke ausgeben
        lda #'B'
        jsr kchrout
        lda #$0d
        jsr kchrout
        jsr kdefault                ; Standardabbildung fuer den Ruecksprung nach BASIC
        cli
        rts

mark:   sta $f0
        lda #$00
        sta $f1
        sta $f2
        lda #$05
        sta $f3
        lda #$00
        sta $f4
        ldz #$00
        lda $f0
        sta [$f1],z
        rts

; Bruecke (laeuft bei $1700)
bridge_src:
.pseudopc BR
kdefault:
        lda #$00
        ldx #$00
        ldy #$00
        ldz #$83
        map
        eom
        rts
kchrout:
        sta ka
        lda #$00
        ldx #$00
        ldy #$00
        ldz #$83
        map
        eom
        lda ka
        jsr $ffd2
        lda #$00
        ldx #MAPX
        ldy #$00
        ldz #MAPZ
        map
        eom
        rts
ka:     .byte 0
.endpseudopc
bridge_end:
