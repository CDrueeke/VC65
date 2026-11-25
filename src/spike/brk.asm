; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; brk.asm - Spike N0, Pruefpunkt 5 (Teil 3): Rueckkehr aus einem BRK. Grundlage der Haltepunkte des Debuggers (Konzept
; Abschnitt 10). Die Nutzlast in Bank 0 ab $4000 besteht aus BRK, Signaturbyte (NOP) und RTS. Der BRK-Vektor des
; KERNALs ($0316/$0317, nach dem Eintritt liegen Y, X, A auf dem Stapel) wird auf einen eigenen Behandler gesetzt: er
; schreibt $42 nach $4100 und kehrt per RTI hinter das Signaturbyte zurueck (dort steht RTS). Der alte Vektor wird
; danach wiederhergestellt.
; Xemu-Befund (Windows, Stand 33ea766): Das MEGA65-KERNAL verteilt BRK ueber $0316 (Behandler wird erreicht), legt aber
; mehr als A, X, Y auf den Stapel; ein Abbau mit drei PLA und RTI landete falsch. Darum merkt sich diese Fassung den
; Stapelzeiger SP vor dem JSR und stellt ihn im Behandler her: JSR (2 Byte) und BRK (PC hoch, PC tief, P = 3 Byte) liegen
; fest unter SP; SP = SP_vor_JSR - 5 zeigt auf P, RTI kehrt dann unabhaengig von den Pushes des KERNALs hinter das BRK
; zurueck. Zur Auswertung kopiert der Behandler ausserdem 16 Byte des Stapels ab dem Eintritts-SP nach $4300 (Layout
; der KERNAL-Pushes, Eintritts-SP in $4210).
; =====================================================================================================================
.target mega65
.cpu 45gs02 { illegals = deny }

.org $2001
.basicstub start

TARGET = $4000
MARK = $4100
SPSAVE = $4200                      ; SP vor dem JSR
SPENTRY = $4210                     ; SP beim Eintritt in den Behandler
SNAP = $4300                        ; 16 Byte Stapelabzug

start:  sei
        lda $0316
        sta $fb
        lda $0317
        sta $fc                     ; alten BRK-Vektor merken
        lda #<(hand)
        sta $0316
        lda #>(hand)
        sta $0317
        lda #$00
        sta MARK
        ldx #$00
cp:     lda payload,x
        sta TARGET,x
        inx
        cpx #PLEN
        bne cp
        tsx
        stx SPSAVE                  ; SP vor dem JSR merken
        cli
        jsr TARGET                  ; BRK, Behandler, RTI, RTS
        sei
        lda $fb
        sta $0316
        lda $fc
        sta $0317                   ; Vektor zurueck
        cli
        lda MARK
        cmp #$42
        bne bad
        ldx #ok-msgs
        jmp out
bad:    ldx #fail-msgs
out:    lda msgs,x
        beq done
        jsr $ffd2
        inx
        bne out
done:   rts

hand:   tsx
        stx SPENTRY
        ldy #$00
hs:     lda $0101,x                 ; Stapelabzug ab SP + 1
        sta SNAP,y
        inx
        iny
        cpy #$10
        bne hs
        lda #$42
        sta MARK
        lda SPSAVE
        sec
        sbc #$05                    ; SP so setzen, dass RTI das P des BRK holt
        tax
        txs
        rti

PLEN = 3
payload: .byte $00, $ea, $60        ; BRK / NOP (Signatur) / RTS

msgs:
ok:     .text "BRK-RUECKKEHR OK"
        .byte 13, 0
fail:   .text "FEHLER: BRK NICHT BEHANDELT"
        .byte 13, 0
