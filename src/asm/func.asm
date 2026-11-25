; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; func.asm - Funktionen im Ausdruck: eingebaute Ganzzahlfunktionen (abs, sign, min, max, int, floor, ceil, round, next,
; align, pow, sqrt, sin, cos, tan, asin, acos, atan, atan2, exp, log, log2, log10, len, range) und eigene Funktionen mit
; `.function name(a, b) = ausdruck`. Die Winkel-/Wurzel-/Exponential-/Logarithmusfunktionen rechnet math.asm (Festkomma
; 32.32, siehe numx.asm); len/range liegen in list.asm.
; Aufruf aus dem Ausdrucksrechner: Bezeichner gefolgt von '(' (NAMEBUF/NAMELEN, SRC auf der Klammer) -> ex_call (aus ex_prim0
; in expr.asm). Die Direktive .function steht in der Direktiventabelle von asm.asm (d_function).
; Bank 4 (S2BANK, 32-Bit-Zeiger P6/P7 aus stage2.asm, Zugriff `lda [P7],z`): Funktionstabelle $4800-$4BFF (Eintrag, fortlaufend:
; Gesamtgroesse (1), Namenlaenge (1), Name, Parameterzahl (1), je Parameter Laenge (1) + Name, Zeiger auf den Ausdruck im
; Quelltext (4 Byte SRC); Gesamtgroesse also hoechstens 255, der Z-Versatz bleibt 8 Bit), Argumentstapel $4C00-$5FFF
; (je Argument 9 Byte: VTY, VAL (4), VFR (4)).
;
; Ablauf eines Aufrufs: ex_call wertet die Argumente mit ex_expr aus und legt sie nacheinander auf den Argumentstapel (asp,
; wachsend). Eingebaute Funktionen lesen die Argumente mit arg_get (Nummer -> VTY/VAL/VFR) direkt dort. Eigene Funktionen
; binden die Argumente als Variablen (var_new aus stage2.asm) an die Parameternamen, werten den Ausdruck (der erst jetzt aus dem
; Quelltext gelesen wird: SRC wird kurz dorthin gesetzt) aus und geben die Variablen wieder frei (vare). Rekursion ist bis
; Tiefe 16 erlaubt (fdepth). Fehler ueber ex_error: Stapel wird ueber ESP abgebaut (siehe expr.asm).
; Eingebaute Funktionen sind unabhaengig von der Gross-/Kleinschreibung, eigene Funktionen dagegen nicht (fn_find vergleicht roh).
; =====================================================================================================================
FUNBASE = $4800
FUNEND  = $4c00
ARGBASE = $4c00
ARGEND  = $6000
.ifndef OA_BUILD
ERR_E204 = $04                      ; im Overlay A kommt der Wert aus den Namen des Hauptprogramms (funcres.asm)
.endif

; f_pass: Beginn eines Durchlaufs (von asm.asm): Funktionstabelle und Argumentstapel leeren, Rekursionstiefe 0.
; In jedem Durchlauf werden die .function-Zeilen neu eingelesen, daher geht nichts verloren. Veraendert A.
f_pass:                             ; Beginn eines Durchlaufs
        lda #<FUNBASE
        sta fune
        lda #>FUNBASE
        sta fune + 1
        lda #<ARGBASE
        sta asp
        lda #>ARGBASE
        sta asp + 1
        lda #$00
        sta fdepth
        sta ciq                     ; int()-Merker zuruecksetzen (nach einem Fehler in coerce_int)
        rts

; fn_find: NAMEBUF/NAMELEN in der Tabelle eigener Funktionen suchen; Carry geloescht = gefunden, fptr = Versatz des Eintrags
; in Bank 4; Carry gesetzt = nicht gefunden. Laeuft die Eintraege ueber das Groessenbyte ab, bis P7 = fune (Tabellenende).
; Veraendert A, X, Z, P7.
fn_find:
        lda #<FUNBASE
        ldx #>FUNBASE
        jsr p7_load
ff_l:   lda P7
        cmp fune
        bne ff_go
        lda P7 + 1
        cmp fune + 1
        bne ff_go
        sec
        rts
ff_go:  ldz #$01                    ; Z = 1: Namenlaenge des Eintrags (Byte 0 = Gesamtgroesse)
        lda [P7],z
        cmp NAMELEN
        bne ff_n
        inz
        ldx #$00
ff_c:   cpx NAMELEN
        beq ff_hit
        lda [P7],z
        cmp NAMEBUF,x
        bne ff_n
        inz
        inx
        bne ff_c
ff_hit: lda P7
        sta fptr
        lda P7 + 1
        sta fptr + 1
        clc
        rts
ff_n:   ldz #$00                    ; naechster Eintrag: P7 += Gesamtgroesse (Byte 0)
        lda [P7],z
        clc
        adc P7
        sta P7
        bcc ff_l
        inc P7 + 1
        jmp ff_l

