; SPDX-License-Identifier: GPL-3.0-or-later
; Spike N0 (altes Pixelblock-Logo, Generator tools/gen_logo.py entfernt) - nicht von Hand aendern.
; =====================================================================================================================
; logo.asm - Spike N0: Zeigt das VC65-Logo auf dem MEGA65 im Standard-Textmodus (80 x 25, BASIC-65-Bildschirm).
; Jeder Logo-Block ist eine Zeichenzelle: Bildschirmcode $A0 (invertiertes Leerzeichen = voller Block), Farbe aus dem
; Farb-RAM ($0FF8_0000, ueber 32-Bit-Zeiger; $D800 reicht nur fuer 1000 Zellen, darueber liegt $DC00 = CIA): 14 (Hellblau, Block) bzw. 7 (Gelb, Punkt); Hintergrund und Rahmen schwarz. Taste beendet.
; Zeropage: $F7-$FA = 32-Bit-Farb-RAM-Zeiger, $FB/$FC = Kartenzeiger, $FD/$FE = Bildschirmzeiger, $02 = Zeilenzaehler.
; Bildschirm ab $0800 (80 Spalten), Logo @W@ x @H@ Zellen ab Zeile 8, Spalte 27.
; =====================================================================================================================
.target mega65
.cpu 45gs02 { illegals = deny }

.org $2001
.basicstub start

LOGO_W = @W@
LOGO_H = @H@
POS = 8 * 80 + 27

start:  lda #$00
        sta $d020
        sta $d021                   ; Rahmen und Hintergrund schwarz
        lda #$93
        jsr $ffd2                   ; Bildschirm loeschen
        lda #<(map)
        sta $fb
        lda #>(map)
        sta $fc
        lda #<($0800 + POS)
        sta $fd
        lda #>($0800 + POS)
        sta $fe
        lda #<(POS)
        sta $f7
        lda #>(POS)
        sta $f8                     ; Farb-RAM-Zeiger = $0FF8_0000 + POS (80x25: 2000 Byte ab $0FF8_0000)
        lda #$f8
        sta $f9
        lda #$0f
        sta $fa
        lda #LOGO_H
        sta $02
        ldz #$00
rowlp:  ldy #$00
        ldz #$00
collp:  lda ($fb),y
        tax
        lda scrtab,x
        sta ($fd),y
        lda coltab,x
        sta [$f7],z
        inz
        iny
        cpy #LOGO_W
        bne collp
        clc                         ; Kartenzeiger += LOGO_W
        lda $fb
        adc #LOGO_W
        sta $fb
        bcc +
        inc $fc
+       clc                         ; Bildschirmzeiger += 80
        lda $fd
        adc #80
        sta $fd
        bcc +
        inc $fe
+       clc                         ; Farb-RAM-Zeiger += 80
        lda $f7
        adc #80
        sta $f7
        bcc +
        inc $f8
+       dec $02
        bne rowlp
wait:   jsr $ffe4                   ; auf eine Taste warten
        beq wait
        rts

scrtab: .byte $20, $a0, $a0
coltab: .byte 0, 14, 7

map:
@MAP@
