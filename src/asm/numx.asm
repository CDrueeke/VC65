; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; numx.asm - Kommazahlen (Festkomma 32.32, vorzeichenbehaftet, als 64-Bit-Zweierkomplement) im Ausdrucksrechner.
; Ein Wert besteht aus VTY (0 Ganzzahl, 1 Kommazahl, 2 Liste), VAL (Ganzzahlteil, 32 Bit) und VFR (Nachkommateil,
; 32 Bit, nur bei VTY = 1). Kommazahl = VAL + VFR / 2^32. Ganzzahl mit Ganzzahl bleibt Ganzzahl (alter Rechenweg);
; sobald eine Kommazahl beteiligt ist, wird in Festkomma gerechnet (ex_apply_x).
; Puffer (je 8 Byte, tief zuerst: Nachkomma 4 Byte, dann Ganzzahlteil 4 Byte): fxa (rechter Wert), fxb (linker Wert).
;
; Zahlenformat 32.32: ein 64-Bit-Zweierkomplementwert W, interpretiert als W / 2^32. Byte 0..3 = Nachkommateil (Byte 0 niedrigste
; Stelle), Byte 4..7 = Ganzzahlteil mit Vorzeichen (Byte 7 Bit 7 = Vorzeichen). Wertebereich also etwa +-2.147.483.648, kleinste
; Schrittweite 2^-32 (ca. 2.3e-10). Weil das Vorzeichen im Zweierkomplement des GANZEN 64-Bit-Werts steckt, hat eine negative
; Kommazahl einen um 1 kleineren Ganzzahlteil als die "Betragsdarstellung" (-1,5 = -2 + 0,5; VAL = $FFFFFFFE, VFR = $80000000).
; coerce_int wandelt das fuer Stellen, die eine Ganzzahl brauchen, zur Null hin um.
;
; Rolle: Dieses Modul sitzt zwischen dem Parser (expr.asm) und den Funktionen (math.asm/func.asm). ex_apply_x verteilt je
; Operatorkennung auf Ganzzahlweg (expr.asm: ex_apply), Festkommaweg (fx_*) oder Listenweg (list.asm: list_apply). math.asm
; benutzt die Rechenwerke fx_add/fx_sub/fx_mul/fx_div/fx_cmp direkt auf fxa/fxb ("Akkumulator" fxa, zweiter Operand fxb).
; Konvention der Rechenwerke: fxa = fxb OP fxa (das Ergebnis ueberschreibt fxa; fxb bleibt bei fx_add/fx_sub/fx_cmp erhalten,
; fx_mul/fx_div machen fxb zum Betrag, siehe fx_signs). Der Parser legt den linken Operanden nach fxb (ld_b) und den
; rechten nach fxa (ld_a), daher ist `fxb - fxa` = `links - rechts`.
; Genauigkeit/Ueberlauf: Addition/Subtraktion laufen im 64-Bit-Ring ohne Meldung ueber; fx_mul schneidet die Nachkommastellen
; hinter 2^-32 ab (kein Runden) und verwirft Ueberlauf oberhalb 2^31; fx_div liefert bei Divisor 0 Unsinn (Aufrufer muss
; vorher mit fx_isz_a pruefen).
; Zeropage: nutzt CLT/CEQ/CNT/TMP aus zp.asm; die Puffer am Dateiende liegen im Programmspeicher, nicht in der Zeropage.
; =====================================================================================================================
set_vint:                           ; Wert ist eine Ganzzahl (VTY = 0)
        lda #$00
        sta VTY
        rts

; ld_a / ld_b: VAL/VFR bzw. LHS/LFR als 64-Bit-Festkommawert nach fxa / fxb. Ist VTY (bzw. LTY) keine Kommazahl (!= 1),
; wird der Nachkommateil mit 0 aufgefuellt (Ganzzahl -> Festkomma). Veraendert A, X.
ld_a:   ldx #$03
        lda VTY
        cmp #$01
        bne la0
la1:    lda VFR,x                   ; Kommazahl: Nachkommateil nach fxa[0..3]
        sta fxa,x
        dex
        bpl la1
        bmi la2
