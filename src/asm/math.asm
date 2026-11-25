; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; math.asm - Winkel-, Wurzel-, Exponential- und Logarithmusfunktionen in Festkomma 32.32 (CORDIC, Newton, Taylorreihe,
; Bit-fuer-Bit-Logarithmus). Eingabe in VAL/VFR/VTY, Ergebnis ebenso (Kommazahl). Ergebnisse, die bis auf Rundungsfehler
; (etwa 2^-22) ganzzahlig sind, werden auf die ganze Zahl gesetzt (sin(pi/2) = 1, log10(1000) = 3).
; Register: fr[0..8] zu je 8 Byte; ga/gb laden fxa/fxb aus Register X, pa/pb schreiben sie zurueck.
;
; Rolle im Assembler: func.asm (ex_call) bildet die Funktionsnamen (sin, cos, tan, asin, acos, atan, atan2, sqrt, exp, ln, log,
; log2, log10, pow ...) auf die Einsprungpunkte m_* hier ab. Die Rechenwerke (fx_add/fx_sub/fx_mul/fx_div/fx_cmp, neg_a,
; ld_a/st_a) und der Puffer fxa/fxb stammen aus numx.asm; die Konstanten (pi, ln 2, atan-Tabelle, CORDIC-Faktor) aus
; mathtab.asm (erzeugt von tools/gen_mathtab.py).
;
; Zahlenformat: 32.32 (64-Bit-Zweierkomplement, Byte 0 niedrigstes; Byte 4..7 = Ganzzahlteil); siehe numx.asm.
; Aufrufkonvention der m_*-Routinen: Eingabe fxa (m_atan2: Register R_Y = y, R_X = x), Ausgabe als Kommazahl in VAL/VFR
; (VTY = 1) ueber m_out/st_a. Ungueltige Argumente (sqrt/log von <= 0, tan bei cos = 0) -> ERR_E202, exp-Ueberlauf -> ERR_E203,
; jeweils ueber ex_error (kehrt direkt zum Aufrufer von ex_eval zurueck).
;
; Genauigkeit: 32 Bruchbits, aber Mehrfachrechnungen (CORDIC, Reihen) sammeln Fehler von einigen 2^-32; die Ergebnisse sind
; daher auf ca. 2^-22 genau. snap_a rundet Werte, die so nah an einer ganzen Zahl liegen, auf diese (damit sin(pi/2) = 1,
; log10(1000) = 3 exakt erscheinen und `int(...)` nicht um 1 danebenliegt).
;
; Register fr ($1600-$1647): 9 Zwischenspeicher R_X..R_D zu je 8 Byte (Festkomma). Sie sind NICHT schachtelbar: ein Aufruf
; der m_*-Routinen zerstoert alle Register; Argumente muessen vorher in Variablen oder auf den Stapel gerettet werden
; (func.asm macht das beim Auswerten der Argumente). Zeropage: MP ($fc/$fd) = Zeiger auf eine 8-Byte-Konstante,
; CLT/CEQ aus fx_cmp.
; Rollen in den Algorithmen: R_X/R_Y/R_Z = CORDIC-Koordinaten und Winkel, R_T1/R_T2 = Zwischenwerte (y>>i, x>>i),
; R_A..R_D = freie Hilfsregister (siehe jeweilige Routine).
; =====================================================================================================================
R_X = 0
R_Y = 1
R_Z = 2
R_T1 = 3
R_T2 = 4
R_A = 5
R_B = 6
R_C = 7
R_D = 8

; ga/gb: Register X (0..8) -> fxa bzw. fxb (8 Byte kopieren). Index = X*8 in Y. Veraendert A, X, Y.
ga:     txa
        asl
        asl
        asl
        tay
        ldx #$00
ga1:    lda fr,y
        sta fxa,x
        iny
        inx
        cpx #$08
        bne ga1
        rts

gb:     txa
        asl
        asl
        asl
        tay
        ldx #$00
gb1:    lda fr,y
        sta fxb,x
        iny
        inx
        cpx #$08
        bne gb1
        rts

