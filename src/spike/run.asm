; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; run.asm - Spike N0, Pruefpunkt 5 (Teil 1): Programm in die Zielbank kopieren, per JSR starten, per RTS zurueckkehren.
; Die Nutzlast (6 Byte, von Hand uebersetzt) liegt hier im Lader und wird mit der CPU nach $4000 (Bank 0) kopiert;
; spaeter ersetzt DMA aus der Ausgabebank (Attic) diesen Kopierschritt. Die Nutzlast schreibt $42 nach $4100 und kehrt
; mit RTS zurueck. Der Lader prueft die Markierung und meldet das Ergebnis ueber CHROUT ($FFD2).
; Nutzlast: A9 42 (LDA #$42) / 8D 00 41 (STA $4100) / 60 (RTS)
; =====================================================================================================================
.target mega65
.cpu 45gs02 { illegals = deny }

.org $2001
.basicstub start

TARGET = $4000
MARK = $4100

start:  lda #$00
        sta MARK                    ; Markierung loeschen
        ldx #$00
cp:     lda payload,x
        sta TARGET,x
        inx
        cpx #PLEN
        bne cp
        jsr TARGET                  ; Nutzlast in Bank 0 starten; Rueckkehr per RTS
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

PLEN = 6
payload: .byte $a9, $42, $8d, $00, $41, $60

msgs:
ok:     .text "START UND RUECKKEHR OK"
        .byte 13, 0
fail:   .text "FEHLER: MARKIERUNG FEHLT"
        .byte 13, 0