la0:    lda #$00                    ; Ganzzahl: Nachkommateil = 0
la3:    sta fxa,x
        dex
        bpl la3
la2:    ldx #$03                    ; Ganzzahlteil nach fxa[4..7]
la4:    lda VAL,x
        sta fxa + 4,x
        dex
        bpl la4
        rts

ld_b:   ldx #$03
        lda LTY
        cmp #$01
        bne lb0
lb1:    lda LFR,x
        sta fxb,x
        dex
        bpl lb1
        bmi lb2
lb0:    lda #$00
lb3:    sta fxb,x
        dex
        bpl lb3
lb2:    ldx #$03
lb4:    lda LHS,x
        sta fxb + 4,x
        dex
        bpl lb4
        rts

; st_a: fxa -> VAL/VFR, VTY = 1 (Ergebnis ist immer Kommazahl; coerce_int macht daraus bei Bedarf eine Ganzzahl). Veraendert A, X.
st_a:   ldx #$03
sa1:    lda fxa,x
        sta VFR,x
        lda fxa + 4,x
        sta VAL,x
        dex
        bpl sa1
        lda #$01
        sta VTY
        rts

; neg_a / neg_b: 64-Bit-Zweierkomplementnegation von fxa bzw. fxb (0 - Wert, Carry als Borgen). Veraendert A, X, Y.
neg_a:  sec
        ldx #$00
        ldy #$08
x_na1:    lda #$00
        sbc fxa,x
        sta fxa,x
        inx
        dey
        bne x_na1
        rts

neg_b:  sec
        ldx #$00
        ldy #$08
nb1:    lda #$00
        sbc fxb,x
        sta fxb,x
        inx
        dey
        bne nb1
        rts

; fx_add: fxa = fxb + fxa (64 Bit, Ueberlauf ohne Meldung). Veraendert A, X, Y.
fx_add: clc
        ldx #$00
        ldy #$08
fa1:    lda fxb,x
        adc fxa,x
        sta fxa,x
        inx
        dey
        bne fa1
        rts

; fx_sub: fxa = fxb - fxa. Veraendert A, X, Y.
fx_sub: sec
        ldx #$00
        ldy #$08
x_fs1:    lda fxb,x
        sbc fxa,x
        sta fxa,x
        inx
        dey
        bne x_fs1
        rts

; fx_cmp: fxb gegen fxa: CLT = 1 wenn fxb < fxa (vorzeichenbehaftet), CEQ = 1 wenn gleich. fxa/fxb bleiben unveraendert, die
; Differenz liegt in fxt. Vorzeichenvergleich wie cmp32 (expr.asm): fxb < fxa <=> N xor V = 1 nach fxb - fxa.
fx_cmp: sec
        ldx #$00
        ldy #$08
fc1:    lda fxb,x
        sbc fxa,x
        sta fxt,x
        inx
        dey
        bne fc1
        lda fxt + 7                 ; Vorzeichenbyte der Differenz
        bvc fc2                     ; V (vom letzten sbc) gesetzt: Vorzeichen ist verkehrt
        eor #$80
fc2:    and #$80
        beq fc3
        lda #$01
fc3:    sta CLT
        lda fxt
        ora fxt + 1
        ora fxt + 2
        ora fxt + 3
        ora fxt + 4
        ora fxt + 5
        ora fxt + 6
        ora fxt + 7
        beq fc4
        lda #$01
fc4:    eor #$01                    ; A = 0 (Differenz 0) -> 1; A = 1 -> 0
        sta CEQ
        rts

; fx_signs: Vorzeichen des Ergebnisses von Mal/Geteilt nach fsg (Bit 7; Vorzeichen von fxa xor fxb), beide Werte werden zu
; Betraegen (fxa und fxb sind danach ueberschrieben). Veraendert A, X, Y.
fx_signs:
        lda fxa + 7
        eor fxb + 7
        and #$80
        sta fsg
        lda fxa + 7
        bpl fg1
        jsr neg_a