; fn_resolve: fkind = 1 (eigene Funktion, fptr = Versatz) oder 0 (eingebaut, fptr = Kennung 1..25 aus bitab); Carry gesetzt =
; unbekannt. Eigene Funktionen haben Vorrang vor eingebauten (so lassen sich eingebaute nicht ersetzen, aber ueberdecken).
; Veraendert A, X, Y, Z, P7, MP, flow, fptr, fkind.
fn_resolve:
        jsr fn_find
        bcs fr_bi
        lda #$01
        sta fkind
        clc
        rts
fr_bi:  ldx #$00                    ; Name in Kleinbuchstaben nach flow kopieren (bitab ist klein geschrieben)
fr1:    cpx NAMELEN
        beq fr2
        lda NAMEBUF,x
        cmp #$41
        bcc fr1s
        cmp #$5b
        bcs fr1s
        ora #$20
fr1s:   sta flow,x
        inx
        bne fr1
fr2:    lda #<bitab                 ; MP = Tabellenanfang; Eintrag: Laenge, Name, Kennung; Ende = Laenge 0
        sta MP
        lda #>bitab
        sta MP + 1
fr_l:   ldy #$00
        lda (MP),y
        beq fr_no
        cmp NAMELEN
        bne fr_n
        iny
        ldx #$00
fr_c:   cpx NAMELEN
        beq fr_hit
        lda (MP),y
        cmp flow,x
        bne fr_n
        iny
        inx
        bne fr_c
fr_hit: lda (MP),y                  ; Y steht hinter dem Namen: Kennung
        sta fptr
        lda #$00
        sta fptr + 1
        sta fkind
        clc
        rts
fr_n:   ldy #$00                    ; naechster Eintrag: MP += Laenge + 2 (Laenge- und Kennungsbyte)
        lda (MP),y
        clc
        adc #$02
        clc
        adc MP
        sta MP
        bcc fr_l
        inc MP + 1
        jmp fr_l
fr_no:  sec
        rts

; bitab: Tabelle der eingebauten Funktionen: Namenlaenge, Name, Kennung (= Index in bi_jmp + 1); Ende = Laenge 0.
; Neue Funktionen: hier eintragen UND in bi_jmp an der passenden Stelle (Reihenfolge = Kennung). `align` hat die Kennung 10
; und teilt sich bi_next mit `next`.
bitab:  .byte 3, "abs", 1
        .byte 4, "sign", 2
        .byte 3, "min", 3
        .byte 3, "max", 4
        .byte 3, "int", 5
        .byte 5, "floor", 6
        .byte 4, "ceil", 7
        .byte 5, "round", 8
        .byte 4, "next", 9
        .byte 5, "align", 10
        .byte 3, "pow", 11
        .byte 4, "sqrt", 12
        .byte 3, "sin", 13
        .byte 3, "cos", 14
        .byte 3, "tan", 15
        .byte 4, "asin", 16
        .byte 4, "acos", 17
        .byte 4, "atan", 18
        .byte 5, "atan2", 19
        .byte 3, "exp", 20
        .byte 3, "log", 21
        .byte 4, "log2", 22
        .byte 5, "log10", 23
        .byte 3, "len", 24
        .byte 5, "range", 25
        .byte 0

; argpush: Wert (VTY, VAL, VFR) auf den Argumentstapel (9 Byte: VTY, VAL, VFR) legen; asp += 9. Fehler E211, wenn der
; Stapel (Obergrenze ARGEND) voll waere. Veraendert A, X, Z, P6.
argpush:
        lda asp
        ldx asp + 1
        jsr p6_load
        lda asp + 1
        cmp #>ARGEND - 1
        bcc ap1
        lda #ERR_E211
        jmp ex_error
ap1:    ldz #$00
        lda VTY
        sta [P6],z
        inz
        ldx #$00
ap2:    lda VAL,x
        sta [P6],z
        inz
        inx
        cpx #$04
        bne ap2
        ldx #$00
ap2b:   lda VFR,x
        sta [P6],z
        inz
        inx
        cpx #$04
        bne ap2b
        lda asp
        clc
        adc #$09
        sta asp
        bcc ap3
        inc asp + 1
ap3:    rts

; arg_get: A = Nummer (0..) -> VTY, VAL, VFR = Argument; fbase = Anfang der Argumente des laufenden Aufrufs (Adresse = fbase +
; Nummer * 9). Veraendert A, X, Z, P6, S2T.
arg_get:
        sta S2T
        asl
        asl
        asl
        clc
        adc S2T                     ; Nummer * 9 (Nummer*8 + Nummer)
        clc
        adc fbase
        pha
        lda fbase + 1
        adc #$00
        tax
        pla
        jsr p6_load
        ldz #$00
        lda [P6],z
        sta VTY
        inz
        ldx #$00
ag1:    lda [P6],z
        sta VAL,x
        inz
        inx
        cpx #$04
        bne ag1
        ldx #$00
ag2:    lda [P6],z
        sta VFR,x
        inz
        inx
        cpx #$04
        bne ag2
        rts

