; SPDX-License-Identifier: GPL-3.0-or-later
; Testprogramm fuer den Editorkern (tools/edtest.py): laedt einen Text, spielt ein Tastenskript ab und hinterlaesst
; Zustand, Bild und Text im Speicher. Vorlage: tools/edtest.py setzt Zeilenzahl, Text und Tasten ein.
.target mega65
.cpu 45gs02 { illegals = deny }
.branchlong auto
.org $2001
.basicstub start
ed_scr  = $b000
ed_attr = $8000
ED_ATTR32 = $8000                   ; Attributpuffer in Bank 0 (der Test liest ihn aus)
DISP_DIRECT = 0
KP      = $50                       ; Zeiger auf das Tastenskript (ausserhalb der Editor-Zeiger)
start:  sei
        lda #$02
        tab                         ; Basisseite $0200
        lda #{rows}
        jsr ed_init
        lda #{hdr}
        ldx #{ftr}
        jsr ed_layout
        lda #{deco}
        sta ed_deco
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
kl:     jsr kn
        beq kd
        cmp #$fe
        beq kc
        jsr ed_key
        jmp kl
kc:     jsr kn                      ; Befehle: g lo hi (Gehe zu), f n Muster (Muster setzen), n (weiter), p (zurueck)
        cmp #$67
        bne k1
        jsr kn
        sta ed_garg
        jsr kn
        sta ed_garg + 1
        jsr ed_goto
        jmp kv
k1:     cmp #$66
        bne k2
        jsr kn
        sta ed_patn
        ldx #$00
kf:     cpx ed_patn
        beq kl
        phx
        jsr kn
        plx
        sta ed_pat,x
        inx
        jmp kf
k2:     cmp #$6e
        bne k3
        jsr ed_find_next
        jmp kv
k3:     cmp #$72                    ; r n Muster m Ersatz: alles ersetzen
        bne k4
        jsr kn
        sta ed_patn
        ldx #$00
kq:     cpx ed_patn
        beq kq2
        phx
        jsr kn
        plx
        sta ed_pat,x
        inx
        jmp kq
kq2:    jsr kn
        sta ed_repn
        ldx #$00
kq3:    cpx ed_repn
        beq kq4
        phx
        jsr kn
        plx
        sta ed_rep,x
        inx
        jmp kq3
kq4:    jsr ed_repl_all
        jmp kv
k4:     cmp #$6c                    ; l n Name: Label suchen
        bne k4b
        jsr kn
        sta ed_patn
        ldx #$00
kl2:    cpx ed_patn
        beq kl3
        phx
        jsr kn
        plx
        sta ed_pat,x
        inx
        jmp kl2
kl3:    jsr ed_find_label
        jmp kv
k4b:    cmp #$46                    ; F: alles formatieren, L: Zeile formatieren
        bne k5
        jsr ed_fmt_all
        jmp kv
k5:     cmp #$4c
        bne k6
        jsr ed_fmt_line
        jmp kv
k6:     jsr ed_find_prev
kv:     jsr ed_view
        jmp kl
kn:     ldz #$00
        lda [KP],z
        inc KP
        bne kn1
        inc KP + 1
kn1:    cmp #$00
        rts
kd:     ldx #$03                    ; Ergebnis: cur, top, len, curline/topline/left nach $C400
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
        lda #$00                    ; Text nach $C600
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
.include "../editor/ed.asm"
.include "../editor/fmt.asm"
.include "../asm/optab.asm"
.include "../asm/mnfind.asm"
text:   {text}
textend:
keys:   {keys}
