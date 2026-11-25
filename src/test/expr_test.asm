; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; expr_test.asm - Test des Ausdrucksrechners (src/asm/expr.asm) mit den Faellen aus expr_cases.asm.
; Zeropage-Seite: das Programm legt die Basisseite (B) auf $6F00, damit die Zeropage von BASIC unberuehrt bleibt.
; Ausgabe: "EXPR: OK (n)" oder "EXPR: FEHLER IN FALL xx" (xx hexadezimal). $4200 = 1 bestanden / 0 Fehler,
; $4201 = Fallnummer des ersten Fehlers.
; =====================================================================================================================
.target mega65
.branchlong auto
.cpu 45gs02 { illegals = deny }

.org $2001
.basicstub start

CP = $90                            ; Zeiger auf den aktuellen Testfall (16 Bit)
CI = $92                            ; Fallnummer

start:  lda #$6f
        tab                         ; Basisseite = $6F00
        lda #$00
        sta CI
        lda #<(cases)
        sta CP
        lda #>(cases)
        sta CP + 1
        lda #$00
        sta PC
        sta PC + 1
        sta PASS                    ; PASS = 0: unbekannte Symbole sind Fehler (E202)
        jsr sym_init
tl:     ldy #$00
        lda (CP),y                  ; Zeiger auf den Ausdruck
        sta SRC
        iny
        lda (CP),y
        sta SRC + 1
        lda #$00
        sta SRC + 2
        sta SRC + 3
        jsr ex_eval
        bcs gone
        ldy #$06                    ; erwartet Fehler?
        lda (CP),y
        bne fail
        ldy #$02                    ; Wert vergleichen
        ldx #$00
vc:     lda (CP),y
        cmp VAL,x
        bne fail
        iny
        inx
        cpx #$04
        bne vc
        jsr src_peek                ; Ausdruck vollstaendig gelesen?
        bne fail
        jmp nxt
gone:   ldy #$06
        lda (CP),y
        cmp ERR
        bne fail
nxt:    clc
        lda CP
        adc #$07
        sta CP
        bcc n1
        inc CP + 1
n1:     inc CI
        lda CI
        cmp #CASES_N
        bne tl
        lda #$00
        tab                         ; Basisseite zurueck
        lda #$01
        sta $4200
        ldx #ok-msgs
        jsr pstr
        lda #CASES_N
        jsr phex
        lda #41
        jsr $ffd2
        lda #13
        jsr $ffd2
        rts
fail:   lda CI
        sta $4201
        lda #$00
        tab
        sta $4200
        ldx #bad-msgs
        jsr pstr
        lda $4201
        jsr phex
        lda #13
        jsr $ffd2
        rts

pstr:   lda msgs,x
        beq ps1
        jsr $ffd2
        inx
        bne pstr
ps1:    rts

phex:   pha
        lsr
        lsr
        lsr
        lsr
        jsr nib
        pla
nib:    and #$0f
        cmp #$0a
        bcc nd
        adc #$36
        bne np
nd:     ora #$30
np:     jmp $ffd2

msgs:
ok:     .text "EXPR: OK ("
        .byte 0
bad:    .text "EXPR: FEHLER IN FALL "
        .byte 0

as_error: rts                       ; Stub: im Einzeltest werden Fehler ueber ex_error gemeldet
.include "../asm/zp.asm"
.include "../asm/src.asm"
HBASE = $c000
HMASK = $1fff
S2BANK = $04
.include "../asm/sym.asm"
ERR_E204 = 4
err_add: rts
sym_resolve: jmp sym_known_old
ex_postfix: lda #ERR_E202
        jmp ex_error
lst_literal: lda #ERR_E202
        jmp ex_error
list_apply: lda #ERR_E202
        jmp ex_error
ex_call: lda #ERR_SYNTAX
        jmp ex_error
.include "../asm/expr.asm"
.include "../asm/numx.asm"

.include "expr_cases.asm"