; ex_call: Funktionsaufruf; NAMEBUF = Name, SRC steht auf '('. Ablauf: Name aufloesen (E202 wenn unbekannt); fkind, fptr und den
; Stapelstand asp auf dem Hardware-Stapel sichern (damit verschachtelte Aufrufe wie f(g(x)) funktionieren, jeder Aufruf hat
; seinen eigenen Argumentbereich); die kommagetrennten Argumente auswerten und auf den Argumentstapel legen; bei `)` die
; Daten zurueckholen, fbase = Anfang der Argumente, Argumentzahl fnargs = (asp - fbase)/9, asp = fbase (Platz freigeben -
; die Werte bleiben stehen, bis sie gelesen sind), dann builtin_run oder user_run. Ergebnis in VAL/VFR/VTY.
; Fehler: E202 (unbekannt), ERR_SYNTAX (weder `,` noch `)`), E211 (Argumentstapel voll).
ex_call:
        jsr src_adv
        jsr fn_resolve
        bcc f_ec1
        lda #ERR_E202
        jmp ex_error
f_ec1:    lda fkind                 ; Zustand des Aufrufs sichern (5 Byte)
        pha
        lda fptr
        pha
        lda fptr + 1
        pha
        lda asp
        pha
        lda asp + 1
        pha
        jsr skipws
        jsr src_peek
        cmp #$29
        beq ec_done
ec_arg: lda #$01                    ; ein Argument: voller Ausdruck mit kleinstem Vorrang
        jsr ex_expr
        jsr argpush
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne ec_close
        jsr src_adv
        jmp ec_arg
ec_close:
        cmp #$29
        beq ec_done
        lda #ERR_SYNTAX
        jmp ex_error
ec_done:
        jsr src_adv                 ; `)` verbrauchen
        pla                         ; (asp beim Eintritt = Anfang der Argumente dieses Aufrufs)
        sta fbase + 1
        pla
        sta fbase
        pla
        sta fptr + 1
        pla
        sta fptr
        pla
        sta fkind
        sec                         ; Anzahl der Argumente = (asp - fbase) / 9
        lda asp
        sbc fbase
        sta S2T
        lda asp + 1
        sbc fbase + 1
        sta S2T + 1
        ldx #$00
ec_cnt: lda S2T                     ; Division durch 9 per fortgesetzter Subtraktion (X = Quotient)
        ora S2T + 1
        beq ec_cd
        sec
        lda S2T
        sbc #$09
        sta S2T
        lda S2T + 1
        sbc #$00
        sta S2T + 1
        inx
        bne ec_cnt
ec_cd:  stx fnargs
        lda fbase                   ; Argumentstapel freigeben (die Werte bleiben stehen, bis sie gelesen sind)
        sta asp
        lda fbase + 1
        sta asp + 1
        lda fkind
        bne ec_user
        jmp builtin_run
ec_user:
        jmp user_run

; ---- eigene Funktionen
; user_run: ruft die mit .function definierte Funktion fptr mit den fnargs Argumenten auf. Pruefungen: Rekursionstiefe (E202
; ab 17), Argumentzahl = Parameterzahl (sonst E202). Danach: Parameter als Variablen anlegen (arg_get + var_new; vare merken,
; um sie hinterher zu verwerfen), SRC auf den Ausdruck setzen (alten SRC auf dem Stapel sichern), mit ex_expr auswerten.
; Die Parameter verdecken gleichnamige Variablen (der letzte gleichnamige Eintrag gilt, siehe stage2.asm). Veraendert VAL/VFR/VTY.
user_run:
        inc fdepth
        lda fdepth
        cmp #$11
        bcc ur0
        lda #ERR_E202               ; Rekursion
        jmp ex_error
ur0:    lda fptr
        ldx fptr + 1
        jsr p7_load
        ldz #$01
        lda [P7],z
        clc
        adc #$02
        taz                         ; Z = Versatz der Parameterzahl (Namenlaenge + 2: Gesamtgroesse, Laenge, Name)
        lda [P7],z
        sta fnp
        cmp fnargs
        beq ur1
        lda #ERR_E202               ; falsche Argumentzahl
        jmp ex_error
ur1:    inz                         ; Z = erster Parameter
        tza
        sta fzo                     ; fzo = Lesezeiger im Eintrag
        lda vare
        pha
        lda vare + 1
        pha
        lda #$00
        sta fi
ub_l:   lda fi                      ; je Parameter: Namen nach NAMEBUF, Argument fi holen, Variable anlegen
        cmp fnp
        beq ub_done
        ldz fzo
        lda [P7],z
        sta NAMELEN
        inz
        ldx #$00
ub_c:   cpx NAMELEN
        beq ub_c2
        lda [P7],z
        sta NAMEBUF,x
        inz
        inx
        bne ub_c
ub_c2:  tza
        sta fzo
        lda fi
        jsr arg_get
        jsr var_new
        inc fi
        jmp ub_l
ub_done:                            ; fzo zeigt jetzt auf den gespeicherten SRC-Zeiger (4 Byte) des Ausdrucks
        ldx #$00                    ; SRC sichern