fg1:    lda fxb + 7
        bpl fg2
        jsr neg_b
fg2:    rts

; umul: mpr (16 Byte) = fxa * fxb, beide als vorzeichenlose 64-Bit-Zahlen (fxa wird zerstoert). Shift-and-Add in 64 Durchlaeufen:
; fxa wird nach rechts geschoben (niedrigstes Bit ins Carry); ist es 1, wird das nach links wandernde 128-Bit-Register mcd
; (Startwert fxb) zum Produkt mpr addiert. Langsam (ca. 64 x 16 Byte-Additionen), aber ohne Hardware-Multiplikation einfach und
; exakt. Veraendert A, X, Y, CNT, mpr, mcd.
umul:   ldx #$0f
        lda #$00
um0:    sta mpr,x
        sta mcd,x
        dex
        bpl um0
        ldx #$07
um1:    lda fxb,x
        sta mcd,x
        dex
        bpl um1
        lda #64
        sta CNT
um2:    lsr fxa + 7                 ; Multiplikator um 1 nach rechts, Carry = abgeschobenes Bit
        ror fxa + 6
        ror fxa + 5
        ror fxa + 4
        ror fxa + 3
        ror fxa + 2
        ror fxa + 1
        ror fxa
        bcc um4
        clc
        ldx #$00
        ldy #$10
um3:    lda mpr,x
        adc mcd,x
        sta mpr,x
        inx
        dey
        bne um3
um4:    asl mcd                     ; Multiplikand um 1 nach links (128 Bit)
        ldx #$01
        ldy #$0f
um5:    rol mcd,x
        inx
        dey
        bne um5
        dec CNT
        bne um2
        rts

; fx_mul: fxa = fxb * fxa (Festkomma: Produkt / 2^32). Das 128-Bit-Produkt (64.64) wird durch Bytes 4..11 von mpr auf 32.32
; reduziert; Bytes 0..3 (Stellen unter 2^-32) werden abgeschnitten, Bytes 12..15 (Ueberlauf) verworfen. Betragsrechnung
; ueber fx_signs, am Ende wird das Vorzeichen wieder angebracht. Veraendert A, X, Y und fxb.
fx_mul: jsr fx_signs
        jsr umul
        ldx #$07
fm1:    lda mpr + 4,x               ; Bytes 4..11 des Produkts = Produkt / 2^32
        sta fxa,x
        dex
        bpl fm1
        lda fsg
        bpl fm2
        jmp neg_a
fm2:    rts

; fx_div: fxa = fxb / fxa (Festkomma: fxb * 2^32 / fxa); fxa darf nicht 0 sein (sonst Unsinn; der Aufrufer prueft).
; Verfahren: Dividend = fxb * 2^32 als 96-Bit-Zahl (dvd, 12 Byte: unten 4 Byte Nullen), Divisor fxa, Rest rem (72 Bit, 9 Byte,
; damit die Verschiebung nicht ueberlaeuft). 96 Durchlaeufe schriftliche Division: Dividend nach links, oberstes Bit in
; den Rest,
; Divisor abziehen wenn moeglich und Quotientenbit unten in dvd einschieben (das frei gewordene Bit 0 wird mit `inc dvd`
; gesetzt). Nach 96 Schiebungen steht in dvd das 96-Bit-Quotient; die unteren 64 Bit sind das Ergebnis. Abschneiden
; (kein Runden). Betragsrechnung ueber fx_signs. Veraendert A, X, Y, CNT, dvd, rem, rtmp und fxb.
fx_div: jsr fx_signs
        ldx #$0b                    ; Dividend = fxb * 2^32 (12 Byte) in dvd (untere 4 Byte = 0)
        lda #$00
fd0:    sta dvd,x
        dex
        bpl fd0
        ldx #$07
fd1:    lda fxb,x
        sta dvd + 4,x
        dex
        bpl fd1
        ldx #$08
        lda #$00
fd2:    sta rem,x
        dex
        bpl fd2
        lda #96
        sta CNT
