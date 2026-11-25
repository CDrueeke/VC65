; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; expr.asm - Ausdruecke des VCASM (Stufe 1): 32-Bit-Ganzzahlen mit Vorzeichen, Operatoren und Vorrang wie vcc
; (asm-expr.md): einstellig - + ! ~ < > (staerkster Vorrang), dann * / %, + -, << >>, &, ^, |, Vergleiche, == !=, &&, ||.
; Zahlen: dezimal, $hex, 0xhex, %binaer, 'c', Kommazahlen (numx.asm). Symbole und Funktionsaufrufe gehen an sym.asm
; (sym_lookup_ref) bzw. func.asm (ex_call); `*` = PC. Listenliteral und Indizes `[..]` an list.asm.
;
; Rolle im Assembler: asm.asm (Zeilenanalyse, Direktiven), enc.asm, stage2.asm (Variablen, Schleifen) und list.asm rufen
; ex_eval bzw. ex_eval_any, sobald ein Operand/Argument ein Ausdruck ist. expr.asm enthaelt den Parser (Vorrangklettern), die
; reine 32-Bit-Ganzzahlarithmetik (ap_*) und die Zahlenerkennung. Sobald ein Operand eine Kommazahl ist, uebernimmt
; numx.asm (ex_apply_x) mit Festkomma 32.32; sonst ex_apply hier ("alter Rechenweg"). Funktionen: func.asm/math.asm.
;
; Schnittstelle: SRC zeigt auf den Ausdruck. ex_eval: Ergebnis in VAL ($70-$73), Carry geloescht; bei Fehler Carry
; gesetzt, ERR gesetzt, SRC steht an der Fehlerstelle. Der Stapel wird bei Fehlern ueber ESP sauber abgebaut.
; Wertdarstellung (siehe numx.asm): VTY = Art (0 Ganzzahl, 1 Kommazahl, 2 Liste), VAL = 32-Bit-Ganzzahl (bei Kommazahl der
; Ganzzahlteil), VFR = 32-Bit-Nachkommateil; analog LTY/LHS/LFR fuer den linken Operanden. Ganzzahlen sind 32 Bit mit Vorzeichen
; (Zweierkomplement); Ueberlauf wird nicht gemeldet, das Ergebnis wird modulo 2^32 abgeschnitten.
; Rekursion: Vorrangklettern (ex_expr), Zwischenwerte auf dem Hardware-Stapel (je Ebene 10 Byte fuer linken Wert samt
; Nachkommateil, Art und Operator, dazu 1 Byte Mindestvorrang und die Ruecksprungadressen). Eine Tiefengrenze wird nicht
; geprueft; es gilt der 256-Byte-Hardwarestapel.
; Operatorkennungen (OPID 1..18): || && == != < <= > >= | ^ & << >> + - * / % ; Vorrang ueber ptab, Rechenroutine ueber aptab.
; Veraendert A, X, Y, Z, VAL, LHS, TMP, TMP2 und die Zeropage-Zellen aus zp.asm.
; Alle Vergleiche und logischen Operatoren liefern 0 oder 1 als Ganzzahl (VTY = 0).
; =====================================================================================================================

; ex_eval: wertet den Ausdruck ab SRC aus und liefert eine GANZZAHL.
;   Eingabe: SRC. Ausgabe: VAL = Wert, VTY = 0; Carry gesetzt = Fehler (ERR, SRC an der Fehlerstelle); sonst Carry geloescht.
;   Merkt den Stapelzeiger in ESP: ex_fail/ex_error springen aus beliebig tiefer Rekursion zurueck, indem sie S wieder auf
;   ESP setzen und `rts` ausfuehren - der RTS kehrt dadurch direkt zum Aufrufer von ex_eval zurueck. Folge: Der Aufrufer
;   darf zwischen ex_eval-Aufruf und -Rueckkehr nichts auf den Stapel legen, das er nicht selbst abraeumt.
ex_eval:
        tsx
        stx ESP                     ; Stapelstand fuer Fehlerabbruch merken
        lda #$00
        sta ERR
        lda #$01                    ; kleinster Vorrang
        jsr ex_expr
        jsr coerce_int              ; Kommazahl -> Ganzzahl, Liste -> Fehler
        clc
        rts

