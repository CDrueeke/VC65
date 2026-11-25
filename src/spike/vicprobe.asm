; SPDX-License-Identifier: GPL-3.0-or-later
; vicprobe.asm - Messung der VIC-IV-Register in Xemu: Abzuege von $D000-$D07F (nach $4000, $4080, $4100, $4180):
;   A = Zustand nach dem Start, B = H640 gesetzt, C = zusaetzlich V400, D = V400 wieder aus.
.target mega65
.cpu 45gs02 { illegals = deny }

.org $2001
.basicstub start

start:  sei
        lda #$47
        sta $d02f
        lda #$53
        sta $d02f
        lda #$00
        sta $fb
        lda #$40
        sta $fc
        jsr dump
        lda $d031
        ora #$80
        sta $d031
        lda #$80
        sta $fb
        lda #$40
        sta $fc
        jsr dump
        lda $d031
        ora #$08
        sta $d031
        lda #$00
        sta $fb
        lda #$41
        sta $fc
        jsr dump
        lda $d031
        and #$f7
        sta $d031
        lda #$80
        sta $fb
        lda #$41
        sta $fc
        jsr dump
        cli
        rts

dump:   ldy #$00
dl:     lda $d000,y
        sta ($fb),y
        iny
        cpy #$80
        bne dl
        rts