fd3:    asl dvd                     ; Dividend nach links, hoechstes Bit in den Rest (ueber alle 12 Bytes)
        ldx #$01
        ldy #$0b
fd4:    rol dvd,x
        inx
        dey
        bne fd4
        rol rem
        ldx #$01
        ldy #$08
fd5:    rol rem,x
        inx
        dey
        bne fd5
        sec                         ; Rest - Divisor (9 Byte, Divisor mit 0 erweitert)
        ldx #$00
        ldy #$08
fd6:    lda rem,x
        sbc fxa,x
        sta rtmp,x
        inx
        dey
        bne fd6
        lda rem + 8
        sbc #$00
        bcc fd8                     ; Rest < Divisor: nichts abziehen, Quotientenbit bleibt 0
        sta rem + 8
        ldx #$07
fd7:    lda rtmp,x
        sta rem,x
        dex
        bpl fd7
        inc dvd                     ; Quotientenbit 1 (Bit 0 von dvd ist nach dem Schieben frei)
fd8:    dec CNT
        bne fd3
        ldx #$07
fd9:    lda dvd,x
        sta fxa,x
        dex
        bpl fd9
        lda fsg
        bpl fda
        jmp neg_a
fda:    rts

; ---- Anbindung an den Ausdrucksrechner
; coerce_int: Ergebnis eines Ausdrucks fuer Stellen, die eine Ganzzahl brauchen: Kommazahl wird zur Null hin gekuerzt,
; eine Liste ist ein Fehler (E202). Eingabe VAL/VFR/VTY; Ausgabe VAL (Ganzzahl), VTY = 0. Veraendert A.
; Da VAL der Boden (floor) ist, braucht eine NEGATIVE Kommazahl mit Nachkommateil +1, um zur Null hin zu kuerzen (-1,5: VAL = -2,
; VFR = 0,5 -> -1). Rundungsfehler der Funktionen (math.asm) werden vorher abgefangen: liegt der Wert um weniger als 2^-20
; neben einer ganzen Zahl, gilt er als diese ganze Zahl (z. B. 2,9999999 -> 3; -3,0000001 -> -3).
coerce_int:
        lda VTY
        beq ci_ok
        cmp #$01
        beq ci_fx
        jmp ci_list
ci_fx:  lda ciq                     ; int(): ausdrueckliches Abschneiden, keine Warnung
        bne cw_no
        lda VFR + 3                 ; Nachkommateil abzuschneiden: W202 (nicht bei Rundungsrauschen knapp neben einer ganzen Zahl)
        ora VFR + 2
        beq cw_no
        lda VFR + 3
        and VFR + 2
        cmp #$ff
        bne cw_warn
        lda VFR + 1
        cmp #$f0
        bcs cw_no
cw_warn: lda #WARN_W202
        jsr warn_add
cw_no:  lda VAL + 3                 ; Vorzeichen des Ganzzahlteils
        bmi ci_neg
        lda VFR + 3                 ; knapp unter der naechsten ganzen Zahl (Rundungsfehler bis 2^-20): aufrunden
        and VFR + 2
        cmp #$ff
        bne ci_z
        lda VFR + 1
        cmp #$f0
        bcc ci_z
        inc VAL
        bne ci_z
        inc VAL + 1
        bne ci_z
        inc VAL + 2
        bne ci_z
        inc VAL + 3
        jmp ci_z
ci_neg: lda VFR + 3                 ; knapp ueber einer ganzen Zahl (Nachkommateil < 2^-20): Nachkommateil weglassen
        ora VFR + 2
        bne ci_n1
        lda VFR + 1
        cmp #$10
        bcs ci_n1
        lda #$00
        sta VFR + 1
        sta VFR
ci_n1:  lda VFR                     ; negativ mit Nachkommateil: Ganzzahlteil + 1 (Kuerzen zur Null)
        ora VFR + 1
        ora VFR + 2
        ora VFR + 3
        beq ci_z
        inc VAL
        bne ci_z
        inc VAL + 1
        bne ci_z
        inc VAL + 2
        bne ci_z
        inc VAL + 3
