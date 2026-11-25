; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; sd.asm - Spike N0, Pruefpunkt 4 (Teil 1): Datei auf Laufwerk 8 (SD-Karte / eingelegtes D81) schreiben und zurueck-
; lesen, ueber die KERNAL-Dateiroutinen (SETLFS $FFBA, SETNAM $FFBD, OPEN $FFC0, CHKOUT $FFC9, CHKIN $FFC6, CHRIN $FFCF,
; CHROUT $FFD2, CLRCHN $FFCC, CLOSE $FFC3, READST $FFB7). Hyppo-Direktzugriff (Ordner, lange Namen) folgt in Teil 2.
; Ablauf: schreibt "HALLO VC65" als sequentielle Datei "VC65TEST", liest sie zurueck, vergleicht und meldet.
; Zeropage: $FB/$FC = Zeiger, $02 = Zaehler.
; =====================================================================================================================
.target mega65
.cpu 45gs02 { illegals = deny }

.org $2001
.basicstub start

LEN = 10

start:  ; --- schreiben ---
        lda #wnamel
        ldx #<(wname)
        ldy #>(wname)
        jsr $ffbd                   ; SETNAM
        lda #$02
        ldx #$08
        ldy #$02
        jsr $ffba                   ; SETLFS: Datei 2, Geraet 8, Sekundaeradresse 2
        jsr $ffc0                   ; OPEN
        bcs ferr
        ldx #$02
        jsr $ffc9                   ; CHKOUT
        bcs ferr
        ldx #$00
wlp:    lda data,x
        jsr $ffd2
        inx
        cpx #LEN
        bne wlp
        jsr $ffcc                   ; CLRCHN
        lda #$02
        jsr $ffc3                   ; CLOSE
        ; --- lesen ---
        lda #rnamel
        ldx #<(rname)
        ldy #>(rname)
        jsr $ffbd
        lda #$02
        ldx #$08
        ldy #$02
        jsr $ffba
        jsr $ffc0
        bcs ferr
        ldx #$02
        jsr $ffc6                   ; CHKIN
        bcs ferr
        ldx #$00
rlp:    jsr $ffcf                   ; CHRIN
        sta buf,x
        inx
        cpx #LEN
        bne rlp
        jsr $ffcc
        lda #$02
        jsr $ffc3
        ; --- vergleichen ---
        ldx #$00
cmp1:   lda buf,x
        cmp data,x
        bne bad
        inx
        cpx #LEN
        bne cmp1
        ldx #ok-msgs
        jmp out
bad:    ldx #fail-msgs
        jmp out
ferr:   jsr $ffcc
        lda #$02
        jsr $ffc3
        ldx #err-msgs
out:    lda msgs,x
        beq done
        jsr $ffd2
        inx
        bne out
done:   rts

wname:  .text "@0:VC65TEST,S,W"
wnamel = 15
rname:  .text "VC65TEST,S,R"
rnamel = 12
data:   .text "HALLO VC65"
buf:    .fill LEN, 0

msgs:
ok:     .text "DATEI GESCHRIEBEN UND GELESEN: OK"
        .byte 13, 0
fail:   .text "FEHLER: GELESENE DATEN ABWEICHEND"
        .byte 13, 0
err:    .text "FEHLER: OPEN ODER CHKIN/CHKOUT"
        .byte 13, 0
