; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; mnfind_test.asm - Test von mn_find: sucht bekannte und unbekannte Namen und prueft Fund und Quad-Flag.
; Ausgabe: "MNFIND: OK" oder "MNFIND: FEHLER BEI <Name>" (CHROUT). Zusaetzlich steht am Ende in $4200 das Ergebnis:
; $01 = bestanden, $00 = Fehler (fuer Pruefung per Monitor/Speicherabzug).
; =====================================================================================================================
.target mega65
.cpu 45gs02 { illegals = deny }

.org $2001
.basicstub start

start:  ldx #$00                    ; X = Testindex * 6
tl:     ldy #$00
cn:     lda cases,x                 ; Name (4 Byte) nach MN_TOK
        sta MN_TOK,y
        inx
        iny
        cpy #$04
        bne cn
        lda cases,x
        sta exp_found
        inx
        lda cases,x
        sta exp_quad
        inx
        stx save_x
        jsr mn_find
        ldx save_x
        bcs nf
        lda exp_found               ; gefunden: erwartet 1?
        beq fail
        ldy #$04
        lda (MN_PTR),y              ; Flags
        cmp exp_quad
        bne fail
        jmp nxt
nf:     lda exp_found               ; nicht gefunden: erwartet 0?
        bne fail
nxt:    cpx #CASES_LEN
        bne tl
        lda #$01
        sta $4200
        ldx #ok-msgs
        jmp out
fail:   lda #$00
        sta $4200
        ldx #bad-msgs
        jsr pstr
        ldy #$00
        txa                         ; Name des fehlgeschlagenen Falls ausgeben
        pha
        ldx #$00
pn:     lda MN_TOK,x
        beq pe
        jsr $ffd2
        inx
        cpx #$04
        bne pn
pe:     lda #13
        jsr $ffd2
        pla
        tax
        rts
out:    jsr pstr
        rts

pstr:   lda msgs,x
        beq ps1
        jsr $ffd2
        inx
        bne pstr
ps1:    rts

exp_found: .byte 0
exp_quad:  .byte 0
save_x:    .byte 0

; Faelle: Name(4), erwartet gefunden (1/0), erwartet Quad-Flag
cases:  .byte 'A', 'D', 'C', 0, 1, 0
        .byte 'T', 'Z', 'A', 0, 1, 0
        .byte 'L', 'D', 'A', 0, 1, 0
        .byte 'S', 'T', 'A', 0, 1, 0
        .byte 'B', 'B', 'R', '7', 1, 0
        .byte 'L', 'D', 'Q', 0, 1, 1
        .byte 'N', 'E', 'G', 'Q', 1, 1
        .byte 'L', 'B', 'N', 'E', 1, 0
        .byte 'Z', 'Z', 'Z', 0, 0, 0
        .byte 'A', 'B', 'C', 0, 0, 0
        .byte 'L', 'D', 'B', 0, 0, 0
        .byte 'X', 'X', 'X', 'X', 0, 0
CASES_LEN = 72

msgs:
ok:     .text "MNFIND: OK"
        .byte 13, 0
bad:    .text "MNFIND: FEHLER BEI "
        .byte 0

.include "../asm/optab.asm"
.include "../asm/mnfind.asm"