ub_s:   lda SRC,x
        pha
        inx
        cpx #$04
        bne ub_s
        ldz fzo                     ; SRC = Zeiger auf den Ausdruck
        ldx #$00
ub_p:   lda [P7],z
        sta SRC,x
        inz
        inx
        cpx #$04
        bne ub_p
        lda #$01
        jsr ex_expr                 ; Funktionsrumpf auswerten (liest ab dem neuen SRC)
        ldx #$03
ub_r:   pla                         ; SRC zurueck (umgekehrte Reihenfolge)
        sta SRC,x
        dex
        bpl ub_r
        pla                         ; Parametervariablen verwerfen
        sta vare + 1
        pla
        sta vare
        dec fdepth
        rts

; .function name(parameter, ...) = ausdruck
; d_function: Direktive. Legt einen Eintrag am Ende der Funktionstabelle (fune) an: Name, Parameterzahl und -namen, dann den
; SRC-Zeiger auf den Ausdruck; gelesen wird der Ausdruck erst beim Aufruf (user_run). Fehler: ERR_SYNTAX (Name/Klammer/`=`
; fehlt), E204 (Name schon definiert; in jedem Durchlauf neu, die Tabelle wird bei f_pass geleert), E211 (Tabelle voll oder
; Eintrag zu gross: Schreibposition ab $e0). Hilfszellen: fzo = Schreibzeiger Parameterzahl, fzo + 1 = naechste
; freie Stelle, fnp = Parameterzahl. Springt am Ende nach dsk1 (dir2.asm: Rest der Zeile ueberspringen).
d_function:

        jsr skipws
        jsr read_ident
        lda NAMELEN
        bne df0
        lda #ERR_SYNTAX
        jmp as_error
df0:    jsr fn_find
        bcs f_df1
        lda #ERR_E204               ; doppelt definiert
        jmp as_error
f_df1:  jsr fn_resolve              ; Name einer eingebauten Funktion (sin, pow, ...): E204 wie vcc ("ist eine eingebaute Funktion")
        bcs f_df1b
        lda #ERR_E204
        jmp as_error
f_df1b: lda fune                    ; neuer Eintrag beginnt bei fune; Byte 0 (Groesse) wird zuletzt gesetzt
        ldx fune + 1
        jsr p7_load
        ldz #$01                    ; Name
        lda NAMELEN
        sta [P7],z
        inz
        ldx #$00
f_df2:    cpx NAMELEN
        beq f_df3
        lda NAMEBUF,x
        sta [P7],z
        inz
        inx
        bne f_df2
f_df3:    tza
        sta fzo                     ; Versatz der Parameterzahl
        lda #$00
        sta fnp
        inz
        tza
        sta fzo + 1                 ; naechste freie Stelle
        jsr skipws
        jsr src_peek
        cmp #$28
        beq f_df4
        lda #ERR_SYNTAX
        jmp as_error
f_df4:    jsr src_adv
f_df5:    jsr skipws
        jsr src_peek
        cmp #$29
        beq df9
        jsr read_ident
        lda NAMELEN
        beq f_df_syn
        ldz fzo + 1
        cpz #$e0                    ; Eintrag darf nicht ueber $e0 hinauswachsen (Reserve fuer den 4-Byte-Zeiger)
        bcc df6
        lda #ERR_E211
        jmp as_error
df6:    lda NAMELEN
        sta [P7],z
        inz
        ldx #$00
df7:    cpx NAMELEN
        beq df8
        lda NAMEBUF,x
        sta [P7],z
        inz
        inx
        bne df7
df8:    tza
        sta fzo + 1
        inc fnp
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne df9
        jsr src_adv
        jmp f_df5
f_df_syn: lda #ERR_SYNTAX
        jmp as_error
df9:    jsr src_peek
        cmp #$29
        bne f_df_syn
        jsr src_adv
        jsr skipws
        jsr src_peek
        cmp #$3d
        bne f_df_syn
        jsr src_adv
        jsr skipws
        ldz fzo                     ; Parameterzahl eintragen (am reservierten Platz hinter dem Namen)
        lda fnp
        sta [P7],z
        ldz fzo + 1                 ; Zeiger auf den Ausdruck (SRC)
        ldx #$00
dfa:    lda SRC,x
        sta [P7],z
        inz
        inx
        cpx #$04
        bne dfa
        tza                         ; Gesamtgroesse (Z = Schreibposition = Eintragslaenge) nach Byte 0
        ldz #$00
        sta [P7],z
        clc
        adc fune
        sta fune
        bcc dfb
        inc fune + 1
dfb:    lda fune + 1
        cmp #>FUNEND
        bcc dfc
        lda #ERR_E211
        jmp as_error
dfc:    jmp dsk1                    ; Rest der Zeile (der Ausdruck) wird erst beim Aufruf gelesen

