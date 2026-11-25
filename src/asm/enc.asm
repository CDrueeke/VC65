; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; enc.asm - Operanden lesen, Adressierungsart waehlen, Befehl ausgeben (45GS02).
; Eingabe: MN_PTR zeigt auf den Eintrag in mn_table (nach mn_find), SRC hinter dem Mnemonik.
; Ausgabe: Bytes ueber emit_byte nach [OUTP] (PC wird mitgezaehlt). Fehler: Sprung nach as_error mit Fehlercode.
; Regeln (aus vcc geprueft): plain-Operanden waehlen Zeropage, wenn der Wert bekannt ist und 0..255 betraegt (und der
; Befehl die Form hat), sonst absolut; unbekannte Symbole (erster Durchlauf) gelten als gross.
;
; Rolle im Assembler: asm.asm liest je Quelltextzeile Marke und Mnemonik, sucht das Mnemonik mit mn_find (mnfind.asm, Tabelle in
; optab.asm), setzt SUF/QUAD aus Befehlssuffix und Tabellenflag und ruft hier parse_operand (Operandenform erkennen, Ausdruecke
; ueber ex_eval aus expr.asm auswerten) und encode (Adressierungsart waehlen, Bytes ausgeben). encode ruft cyc_add (cyc.asm)
; und long_check (.branchlong auto). Symbole kommen ueber sym.asm (nur fuer anonyme Marken - und +, siehe anon_ref).
;
; Ablauf je Befehl (zwei Stufen, damit die Wahl von der Syntaxform unabhaengig von der Befehlsliste bleibt):
;   1. parse_operand: PMODE (Syntaxform P_*), OPVAL (erster Wert), OPVAL2 (zweiter Wert, nur BBR/BBS), UNK, PFX32.
;   2. choose_mode: aus PMODE und den Modenlisten des Befehls (optab.asm) MODEID (Adressierungsart M_*) und OPCODE.
;   3. encode: Praefixe ($42 $42 fuer Q-Befehle, $EA fuer 32-Bit-Zeiger), Opcode, Operandenbytes via emit_byte.
;
; Zeropage (zp.asm): PMODE, MODEID, OPCODE, QUAD, PFX32, SUF, UNK, OPVAL/OPVAL2 (je 32 Bit), MDP (Zeiger auf die Modenliste),
; TMP/TMP2 als Arbeitszellen, OUTP (32-Bit-Ausgabezeiger, Zugriff [OUTP],z) und PC (16 Bit, wird mit OUTP gleichlaufend gezaehlt).
; UNK = 1 heisst: der Ausdruck benutzt ein noch unbekanntes Symbol (im ersten Durchlauf normal); dann wird absolut/gross
; angenommen und der Wertebereich nicht geprueft; im letzten Durchlauf ist jeder Wert bekannt und wird geprueft.
; Fehlerkonvention: harte Fehler springen mit A = Code nach as_error (bricht die Zeile ab, kehrt nicht zurueck); weiche Fehler
; (Wertebereich E203, E214) laufen ueber soft_err (= err_add): Meldung vermerken, aber weiter uebersetzen; nur die Meldungen
; des letzten Durchlaufs zaehlen (err.asm).
; Carry-Konvention der kleinen Helfer (md_has, try_mode, byte_val, rel_fits, sym-Aufrufe): C=0 = Ja/gefunden, C=1 = Nein.
; =====================================================================================================================
; Syntaxformen (PMODE): was der Operand rein textlich ist, ohne Rueckblick auf den Befehl
P_IMP  = 0                          ; kein Operand
P_ACC  = 1                          ; A
P_IMM  = 2                          ; #wert
P_PLAIN = 3                         ; wert
P_X    = 4                          ; wert,x
P_Y    = 5                          ; wert,y
P_IND  = 6                          ; (wert)
P_INDY = 7                          ; (wert),y
P_INDZ = 8                          ; (wert),z
P_INDX = 9                          ; (wert,x)
P_ISY  = 10                         ; (wert,sp),y
P_BR   = 11                         ; [wert] oder [wert],z  (32-Bit-Zeiger)
P_ZPR  = 12                         ; wert,wert (BBR/BBS)

; opval_from_val: OPVAL = VAL (Ergebnis der Ausdrucksauswertung uebernehmen). Zerstoert A.
opval_from_val:
        lda VAL
        sta OPVAL
        lda VAL + 1
        sta OPVAL + 1
        lda VAL + 2
        sta OPVAL + 2
        lda VAL + 3
        sta OPVAL + 3
        rts