; ex_eval_any: wie ex_eval, aber Kommazahlen und Listen bleiben erhalten (VTY, VFR). Gebraucht fuer .var/.set und Listen.
ex_eval_any:
        tsx
        stx ESP
        lda #$00
        sta ERR
        lda #$01
        jsr ex_expr
        clc
        rts

; ex_error: A = Fehlercode -> ERR; danach wie ex_fail. Wird per jmp (nicht jsr) angesprungen, damit der Stapel egal ist.
ex_error:                           ; A = Fehlercode
        sta ERR
; ex_fail: Abbruch: Stapel auf den Stand von ex_eval zurueck, Carry gesetzt, zurueck zum Aufrufer von ex_eval.
ex_fail:
        ldx ESP
        txs
        sec
        rts

; ex_expr: Vorrangklettern (precedence climbing). Eingabe A = kleinster Vorrang, den ein Operator haben muss, um noch
; in diesem Aufruf verarbeitet zu werden. Ausgabe: VAL/VFR/VTY = Wert. Ablauf: linken Operanden mit ex_unary lesen; solange der
; folgende Operator Vorrang >= Minimum hat: Operator verbrauchen, linken Wert samt Operator auf den Stapel, rechten Operanden
; mit Minimum = Vorrang+1 rekursiv lesen (macht alle Operatoren linksassoziativ), dann ex_apply_x. Der Mindestvorrang bleibt
; waehrenddessen als unterstes Byte dieses Rahmens auf dem Stapel (pha am Anfang, pla bei exd).
ex_expr:
        pha
        jsr ex_unary
exl:    jsr skipws
        jsr ex_peekop               ; A = Operatorkennung (0 = keiner), OPLEN
        beq exd
        sta OPID
        tax
        lda ptab - 1,x
        sta PREC                    ; Vorrang des gelesenen Operators (aus ptab, Index Kennung-1)
        tsx
        lda PREC
        cmp $0101,x                 ; kleinster Vorrang liegt oben auf dem Stapel ($0100 + S + 1 = zuletzt gepusht)
        bcc exd                     ; Vorrang < Minimum: fertig
        ldy OPLEN
exa:    jsr src_adv                 ; Operator verbrauchen (OPLEN Zeichen, 1 oder 2)
        dey
        bne exa
        lda VAL                     ; linken Wert und Operator auf den Stapel (10 Byte: VAL, VFR, VTY, OPID)
        pha
        lda VAL + 1
        pha
        lda VAL + 2
        pha
        lda VAL + 3
        pha
        lda VFR                     ; Nachkommateil und Art des linken Werts
        pha
        lda VFR + 1
        pha
        lda VFR + 2
        pha
        lda VFR + 3
        pha
        lda VTY
        pha
        lda OPID
        pha
        lda PREC
        clc
        adc #$01                    ; rechter Operand: nur staerker bindende Operatoren (Linksassoziativitaet)
        jsr ex_expr                 ; rechter Operand in VAL
        pla                         ; Stapel wieder abbauen in umgekehrter Reihenfolge: OPID, LTY, LFR, LHS
        sta OPID
        pla
        sta LTY
        pla
        sta LFR + 3
        pla
        sta LFR + 2
        pla
        sta LFR + 1
        pla
        sta LFR
        pla
        sta LHS + 3
        pla
        sta LHS + 2
        pla
        sta LHS + 1
        pla
        sta LHS
        jsr ex_apply_x              ; LHS OPID VAL -> VAL (Ganzzahl- oder Festkommaweg)
        jmp exl                     ; weitere Operatoren gleichen oder hoeheren Vorrangs
exd:    pla                         ; Mindestvorrang dieses Rahmens verwerfen
        rts