ci_z:   lda #$00
        sta VTY
ci_ok:  rts
ciq:    .byte 0                     ; 1 = coerce_int ohne W202 (int())
ci_list:
        lda #ERR_E202
        jmp ex_error

; ex_apply_x: LHS (LTY, LFR) OPID VAL (VTY, VFR) -> VAL. Eintritt aus ex_expr (expr.asm) nach jedem zweistelligen Operator.
; Ablauf: beide Ganzzahlen -> ex_apply; Liste beteiligt -> list_apply; sonst Kommazahlrechnung nach Kennungsbereich:
; 1..8 (|| && == != < <= > >=) Vergleiche/Logik, 9..13 (| ^ & << >>) und 18 (%) nur Ganzzahl (E202), 14..17 (+ - * /) Festkomma.
; Ergebnis der Arithmetik ist VTY = 1; Vergleiche/Logik liefern eine Ganzzahl 0/1. Division durch 0: weicher Fehler, Ergebnis 0.
ex_apply_x:
        lda LTY
        ora VTY
        bne x_ax1
        jsr ex_apply                ; beide Ganzzahlen: alter Weg
        lda #$00
        sta VTY
        rts
x_ax1:    lda LTY                   ; mindestens ein Operand ist Kommazahl oder Liste
        cmp #$02
        beq ax_list
        lda VTY
        cmp #$02
        beq ax_list
        lda OPID                    ; Kommazahl beteiligt
        cmp #$09
        bcc ax_cmp                  ; 1..8: ||, &&, ==, !=, <, <=, >, >=
        cmp #$0e
        bcc ax_err                  ; | ^ & << >> nur mit Ganzzahlen
        cmp #$12
        beq ax_err                  ; % ebenso
        jsr ld_a                    ; rechten Operanden nach fxa, linken nach fxb
        jsr ld_b
        lda OPID
        cmp #$0e
        beq ax_add
        cmp #$0f
        beq ax_sub
        cmp #$10
        beq ax_mul
        jsr fx_isz_a                ; Division (Kennung $11)
        bne ax_dv
        lda #$00                    ; Division durch 0: weicher Fehler, Ergebnis 0
        sta VTY
        sta VAL
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        jmp div_zero
ax_dv:  jsr fx_div
        jmp st_a
ax_add: jsr fx_add
        jmp st_a
ax_sub: jsr fx_sub
        jmp st_a
ax_mul: jsr fx_mul
        jmp st_a
ax_err: lda #ERR_E202
        jmp ex_error
ax_cmp: lda OPID                    ; || (1) und && (2) vergleichen nicht, sondern verknuepfen die Wahrheitswerte
        cmp #$02
        bcc ax_or
        beq ax_and
        jsr ld_a
        jsr ld_b
        jsr fx_cmp
        lda OPID
        cmp #$03
        beq ax_eq
        cmp #$04
        beq ax_ne
        cmp #$05
        beq ax_lt
        cmp #$06
        beq ax_le
        cmp #$07
        beq ax_gt
        lda CLT                     ; >=
        eor #$01
        jmp ax_b
ax_eq:  lda CEQ
        jmp ax_b
ax_ne:  lda CEQ
        eor #$01
        jmp ax_b
ax_lt:  lda CLT
        jmp ax_b
ax_le:  lda CLT
        ora CEQ
        jmp ax_b
ax_gt:  lda CLT
        ora CEQ
        eor #$01
ax_b:   jsr set_bool                ; A = 0/1 -> VAL, Ganzzahl
        lda #$00
        sta VTY
        rts
ax_or:  jsr lhs_isnz
        sta TMP
        jsr val_isnz
        ora TMP
        jmp ax_b
ax_and: jsr lhs_isnz
        sta TMP
        jsr val_isnz
        and TMP
        jmp ax_b
ax_list:                            ; Liste beteiligt: list.asm uebernimmt (Verkettung, Vervielfachung, ...)
        jmp list_apply              ; Listen: siehe list.asm