; eval_op: Ausdruck lesen, Ergebnis nach OPVAL. Fehler im Ausdruck (Carry gesetzt von ex_eval): Abbruch ueber as_fail.
; Zerstoert A, X, Y und die Ausdruckszellen (VAL, LHS, TMP ...). UNK wird von ex_eval gesetzt (nie geloescht).
eval_op:
        jsr ex_eval
        bcc eo1
        jmp as_fail
eo1:    jmp opval_from_val

; expect_char: Zeichen A muss folgen (nach Leerraum), wird verbraucht, sonst Syntaxfehler. Zerstoert A, TMP.
expect_char:
        pha
        jsr skipws
        jsr src_peek
        sta TMP
        pla
        cmp TMP
        beq ec1
        lda #ERR_SYNTAX
        jmp as_error
ec1:    jmp src_adv

; at_eol: Z gesetzt, wenn am Zeilenende (0, LF, CR oder ;). Zerstoert A. Die Pruefung auf "//" macht is_cmt2 (src.asm) im Rueckflug.
at_eol: jsr src_peek
        beq ae1
        cmp #$0a
        beq ae1
        cmp #$0d
        beq ae1
        cmp #$3b
        beq ae1
        jmp is_cmt2                 ; // beginnt ebenfalls einen Kommentar
ae1:    rts

; parse_operand: Operandenform erkennen und Werte lesen.
;   Eingabe : SRC hinter dem Mnemonik (ggf. nach Befehlssuffix), QUAD (Q-Befehl: dann ist auch "q" ein Akkumulatorname)
;   Ausgabe : PMODE = P_*; OPVAL (+ OPVAL2 bei P_ZPR); UNK = 1, wenn ein Wert unbekannt ist; PFX32 = 1 bei [wert]-Form
;   Zerstoert: A, X, Y, VAL, TMP und alle Ausdruckszellen; Fehler: as_error/as_fail.
;   Erkennung am ersten Zeichen: '#' Immediate, '(' Klammerformen, '[' 32-Bit-Zeiger, a/q Akkumulator, sonst Ausdruck
;   (danach ',x' ',y' oder ',wert' fuer BBR/BBS).
parse_operand:
        lda #$00
        sta UNK
        sta PFX32
        jsr skipws
        jsr at_eol
        bne po1
        lda #P_IMP
        sta PMODE
        rts
po1:    jsr src_peek
        cmp #$23                    ; #
        bne po2
        jsr src_adv
        jsr eval_op
        lda #P_IMM
        sta PMODE
        rts
po2:    cmp #$28                    ; (
        beq po_par
        cmp #$5b                    ; [
        beq po_br
        ; Akkumulator: nach Kleinschreibung ($20 setzen) steht 'a'=$61, 'q'=$71 in A; 'q' nur bei Q-Befehlen (aslq q)
        ora #$20                    ; Akkumulator: einzelnes A (bei Q-Befehlen auch Q: aslq q)
        cmp #$61
        beq po_acc
        cmp #$71
        bne po_plain
        ldx QUAD
        beq po_plain
po_acc:
        ; Ein einzelnes a/q ist nur dann Akkumulator, wenn kein Bezeichnerzeichen folgt (sonst Symbol wie "abc")
        jsr src_peek1
        jsr is_identchar
        bcc po_plain                ; A gefolgt von Bezeichnerzeichen: Symbol
        jsr src_adv
        lda #P_ACC
        sta PMODE
        rts
        ; Ausdruck. Sonderfall: ein einzelnes '-' oder '+' ist eine anonyme Marke (z. B. "bne -", "bra ++"), kein Vorzeichen
po_plain:
        jsr src_peek
        cmp #$2d
        beq pl_an
        cmp #$2b
        bne pl_ev
pl_an:  jsr src_peek
        ; pl_sg = erstes Zeichen. Zeichen DAHINTER entscheidet: Ende/gleiches Zeichen/Leerraum/Komma/; -> anonyme Marke, sonst Ausdruck
        sta pl_sg
pl_a1:  jsr src_peek1               ; - oder + allein (Leerraum, Komma, Zeilenende danach): anonyme Marke
        beq pl_ref
        cmp pl_sg                   ; --, ++ ...: wie ein einzelnes Zeichen, die Anzahl zaehlt anon_ref
        beq pl_ref
        cmp #$20
        beq pl_ref
        cmp #$09
        beq pl_ref
        cmp #$0a
        beq pl_ref
        cmp #$0d
        beq pl_ref
        cmp #$3b
        beq pl_ref
        cmp #$2c
        bne pl_ev
pl_ref: jsr anon_ref
        jmp pl_after
pl_ev:  jsr eval_op
pl_after:
        jsr skipws
        jsr src_peek
        cmp #$2c                    ; ,
        beq po_comma
        lda #P_PLAIN
        sta PMODE
        rts
        ; Nach ',' : x -> P_X, y -> P_Y, sonst zweiter Ausdruck (BBR/BBS: "bbr0 zp,ziel")