; ex_peekop: liest den Operator am SRC (ohne ihn zu verbrauchen); A = Kennung 1..18 oder 0, OPLEN = Laenge (1 oder 2).
; Z-Flag gemaess A. Ein einzelnes `=` oder `!` ist kein Operator (A = 0), ebenso `//` (Zeilenkommentar, nicht Division).
; Die Kennungen sind nach Vorrang aufsteigend vergeben (siehe ptab); die Nummernfolge ist an aptab gekoppelt - Aenderungen
; nur gemeinsam mit ptab und aptab (und der Pruefung in ex_apply_x, die Bereiche 1..8, 9..13, 14..18 unterscheidet).
ex_peekop:
        lda #$01
        sta OPLEN
        jsr src_peek
        cmp #$7c                    ; |
        beq po_or
        cmp #$26                    ; &
        beq po_and
        cmp #$3d                    ; =
        beq po_eq
        cmp #$21                    ; !
        beq po_ne
        cmp #$3c                    ; <
        beq po_lt
        cmp #$3e                    ; >
        beq po_gt
        cmp #$5e                    ; ^
        beq po_xor
        cmp #$2b                    ; +
        beq po_add
        cmp #$2d                    ; -
        beq po_sub
        cmp #$2a                    ; *
        beq po_mul
        cmp #$2f                    ; /
        beq po_div
        cmp #$25                    ; %
        beq po_mod
        lda #$00
        rts
po_or:  jsr src_peek1                ; | oder ||
        cmp #$7c
        bne po_or1
        inc OPLEN
        lda #$01                    ; ||
        rts
po_or1: lda #$09                    ; |
        rts
po_and: jsr src_peek1
        cmp #$26
        bne po_and1
        inc OPLEN
        lda #$02                    ; &&
        rts
po_and1:
        lda #$0b                    ; &
        rts
po_eq:  jsr src_peek1
        cmp #$3d
        bne po_none
        inc OPLEN
        lda #$03                    ; ==
        rts
po_ne:  jsr src_peek1
        cmp #$3d
        bne po_none
        inc OPLEN
        lda #$04                    ; !=
        rts
po_lt:  jsr src_peek1                ; < , << oder <=
        cmp #$3c
        beq po_shl
        cmp #$3d
        beq po_le
        lda #$05                    ; <
        rts
po_shl: inc OPLEN
        lda #$0c                    ; <<
        rts
po_le:  inc OPLEN
        lda #$06                    ; <=
        rts
po_gt:  jsr src_peek1                ; > , >> oder >=
        cmp #$3e
        beq po_shr
        cmp #$3d
        beq po_ge
        lda #$07                    ; >
        rts
po_shr: inc OPLEN
        lda #$0d                    ; >>
        rts
po_ge:  inc OPLEN
        lda #$08                    ; >=
        rts
po_xor: lda #$0a
        rts
po_add: lda #$0e
        rts
po_sub: lda #$0f
        rts
po_mul: lda #$10
        rts
po_div: jsr is_cmt2                 ; `//` beginnt einen Kommentar: kein Operator
        beq po_none
        lda #$11
        rts
po_mod: lda #$12
        rts
po_none:
        lda #$00
        rts

; Vorrang je Operatorkennung 1..18 (Index = Kennung-1): || && == != < <= > >= | ^ & << >> + - * / %
; Groessere Zahl bindet staerker; 1 ist der niedrigste (kleinster Vorrang beim Start von ex_eval).
ptab:   .byte 1, 2, 3, 3, 4, 4, 4, 4, 5, 6, 7, 8, 8, 9, 9, 10, 10, 10

; ex_unary: einstellige Operatoren (- + ! ~ < >), Klammern und Primaerausdruecke; Ergebnis in VAL/VTY/VFR.
; Einstellige Operatoren binden staerker als jeder zweistellige (sie rufen sich rekursiv selbst auf, nicht ex_expr), daher
; ist -2*3 = (-2)*3. `<x` = niederwertiges Byte, `>x` = zweites Byte (Bits 8..15) - wie in 6502-Assemblern ueblich.
ex_unary:
        jsr skipws
        jsr src_peek
        cmp #$2d                    ; -
        beq un_neg
        cmp #$2b                    ; +
        beq un_plus
        cmp #$21                    ; !
        beq un_not
        cmp #$7e                    ; ~
        beq un_inv
        cmp #$3c                    ; <
        beq un_lo
        cmp #$3e                    ; >
        beq un_hi
        cmp #$28                    ; (
        beq un_par
        jmp ex_primary
un_plus:
        jsr src_adv
        jmp ex_unary
un_neg: jsr src_adv
        jsr ex_unary
        jmp ex_neg_x