; fx_isz_a: A = 0 genau dann, wenn fxa = 0 (Z-Flag gemaess A; bei 0 gesetzt!). Veraendert A.
fx_isz_a:                           ; A = 0 wenn fxa = 0
        lda fxa
        ora fxa + 1
        ora fxa + 2
        ora fxa + 3
        ora fxa + 4
        ora fxa + 5
        ora fxa + 6
        ora fxa + 7
        rts

; ex_neg_x: Vorzeichenwechsel (VTY = 1: 64-Bit ueber fxa, VTY = 0: 32-Bit ueber negate; Liste: E202). Aufruf aus un_neg.
ex_neg_x:
        lda VTY
        cmp #$01
        beq nx1
        cmp #$02
        beq nx_l
        ldx #VAL
        jmp negate
nx1:    jsr ld_a
        jsr neg_a
        jmp st_a
nx_l:   lda #ERR_E202
        jmp ex_error

; dec_float_tail: hinter einer Dezimalzahl (VAL) folgt `.ziffern` und/oder `e[+-]ziffern`? Dann wird daraus eine Kommazahl.
; Eingang: VAL = bereits gelesener Ganzzahlteil, SRC dahinter. Ausgang: unveraendert (keine Kommazahl) oder VAL/VFR/VTY = 1 mit
; dem Wert, SRC hinter der Zahl. Erst vorausschauen (dft_*), damit `1.foo` oder `2e` als Ganzzahl plus Rest stehen bleiben
; (z. B. `5.` ohne Ziffer oder Marken wie `1e` sind keine Kommazahl). Nachkommastellen: hoechstens 9 zaehlen; Exponent 0..99,
; ab 48 begrenzt. Dezimalbruch -> Binaerbruch durch Division fdig / 10^n in Festkomma (fx_div): fdig = Ziffernfolge als
; Ganzzahl, fden = 10^n. Dadurch ist z. B. 0,1 nicht exakt (Abschneiden bei 2^-32), spaetere Rundung faengt coerce_int ab.
dec_float_tail:
        jsr src_peek
        cmp #$2e
        bne dft_e
        jsr src_peek1
        cmp #$30
        bcc dft_e
        cmp #$3a
        bcs dft_e
        jmp dft_go
dft_e:  jsr src_peek                ; Exponent `e` oder `E`?
        ora #$20
        cmp #$65
        bne dft_no
        jsr src_peek1
        cmp #$2b
        beq dft_e2
        cmp #$2d
        beq dft_e2
        cmp #$30
        bcc dft_no
        cmp #$3a
        bcs dft_no
        jmp dft_go
dft_e2: ldz #$02                    ; Vorzeichen e+/e-: dritte Stelle muss eine Ziffer sein (32-Bit-Zeiger [SRC],z)
        lda [SRC],z
        cmp #$30
        bcc dft_no
        cmp #$3a
        bcc dft_go
dft_no: rts
dft_go: ldx #$03                    ; Ganzzahlteil sichern (fint); fxa/fxb loeschen
dg0:    lda VAL,x
        sta fint,x
        dex
        bpl dg0
        ldx #$07
        lda #$00
dg1:    sta fxa,x                   ; (fxa/fxb auf 0; spaeter fxa = Nenner, fxb = Zaehler)
        sta fxb,x
        dex
        bpl dg1
        jsr src_peek
        cmp #$2e
        bne dg_exp
        jsr src_adv                 ; `.` verbrauchen
        lda #$00                    ; Zaehler (64 Bit, ganzzahlig in fdig) und Nenner (fden = 10^n)
        ldx #$07
dg2:    sta fdig,x
        sta fden,x
        dex
        bpl dg2
        lda #$01
        sta fden
        lda #$00
        sta fnd
dg3:    jsr src_peek
        cmp #$30
        bcc dg4
        cmp #$3a
        bcs dg4
        ldx fnd
        cpx #$09                    ; mehr als 9 Nachkommastellen zaehlen nicht mehr (10^9 < 2^32 passt in fden/fdig)
        bcs dg5
        pha                         ; Ziffernzeichen retten (fdig_x10 zerstoert A)
        jsr fdig_x10
        pla
        sec
        sbc #$30                    ; ASCII -> Wert 0..9
        clc
        adc fdig
        sta fdig
        bcc dg6
        inc fdig + 1
        bne dg6
        inc fdig + 2