po_comma:
        jsr src_adv
        jsr skipws
        jsr src_peek
        ora #$20
        cmp #$78                    ; x
        beq po_x
        cmp #$79                    ; y
        beq po_y
        lda UNK                     ; zweiter Ausdruck (BBR/BBS): Wert merken
        pha
        jsr eval_op_2
        pla
        ora UNK
        sta UNK
        lda #P_ZPR
        sta PMODE
        rts
po_x:   jsr src_adv
        lda #P_X
        sta PMODE
        rts
po_y:   jsr src_adv
        lda #P_Y
        sta PMODE
        rts
; eval_op_2: zweiten Wert nach OPVAL2 lesen (OPVAL bleibt erhalten; UNK wird hier nicht zurueckgesetzt). Zerstoert A, X.
;   eval_op ueberschreibt OPVAL, daher wird OPVAL vorher auf dem Stapel gerettet und danach zurueckgeholt.
eval_op_2:
        lda OPVAL
        pha
        lda OPVAL + 1
        pha
        lda OPVAL + 2
        pha
        lda OPVAL + 3
        pha
        jsr eval_op
        ldx #$03
e2a:    lda OPVAL,x
        sta OPVAL2,x
        dex
        bpl e2a
        pla
        sta OPVAL + 3
        pla
        sta OPVAL + 2
        pla
        sta OPVAL + 1
        pla
        sta OPVAL
        rts
        ; [wert] oder [wert],z: 32-Bit-Zeigerform; das ",z" ist optional und aendert nichts (der Befehl bekommt Praefix $EA)
po_br:  jsr src_adv                 ; [wert] oder [wert],z
        jsr eval_op
        lda #$5d                    ; ]
        jsr expect_char
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne pb1
        jsr src_adv
        jsr skipws
        jsr src_peek
        ora #$20
        cmp #$7a                    ; z
        beq pb2
        lda #ERR_SYNTAX
        jmp as_error
pb2:    jsr src_adv
pb1:    lda #$01
        sta PFX32
        lda #P_BR
        sta PMODE
        rts
        ; '(': Klammerformen (wert) (wert),y (wert),z (wert,x) (wert,sp),y
        ; Der Ausdruck in der Klammer wird ohne Klammer-Sonderbehandlung ausgewertet; ex_eval hoert am ',' oder ')' auf.
po_par: jsr src_adv
        jsr eval_op
        jsr skipws
        jsr src_peek
        cmp #$2c                    ; (wert, ...
        beq pp_comma
        lda #$29                    ; )
        jsr expect_char
        jsr skipws
        jsr src_peek
        cmp #$2c
        beq pp_after
        lda #P_IND
        sta PMODE
        rts
pp_after:
        jsr src_adv
        jsr skipws
        jsr src_peek
        ora #$20
        cmp #$79
        beq pp_y
        cmp #$7a
        beq pp_z
        lda #ERR_SYNTAX
        jmp as_error
pp_y:   jsr src_adv
        lda #P_INDY
        sta PMODE
        rts