un_inv: jsr src_adv                 ; ~ bitweises Komplement (nur Ganzzahl)
        jsr ex_unary
        jsr need_int
        ldx #$00
        ldy #$04
ui1:    lda VAL,x
        eor #$ff                    ; alle 4 Bytes invertieren
        sta VAL,x
        inx
        dey
        bne ui1
        rts
un_not: jsr src_adv                 ; ! logisches Nicht: 1 wenn Operand 0 (auch bei Kommazahl/Liste), sonst 0
        jsr ex_unary
        jsr val_isnz                ; A = 0 wenn VAL == 0
        eor #$01
        jsr set_bool
        lda #$00
        sta VTY
        rts
un_lo:  jsr src_adv                 ; < Low-Byte: hoehere Bytes loeschen
        jsr ex_unary
        jsr need_int
        lda #$00
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        rts
un_hi:  jsr src_adv                 ; > High-Byte: Bits 8..15 nach unten, Rest 0 (nicht Bits 16..31)
        jsr ex_unary
        jsr need_int
        lda VAL + 1
        sta VAL
        lda #$00
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        rts
un_par: jsr src_adv                 ; ( Ausdruck ): neuer Ausdruck mit kleinstem Vorrang
        lda #$01
        jsr ex_expr
        jsr skipws
        jsr src_peek
        cmp #$29                    ; )
        beq up1
        lda #ERR_SYNTAX
        jmp ex_error
up1:    jmp src_adv                 ; `)` verbrauchen

