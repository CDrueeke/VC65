; SPDX-License-Identifier: GPL-3.0-or-later
; Testprogramm fuer die Anzeigeschicht (tools/disptest.py): Tasten kommen aus einem Skript (PETSCII-Ebene) statt von der
; Tastatur. Ist das Skript zu Ende, wird der Bildschirm ($0800, Farb-RAM) einmal nach $A000/$9000 gesichert und STOP gemeldet.
.target mega65
.cpu 45gs02 { illegals = deny }
.branchlong auto
.org $2001
.basicstub start
ed_scr  = $b000
ed_attr = $8000
ED_ATTR32 = $8000                   ; Attributpuffer in Bank 0 (der Test liest ihn aus)
DISP_DIRECT = 0
KP      = $50
KQ      = $5c
start:  sei
        lda #$02
        tab                         ; Basisseite $0200
        lda #25
        jsr ed_init
        lda #<(text)
        sta ed_src
        lda #>(text)
        sta ed_src + 1
        lda #<(textend - text)
        sta ed_cnt
        lda #>(textend - text)
        sta ed_cnt + 1
        jsr ed_load
        lda #<(keys)
        sta KP
        lda #>(keys)
        sta KP + 1
        lda #$00
        sta KP + 2
        sta KP + 3
        sta snapped
        lda #<(script_key)
        sta disp_keyv
        lda #>(script_key)
        sta disp_keyv + 1
        jsr ed_run
        ldx #$03                    ; Ergebnis wie edtest
kr:     lda ed_cur,x
        sta $c400,x
        lda ed_top,x
        sta $c404,x
        lda ed_len,x
        sta $c408,x
        dex
        bpl kr
        lda ed_curline
        sta $c40c
        lda ed_curline + 1
        sta $c40d
        lda ed_topline
        sta $c40e
        lda ed_topline + 1
        sta $c40f
        lda ed_left
        sta $c410
        lda ed_left + 1
        sta $c411
        lda ed_patn
        sta $c412
        lda #$00                    ; Text nach $C600 (hoechstens 2 KB reichen fuer die Tests)
        sta E0
        sta E0 + 1
        sta E0 + 2
        sta E0 + 3
        sta E2
        lda #$c6
        sta E2 + 1
        lda #$00
        sta E2 + 2
        sta E2 + 3
tx:     jsr ed_eq_len
        beq tdone
        jsr ed_get
        ldz #$00
        sta [E2],z
        jsr ed_inc
        inc E2
        bne tx
        inc E2 + 1
        jmp tx
tdone:  lda #$00
        tab
        rts

; Tastenquelle: naechstes Skriptbyte; am Ende einmal Bild sichern, dann STOP
script_key:
        ldz #$00
        lda [KP],z
        beq sk_end
        inc KP
        bne sk_r
        inc KP + 1
sk_r:   rts
sk_end: lda snapped
        bne sk_stop
        lda #$01
        sta snapped
        lda #<SCRADDR               ; Bildschirmcodes -> $A000
        sta ET + 2
        lda #>SCRADDR
        sta ET + 3
        lda #$00
        sta ET + 4
        lda #$a0
        sta ET + 5
        ldx #$07
sn_p:   ldy #$00
sn_b:   lda (ET + 2),y
        sta (ET + 4),y
        iny
        bne sn_b
        inc ET + 3
        inc ET + 5
        dex
        bne sn_p
sn_t:   lda (ET + 2),y
        sta (ET + 4),y
        iny
        cpy #208
        bne sn_t
        lda #$00                    ; Farb-RAM -> $9000
        sta KQ
        sta KQ + 1
        lda #$f8
        sta KQ + 2
        lda #$0f
        sta KQ + 3
        lda #$00
        sta ET + 4
        lda #$90
        sta ET + 5
        ldx #$07
sc_p:   ldy #$00
        ldz #$00
sc_b:   lda [KQ],z
        sta (ET + 4),y
        iny
        inz
        bne sc_b
        inc KQ + 1
        inc ET + 5
        dex
        bne sc_p
sc_t:   lda [KQ],z
        sta (ET + 4),y
        iny
        inz
        cpy #208
        bne sc_t
sk_stop: lda #$03
        rts
.include "../editor/ed.asm"
.include "../editor/disp.asm"
.include "../editor/file.asm"
.include "../asm/optab.asm"
.include "../asm/mnfind.asm"
snapped: .byte 0
text:   {text}
textend:
keys:   {keys}