pp_z:   jsr src_adv
        lda #P_INDZ
        sta PMODE
        rts
        ; (wert,... : x -> (wert,x); s -> (wert,sp),y  (Stapelzeiger-relativ, nur mit anschliessendem ,y)
pp_comma:
        jsr src_adv
        jsr skipws
        jsr src_peek
        ora #$20
        cmp #$78
        beq pc_x
        cmp #$73                    ; s -> sp
        beq pc_sp
        lda #ERR_SYNTAX
        jmp as_error
pc_x:   jsr src_adv
        lda #$29
        jsr expect_char
        lda #P_INDX
        sta PMODE
        rts
pc_sp:  jsr src_adv                 ; s
        jsr src_peek
        ora #$20
        cmp #$70                    ; p
        beq pc_p
        lda #ERR_SYNTAX
        jmp as_error
pc_p:   jsr src_adv
        lda #$29
        jsr expect_char
        lda #$2c
        jsr expect_char
        jsr skipws
        jsr src_peek
        ora #$20
        cmp #$79
        beq pc_y
        lda #ERR_SYNTAX
        jmp as_error
pc_y:   jsr src_adv
        lda #P_ISY
        sta PMODE
        rts

; md_has: pruefen, ob der Befehl die Adressierungsart kennt (ohne Seiteneffekte auf MODEID/OPCODE).
;   Eingabe : A = Modenkennung M_*, MN_PTR = Eintrag in mn_table
;   Ausgabe : C=0 und A = Opcode, wenn vorhanden; sonst C=1
;   Zerstoert: X, Y, TMP, MDP. Modenliste (optab.asm): [Anzahl][Modus, Opcode]*Anzahl; MDP zeigt darauf (Wort im Eintrag, Offset 5).
md_has: sta TMP
        ldy #$05
        lda (MN_PTR),y
        sta MDP
        iny
        lda (MN_PTR),y
        sta MDP + 1
        ldy #$00
        lda (MDP),y                 ; Anzahl
        beq mh_no
        tax
        iny
mh_l:   lda (MDP),y
        cmp TMP
        beq mh_yes
        iny
        iny
        dex
        bne mh_l
mh_no:  sec
        rts
mh_yes: iny
        lda (MDP),y
        clc
        rts

; try_mode: Art waehlen, wenn vorhanden. Eingabe: A = Modenkennung. Ausgabe: C=0: MODEID und OPCODE gesetzt; C=1: nicht vorhanden
;   (MODEID/OPCODE unveraendert). Zerstoert A, X, Y, TMP, MDP.
try_mode:
        pha
        jsr md_has
        bcs tm_no
        sta OPCODE
        pla
        sta MODEID
        clc
        rts
tm_no:  pla
        sec
        rts

; byte_val: Carry geloescht wenn OPVAL bekannt (UNK = 0) und im Bereich 0..255 (Zeropage geeignet). Zerstoert A.
byte_val:
        lda UNK
        bne bv_no
        lda OPVAL + 1
        ora OPVAL + 2
        ora OPVAL + 3
        bne bv_no
        clc
        rts
bv_no:  sec
        rts

; zp_or_abs: Zeropage- oder absolute Form waehlen. Eingabe: Y = Zeropage-Art, X = absolute Art (M_*), SUF.
;   Suffix .z (SUF = 1) erzwingt Zeropage, .a (SUF = 2) absolut: fehlt die Form, E215. Ohne Suffix: Zeropage, wenn der Wert
;   bekannt und 0..255 ist und der Befehl die Form hat; sonst absolut (unbekannte Werte gelten als gross); hat der Befehl nur
;   eine der beiden Formen, wird diese genommen (Bereichspruefung spaeter in encode). Ausgabe: C=0 gewaehlt, C=1 keine Form.
;   Zerstoert A, X, Y, TMP, TMP2, MDP.
zp_or_abs:
        stx TMP2
        sty TMP2 + 1
        lda SUF
        beq zs_auto
        cmp #$01
        bne zs_abs
        lda TMP2 + 1                ; .z: Zeropage erzwingen
        jsr try_mode
        bcs zs_fail
        rts
zs_abs: lda TMP2                    ; .a: absolut erzwingen
        jsr try_mode
        bcs zs_fail
        rts
zs_fail:
        lda #ERR_E215
        jmp as_error
        ; automatisch: bekannter Wert 0..255 -> zuerst Zeropage; sonst zuerst absolut, danach (Rueckfall) die andere Form
zs_auto:
        jsr byte_val
        bcs za_abs
        lda TMP2 + 1
        jsr try_mode
        bcc za_ok
za_abs: lda TMP2
        jsr try_mode
        bcc za_ok
        lda TMP2 + 1
        jsr try_mode
za_ok:  rts

; choose_mode: Adressierungsart zu PMODE und Befehl waehlen (MODEID, OPCODE); E206, wenn keine passt.
;   Sprungverteiler ueber cmtab (Wort-Tabelle in P_*-Reihenfolge, daher PMODE * 2 als Index). Je Syntaxform eine kleine Routine
;   cm_*, die mit try_mode die in Frage kommenden M_*-Arten in Prioritaetsreihenfolge probiert. Zerstoert A, X, Y u. a.
choose_mode:
        lda PMODE
        asl
        tax
        jmp (cmtab,x)
; Reihenfolge exakt wie P_IMP .. P_ZPR (siehe oben); neue Syntaxform: hier und bei den P_*-Konstanten ergaenzen
cmtab:  .word cm_imp, cm_acc, cm_imm, cm_plain, cm_x, cm_y, cm_ind, cm_indy, cm_indz, cm_indx, cm_isy, cm_br, cm_zpr
cm_fail:
        lda #ERR_E206
        jmp as_error
        ; ohne Operand: implizit, sonst Akkumulator (z. B. "asl" = "asl a")
cm_imp: lda #M_IMP
        jsr try_mode
        bcc cm_done
        lda #M_ACC
        jsr try_mode
        bcs cm_fail
cm_done:
        rts
cm_acc: lda #M_ACC
        jsr try_mode
        bcs cm_fail
        rts
        ; #wert: 8 Bit (M_IMM) oder, wenn nur vorhanden, 16 Bit (M_IMW, nur PHW)
cm_imm: lda #M_IMM
        jsr try_mode
        bcc cm_done
        lda #M_IMW
        jsr try_mode
        bcs cm_fail
        rts
        ; "wert" ohne Zusatz: erst relativer Sprung (Bxx); lange relative Form (BSR, LBxx) nur, wenn der Befehl weder abs noch zp
        ; kennt (sonst waere z. B. JMP/JSR gemeint); sonst Zeropage oder absolut
cm_plain:
        lda #M_REL
        jsr try_mode
        bcc cm_done
        lda #M_ABS                  ; lange Sprungform (Rl) nur, wenn der Befehl weder abs noch zp kennt
        jsr md_has
        bcc cm_pz
        lda #M_ZP
        jsr md_has
        bcc cm_pz
        lda #M_RL
        jsr try_mode
        bcc cm_done
cm_pz:  ldx #M_ABS
        ldy #M_ZP
        jsr zp_or_abs
        bcs cm_fail
        rts
cm_x:   ldx #M_ABX
        ldy #M_ZPX
        jsr zp_or_abs
        bcs cm_fail
        rts
cm_y:   ldx #M_ABY
        ldy #M_ZPY
        jsr zp_or_abs
        bcs cm_fail
        rts
        ; (wert): indirekt (JMP); bei Q-Befehlen ist "(wert)" gleich "(wert),z" (Quad-Indirektform M_IZZ)
cm_ind: lda #M_IND
        jsr try_mode
        bcc cm_done
        lda QUAD
        beq cm_fail
        lda #M_IZZ
        jsr try_mode
        bcs cm_fail
        rts
cm_indy:
        lda #M_IZY
        jsr try_mode
        bcs cm_fail
        rts
cm_indz:
        lda #M_IZZ
        jsr try_mode
        bcs cm_fail
        rts
        ; (wert,x): Zeropage-indiziert-indirekt (zp,x) oder bei JMP/JSR absolut (abs,x)
cm_indx:
        lda #M_IZX
        jsr try_mode
        bcc cm_done
        lda #M_IAX
        jsr try_mode
        bcs cm_fail
        rts
cm_isy: lda #M_ISY
        jsr try_mode
        bcs cm_fail
        rts
        ; [wert]: 32-Bit-Zeiger = (zp),z mit Praefix $EA
cm_br:  lda #M_IZZ
        jsr try_mode
        bcs cm_fail
        rts
cm_zpr: lda #M_ZPR
        jsr try_mode
        bcs cm_fail
        rts

; emit_byte: A nach [OUTP] schreiben, OUTP (32 Bit) und PC (16 Bit) um 1 weiter.
;   Ausgabe: A, X, Y bleiben erhalten; Z = 0 (Z-Register wird zerstoert, ldz #0 fuer [OUTP],z). Vor dem ersten .org (orgs = 0): E300.
emit_byte:
        pha                         ; vor dem ersten .org darf nichts ausgegeben werden (E300); X bleibt erhalten (emit_word)
        lda orgs
        bne eb0
        lda #ERR_E300
        jmp as_error
eb0:    lda segon                   ; .segment aktiv: die echte Ausgabeadresse muss im Bereich seglo..seghi liegen, sonst E301 (wie vcc)
        beq eb_sok
        lda PC                      ; echte Adresse = PC, in einer .pseudopc-Region psreal + (OUTP - psout)
        sta segpc
        lda PC + 1
        sta segpc + 1
        lda pson
        beq eb_sc
        sec
        lda OUTP
        sbc psout
        sta segpc
        lda OUTP + 1
        sbc psout + 1
        sta segpc + 1
        clc
        lda segpc
        adc psreal
        sta segpc
        lda segpc + 1
        adc psreal + 1
        sta segpc + 1
eb_sc:  lda segpc + 1
        cmp seglo + 1
        bcc eb_sbad
        bne eb_shi
        lda segpc
        cmp seglo
        bcc eb_sbad
eb_shi: lda seghi + 1
        cmp segpc + 1
        bcc eb_sbad
        bne eb_sok
        lda seghi
        cmp segpc
        bcs eb_sok
eb_sbad: lda #ERR_E301
        jmp as_error
eb_sok:  lda segwrap                ; PC ist von $FFFF auf 0 uebergelaufen: weitere Ausgabe E301 (Segment ueberschreitet $FFFF, wie vcc)
        beq eb_nw
        lda #ERR_E301
        jmp as_error
eb_nw:  pla
        ldz #$00
        ; [OUTP],z: 32-Bit-Zeigerzugriff der 45GS02 (Z = Offset)
        sta [OUTP],z
        inc OUTP
        bne eb1
        inc OUTP + 1
        bne eb1
        inc OUTP + 2
eb1:    inc PC
        bne eb2
        inc PC + 1
        bne eb2
        lda #$01                    ; PC hat $FFFF ueberschritten
        sta segwrap
eb2:    rts

; .segment-Zustand (d_segment in asm.asm): segon = 1 mit Bereich seglo..seghi (16 Bit je)
segon:  .byte 0
segwrap: .byte 0                    ; 1 = PC von $FFFF auf 0 uebergelaufen (je Durchlauf und .org zurueckgesetzt)
seglo:  .word 0
seghi:  .word 0
segpc:  .word 0                     ; echte Ausgabeadresse bei der Pruefung (Zwischenwert)

; emit_word: 16-Bit-Wert little-endian ausgeben: A = tiefes Byte, X = hohes Byte. Zerstoert A.
emit_word:
        jsr emit_byte
        txa
        jmp emit_byte

; range_byte: Wert als Byte pruefen (nur wenn bekannt, UNK = 0): erlaubt -128..255 (vorzeichenlos oder als zweierkomplement-Byte);
;   sonst weicher Fehler E203. Vorzeichenerweiterung: obere 3 Bytes alle 0 oder alle $FF und bei $FF Bit 7 von OPVAL gesetzt.
;   Zerstoert A.
range_byte:
        lda UNK
        bne rb_ok
        lda OPVAL + 1
        ora OPVAL + 2
        ora OPVAL + 3
        beq rb_ok                   ; 0..255
        lda OPVAL + 1
        and OPVAL + 2
        and OPVAL + 3
        cmp #$ff
        bne rb_bad
        lda OPVAL
        bmi rb_ok                   ; -128..-1
rb_bad: lda #ERR_E203
        jmp soft_err
rb_ok:  rts

; range_word: wie range_byte fuer 16 Bit: erlaubt -32768..65535 (obere 2 Bytes 0, oder $FFFF mit Bit 7 von OPVAL+1 gesetzt)
range_word:
        lda UNK
        bne rw_ok
        lda OPVAL + 2
        ora OPVAL + 3
        beq rw_ok
        lda OPVAL + 2
        and OPVAL + 3
        cmp #$ff
        bne rw_bad
        lda OPVAL + 1
        bmi rw_ok
rw_bad: lda #ERR_E203
        jmp soft_err
rw_ok:  rts

; rel_offset: Sprungweite berechnen. Eingabe: X = Abstand von PC zum Ende des Befehls, OPVAL = Ziel. Ausgabe: TMP/TMP+1 =
;   OPVAL - (PC + X), 16 Bit vorzeichenbehaftet. PC steht hinter dem bereits ausgegebenen Opcode (PC = Opcode + 1).
;   Zerstoert A, TMP/TMP+1 (hohe Bytes von OPVAL werden ignoriert).
rel_offset:
        txa
        clc
        adc PC
        sta TMP
        lda PC + 1
        adc #$00
        sta TMP + 1
        sec
        lda OPVAL
        sbc TMP
        sta TMP
        lda OPVAL + 1
        sbc TMP + 1
        sta TMP + 1
        rts

; encode: Befehl ausgeben (PMODE, OPVAL, OPVAL2, UNK, PFX32, QUAD, SUF gesetzt; MN_PTR gueltig). Reihenfolge der Bytes:
;   [$42 $42 bei Q-Befehl] [$EA bei 32-Bit-Zeiger] Opcode [Operand]. Zerstoert alle Register und TMP/TMP2.
encode: jsr long_check
        jsr choose_mode
        lda SUF                     ; Suffix .z/.a gilt nur fuer Zeropage- und absolute Formen (M_ZP..M_ABY), sonst E215 (wie vcc)
        beq en_sf
        lda MODEID
        cmp #M_ZP
        bcc en_sx
        cmp #M_IND
        bcc en_sf
en_sx:  lda #ERR_E215
        jmp as_error
en_sf:
        ; Praefixe: Q-Befehle sind NEG NEG ($42 $42) vor dem Opcode des 32-Bit-Befehls; $EA = EOM/NOP-Praefix fuer ([zp]),z
        lda QUAD
        beq en1
        lda #$42
        jsr emit_byte
        lda #$42
        jsr emit_byte
en1:    lda PFX32
        beq en2
        lda #$ea
        jsr emit_byte
        ; Zyklenzaehlung nur einmal je Befehl (nach den Praefixen, mit dem eigentlichen Opcode)
en2:    lda OPCODE
        jsr cyc_add                 ; .cycles: Zyklen des Befehls zaehlen
        lda OPCODE
        jsr emit_byte
        ; Verzweigung nach Operandenbreite der gewaehlten Art
        lda MODEID
        cmp #M_IMP
        beq en_done
        cmp #M_ACC
        beq en_done
        cmp #M_IMM
        beq en_imm
        cmp #M_IMW
        beq en_w
        cmp #M_ABS
        beq en_w
        cmp #M_ABX
        beq en_w
        cmp #M_ABY
        beq en_w
        cmp #M_IND
        beq en_w
        cmp #M_IAX
        beq en_w
        cmp #M_REL
        beq en_rel
        cmp #M_RL
        beq en_rl
        cmp #M_ZPR
        beq en_zpr
        ; alle uebrigen (zp, zp,x, zp,y, (zp,x), (zp),y, (zp),z, (d,sp),y): ein Byte, 0..255
        jsr byte_chk
        lda OPVAL
        jmp emit_byte
en_imm: jsr range_byte
        lda OPVAL
        jmp emit_byte
en_w:   jsr range_word
        lda OPVAL
        ldx OPVAL + 1
        jmp emit_word
        ; (en_rel) Basis = PC + 1: Ende des 2-Byte-Befehls (Opcode steht schon)
en_rel: ldx #$01                    ; relativ zum Befehlsende: PC steht hinter dem Opcode, Basis = PC + 1
        jsr rel_offset
        jsr rel_range
        lda TMP
        jmp emit_byte
        ; (en_rl) 16-Bit-Sprung: 3-Byte-Befehl; die 45GS02 bezieht den Versatz auf Opcode + 2, also ebenfalls PC + 1
en_rl:  ldx #$01
        jsr rel_offset
        lda TMP
        ldx TMP + 1
        jmp emit_word
        ; (en_zpr) BBRn/BBSn zp,ziel: Bytes Opcode, zp, Versatz; Versatz relativ zum Befehlsende (Opcode + 3)
en_zpr: lda OPVAL
        sta TMP2                    ; Zeropage-Adresse
        lda UNK
        pha
        ldx #$03
ez1:    lda OPVAL2,x
        sta OPVAL,x
        dex
        bpl ez1
        ldx #$02                    ; relativ zum Befehlsende: Basis = PC + 2 (Zeropage-Byte folgt noch)
        jsr rel_offset
        jsr rel_range
        lda TMP2
        jsr emit_byte
        pla
        lda TMP
        jmp emit_byte
en_done:
        rts

; byte_chk: Zeropage-Operand muss bekannt 0..255 sein, sonst weicher Fehler E203 (unbekannt: erlaubt, UNK = 1). Zerstoert A.
byte_chk:
        lda UNK
        bne bc_ok
        lda OPVAL + 1
        ora OPVAL + 2
        ora OPVAL + 3
        beq bc_ok
        lda #ERR_E203
        jmp soft_err
bc_ok:  rts

; rel_range: Sprungweite in TMP/TMP+1 muss -128..127 sein, sonst weicher Fehler E203 (unbekannt: nicht pruefen). Zerstoert A.
rel_range:
        lda UNK
        bne rr_ok
        lda TMP + 1
        beq rr_pos
        cmp #$ff
        bne rr_bad
        lda TMP
        bmi rr_ok
rr_bad: lda #ERR_E203
        jmp soft_err
rr_pos: lda TMP
        bpl rr_ok
        jmp rr_bad
rr_ok:  rts

; anon_ref: anonyme Marke als Operand: "-" = letzte zurueckliegende Marke, "--" zweitletzte; "+" = naechste vorwaerts, "++" uebernaechste.
;   Ausgabe: OPVAL = Adresse; Zeichen werden verbraucht. Symbolname fuer die Tabelle (sym.asm): NAMEBUF = [Vorzeichenzeichen]
;   [Nummer], NAMELEN = 2; die Nummer ist der laufende Zaehler der Marken derselben Sorte (NEGN fuer '-', POSN fuer '+', beide
;   im Durchlauf, siehe asm.asm). Fuer '-': Nummer = NEGN - n + 1; fuer '+': POSN + n (n = Anzahl gleicher Zeichen).
;   Keine passende Marke: '-' zu weit zurueck: sofort E214 (as_error); '+' ohne Marke: weicher Fehler E214.
anon_ref:
        jsr src_peek
        sta ar_sgn
        ; ar_n = Zahl der gleichen Zeichen (X: bei jedem Zeichen +1); das Zeichen hinter der Kette entscheidet nichts mehr
        ldx #$00                    ; Zahl der gleichen Zeichen (-- = zweitletzte Marke, ++ = uebernaechste)
ar_cnt: inx
        stx ar_n
        jsr src_adv
        jsr src_peek
        cmp ar_sgn
        bne ar_cd
        ldx ar_n
        jmp ar_cnt
ar_cd:  lda ar_sgn
        cmp #$2d
        bne ar_plus
        lda NEGN
        sec
        sbc ar_n
        ; (Carry geloescht = Unterlauf, NEGN < n: so weit zurueck gibt es keine Marke)
        bcc ar_err                  ; so weit zurueck gibt es keine Marke `-`
        clc
        adc #$01
        sta NAMEBUF + 1
        lda #$2d
        jmp ar_go
ar_plus:
        lda POSN
        clc
        adc ar_n
        sta NAMEBUF + 1
        lda #$2b
ar_go:  sta NAMEBUF
        lda #$02
        sta NAMELEN
        lda NAMEBUF
        cmp #$2d
        beq ar_back
        ; '+': Vorwaertsmarke ist noch nicht definiert; Wert aus dem vorigen Durchlauf (unbekannt -> UNK = 1, Wert 0)
        jsr sym_known_old           ; `+`: Marke weiter unten, Wert aus dem vorigen Durchlauf
        bcs ar_none
        jmp opval_from_val
ar_back:
        ; '-': Rueckwaertsmarke in diesem Durchlauf schon definiert -> neuer Wert
        jsr sym_find                ; `-`: Marke weiter oben, in diesem Durchlauf schon definiert (neuer Wert)
        bcs ar_none
        jsr sym_getnew
        jmp opval_from_val
        ; Marke nicht gefunden: Wert 0, UNK = 1 (damit der erste Durchlauf weiterlaeuft), E214 als weicher Fehler
ar_none:
        lda #$01
        sta UNK
        lda #$00
        sta VAL
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        lda #ERR_E214
        jsr soft_err
        jmp opval_from_val
ar_err: lda #ERR_E214
        jmp as_error
; Daten: ar_sgn = Vorzeichenzeichen der anonymen Marke, ar_n = Anzahl, pl_sg = erstes Zeichen in parse_operand
ar_sgn: .byte 0
ar_n:   .byte 0
pl_sg:  .byte 0

; rel_fits: C=0, wenn TMP/TMP+1 (16 Bit, vorzeichenbehaftet) in -128..127 liegt; sonst C=1. Zerstoert A.
rel_fits:
        lda TMP + 1
        beq rf_pos
        cmp #$ff
        bne rf_no
        lda TMP
        bmi rf_yes
rf_no:  sec
        rts
rf_pos: lda TMP
        bpl rf_yes
        bne rf_no
rf_yes: clc
        rts

; long_check: .branchlong auto: Verzweigungsbefehle (Bxx mit M_REL, Operand "wert", ohne Q-Praefix/32-Bit-Zeiger), die nicht
;   reichen, werden zur langen Form (LBxx, M_RL); einmal lang, immer lang (sonst wuerde das Ergebnis zwischen Durchlaeufen
;   schwanken). Je Verzweigung ein Merkbyte in der Tabelle der langen Spruenge (BITP, bit_ptr aus asm.asm; Index BIDX).
;   Zu weit: Merkbyte = 1, CHG = 1 (weiterer Durchlauf erzwungen), dann sofort die lange Form nehmen. Ist der Operand noch
;   unbekannt (UNK), wird kurz angenommen.  Ist BLONG = 0, kehrt die Routine sofort zurueck. Zerstoert A, X, Y, Z, TMP und MN_TOK/MN_PTR.
long_check:
        lda BLONG
        beq lc_no
        lda PMODE
        cmp #P_PLAIN
        bne lc_no
        lda QUAD
        ora PFX32
        bne lc_no
        lda #M_REL
        jsr md_has
        bcs lc_no                   ; kein Verzweigungsbefehl
        jsr bit_ptr
        ldz #$00
        lda [BITP],z
        bne lc_long                 ; schon als lang vermerkt
        lda UNK
        bne lc_inc
        ; PC steht noch am Befehlsanfang (Opcode nicht ausgegeben): Befehlsende = PC + 2
        ldx #$02                    ; Weite zum Befehlsende (PC steht noch am Befehlsanfang)
        jsr rel_offset
        jsr rel_fits
        bcc lc_inc
        lda #$01
        sta [BITP],z                ; zu weit: lang vermerken, nochmal uebersetzen
        sta CHG
lc_long: lda #WARN_W203
        jsr warn_add                ; Sprung zu weit: lange Form (W203, wie vcc)
        inc BIDX
        bne lc_l2
        inc BIDX + 1
        ; Name um ein Zeichen nach rechts schieben und 'L' ($4c) voranstellen (BNE -> LBNE), dann neu suchen; fehlt der Name: E206
lc_l2:  lda MN_TOK + 2              ; L + Name: LBNE, LBRA, ...
        sta MN_TOK + 3
        lda MN_TOK + 1
        sta MN_TOK + 2
        lda MN_TOK
        sta MN_TOK + 1
        lda #$4c
        sta MN_TOK
        jsr mn_find
        bcc lc_no
        lda #ERR_E206
        jmp as_error
lc_inc: inc BIDX
        bne lc_no
        inc BIDX + 1
lc_no:  rts