; negate: 32-Bit-Zweierkomplement-Negation (0 - Wert) des Werts ab Zeropage-Adresse X (z. B. ldx #VAL). Veraendert A, X, Y.
; Die Basisseiten-Adressierung `$00,x` ist hier gewollt: X traegt die Zelladresse, daher gilt nur fuer Zeropage-Zellen.
negate: sec
        ldy #$04
ng1:    lda #$00
        sbc $00,x
        sta $00,x
        inx
        dey
        bne ng1
        rts

; val_isnz: A = 1 wenn VAL != 0, sonst 0 (Z gemaess A). Bei VTY = 1 zaehlt auch VFR;
; eine Liste (VTY = 2) zaehlt als wahr.
val_isnz:
        lda VAL
        ora VAL + 1
        ora VAL + 2
        ora VAL + 3
        ldx VTY
        cpx #$01
        bne vz0
        ora VFR
        ora VFR + 1
        ora VFR + 2
        ora VFR + 3
vz0:    cpx #$02
        beq vz2
        cmp #$00
        beq vz1
vz2:    lda #$01
vz1:    rts

; need_int: einstellige Bit-Operatoren gibt es nur fuer Ganzzahlen (E202 sonst)
need_int:
        lda VTY
        beq ni1
        lda #ERR_E202
        jmp ex_error
ni1:    rts

; lhs_isnz: wie val_isnz fuer den linken Operanden (LHS/LFR/LTY).
lhs_isnz:
        lda LHS
        ora LHS + 1
        ora LHS + 2
        ora LHS + 3
        ldx LTY
        cpx #$01
        bne lz0
        ora LFR
        ora LFR + 1
        ora LFR + 2
        ora LFR + 3
lz0:    cpx #$02
        beq lz2
        cmp #$00
        beq lz1
lz2:    lda #$01
lz1:    rts

; set_bool: VAL = A (0 oder 1) als 32-Bit-Ganzzahl; VTY setzt der Aufrufer. Veraendert A.
set_bool:
        sta VAL
        lda #$00
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        rts

; ex_primary: Primaerausdruck, danach beliebig viele Indizes/Ausschnitte `[..]` (nur Listen)
ex_primary:
        jsr ex_prim0
pp_l:   jsr src_peek
        cmp #$5b
        bne pp_d
        jsr ex_postfix
        jmp pp_l
pp_d:   rts

; ex_prim0: Zahl, Zeichen, Programmzaehler, Symbol, Listenliteral. Verzweigt am ersten Zeichen:
; $ % ' * [ , Ziffer, sonst Symbolname.
ex_prim0:
        lda #$00
        sta VTY                     ; Zahlen und Zeichen sind Ganzzahlen; Symbole und Aufrufe setzen VTY selbst
        jsr src_peek
        cmp #$24                    ; $
        beq pr_hex
        cmp #$25                    ; %
        beq pr_bin
        cmp #$27                    ; '
        beq pr_chr
        cmp #$2a                    ; *
        beq pr_pc
        cmp #$5b                    ; [ : Listenliteral
        bne pr_nl
        jmp lst_literal
pr_nl:  cmp #$30                    ; Ziffer 0..9?
        bcc pr_sym
        cmp #$3a
        bcs pr_sym
        cmp #$30                    ; 0x ?
        bne pr_dec
        jsr src_peek1
        cmp #$78                    ; x
        beq pr_0x
        cmp #$58                    ; X
        beq pr_0x
pr_dec: lda #10                     ; Dezimalzahl; danach prueft dec_float_tail auf `.5` / `e3` (Kommazahl)
        sta NBASE
        jsr num_digits
        jmp dec_float_tail          ; 2.5, 1e3, 1.5e-2
pr_0x:  jsr src_adv                 ; `0x` ueberspringen
        jsr src_adv
        jmp pr_hex2
pr_hex: jsr src_adv
pr_hex2:
        lda #16
        sta NBASE
        jmp num_digits
pr_bin: jsr src_adv
        lda #$02
        sta NBASE
        jmp num_digits
pr_chr: jsr src_adv                 ; 'c': Zeichenliteral, Wert = Code des Zeichens (Rohbyte, keine Umcodierung)
        jsr src_peek
        beq pr_synt                 ; Textende innerhalb des Literals
        sta VAL
        lda #$00
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        jsr src_adv
        jsr src_peek
        cmp #$27
        bne pr_synt
        jmp src_adv
pr_synt:
        lda #ERR_SYNTAX
        jmp ex_error
pr_pc:  jsr src_adv                 ; `*` als Wert: aktueller Programmzaehler (16 Bit)
        lda PC
        sta VAL
        lda PC + 1
        sta VAL + 1
        lda #$00
        sta VAL + 2
        sta VAL + 3
        rts
pr_sym: cmp #$2e                    ; . oder _ oder Buchstabe: Symbol (folgt mit der Symboltabelle)
        beq pr_sym2
        cmp #$5f
        beq pr_sym2
        ora #$20
        cmp #$61
        bcc pr_synt2
        cmp #$7b
        bcs pr_synt2
pr_sym2:                            ; Bezeichner einlesen (nach NAMEBUF/NAMELEN)
        jsr read_ident
        jsr src_peek
        cmp #$28                    ; Bezeichner direkt gefolgt von ( : Funktionsaufruf
        bne ps_nc
        jmp ex_call
ps_nc:  lda NAMEBUF
        cmp #$2e                    ; fuehrender Punkt = lokale Marke
        bne ps_look
        jsr mangle                  ; .name -> <globale Marke>.name
ps_look:
        jmp sym_lookup_ref
pr_synt2:
        lda #ERR_SYNTAX
        jmp ex_error

; num_digits: Ziffern der Basis NBASE (2, 10, 16) nach VAL einlesen (mindestens eine, sonst ERR_SYNTAX). SRC steht danach hinter
; der letzten Ziffer. Ueberlauf ueber 32 Bit wird nicht erkannt (Wert modulo 2^32). Veraendert A, X, Y, CNT, VAL, TMP.
num_digits:
        lda #$00
        sta VAL
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        sta CNT
nd1:    jsr src_peek
        jsr digval
        bcs nd2
        cmp NBASE                   ; Ziffer muss kleiner als die Basis sein (z. B. 9 in %-Zahl endet die Zahl)
        bcs nd2
        pha
        jsr val_mulbase
        pla
        jsr val_add8
        inc CNT
        jsr src_adv
        jmp nd1
nd2:    lda CNT
        bne nd3
        lda #ERR_SYNTAX
        jmp ex_error
nd3:    rts

; digval: A = Zeichen; liefert Carry geloescht und A = Wert 0..15 bei Hexziffer (0-9, a-f, A-F), sonst Carry gesetzt.
digval: cmp #$30
        bcc dv_bad
        cmp #$3a
        bcc dv_dec
        ora #$20                    ; Gross- in Kleinbuchstaben
        cmp #$61
        bcc dv_bad
        cmp #$67                    ; nur a..f
        bcs dv_bad
        sec
        sbc #$57                    ; 'a' - 10
        clc
        rts
dv_dec: sec
        sbc #$30
        clc
        rts
dv_bad: sec
        rts

; val_shl1: VAL um 1 Bit nach links (mal 2).
val_shl1:
        asl VAL
        rol VAL + 1
        rol VAL + 2
        rol VAL + 3
        rts

; val_mulbase: VAL = VAL * NBASE (16: 4 Schiebungen; 2: 1; sonst 10 = 2x + 8x). Veraendert A, X, Y, TMP.
val_mulbase:
        lda NBASE
        cmp #16
        beq vm16
        cmp #$02
        beq vm2
        jsr val_shl1                ; mal 10 = mal 2 + mal 8
        lda VAL
        sta TMP
        lda VAL + 1
        sta TMP + 1
        lda VAL + 2
        sta TMP + 2
        lda VAL + 3
        sta TMP + 3
        jsr val_shl1
        jsr val_shl1
        clc
        ldx #$00
        ldy #$04
vm1:    lda VAL,x
        adc TMP,x
        sta VAL,x
        inx
        dey
        bne vm1
        rts
vm16:   jsr val_shl1                ; mal 16 = 3 Schiebungen hier + 1 in vm2
        jsr val_shl1
        jsr val_shl1
vm2:    jmp val_shl1

; val_add8: VAL = VAL + A (A = 0..15), mit Uebertrag durch alle 4 Bytes.
val_add8:
        clc
        adc VAL
        sta VAL
        bcc va1
        inc VAL + 1
        bne va1
        inc VAL + 2
        bne va1
        inc VAL + 3
va1:    rts

; ex_apply: LHS (OPID) VAL -> VAL fuer zwei Ganzzahlen. Sprungtabelle: Kennung*2-2 (Kennungen beginnen bei 1) -> aptab.
; Die ap_*-Routinen erwarten LHS = linker, VAL = rechter Operand und liefern das Ergebnis in VAL (LHS darf zerstoert werden).
ex_apply:
        lda OPID
        asl
        tax
        jmp (aptab - 2,x)

; aptab: Rechenroutine je Kennung 1..18 (Reihenfolge wie ptab und ex_peekop)
aptab:  .word ap_oror, ap_andand, ap_eq, ap_ne, ap_lt, ap_le, ap_gt, ap_ge
        .word ap_or, ap_xor, ap_and, ap_shl, ap_shr, ap_add, ap_sub, ap_mul, ap_div, ap_mod

ap_oror:                            ; || und &&: beide Seiten werden bereits ausgewertet (keine Kurzschlussauswertung)
        jsr lhs_isnz
        sta TMP
        jsr val_isnz
        ora TMP
        jmp set_bool
ap_andand:
        jsr lhs_isnz
        sta TMP
        jsr val_isnz
        and TMP
        jmp set_bool

ap_or:  ldx #$00
        ldy #$04
ao1:    lda LHS,x
        ora VAL,x
        sta VAL,x
        inx
        dey
        bne ao1
        rts
ap_xor: ldx #$00
        ldy #$04
ax1:    lda LHS,x
        eor VAL,x
        sta VAL,x
        inx
        dey
        bne ax1
        rts
ap_and: ldx #$00
        ldy #$04
an1:    lda LHS,x
        and VAL,x
        sta VAL,x
        inx
        dey
        bne an1
        rts
ap_add: clc
        ldx #$00
        ldy #$04
ad1:    lda LHS,x
        adc VAL,x
        sta VAL,x
        inx
        dey
        bne ad1
        rts
ap_sub: sec
        ldx #$00
        ldy #$04
sb1:    lda LHS,x
        sbc VAL,x
        sta VAL,x
        inx
        dey
        bne sb1
        rts

; Vergleiche: cmp32 setzt CLT (LHS < VAL, vorzeichenbehaftet) und CEQ (LHS == VAL). Verfahren: LHS - VAL berechnen (Ergebnis
; nach TMP); vorzeichenbehaftet ist LHS < VAL, wenn N xor V = 1 (N = Bit 7 des Ergebnisses, V = Ueberlauf des letzten sbc).
; Aus CLT und CEQ ergeben sich alle sechs Vergleiche: <= = CLT|CEQ, > = nicht <=, >= = nicht CLT, != = nicht CEQ.
cmp32:  sec
        ldx #$00
        ldy #$04
cm1:    lda LHS,x
        sbc VAL,x                   ; 4-Byte-Subtraktion, Carry laeuft durch (sec vorab)
        sta TMP,x
        inx
        dey
        bne cm1
        lda TMP + 3                 ; V-Flag stammt vom letzten sbc
        bvc cm2                     ; bei Ueberlauf ist das Vorzeichenbit invertiert
        eor #$80
cm2:    and #$80
        beq cm3
        lda #$01
cm3:    sta CLT
        lda TMP
        ora TMP + 1
        ora TMP + 2
        ora TMP + 3
        beq cm4                     ; Differenz 0 -> A = 0 -> CEQ = 1
        lda #$01
cm4:    eor #$01                    ; A = 0 (gleich) -> 1, A = 1 (ungleich) -> 0
        sta CEQ
        rts
ap_lt:  jsr cmp32
        lda CLT
        jmp set_bool
ap_ge:  jsr cmp32
        lda CLT
        eor #$01
        jmp set_bool
ap_eq:  jsr cmp32
        lda CEQ
        jmp set_bool
ap_ne:  jsr cmp32
        lda CEQ
        eor #$01
        jmp set_bool
ap_le:  jsr cmp32
        lda CLT
        ora CEQ
        jmp set_bool
ap_gt:  jsr cmp32
        lda CLT
        ora CEQ
        eor #$01
        jmp set_bool

; shcount: Schiebezaehler aus VAL: X = A = min(VAL, 32) (Z-Flag gemaess A). 32 genuegt, um alles herauszuschieben; hoehere Bytes
; von VAL oder Werte > 32 werden darauf begrenzt (negative Zaehler = sehr gross = 32).
shcount:
        lda VAL + 1
        ora VAL + 2
        ora VAL + 3
        bne sc_big
        lda VAL
        cmp #33
        bcc sc_ok
sc_big: lda #32
sc_ok:  tax
        rts
ap_shl: jsr shcount                 ; LHS << VAL (logisch, Nullen von rechts)
        beq shl_d
shl_l:  asl LHS
        rol LHS + 1
        rol LHS + 2
        rol LHS + 3
        dex
        bne shl_l
shl_d:  jmp lhs_to_val
ap_shr: jsr shcount                 ; LHS >> VAL (arithmetisch: Vorzeichenbit wird nachgeschoben)
        beq shr_d
shr_l:  lda LHS + 3
        cmp #$80                    ; Carry = Vorzeichenbit (arithmetisches Schieben): CMP #$80 setzt C = (A >= $80)
        ror LHS + 3
        ror LHS + 2
        ror LHS + 1
        ror LHS
        dex
        bne shr_l
shr_d:  jmp lhs_to_val

; lhs_to_val: VAL = LHS (4 Byte kopieren); gemeinsamer Ausgang der Schiebeoperationen und der Division.
lhs_to_val:
        lda LHS
        sta VAL
        lda LHS + 1
        sta VAL + 1
        lda LHS + 2
        sta VAL + 2
        lda LHS + 3
        sta VAL + 3
        rts

; Multiplikation (untere 32 Bit): Shift-and-Add. Je Bit von VAL (niedrigstes zuerst, durch Rechtsschieben von VAL) wird das nach
; links wandernde LHS zur Summe in TMP addiert. Hoehere Ueberlaufbits entfallen (Ergebnis modulo 2^32). Das Vorzeichen
; ergibt sich im Zweierkomplement automatisch richtig. 32 Durchlaeufe (CNT).
ap_mul: lda #$00
        sta TMP
        sta TMP + 1
        sta TMP + 2
        sta TMP + 3
        lda #32
        sta CNT
mu1:    lsr VAL + 3                 ; niedrigstes Bit des Multiplikators ins Carry
        ror VAL + 2
        ror VAL + 1
        ror VAL
        bcc mu2
        clc
        ldx #$00
        ldy #$04
mu3:    lda TMP,x
        adc LHS,x
        sta TMP,x
        inx
        dey
        bne mu3
mu2:    asl LHS                     ; Multiplikand fuer die naechste Bitstelle verdoppeln
        rol LHS + 1
        rol LHS + 2
        rol LHS + 3
        dec CNT
        bne mu1
        lda TMP
        sta VAL
        lda TMP + 1
        sta VAL + 1
        lda TMP + 2
        sta VAL + 2
        lda TMP + 3
        sta VAL + 3
        rts

; divmod: Division und Rest: vorzeichenbehaftet, zur Null hin gerundet; Division durch 0 = E202.
; Eingang LHS = Dividend, VAL = Divisor. Ausgang: LHS = Quotient (Betrag), TMP = Rest (Betrag), SGNQ = Vorzeichen des Quotienten
; (Bit 7), SGNL = Vorzeichen des Dividenden (Bit 7; der Rest bekommt dessen Vorzeichen, wie in C). Beide Operanden werden
; zuerst zu Betraegen gemacht. Verfahren: schriftliche Division bitweise, 32 Durchlaeufe: Dividend (LHS) nach links in den
; Rest (TMP) schieben; wenn Rest >= Divisor, Divisor abziehen und das frei gewordene
; unterste Bit von LHS (= Quotientenbit) setzen.
; Zerstoert VAL (Betrag des Divisors) und TMP2.
divmod: jsr val_isnz
        bne dm0
        lda #ERR_E202
        jmp ex_error
dm0:    lda LHS + 3                 ; Vorzeichen merken, dann Betraege bilden
        and #$80
        sta SGNL
        lda LHS + 3
        eor VAL + 3
        and #$80
        sta SGNQ
        lda LHS + 3
        bpl dm1
        ldx #LHS
        jsr negate
dm1:    lda VAL + 3
        bpl dm2
        ldx #VAL
        jsr negate
dm2:    lda #$00
        sta TMP
        sta TMP + 1
        sta TMP + 2
        sta TMP + 3
        lda #32
        sta CNT
dm3:    asl LHS                     ; (LHS:TMP) um ein Bit nach links: oberstes Dividendenbit wird unterstes Restbit
        rol LHS + 1
        rol LHS + 2
        rol LHS + 3
        rol TMP
        rol TMP + 1
        rol TMP + 2
        rol TMP + 3
        sec                         ; TMP2 = TMP - VAL
        ldx #$00
        ldy #$04
dm4:    lda TMP,x
        sbc VAL,x
        sta TMP2,x
        inx
        dey
        bne dm4
        bcc dm5                     ; Rest < Divisor (Borgen): Quotientenbit 0, Rest unveraendert
        lda TMP2
        sta TMP
        lda TMP2 + 1
        sta TMP + 1
        lda TMP2 + 2
        sta TMP + 2
        lda TMP2 + 3
        sta TMP + 3
        inc LHS                     ; Quotientenbit setzen
dm5:    dec CNT
        bne dm3
        rts
ap_div: jsr val_isnz                ; Quotient: Divisor 0 -> div_zero (weich oder hart je nach PASS)
        bne ad_ok
        jmp div_zero
ad_ok:  jsr divmod
        jsr lhs_to_val              ; Quotient steht in LHS
        lda SGNQ
        beq dv1
        ldx #VAL
        jmp negate
dv1:    rts
ap_mod: jsr val_isnz                ; Rest (Modulo) mit Vorzeichen des Dividenden
        bne am_ok
        jmp div_zero
am_ok:  jsr divmod
        lda TMP
        sta VAL
        lda TMP + 1
        sta VAL + 1
        lda TMP + 2
        sta VAL + 2
        lda TMP + 3
        sta VAL + 3
        lda SGNL
        beq md1
        ldx #VAL
        jmp negate
md1:    rts

; div_zero: Division durch 0: im Einzeltest (PASS = 0) sofortiger Fehler E202, sonst weicher Fehler (soft_err, sym.asm) und
; Ergebnis bleibt VAL (der Aufrufer setzt es auf 0). Weich, weil der Divisor im ersten Durchlauf noch ein unbekanntes
; Vorwaertssymbol sein kann (Wert 0); erst am Ende des Durchlaufs wird der Fehler gemeldet.
div_zero:
        lda PASS
        bne dz1
        lda #ERR_E202
        jmp ex_error
dz1:    lda #ERR_E202
        jmp soft_err