; ---- eingebaute Funktionen (Ganz- und Kommazahlen)
; builtin_run: Sprung ueber bi_jmp mit der Kennung aus fptr (Kennung*2-2 = Tabellenversatz). Argumente: fnargs, arg_get.
builtin_run:
        lda fptr
        asl
        tax
        jmp (bi_jmp - 2,x)
; bi_jmp: Einsprungtabelle in Reihenfolge der Kennungen aus bitab (next und align teilen sich bi_next)
bi_jmp: .word bi_abs, bi_sign, bi_min, bi_max, bi_int, bi_floor, bi_ceil, bi_round, bi_next, bi_next, bi_pow, bi_sqrt
        .word bi_sin, bi_cos, bi_tan, bi_asin, bi_acos, bi_atan, bi_atan2, bi_exp, bi_log, bi_log2, bi_log10, bi_len, bi_range

; need1: genau ein Argument, Ganz- oder Kommazahl nach VTY/VAL/VFR; E202 bei anderer Argumentzahl oder wenn es eine Liste ist.
need1:  lda fnargs
        cmp #$01
        beq n1ok
n1bad:  lda #ERR_E202
        jmp ex_error
n1ok:   lda #$00
        jsr arg_get
        lda VTY
        cmp #$02
        beq n1bad                   ; eine Liste ist keine Zahl
        rts

; need1f: wie need1, danach als Festkommawert in fxa (ld_a) - Eingang der Funktionen aus math.asm.
need1f: jsr need1
        jmp ld_a

; Rundungsfunktionen. int/floor/ceil/round beruecksichtigen Rechenfehler der Festkommafunktionen: Liegt der Wert um weniger
; als 2^-20 neben einer ganzen Zahl (z. B. 2,9999999), gilt er als diese ganze Zahl. Rueckgabe immer Ganzzahl (VTY = 0).
; int(x): zur Null hin kuerzen (coerce_int). floor(x): Boden (zum kleineren Wert; VAL ist im Zweierkomplement schon der Boden).
bi_int: jsr need1
        lda #$01                    ; ausdrueckliches Abschneiden: ohne W202
        sta ciq
        jsr coerce_int
        lda #$00
        sta ciq
        rts

bi_floor:
        jsr need1
        lda VTY
        beq bf2
        lda VFR + 3                 ; knapp unter der naechsten ganzen Zahl: aufrunden
        and VFR + 2
        cmp #$ff
        bne bf1
        lda VFR + 1
        cmp #$f0
        bcc bf1
        inc VAL
        bne bf1
        inc VAL + 1
        bne bf1
        inc VAL + 2
        bne bf1
        inc VAL + 3
bf1:    lda #$00
        sta VTY
bf2:    rts

; ceil(x): zur naechsten ganzen Zahl nach oben: Ganzzahlteil + 1, sobald ein Nachkommateil >= 2^-20 vorhanden ist.
bi_ceil:
        jsr need1
        lda VTY
        beq bc2
        lda VFR + 3
        ora VFR + 2
        bne bc3
        lda VFR + 1
        cmp #$10
        bcc bc1                     ; knapp ueber einer ganzen Zahl: Nachkommateil weglassen
bc3:    lda VFR
        ora VFR + 1
        ora VFR + 2
        ora VFR + 3
        beq bc1
        inc VAL
        bne bc1
        inc VAL + 1
        bne bc1
        inc VAL + 2
        bne bc1
        inc VAL + 3
bc1:    lda #$00
        sta VTY
bc2:    rts

; round(x): zur naechsten ganzen Zahl; .5 wird vom Nullpunkt weg gerundet (Betrag bilden, runden, Vorzeichen wieder anbringen).
bi_round:
        jsr need1
        lda VTY
        beq br9
        jsr ld_a
        lda #$00
        sta fsg
        lda fxa + 7
        bpl br1
        jsr neg_a
        lda #$80
        sta fsg
br1:    ldx #$03                    ; Ganzzahlteil
br2:    lda fxa + 4,x
        sta VAL,x
        dex
        bpl br2
        lda fxa + 3                 ; Nachkommateil >= 0,5: aufrunden
        bpl br4
        inc VAL
        bne br4
        inc VAL + 1
        bne br4
        inc VAL + 2
        bne br4
        inc VAL + 3
br4:    lda #$00
        sta VTY
        lda fsg
        beq br9
        ldx #VAL
        jmp negate
br9:    rts

; abs(x): Betrag; Ganzzahl bleibt Ganzzahl (negate), Kommazahl bleibt Kommazahl (64-Bit neg_a).
bi_abs: jsr need1
        lda VTY
        bne ba2
        lda VAL + 3
        bpl ba1
        ldx #VAL
        jmp negate
ba1:    rts
ba2:    jsr ld_a
        lda fxa + 7
        bpl ba3
        jsr neg_a
ba3:    jmp st_a

; sign(x): -1, 0 oder +1 als Ganzzahl (auch fuer Kommazahlen; VAL ist der Boden, daher ist jede negative Zahl VAL < 0).
bi_sign:
        jsr need1
        jsr val_isnz
        beq bs_ret                  ; 0 bleibt 0
        lda VAL + 3
        bmi bs_neg
        lda #$00
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        lda #$01
        sta VAL
        sta fsg
        lda #$00
        sta VTY
        rts
