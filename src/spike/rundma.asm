; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; rundma.asm - Spike N0, Pruefpunkt 5 (Teil 2): Programm per DMA ueber das Attic in die Zielbank bringen, starten,
; zurueckkehren. Ablauf wie im Bankplan (Konzept Abschnitt 7): 1. Nutzlast (Hauptspeicher) -> Ausgabebank Attic A8
; ($0800_0000 + $80000); 2. Ausgabebank -> Zielbank 0 ab $4000; 3. JSR $4000; 4. Markierung pruefen.
; DMA-Setup und Listenformat wie im in Xemu geprueften DMA-Test (spike-n0.md): F018A (11 Byte) mit Optionsbytes
; $80/$81 (Quell-/Ziel-MB) und $00 (Ende), Start durch Schreiben der Listenadresse nach $D705 (Enhanced-Trigger).
; Nutzlast: A9 42 (LDA #$42) / 8D 00 41 (STA $4100) / 60 (RTS). Zeropage: $FB = Listenadresse low (Zwischenspeicher).
; =====================================================================================================================
.target mega65
.cpu 45gs02 { illegals = deny }

.org $2001
.basicstub start

TARGET = $4000
MARK = $4100
PLEN = 6

start:  sei
        lda #$47
        sta $d02f
        lda #$53
        sta $d02f                   ; VIC-IV / MEGA65-Register freischalten
        lda #$00
        sta $d703                   ; F018A: 11-Byte-Auftrag
        sta $d704                   ; Liste liegt in MB 0
        sta MARK
        ldx #$00
clr:    sta TARGET,x                ; Zielbereich vorher loeschen
        inx
        cpx #PLEN
        bne clr
        lda #<(list1)
        ldx #>(list1)
        jsr dma                     ; Schritt 1: Hauptspeicher -> Attic A8
        lda #<(list2)
        ldx #>(list2)
        jsr dma                     ; Schritt 2: Attic A8 -> Bank 0 ab $4000
        jsr TARGET                  ; Schritt 3: starten, Rueckkehr per RTS
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

; dma: A = Listenadresse low, X = high (Liste in Bank 0); kehrt nach Ende des Auftrags zurueck
dma:    pha
        phx
        lda #$00
        sta $d702                   ; Bank der Liste
        plx
        stx $d701                   ; Adresse high
        pla
        sta $d705                   ; Adresse low und START
        rts

; Aufträge: 5 Optionsbytes ($80,Quell-MB,$81,Ziel-MB,$00), dann Befehl, Laenge lo/hi, Quelle lo/hi/Bank,
; Ziel lo/hi/Bank, Modulo lo/hi
list1:  .byte $80, $00, $81, $80, $00
        .byte $00, PLEN, $00, <payload, >payload, $00, $00, $00, $08, $00, $00
list2:  .byte $80, $80, $81, $00, $00
        .byte $00, PLEN, $00, $00, $00, $08, $00, $40, $00, $00, $00

payload: .byte $a9, $42, $8d, $00, $41, $60

msgs:
ok:     .text "DMA, START UND RUECKKEHR OK"
        .byte 13, 0
fail:   .text "FEHLER: MARKIERUNG FEHLT"
        .byte 13, 0