; pa/pb: fxa bzw. fxb -> Register X. Veraendert A, X, Y. 
pa:     txa
        asl
        asl
        asl
        tay
        ldx #$00
mm_pa1:    lda fxa,x
        sta fr,y
        iny
        inx
        cpx #$08
        bne mm_pa1
        rts

pb:     txa
        asl
        asl
        asl
        tay
        ldx #$00
mm_pb1:    lda fxb,x
        sta fr,y
        iny
        inx
        cpx #$08
        bne mm_pb1
        rts

; set_mp: MP = A (Low) / X (High) = Adresse einer 8-Byte-Konstante (z. B. lda #<c_pi, ldx #>c_pi). Veraendert nichts weiter.
set_mp: sta MP
        stx MP + 1
        rts

; mp_a / mp_b: 8 Byte ab (MP) nach fxa bzw. fxb (rueckwaerts, Y = 7..0, ueber den 16-Bit-Zeiger (MP),y). Veraendert A, Y.
mp_a:   ldy #$07
mm_ma1:    lda (MP),y
        sta fxa,y
        dey
        bpl mm_ma1
        rts

mp_b:   ldy #$07
mb1:    lda (MP),y
        sta fxb,y
        dey
        bpl mb1
        rts

; z_a: fxa = 0. Veraendert A, X.
z_a:    ldx #$07
        lda #$00
za1:    sta fxa,x
        dex
        bpl za1
        rts

; sar_a: fxa um A Bit arithmetisch nach rechts (Vorzeichenbit wird nachgeschoben); shl_a: nach links (Nullen von unten).
; A = Anzahl (0 = nichts tun; bis 63 sinnvoll). Veraendert A, X, Z-Flag. Je Bit ein Durchlauf ueber 8 Byte (langsam, aber kurz).
sar_a:  tax
        beq sr2
sr1:    lda fxa + 7                 ; CMP #$80 setzt C = Vorzeichenbit, damit ROR es oben wieder einschiebt
        cmp #$80
        ror fxa + 7
        ror fxa + 6
        ror fxa + 5
        ror fxa + 4
        ror fxa + 3
        ror fxa + 2
        ror fxa + 1
        ror fxa
        dex
        bne sr1
sr2:    rts

shl_a:  tax
        beq sl2
sl1:    asl fxa
        rol fxa + 1
        rol fxa + 2
        rol fxa + 3
        rol fxa + 4
        rol fxa + 5
        rol fxa + 6
        rol fxa + 7
        dex
        bne sl1
sl2:    rts

; snap_a: fxa auf die naechste ganze Zahl setzen, wenn der Abstand kleiner als etwa 2^-23 ist.
; Verfahren: fxt = fxa + 2^-23 (Byte 1 + 2 = $200 im Nachkommateil). Liegt fxa im Intervall [n - 2^-23, n + 2^-23), dann ist
; der Nachkommateil von fxt kleiner als 2^-22 ($400, Bytes 2/3 = 0 und Byte 1 < 4) und n = Ganzzahlteil von fxt;
; dann wird fxa = n.
; Gilt auch fuer negative Werte (Zweierkomplement, Ganzzahlteil = Boden). Byte 0 von fxt wird nicht benoetigt und nicht gesetzt.
; Veraendert A, X, fxt, ggf. fxa.
snap_a: clc
        lda fxa
        adc #$00                    ; (wirkungslos: Ergebnis wird verworfen; die Rundungshilfe 2^-23 = $200 steht in Byte 1)
        lda fxa + 1
        clc
        adc #$02
        sta fxt + 1
        lda fxa + 2
        adc #$00
        sta fxt + 2
        lda fxa + 3
        adc #$00
        sta fxt + 3
        lda fxa + 4
        adc #$00
        sta fxt + 4
        lda fxa + 5
        adc #$00
        sta fxt + 5
        lda fxa + 6
        adc #$00
        sta fxt + 6
        lda fxa + 7
        adc #$00
        sta fxt + 7
        lda fxt + 3                 ; liegt (fxa + 2^-23) im Bereich [n, n + 2^-22)? Dann Nachkommateil von fxt < 2^-22
        ora fxt + 2
        bne sn_no
        lda fxt + 1
        cmp #$04
        bcs sn_no
        ldx #$03
mm_sn1:    lda fxt + 4,x
        sta fxa + 4,x
        dex
        bpl mm_sn1
        lda #$00
        sta fxa
        sta fxa + 1
        sta fxa + 2
        sta fxa + 3
sn_no:  rts

; atan_mp: MP = Adresse des Tabelleneintrags arctan(2^-ci): atab + ci*8 (ci < 32, daher passt ci*8 in ein Byte). Veraendert A, MP.
atan_mp:
        lda ci
        asl
        asl
        asl
        clc
        adc #<atab
        sta MP
        lda #>atab
        adc #$00
        sta MP + 1
        rts

; ---- CORDIC, Drehmodus: R_Z = Winkel (-pi/2..pi/2) -> R_X = cos, R_Y = sin
; Idee: Start bei (x, y) = (1/K, 0). Der Vektor wird in 32 Schritten um +-arctan(2^-i) gedreht, bis der Restwinkel z = 0 ist.
; Eine Drehung um arctan(2^-i) ist x' = x - d*y*2^-i, y' = y + d*x*2^-i (nur Verschiebungen und Additionen, keine
; Multiplikation); d = +1 bei z >= 0, sonst -1; z' = z - d*arctan(2^-i). Jeder Schritt streckt den Vektor um sqrt(1 + 2^-2i); das
; Produkt aller 32 Faktoren ist K = 1,6468; deshalb startet x mit 1/K = c_k. Konvergenzbereich |z| < ca. 1,74 rad, daher die
; Reduktion auf +-pi/2 in m_reduce. Eingabe R_Z; Ausgabe R_X (cos), R_Y (sin); zerstoert R_T1, R_T2, ci, fxa, fxb, MP.
cordic_rot:
        lda #<c_k
        ldx #>c_k
        jsr set_mp
        jsr mp_a
        ldx #R_X
        jsr pa
        jsr z_a
        ldx #R_Y
        jsr pa
        lda #$00
        sta ci
cr_l:   ldx #R_Y                    ; T1 = y >> i, T2 = x >> i
        jsr ga
        lda ci
        jsr sar_a
        ldx #R_T1
        jsr pa
        ldx #R_X
        jsr ga
        lda ci
        jsr sar_a
        ldx #R_T2
        jsr pa
        jsr atan_mp
        lda fr + R_Z * 8 + 7        ; Vorzeichen von z entscheidet die Drehrichtung d
        bmi cr_neg
        ldx #R_X                    ; X = X - T1, Y = Y + T2, Z = Z - atan
        jsr gb
        ldx #R_T1
        jsr ga
        jsr fx_sub
        ldx #R_X
        jsr pa
        ldx #R_Y
        jsr gb
        ldx #R_T2
        jsr ga
        jsr fx_add
        ldx #R_Y
        jsr pa
        ldx #R_Z
        jsr gb
        jsr mp_a
        jsr fx_sub
        ldx #R_Z
        jsr pa
        jmp cr_n
cr_neg: ldx #R_X                    ; X = X + T1, Y = Y - T2, Z = Z + atan
        jsr gb
        ldx #R_T1
        jsr ga
        jsr fx_add
        ldx #R_X
        jsr pa
        ldx #R_Y
        jsr gb
        ldx #R_T2
        jsr ga
        jsr fx_sub
        ldx #R_Y
        jsr pa
        ldx #R_Z
        jsr gb
        jsr mp_a
        jsr fx_add
        ldx #R_Z
        jsr pa
cr_n:   inc ci
        lda ci
        cmp #CORDIC_N
        bne cr_l
        rts

; ---- CORDIC, Vektormodus: R_X > 0, R_Y >= 0 (schon normiert) -> R_Z = atan(Y / X)
; Idee: Den Vektor (x, y) so lange um +-arctan(2^-i) drehen, bis y = 0; die Summe der Drehwinkel ist atan(y/x).
; y >= 0: im Uhrzeigersinn drehen (x' = x + y*2^-i, y' = y - x*2^-i), z waechst um arctan(2^-i); y < 0: umgekehrt.
; Die Streckung um K beeinflusst z nicht, daher wird hier kein 1/K benoetigt. Funktioniert auch bei x = 0, y > 0
; (Ergebnis pi/2; Konvergenz bis ca. 99,7 Grad).
; Eingabe R_X, R_Y (so normiert, dass nichts ueberlaeuft, siehe m_atan2); Ausgabe R_Z. Zerstoert R_X, R_Y, R_T1, R_T2, ci.
cordic_vec:
        jsr z_a
        ldx #R_Z
        jsr pa
        lda #$00
        sta ci
cv_l:   ldx #R_Y                    ; T1 = y >> i, T2 = x >> i
        jsr ga
        lda ci
        jsr sar_a
        ldx #R_T1
        jsr pa
        ldx #R_X
        jsr ga
        lda ci
        jsr sar_a
        ldx #R_T2
        jsr pa
        jsr atan_mp
        lda fr + R_Y * 8 + 7        ; Vorzeichen von y
        bmi cv_neg
        ldx #R_X                    ; Y >= 0: X = X + T1, Y = Y - T2, Z = Z + atan
        jsr gb
        ldx #R_T1
        jsr ga
        jsr fx_add
        ldx #R_X
        jsr pa
        ldx #R_Y
        jsr gb
        ldx #R_T2
        jsr ga
        jsr fx_sub
        ldx #R_Y
        jsr pa
        ldx #R_Z
        jsr gb
        jsr mp_a
        jsr fx_add
        ldx #R_Z
        jsr pa
        jmp cv_n
cv_neg: ldx #R_X                    ; Y < 0: X = X - T1, Y = Y + T2, Z = Z - atan
        jsr gb
        ldx #R_T1
        jsr ga
        jsr fx_sub
        ldx #R_X
        jsr pa
        ldx #R_Y
        jsr gb
        ldx #R_T2
        jsr ga
        jsr fx_add
        ldx #R_Y
        jsr pa
        ldx #R_Z
        jsr gb
        jsr mp_a
        jsr fx_sub
        ldx #R_Z
        jsr pa
cv_n:   inc ci
        lda ci
        cmp #CORDIC_N
        bne cv_l
        rts

; m_out: fxa als Ergebnis (gerundet auf ganze Zahlen, wenn nahe dran, siehe snap_a) nach VAL/VFR; gemeinsamer Ausgang aller m_*.
m_out:  jsr snap_a
        jmp st_a

; ---- sin / cos / tan: Eingabe fxa (Bogenmass)
; m_reduce: fxa = x -> R_Z in [-pi/2, pi/2], mneg = 1 wenn cos das Vorzeichen wechselt. Zwei Schritte:
;  1. x auf [-pi, pi] bringen: z = x - n*2pi mit n = floor(x/2pi + 0,5) (floor = Nachkommateil loeschen, im
;     Zweierkomplement richtig).
;  2. nach [-pi/2, pi/2]: z > pi/2: z = pi - z (sin gleich, cos wechselt das Vorzeichen); z < -pi/2: z = -pi - z (ebenso).
; Fehler wachsen mit |x|: c_2pi ist nur auf 2^-32 genau, der Fehler wird mit n multipliziert (bei x ~ 1e6 etwa 1e-4).
; Zerstoert R_A, R_B, R_C, R_Z, fxa, fxb, mneg.
m_reduce:
        ldx #R_A
        jsr pa
        lda #<c_2pi                 ; n = floor(x / 2pi + 0.5)
        ldx #>c_2pi
        jsr set_mp
        jsr mp_a
        ldx #R_A
        jsr gb
        jsr fx_div                  ; fxa = x / 2pi
        lda #<c_half
        ldx #>c_half
        jsr set_mp
        jsr mp_b
        jsr fx_add
        lda #$00                    ; floor: Nachkommateil weg (n = floor(x/2pi + 0,5) = naechste ganze Zahl)
        sta fxa
        sta fxa + 1
        sta fxa + 2
        sta fxa + 3
        ldx #R_B
        jsr pa
        lda #<c_2pi                 ; x - n * 2pi
        ldx #>c_2pi
        jsr set_mp
        jsr mp_b
        ldx #R_B
        jsr ga
        jsr fx_mul
        ldx #R_C
        jsr pa
        ldx #R_A
        jsr gb
        ldx #R_C
        jsr ga
        jsr fx_sub
        ldx #R_Z
        jsr pa
        lda #$00
        sta mneg
        lda #<c_hpi                 ; Z > pi/2 ?
        ldx #>c_hpi
        jsr set_mp
        jsr mp_a
        ldx #R_Z
        jsr gb
        jsr fx_cmp                  ; fxb = Z gegen fxa = pi/2: CLT = Z < pi/2, CEQ = gleich
        lda CLT
        ora CEQ
        bne mr1                     ; Z <= pi/2: nichts zu spiegeln
        lda #<c_pi                  ; Z = pi - Z
        ldx #>c_pi
        jsr set_mp
        jsr mp_b
        ldx #R_Z
        jsr ga
        jsr fx_sub
        ldx #R_Z
        jsr pa
        lda #$01
        sta mneg
        rts
mr1:    lda #<c_hpi                 ; Z < -pi/2 ?  (-pi/2 = -(pi/2): Z + pi/2 < 0)
        ldx #>c_hpi
        jsr set_mp
        jsr mp_a
        ldx #R_Z
        jsr gb
        jsr fx_add
        lda fxa + 7
        bpl mr2
        lda #<c_pi                  ; Z = -pi - Z
        ldx #>c_pi
        jsr set_mp
        jsr mp_a
        jsr neg_a
        ldx #R_Z
        jsr gb
        jsr fx_sub                  ; fxa = fxb - fxa = Z - (-pi) = Z + pi
        jsr neg_a                   ; = -(Z + pi) = -pi - Z
        ldx #R_Z
        jsr pa
        lda #$01
        sta mneg
mr2:    rts

; m_sin / m_cos / m_tan: Eingabe fxa (Bogenmass). sin und cos kommen aus einer CORDIC-Drehung (R_Y bzw. R_X); cos wird bei
; mneg negiert. tan = sin / cos mit Fehler E202 bei cos = 0 (hartes Ende, kein weicher Fehler).
m_sin:  jsr m_reduce
        jsr cordic_rot
        ldx #R_Y
        jsr ga
        jmp m_out

m_cos:  jsr m_reduce
        jsr cordic_rot
        ldx #R_X
        jsr ga
        lda mneg
        beq mm_mc1
        jsr neg_a
mm_mc1:    jmp m_out

m_tan:  jsr m_reduce
        jsr cordic_rot
        ldx #R_Y                    ; sin / cos (das Vorzeichen von cos beachten)
        jsr gb
        ldx #R_X
        jsr ga
        lda mneg
        beq mt1
        jsr neg_a
mt1:    jsr fx_isz_a
        bne mt2
        lda #ERR_E202
        jmp ex_error
mt2:    jsr fx_div
        jmp m_out

; ---- atan2: R_Y = y, R_X = x -> fxa = Winkel (-pi..pi)
; Verfahren: Vorzeichen von x und y merken (xneg/yneg), beide zu Betraegen machen, Werte durch Verdoppeln/Halbieren so
; normieren, dass das groessere hoechste Byte in [$08, $20) liegt (Betrag ca. 2^27..2^29: hohe Genauigkeit, aber die
; CORDIC-Summen wachsen um K = 1,65 ohne die 2^31-Grenze zu erreichen), cordic_vec liefert atan(|y|/|x|) in [0, pi/2];
; dann x < 0: Winkel = pi - Winkel; y < 0: Winkel = -Winkel. Beide Null: Ergebnis 0 (kein Fehler).
; Die Normierung veraendert x und y gleichmaessig, das Verhaeltnis (und damit der Winkel) bleibt gleich.
m_atan2:
        lda #$00
        sta xneg
        sta yneg
        lda fr + R_X * 8 + 7
        bpl at1
        lda #$01
        sta xneg
        ldx #R_X
        jsr ga
        jsr neg_a
        ldx #R_X
        jsr pa
at1:    lda fr + R_Y * 8 + 7
        bpl at2
        lda #$01
        sta yneg
        ldx #R_Y
        jsr ga
        jsr neg_a
        ldx #R_Y
        jsr pa
at2:    ldx #$07                    ; beide null? (alle 16 Byte ODER-verknuepfen)
        lda #$00
at3:    ora fr + R_X * 8,x
        ora fr + R_Y * 8,x
        dex
        bpl at3
        cmp #$00
        bne at4
        jsr z_a
        rts
at4:    lda fr + R_X * 8 + 7        ; normieren: groesstes Byte oben in [$08, $20)
        cmp fr + R_Y * 8 + 7
        bcs at5
        lda fr + R_Y * 8 + 7
at5:    cmp #$20
        bcc at6
        ldx #R_X
        jsr ga
        lda #$01
        jsr sar_a
        ldx #R_X
        jsr pa
        ldx #R_Y
        jsr ga
        lda #$01
        jsr sar_a
        ldx #R_Y
        jsr pa
        jmp at4
at6:    cmp #$08                    ; zu klein: beide Werte verdoppeln
        bcs at7
        ldx #R_X
        jsr ga
        lda #$01
        jsr shl_a
        ldx #R_X
        jsr pa
        ldx #R_Y
        jsr ga
        lda #$01
        jsr shl_a
        ldx #R_Y
        jsr pa
        jmp at4
at7:    jsr cordic_vec              ; R_Z = atan(|y| / |x|)
        ldx #R_Z
        jsr ga
        lda xneg
        beq at8
        lda #<c_pi                  ; pi - Winkel
        ldx #>c_pi
        jsr set_mp
        jsr mp_b
        jsr fx_sub
at8:    lda yneg
        beq at9
        jsr neg_a
at9:    rts

; ---- Wurzel (Newton), Eingabe fxa >= 0
; Verfahren: r' = (x/r + r) / 2 (Heron/Newton). Startwert r = x bei x >= 1, sonst r = 1 (beides liegt ueber der Wurzel, dann
; konvergiert die Folge monoton von oben). Abbruch, wenn r' = r (Fixpunkt in 32.32) oder nach 80 ($50) Schritten, falls die Folge
; wegen Abschneidens zwischen zwei Nachbarwerten pendelt. Negativ -> E202; 0 -> 0. Zerstoert R_A (x), R_B (r), R_C (r').
m_sqrt: lda fxa + 7
        bpl sq0
        lda #ERR_E202
        jmp ex_error
sq0:    jsr fx_isz_a
        bne sq1
        jmp st_a                    ; 0
sq1:    ldx #R_A
        jsr pa                      ; x
        lda fxa + 4                 ; Startwert r = x (ab 1), sonst 1
        ora fxa + 5
        ora fxa + 6
        ora fxa + 7
        bne sq2
        lda #<c_one
        ldx #>c_one
        jsr set_mp
        jsr mp_a
sq2:    ldx #R_B
        jsr pa                      ; r
        lda #$00
        sta ci
sq3:    ldx #R_A                    ; fxa = x / r
        jsr gb
        ldx #R_B
        jsr ga
        jsr fx_div
        ldx #R_B                    ; + r
        jsr gb
        jsr fx_add
        lda #$01                    ; / 2
        jsr sar_a
        ldx #R_C
        jsr pa
        ldx #R_B                    ; gleich dem alten r? fertig
        jsr gb
        ldx #$07
sq4:    lda fxb,x
        cmp fr + R_C * 8,x
        bne sq5
        dex
        bpl sq4
        jmp sq6
sq5:    ldx #R_C
        jsr ga
        ldx #R_B
        jsr pa
        inc ci
        lda ci
        cmp #$50
        bne sq3
sq6:    ldx #R_B
        jsr ga
        jmp m_out

; ---- log2 (Eingabe fxa > 0)
; Verfahren (Bit-fuer-Bit-Logarithmus): x = m * 2^e mit m in [1, 2): e durch Verschieben von x (lg2/lg4 zaehlen die Schritte
; in `le`, vorzeichenbehaftet 8 Bit). Dann gewinnt man die Nachkommabits von log2(m): m wird quadriert (log2 verdoppelt sich);
; ist m^2 >= 2, so ist das naechste Bit 1 und m wird halbiert; sonst 0. 32 Bits -> lacc (32 Bit Nachkommateil). Ergebnis
; log2 x = e + lacc / 2^32; der Ganzzahlteil e wird vorzeichenerweitert, das ist im Zweierkomplement zugleich der korrekte
; Boden (z. B. x = 0,25: e = -2, lacc = 0). Fehler E202 bei x <= 0. Zerstoert R_A, ci, le, lacc, fxa, fxb.
m_log2: lda fxa + 7
        bmi lg_bad
        jsr fx_isz_a
        bne lg1
lg_bad: lda #ERR_E202
        jmp ex_error
lg1:    lda #$00
        sta le                      ; e (vorzeichenbehaftet, 8 Bit)
lg2:    lda fxa + 7                 ; >= 2 ? (Ganzzahlteil >= 2)
        ora fxa + 6
        ora fxa + 5
        bne lg3
        lda fxa + 4
        cmp #$02
        bcc lg4
lg3:    lda #$01
        jsr sar_a
        inc le
        jmp lg2
lg4:    lda fxa + 7                 ; < 1 ?
        ora fxa + 6
        ora fxa + 5
        ora fxa + 4
        bne lg5
        lda #$01
        jsr shl_a
        dec le
        jmp lg4
lg5:    ldx #R_A
        jsr pa                      ; m in [1, 2)
        lda #$00
        sta lacc
        sta lacc + 1
        sta lacc + 2
        sta lacc + 3
        lda #32
        sta ci
lg6:    ldx #R_A
        jsr ga
        ldx #R_A
        jsr gb
        jsr fx_mul                  ; m * m
        asl lacc                    ; naechstes Ergebnisbit von rechts einschieben (zunaechst 0)
        rol lacc + 1
        rol lacc + 2
        rol lacc + 3
        lda fxa + 4
        cmp #$02                    ; m^2 >= 2 ?
        bcc lg7
        lda #$01
        jsr sar_a                   ; ja: m halbieren ...
        lda lacc
        ora #$01                    ; ... und Bit = 1
        sta lacc
lg7:    ldx #R_A
        jsr pa
        dec ci
        bne lg6
        ldx #$03                    ; Ergebnis: Ganzzahlteil e (vorzeichenerweitert), Nachkommateil lacc
lg_cp:  lda lacc,x
        sta fxa,x
        dex
        bpl lg_cp
        lda le
        sta fxa + 4
        ldx #$00
        lda le
        bpl lg8
        ldx #$ff
lg8:    stx fxa + 5
        stx fxa + 6
        stx fxa + 7
        rts

; m_logk: Ergebnis von log2 mit Umrechnungsfaktor: ln2 oder log10(2); fxa = log2(x), MP zeigt auf die Konstante (c_ln2 bzw. c_lg2,
; vom Aufrufer mit set_mp gesetzt). ln x = log2 x * ln 2; log10 x = log2 x * log10 2.
m_logk: ldx #R_A                    ; MP zeigt auf die Konstante
        jsr pa
        jsr mp_b
        ldx #R_A
        jsr ga
        jsr fx_mul
        jmp m_out

; ---- exp: Eingabe fxa
; Verfahren: e^x = 2^k * e^r mit k = floor(x / ln 2) und r = x - k*ln 2 in [0, ln 2). e^r wird als Taylorreihe
; 1 + r + r^2/2! + ... bis zum Glied r^17/17! summiert (Glied = Glied * r / n, n = 1..17; Rest < 1e-15). Danach Multiplikation
; mit 2^k durch Schieben (k > 0: links, nur bis k = 30, sonst E203; k < 0: rechts, ab 63 Bit gilt der Wert als 0).
; Register: R_A = x, R_B = k (ganz), R_C = r, R_D = Summe, R_T1 = Glied; lk = k als Byte.
m_exp:  ldx #R_A
        jsr pa
        lda #<c_ln2                 ; k = floor(x / ln 2)
        ldx #>c_ln2
        jsr set_mp
        jsr mp_a
        ldx #R_A
        jsr gb
        jsr fx_div
        lda #$00
        sta fxa
        sta fxa + 1
        sta fxa + 2
        sta fxa + 3
        ldx #R_B                    ; k (ganze Zahl in fxa)
        jsr pa
        lda fxa + 4
        sta lk
        lda fxa + 7                 ; k = Byte 4..7 von fxa (vorzeichenbehaftet, 32 Bit); lk haelt nur Byte 4
        bmi ex_neg
        ora fxa + 5                 ; k >= 0: nur 0..30 sind darstellbar, sonst E203 (wie vcc)
        ora fxa + 6
        bne ex_big
        lda lk
        cmp #$1f
        bcs ex_big
        bcc ex1
ex_neg: lda fxa + 5                 ; k < 0: ab |k| > 63 ist das Ergebnis 0 (kein Fehler, wie vcc)
        and fxa + 6
        cmp #$ff
        bne ex_zero
        lda lk
        cmp #$c1
        bcs ex1
ex_zero: ldx #$07
        lda #$00
ex_z1:  sta fxa,x
        dex
        bpl ex_z1
        jmp m_out
ex1:    lda #<c_ln2                 ; r = x - k * ln 2
        ldx #>c_ln2
        jsr set_mp
        jsr mp_b
        ldx #R_B
        jsr ga
        jsr fx_mul
        ldx #R_C
        jsr pa
        ldx #R_A
        jsr gb
        ldx #R_C
        jsr ga
        jsr fx_sub
        ldx #R_C
        jsr pa                      ; r
        lda #<c_one                 ; Summe und Glied = 1
        ldx #>c_one
        jsr set_mp
        jsr mp_a
        ldx #R_D
        jsr pa                      ; Summe
        ldx #R_T1
        jsr pa                      ; Glied
        lda #$01                    ; n = 1
        sta ci
ex2:    ldx #R_T1                   ; Glied = Glied * r / n
        jsr ga
        ldx #R_C
        jsr gb
        jsr fx_mul
        ldx #R_T1
        jsr pa
        ldx #$07                    ; fxa = n (ganz)
        lda #$00
ex3:    sta fxa,x
        dex
        bpl ex3
        lda ci
        sta fxa + 4
        ldx #R_T1
        jsr gb
        jsr fx_div
        ldx #R_T1
        jsr pa
        ldx #R_D
        jsr gb
        jsr fx_add
        ldx #R_D
        jsr pa
        inc ci
        lda ci
        cmp #$12                    ; bis n = 17
        bne ex2
        ldx #R_D
        jsr ga
        lda lk                      ; * 2^k
        bmi ex4
        beq ex5
        cmp #$1f                    ; k >= 31: Ergebnis passt nicht mehr in 32 Bit Ganzzahlteil
        bcs ex_big
        jsr shl_a
        jmp ex5
ex4:    eor #$ff                    ; k < 0: Betrag bilden und rechts schieben (begrenzt auf 63)
        clc
        adc #$01
        cmp #$40
        bcc ex6
        lda #$3f
ex6:    jsr sar_a
ex5:    jmp m_out
ex_big: lda #ERR_E203
        jmp ex_error

; ---- Daten
; fr: Registerfeld R_X..R_D (9 x 8 Byte = 72 Byte) im freien Speicher $1200-$17FF (hier fest bei $1600; kein .fill!).
; ci: Schleifenzaehler (CORDIC-Schritt, Reihenglied, Newton-Zaehler); mneg: 1 = cos negiert; xneg/yneg: Vorzeichen bei atan2;
; le: Exponent e von log2; lk: Exponent k von exp; lacc: 32-Bit-Nachkommateil des log2.
fr = $1600                    ; 72 Byte im freien Bereich $1200-$17FF
ci:     .byte 0
mneg:   .byte 0
xneg:   .byte 0
yneg:   .byte 0
le:     .byte 0
lk:     .byte 0
lacc:   .fill 4, 0