bs_neg: lda #$ff
        sta VAL
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
bs_ret: lda #$00
        sta VTY
        ldx #$03                    ; (die folgende Schleife bewirkt nichts; sie zaehlt nur X herunter)
bs_z:   lda #$00
        cpx #$00
        bne bs_z2
bs_z2:  dex
        bpl bs_z
        rts

; min/max: ein oder mehr Argumente (Ganz- oder Kommazahlen). Merkt sich das bisherige Ergebnis in bcur/bcurf/bcurt (bm_save)
; und vergleicht jedes weitere Argument per ex_apply_x mit dem Operator bmop (7 = `>` fuer max, 5 = `<` fuer min):
; LHS = neues Argument, VAL = bisheriges; Wahrheitswert in VAL.
bi_max: lda #$07                    ; neues Argument > bisheriges
        bne bm_go
bi_min: lda #$05                    ; neues Argument < bisheriges
bm_go:  sta bmop
        lda fnargs
        bne bm1
        lda #ERR_E202
        jmp ex_error
bm1:    lda #$00
        jsr arg_get
        jsr bm_save
        lda #$01
        sta fi
bm_l:   lda fi
        cmp fnargs
        beq bm_done
        jsr arg_get
        ldx #$03
bm3:    lda VAL,x
        sta LHS,x
        lda VFR,x
        sta LFR,x
        lda bcur,x
        sta VAL,x
        lda bcurf,x
        sta VFR,x
        dex
        bpl bm3
        lda VTY
        sta LTY
        lda bcurt
        sta VTY
        lda bmop
        sta OPID
        jsr ex_apply_x              ; VAL = (neu ? bisher)
        lda VAL
        beq bm4
        lda fi                      ; neues Argument uebernehmen
        jsr arg_get
        jsr bm_save
bm4:    inc fi
        jmp bm_l
bm_done:
        ldx #$03
bm6:    lda bcur,x
        sta VAL,x
        lda bcurf,x
        sta VFR,x
        dex
        bpl bm6
        lda bcurt
        sta VTY
        rts

bm_save:
        ldx #$03
bs1x:   lda VAL,x
        sta bcur,x
        lda VFR,x
        sta bcurf,x
        dex
        bpl bs1x
        lda VTY
        sta bcurt
        rts

; next(n) / align(n): kleinstes Vielfaches von n, das >= PC ist (PC bleibt, wenn schon ausgerichtet). r = PC % n;
; r = 0: PC; sonst PC + (n - r). Die Rechnung laeuft ueber ex_apply mit den Operatorkennungen $12 (%), $0f (-), $0e (+);
; n = 0 ergibt Division durch 0 (E202 bzw. weicher Fehler). Ergebnis Ganzzahl.
bi_next:
        jsr need1
        jsr coerce_int
        ldx #$03
bn1:    lda VAL,x
        sta bnn,x
        dex
        bpl bn1
        lda PC
        sta LHS
        lda PC + 1
        sta LHS + 1
        lda #$00
        sta LHS + 2
        sta LHS + 3
        lda #$12
        sta OPID
        jsr ex_apply                ; PC % n (LHS = PC, VAL = n)
        lda VAL
        ora VAL + 1
        ora VAL + 2
        ora VAL + 3
        bne bn2
        lda PC
        sta VAL
        lda PC + 1
        sta VAL + 1
        lda #$00
        sta VAL + 2
        sta VAL + 3
        rts
bn2:    ldx #$03
bn3:    lda bnn,x
        sta LHS,x
        dex
        bpl bn3
        lda #$0f
        sta OPID
        jsr ex_apply                ; n - Rest
        jsr cp_val_lhs
        lda PC
        sta VAL
        lda PC + 1
        sta VAL + 1
        lda #$00
        sta VAL + 2
        sta VAL + 3
        lda #$0e
        sta OPID
        jmp ex_apply

; pow(a, b): Ganzzahlen mit b >= 0 ganzzahlig (wiederholte Multiplikation, b Durchlaeufe, ohne Ueberlaufpruefung: Ergebnis
; modulo 2^32; pow(a, 0) = 1), sonst als Kommazahl (bp_fl): dort |a|^|b| bei ganzem b mit |b| <= 64 durch Multiplikationen
; (negativer Exponent: Kehrwert), sonst a^b = e^(b ln a) ueber m_log2/m_exp. Negative Basis nur bei ganzem Exponenten,
; das Vorzeichen ist die Paritaet von b. a = 0 ergibt in der Kommazahlform 0. Register R_A..R_D (siehe math.asm) werden benutzt.
bi_pow: lda fnargs
        cmp #$02
        beq bp1
        lda #ERR_E202
        jmp ex_error
bp1:    lda #$00
        jsr arg_get
        lda VTY
        sta bcurt
        cmp #$02
        bne bp1a
        jmp bi_bad