dg6:    jsr fden_x10                ; Nenner * 10 (je Ziffer)
        inc fnd
dg5:    jsr src_adv
        jmp dg3
dg4:    ldx #$03                    ; Bruch = fdig / fden als Festkomma: (fdig << 32) / fden: fxa = fden (ganz), fxb = fdig (ganz)
        lda #$00
dg7:    sta fxa,x
        sta fxb,x
        dex
        bpl dg7
        ldx #$03
dg8:    lda fden,x
        sta fxa + 4,x
        lda fdig,x
        sta fxb + 4,x
        dex
        bpl dg8
        jsr fx_div
        ldx #$03                    ; Nachkommateil merken (fxa bytes 0..3)
dg9:    lda fxa,x
        sta ffrac,x
        dex
        bpl dg9
        jmp dg_ex2
dg_exp: ldx #$03
        lda #$00
dga:    sta ffrac,x
        dex
        bpl dga
dg_ex2: ldx #$03                    ; Wert = fint + ffrac (Ganzzahlteil nach VAL, Nachkommateil nach VFR)
dgb:    lda fint,x
        sta VAL,x
        lda ffrac,x
        sta VFR,x
        dex
        bpl dgb
        lda #$01
        sta VTY
        jsr src_peek                ; Exponent? (nach der Mantisse, auch bei reiner Ganzzahl wie 1e3)
        ora #$20
        cmp #$65
        beq dgx
        rts
dgx:    jsr src_adv                 ; `e` verbrauchen; fesg = 1 bei negativem Exponent
        lda #$00
        sta fesg
        jsr src_peek
        cmp #$2b
        beq dgx1
        cmp #$2d
        bne dgx2
        lda #$01
        sta fesg
dgx1:   jsr src_adv
dgx2:   lda #$00                    ; Exponentenziffern lesen (hoechstens zweistellig sinnvoll)
        sta fexp
dgx3:   jsr src_peek
        cmp #$30
        bcc dgx4
        cmp #$3a
        bcs dgx4
        sec
        sbc #$30
        pha
        lda fexp                    ; fexp = fexp * 10 + Ziffer (hoechstens 99)
        asl
        sta fnd
        asl
        asl
        clc
        adc fnd
        sta fexp
        pla
        clc
        adc fexp
        sta fexp
        jsr src_adv
        jmp dgx3
dgx4:   lda fexp
        beq dgx_d
        cmp #$30
        bcc dgx5
        lda #$30                    ; mehr als 10^48 ist ohnehin ausser Bereich
        sta fexp
dgx5:   jsr ld_a                    ; fxa = Wert (Mantisse); nun fexp-mal mit 10 malnehmen bzw. durch 10 teilen
        ldx #$07                    ; fxb = 10 (Festkomma)
        lda #$00
dgx6:   sta fxb,x
        dex
        bpl dgx6
        lda #$0a
        sta fxb + 4
        ldx #$07                    ; Wert nach fxt1 sichern
dgx7:   lda fxa,x                    ; Wert in fval sichern (fx_mul/fx_div zerstoeren fxb)
        sta fval,x
        dex
        bpl dgx7
dgx8:   ldx #$07                    ; Schleife je Zehnerpotenz: fxa = fval, fxb = 10
dgx9:   lda fval,x
        sta fxa,x
        dex
        bpl dgx9
        ldx #$07                    ; fxb = 10
        lda #$00
dgxa:   sta fxb,x
        dex
        bpl dgxa
        lda #$0a
        sta fxb + 4
        lda fesg
        bne dgxd                    ; negativer Exponent: dividieren
        jsr fx_mul                  ; Wert * 10
        jmp dgxe
dgxd:   ldx #$07                    ; Wert / 10: fxb = Wert, fxa = 10
        lda #$00
