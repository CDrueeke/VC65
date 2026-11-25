; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; speed.asm - Spike N0, Pruefpunkt 1 (Geschwindigkeit): 64 KB Hauptspeicher (Bank 5) und Attic (A1) schreiben und lesen,
; mit CIA1-Timer gemessen (Timer A zaehlt Takte, Timer B zaehlt die Unterlaeufe von A; CIA-Takt rund 1 MHz). Ausgabe:
; vier Zeilen "<Test> <8 Hexziffern>" = verstrichene CIA-Takte, kleiner = schneller; danach die Fehlerzahl.
; Wichtig fuer Entscheidung N-E11 (Quelltext im Attic oder im Hauptspeicher): Aussagekraft nur am echten MEGA65.
; Zeiger: $40-$43 = 32-Bit-Adresse (Bank 5: $0005_0000, Attic A1: $0801_0000), Z = Index. $41 = Seite (0-255).
; Zeropage: $44 = Mustermarke, $45 = Fehlerzaehler, $46 = Sicherung Y, $50-$53 = Messwert (hoechstes Byte zuerst).
; =====================================================================================================================
.target mega65
.cpu 45gs02 { illegals = deny }

.org $2001
.basicstub start

start:  sei
        lda #$47
        sta $d02f
        lda #$53
        sta $d02f                   ; VIC-IV freischalten
        lda #$40
        sta $d054                   ; 40,5 MHz
        lda #$5a
        sta $44                     ; Mustermarke
        lda #$00
        sta $45                     ; Fehlerzaehler
        ldx #hdr-msgs
        jsr pstr
        ldy #$00
tl:     lda b2tab,y
        sta $42
        lda b3tab,y
        sta $43
        lda #$00
        sta $40
        jsr tstart
        lda mtab,y
        bne chk
        jsr fill
        jmp dn
chk:    jsr check
dn:     jsr tstop
        sty $46
        tya
        asl
        asl
        asl
        asl
        clc
        adc #(n0-msgs)
        tax
        jsr pstr                    ; Name (16 Byte je Test, ab n0)
        lda $50
        jsr phex
        lda $51
        jsr phex
        lda $52
        jsr phex
        lda $53
        jsr phex
        lda #13
        jsr $ffd2
        ldy $46
        iny
        cpy #$04
        bne tl
        ldx #err-msgs
        jsr pstr
        lda $45
        jsr phex
        lda #13
        jsr $ffd2
        cli
        rts

; fill: 64 KB ab [$40] mit Muster (Z xor Seite xor Marke) beschreiben
fill:   lda #$00
        sta $41
fo:     ldz #$00
fi:     tza
        eor $41
        eor $44
        sta [$40],z
        inz
        bne fi
        inc $41
        bne fo
        rts

; check: 64 KB lesen und vergleichen, Fehler zaehlen
check:  lda #$00
        sta $41
co:     ldz #$00
ci:     tza
        eor $41
        eor $44
        cmp [$40],z
        beq okb
        inc $45
okb:    inz
        bne ci
        inc $41
        bne co
        rts

; Zeitmessung: CIA1 Timer A (Takte) und B (zaehlt Unterlaeufe von A) von $FFFFFFFF abwaerts
tstart: lda #$ff
        sta $dc04
        sta $dc05
        sta $dc06
        sta $dc07
        lda #$51
        sta $dc0f                   ; Timer B: Unterlaeufe von A, laden und starten
        lda #$11
        sta $dc0e                   ; Timer A: laden und starten
        rts

tstop:  lda #$00
        sta $dc0e
        sta $dc0f
        lda $dc07
        eor #$ff
        sta $50
        lda $dc06
        eor #$ff
        sta $51
        lda $dc05
        eor #$ff
        sta $52
        lda $dc04
        eor #$ff
        sta $53                     ; Takte = $FFFFFFFF - Zaehlerstand
        rts

; pstr: nullterminierte Zeichenkette ab msgs+X ausgeben
pstr:   lda msgs,x
        beq ps1
        jsr $ffd2
        inx
        bne pstr
ps1:    rts

; phex: A als zwei Hexziffern ausgeben
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

b2tab:  .byte $05, $05, $01, $01
b3tab:  .byte $00, $00, $08, $08
mtab:   .byte 0, 1, 0, 1

msgs:
hdr:    .text "CIA-TAKTE FUER 64 KB (KLEINER=SCHNELLER)"
        .byte 13, 0
; Namen: je Test 16 Byte (15 Zeichen und 0), Reihenfolge wie die Tabellen
n0:     .text "HAUPT SCHREIB: "
        .byte 0
n1:     .text "HAUPT LESEN:   "
        .byte 0
n2:     .text "ATTIC SCHREIB: "
        .byte 0
n3:     .text "ATTIC LESEN:   "
        .byte 0
err:    .text "FEHLER: "
        .byte 0