bp1a:   lda #$01
        jsr arg_get
        lda VTY
        cmp #$02
        bne bp1b
        jmp bi_bad
bp1b:   ora bcurt
        bne bp_fl                   ; eine Kommazahl: Festkomma
        lda VAL + 3
        bmi bp_fl                   ; negativer Exponent: Festkomma
        lda #$00
        jsr arg_get                 ; Basis nach bcur
        ldx #$03
bp2:    lda VAL,x
        sta bcur,x
        dex
        bpl bp2
        lda #$01
        jsr arg_get                 ; Exponent in VAL
        ldx #$03
bp4:    lda VAL,x
        sta bnn,x                   ; Zaehler
        lda #$00
        sta bres,x
        dex
        bpl bp4
        lda #$01
        sta bres
bp_l:   lda bnn
        ora bnn + 1
        ora bnn + 2
        ora bnn + 3
        beq bp_done
        ldx #$03
bp5:    lda bres,x
        sta LHS,x
        lda bcur,x
        sta VAL,x
        dex
        bpl bp5
        lda #$10
        sta OPID
        jsr ex_apply
        ldx #$03
bp6:    lda VAL,x
        sta bres,x
        dex
        bpl bp6
        lda bnn                     ; Zaehler - 1
        bne bp7
        lda bnn + 1
        bne bp8
        lda bnn + 2
        bne bp9
        dec bnn + 3
bp9:    dec bnn + 2
bp8:    dec bnn + 1
bp7:    dec bnn
        jmp bp_l
bp_done:
        ldx #$03
bp_d1:  lda bres,x
        sta VAL,x
        dex
        bpl bp_d1
        lda #$00
        sta VTY
        rts
bp_fl:  lda #$00                    ; a = 0 -> 0
        jsr arg_get
        jsr ld_a
        lda #$00
        sta fsg
        lda fxa + 7
        bpl pf1
        lda #$80                    ; negative Basis: nur mit ganzem Exponenten
        sta fsg
        jsr neg_a
pf1:    ldx #R_D
        jsr pa                      ; |a|
        jsr fx_isz_a
        bne pf2
        jsr z_a
        jmp st_a
pf2:    lda #$01
        jsr arg_get
        jsr ld_a                    ; fxa = b
        lda fsg
        beq pf4
        lda fxa                     ; negative Basis: b muss ganz sein
        ora fxa + 1
        ora fxa + 2
        ora fxa + 3
        beq pf3
        lda #ERR_E202
        jmp ex_error
pf3:    lda fxa + 4                 ; Vorzeichen = Paritaet von b (ungerade -> Ergebnis negativ)
        and #$01
        beq pf4
        lda #$80
        sta fsg
        bne pf5
pf4:    lda #$00
        sta fsg
pf5:    ldx #R_C
        jsr pa                      ; b
        lda fxa                     ; b ganz und |b| <= 64: Multiplikation
        ora fxa + 1
        ora fxa + 2
        ora fxa + 3
        bne pf_exp
        lda fxa + 5
        ora fxa + 6
        ora fxa + 7
        beq pf6
        cmp #$ff
        bne pf_exp
pf6:    lda fxa + 4
        bpl pf7
        eor #$ff
        clc
        adc #$01
pf7:    cmp #$41
        bcs pf_exp
        sta ci                      ; Anzahl der Faktoren
        lda #<c_one
        ldx #>c_one
        jsr set_mp
        jsr mp_a
        ldx #R_A
        jsr pa                      ; Ergebnis = 1
pf8:    lda ci
        beq pf9
        ldx #R_A
        jsr ga
        ldx #R_D
        jsr gb
        jsr fx_mul
        ldx #R_A
        jsr pa
        dec ci
        jmp pf8
pf9:    ldx #R_A
        jsr ga
        lda fr + R_C * 8 + 7        ; negativer Exponent: Kehrwert
        bpl pf10
        ldx #R_A
        jsr pa
        jsr fx_isz_a
        beq pf_ovf
        lda #<c_one
        ldx #>c_one
        jsr set_mp
        jsr mp_b
        jsr fx_div
pf10:   lda fsg
        bpl pf11
        jsr neg_a
pf11:   jmp m_out
pf_ovf: lda #ERR_E202
        jmp ex_error
pf_exp: ldx #R_D                    ; a^b = e^(b * ln a); ln a = log2(a) * ln 2
        jsr ga
        jsr m_log2
        ldx #R_B
        jsr pa
        ldx #R_C
        jsr ga
        ldx #R_B
        jsr gb
        jsr fx_mul
        lda #<c_ln2
        ldx #>c_ln2
        jsr set_mp
        jsr mp_b
        jsr fx_mul
        jsr m_exp
        lda fsg
        bpl pf12
        ldx #$07
pf13:   lda VAL,x                   ; (die Schleife bewirkt nichts; eigentlich geladen wird in ld_a) Vorzeichen: nur selten noetig
        dex
        bpl pf13
        jsr ld_a
        jsr neg_a
        jmp st_a
pf12:   rts