dgxf:   sta fxa,x
        dex
        bpl dgxf
        lda #$0a
        sta fxa + 4
        ldx #$07
dgxg:   lda fval,x
        sta fxb,x
        dex
        bpl dgxg
        jsr fx_div
dgxe:   ldx #$07                    ; Ergebnis nach fval zurueck
dgxh:   lda fxa,x
        sta fval,x
        dex
        bpl dgxh
        dec fexp                    ; naechste Zehnerpotenz
        bne dgx8
        ldx #$07
dgxi:   lda fval,x
        sta fxa,x
        dex
        bpl dgxi
        jsr st_a                    ; fxa -> VAL/VFR, VTY = 1
dgx_d:  rts

; fdig_x10: fdig = fdig * 10 (64 Bit): x*10 = ((x*2)*2 + x)*2; ftmp8 haelt das Original. Veraendert A, X, Y, ftmp8.
fdig_x10:                           ; fdig = fdig * 10 (64 Bit)
        ldx #$07
fx0:    lda fdig,x
        sta ftmp8,x
        dex
        bpl fx0
        asl fdig                    ; * 2
        ldx #$01
        ldy #$07
fx1:    rol fdig,x
        inx
        dey
        bne fx1
        asl fdig                    ; * 4
        ldx #$01
        ldy #$07
fx2:    rol fdig,x
        inx
        dey
        bne fx2
        clc                         ; * 5
        ldx #$00
        ldy #$08
fx3:    lda fdig,x
        adc ftmp8,x
        sta fdig,x
        inx
        dey
        bne fx3
        asl fdig                    ; * 10
        ldx #$01
        ldy #$07
fx4:    rol fdig,x
        inx
        dey
        bne fx4
        rts

; fden_x10: wie fdig_x10, fuer den Nenner fden (10^n).
fden_x10:
        ldx #$07
fy0:    lda fden,x
        sta ftmp8,x
        dex
        bpl fy0
        asl fden
        ldx #$01
        ldy #$07
fy1:    rol fden,x
        inx
        dey
        bne fy1
        asl fden
        ldx #$01
        ldy #$07
fy2:    rol fden,x
        inx
        dey
        bne fy2
        clc
        ldx #$00
        ldy #$08
fy3:    lda fden,x
        adc ftmp8,x
        sta fden,x
        inx
        dey
        bne fy3
        asl fden
        ldx #$01
        ldy #$07
fy4:    rol fden,x
        inx
        dey
        bne fy4
        rts

; ---- Daten (Programmspeicher, kein Zeropage)
; VTY/LTY: Wertart rechts/links (0 Ganzzahl, 1 Kommazahl, 2 Liste); VFR/LFR: Nachkommateile (4 Byte, tief zuerst);
; fxa/fxb: Festkommapuffer (8 Byte); fxt: Differenz bei fx_cmp; fsg: Vorzeichenmerker; mpr/mcd: Produkt/Multiplikand (128 Bit);
; dvd/rem/rtmp: Dividend (96 Bit), Rest (72 Bit), Hilfsrest; fint/ffrac: Teile der gelesenen Zahl; fdig/fden: Ziffernfolge
; und Nenner 10^n; ftmp8: Hilfswert; fval: Zwischenwert der Exponentenschleife; fnd = Zahl der Nachkommastellen;
; fexp/fesg: Exponent und dessen Vorzeichen.
VTY:    .byte 0
LTY:    .byte 0
VFR:    .fill 4, 0
LFR:    .fill 4, 0
fxa:    .fill 8, 0
fxb:    .fill 8, 0
fxt:    .fill 8, 0
fsg:    .byte 0
mpr:    .fill 16, 0
mcd:    .fill 16, 0
dvd:    .fill 12, 0
rem:    .fill 9, 0
rtmp:   .fill 8, 0
fint:   .fill 4, 0
ffrac:  .fill 4, 0
fdig:   .fill 8, 0
fden:   .fill 8, 0
ftmp8:  .fill 8, 0
fval:   .fill 8, 0
fnd:    .byte 0
fexp:   .byte 0
fesg:   .byte 0