bi_bad: lda #ERR_E202               ; gemeinsamer Fehlerausgang: ungueltiges Argument
        jmp ex_error

; Wurzel, Winkel-, Exponential- und Logarithmusfunktionen (math.asm). Alle: ein Argument -> fxa (need1f) -> m_* in math.asm.
; log2 rechnet m_log2 direkt; ln/log10 multiplizieren log2 per m_logk mit ln 2 bzw. log10(2).
bi_sqrt:
        jsr need1f
        jmp m_sqrt
bi_sin: jsr need1f
        jmp m_sin
bi_cos: jsr need1f
        jmp m_cos
bi_tan: jsr need1f
        jmp m_tan
bi_exp: jsr need1f
        jmp m_exp
bi_log2:
        jsr need1f
        jsr m_log2
        jmp m_out
bi_log: jsr need1f
        jsr m_log2
        lda #<c_ln2
        ldx #>c_ln2
        jsr set_mp
        jmp m_logk
bi_log10:
        jsr need1f
        jsr m_log2
        lda #<c_lg2
        ldx #>c_lg2
        jsr set_mp
        jmp m_logk
; atan(x) = atan2(x, 1): R_Y = x, R_X = 1.
bi_atan:
        jsr need1f
        ldx #R_Y
        jsr pa
        lda #<c_one
        ldx #>c_one
        jsr set_mp
        jsr mp_a
        ldx #R_X
        jsr pa
        jsr m_atan2
        jmp m_out
; atan2(y, x): beide Argumente nach R_Y / R_X (Festkomma), Winkel in (-pi, pi].
bi_atan2:
        lda fnargs
        cmp #$02
        beq b2ok
        lda #ERR_E202
        jmp ex_error
b2ok:   lda #$00                    ; atan2(y, x)
        jsr arg_get
        jsr ld_a
        ldx #R_Y
        jsr pa
        lda #$01
        jsr arg_get
        jsr ld_a
        ldx #R_X
        jsr pa
        jsr m_atan2
        jmp m_out
; asin(x) = atan2(x, sqrt(1 - x^2)); acos(x) = atan2(sqrt(1 - x^2), x). ci = 0 (asin) bzw. 1 (acos) wird auf dem Stapel
; gerettet, weil m_sqrt ci als Zaehler benutzt. |x| > 1 ergibt E202.
bi_asin:
        lda #$00
        sta ci
        beq bas
bi_acos:
        lda #$01
        sta ci
bas:    lda ci
        pha
        jsr need1f
        ldx #R_D
        jsr pa                      ; x
        ldx #R_D
        jsr gb
        jsr fx_mul                  ; x * x
        ldx #$07
        lda #$00
bas1:   sta fxb,x
        dex
        bpl bas1
        lda #$01
        sta fxb + 4
        jsr fx_sub                  ; 1 - x * x
        lda fxa + 7
        bpl bas2
        lda #ERR_E202               ; |x| > 1
        jmp ex_error
bas2:   jsr m_sqrt                  ; s = sqrt(1 - x * x) in VAL/VFR
        jsr ld_a
        pla
        bne bas3
        ldx #R_X                    ; asin = atan2(x, s)
        jsr pa
        ldx #R_D
        jsr ga
        ldx #R_Y
        jsr pa
        jmp bas4
bas3:   ldx #R_Y                    ; acos = atan2(s, x)
        jsr pa
        ldx #R_D
        jsr ga
        ldx #R_X
        jsr pa
bas4:   jsr m_atan2
        jmp m_out

; ---- Daten (Programmspeicher)
; fune: Ende der Funktionstabelle (Offset in Bank 4); asp: Argumentstapelzeiger; fptr/fkind: aufgeloeste Funktion (Offset bzw.
; Kennung / Art); fbase: Anfang der Argumente des laufenden Aufrufs; fnargs/fnp: Argumentzahl bzw. Parameterzahl; fi: Zaehler;
; fzo: Lesezeiger/Schreibzeiger im Tabelleneintrag; fdepth: Rekursionstiefe; flow: Name in Kleinschrift; bmop/bcur/bcurf/bcurt:
; Zustand von min/max; bnn/bres: Zaehler und Ergebnis von pow bzw. Zwischenwert von next; bmid: ohne Verwendung.
fune:   .word 0
.ifndef OA_BUILD                     ; im Overlay A (src/ide/aoverlay.asm) liegen asp, fnargs, fi an festen Adressen am Overlayanfang
asp:    .word 0
.endif
fptr:   .word 0
fkind:  .byte 0
fbase:  .word 0
.ifndef OA_BUILD
fnargs: .byte 0
.endif
fnp:    .byte 0
.ifndef OA_BUILD
fi:     .byte 0
.endif
fzo:    .word 0
fdepth: .byte 0
flow:   .fill 32, 0
bmop:   .byte 0
bcur:   .fill 4, 0
bcurf:  .fill 4, 0
bcurt:  .byte 0
bnn:    .fill 4, 0
bres:   .fill 4, 0
bmid:   .word 0
