; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; list.asm - Listen im Ausdruck: [a, b, c], t[i], t[a:b], Liste + Liste, Liste * n, len(t), range(...) und die flache
; Ausgabe durch .byte/.word/.dword. Eine Liste ist ein Wert mit VTY = 2; VAL = Versatz des Listenblocks im Listenspeicher
; (Bank 4, HEAPBASE ff.): Block = Anzahl (2 Byte), dann je Element 9 Byte (Art, Ganzzahlteil 4, Nachkommateil 4).
; Listen werden nie veraendert: jede Rechnung legt einen neuen Block an. Der Speicher wird zu Beginn jedes Durchlaufs
; zurueckgesetzt; `x += [..]` haengt in place an, wenn die Liste zuoberst liegt und keine andere Variable sie benutzt.
;
; Rolle im Assembler:
;   Die Ausdrucksauswertung (expr.asm, numx.asm, func.asm) kennt Listen nur ueber diese Einsprungstellen:
;     lst_literal  (expr.asm, Primaerausdruck '[')      ex_postfix  (expr.asm, nach einem Primaerausdruck '[')
;     list_apply   (numx.asm, ex_apply_x: + und * mit Liste)     bi_len / bi_range (func.asm, Funktionen len/range)
;     l_pass       (asm.asm, je Durchlauf: Heap leeren)         fl_start / fl_next (asm.asm, .byte/.word/.dword mit Liste)
;   Ausserdem benutzt stage2.asm (.for ... in liste) l_open / l_get. Alle Ergebnisse stehen wie bei jedem Wert in
;   VTY/VAL/VFR (numx.asm): bei Listen ist VAL = Blockversatz (16 Bit), VAL + 2/+ 3 und VFR = 0.
;
; Speicherplan (Bank S2BANK von stage2.asm, im IDE-Build Bank 5, sonst 4; Adressen sind Versatze in dieser Bank):
;   $2000-$3FFF  Listen-Heap (8 KByte): wird nur nach oben belegt (ht = Stand), kein Freigeben ausser durch l_pass.
;   Listenblock:  +0/+1 Anzahl (16 Bit, tief zuerst), dann Anzahl * 9 Byte: Art (VTY des Elements), Wert (4), Nachkommateil (4).
;   Ein Element kann selbst eine Liste sein (Art 2, Wert = Blockversatz): Unterlisten werden nicht kopiert, nur verwiesen.
;   Der Argumentstapel (func.asm, ARGBASE) hat dasselbe 9-Byte-Format; lst_literal nutzt ihn als Zwischenspeicher.
;
; Zeropage/Register: P6 = Quellzeiger, P7 = Zielzeiger (je 32 Bit, Bank-Byte durch p6_load/p7_load gesetzt, [zp],z mit Z = 0
;   bzw. Z als Byteindex); S2T = 16-Bit-Hilfszelle; VAL/VFR/VTY = Wert; LHS/LTY = linker Operand; OPID = Operator.
;   Alle Hilfsvariablen (16 Bit, tief zuerst) stehen am Dateiende. Die Zeiger P6/P7 laufen nur mit 16 Bit weiter (Heap < 64 KByte).
; Fehler: ERR_E211 = Listenspeicher voll / zu tief / zu viele Elemente, ERR_E202 = falsche Art/Anzahl/Index, ERR_SYNTAX in
;   Klammern. Fehler brechen ueber ex_error ab (kehrt zur Ausdrucksauswertung zurueck und setzt Carry; nicht ueber RTS).
; =====================================================================================================================
HEAPBASE = $2000                    ; Anfang und Ende (exklusiv) des Listen-Heaps als Versatz in der Bank
HEAPEND  = $4000

; l_pass: Heap leeren; ruft asm_run (asm.asm) zu Beginn jedes Durchlaufs. Aendert A.
l_pass: lda #<HEAPBASE
        sta ht
        lda #>HEAPBASE
        sta ht + 1
        rts

; l_alloc: A/X = Groesse in Byte -> lnew = Versatz des neuen Blocks
; Eingabe: A = Low-, X = High-Byte der Groesse. Ausgabe: lnew = alter Heapstand, ht = neuer Stand. Fehler ERR_E211, wenn
; der Block nicht mehr bis HEAPEND passt (ht = HEAPEND ist noch erlaubt; Uebertrag der 16-Bit-Summe ebenfalls Fehler).
; Aendert A, S2T.
l_alloc:
        sta S2T
        stx S2T + 1
        lda ht
        sta lnew
        lda ht + 1
        sta lnew + 1
        clc
        lda ht
        adc S2T
        sta ht
        lda ht + 1
        adc S2T + 1
        sta ht + 1
        bcs la_full
        cmp #>HEAPEND
        bcc la_ok
        bne la_full
        lda ht
        bne la_full
la_ok:  rts
la_full:
        lda #ERR_E211
        jmp ex_error

; l_size: Anzahl lcnt -> A/X = 2 + lcnt * 9
; Rechnung: lcnt * 8 (drei Linksschiebungen) + lcnt = * 9, dann + 2 fuer den Kopf. Aendert S2T; Ausgabe A = Low, X = High.
l_size: lda lcnt
        sta S2T
        lda lcnt + 1
        sta S2T + 1
        asl S2T                     ; * 2
        rol S2T + 1
        asl S2T                     ; * 4
        rol S2T + 1
        asl S2T                     ; * 8
        rol S2T + 1
        clc
        lda S2T
        adc lcnt                    ; * 9
        sta S2T
        lda S2T + 1
        adc lcnt + 1
        sta S2T + 1
        clc
        lda S2T
        adc #$02                    ; + Kopf (Anzahl)
        pha
        lda S2T + 1
        adc #$00
        tax
        pla
        rts

; l_open: VAL = Liste -> lptr, lcnt; Carry gesetzt, wenn VTY keine Liste ist
; Eingabe: VTY, VAL (Blockversatz). Ausgabe: Carry geloescht: lptr = VAL (16 Bit), lcnt = Anzahl der Elemente; Carry gesetzt:
; keine Liste (lptr/lcnt unveraendert). Aendert A, X, Z, P6.
l_open: lda VTY
        cmp #$02
        beq lo1
        sec
        rts
lo1:    lda VAL
        sta lptr
        lda VAL + 1
        sta lptr + 1
        jsr l_ptr6
        ldz #$00
        lda [P6],z                  ; Anzahl aus dem Blockkopf
        sta lcnt
        inz
        lda [P6],z
        sta lcnt + 1
        clc
        rts

; l_ptr6: P6 = Zeiger auf den Block lptr in der Bank (p6_load setzt Bank-Byte und Megabyte-Byte). Aendert A, X.
l_ptr6: lda lptr                    ; P6 = Block lptr
        ldx lptr + 1
        jmp p6_load

; l_elem: lidx -> P6 = Adresse des Elements lidx von lptr
; Adresse = lptr + 2 + lidx * 9 (wie l_size: * 8 + * 1). Keine Bereichspruefung (der Aufrufer prueft lidx < lcnt).
; Eingabe: lptr, lidx. Aendert A, X, S2T, P6.
l_elem: lda lidx
        sta S2T
        lda lidx + 1
        sta S2T + 1
        asl S2T                     ; * 8
        rol S2T + 1
        asl S2T
        rol S2T + 1
        asl S2T
        rol S2T + 1
        clc
        lda S2T
        adc lidx                    ; * 9
        sta S2T
        lda S2T + 1
        adc lidx + 1
        sta S2T + 1
        clc
        lda S2T
        adc lptr                    ; + Blockanfang
        sta S2T
        lda S2T + 1
        adc lptr + 1
        sta S2T + 1
        clc
        lda S2T
        adc #$02                    ; + Kopf
        pha
        lda S2T + 1
        adc #$00
        tax
        pla
        jmp p6_load

; l_get: Element lidx von lptr -> VTY/VAL/VFR
; Aendert A, X, Z, S2T, P6. Das Element wird unveraendert uebernommen (auch Art 2 = Unterliste).
l_get:  jsr l_elem
        ldz #$00
        lda [P6],z                  ; Art
        sta VTY
        inz
        ldx #$00
ls_lg1:    lda [P6],z               ; Ganzzahlteil (4)
        sta VAL,x
        inz
        inx
        cpx #$04
        bne ls_lg1
        ldx #$00
ls_lg2:    lda [P6],z               ; Nachkommateil (4)
        sta VFR,x
        inz
        inx
        cpx #$04
        bne ls_lg2
        rts

; l_put: VTY/VAL/VFR -> Element bei P7 (9 Byte), P7 wird um 9 weitergesetzt
; Aendert A, X, Z, P7 (nur 16 Bit laufen weiter).
l_put:  ldz #$00
        lda VTY
        sta [P7],z
        inz
        ldx #$00
lp1:    lda VAL,x
        sta [P7],z
        inz
        inx
        cpx #$04
        bne lp1
        ldx #$00
lp2:    lda VFR,x
        sta [P7],z
        inz
        inx
        cpx #$04
        bne lp2
        clc
        lda P7
        adc #$09
        sta P7
        bcc lp3
        inc P7 + 1
lp3:    rts

; l_bytes: lbn Byte von P6 nach P7 kopieren (beide laufen weiter)
; Eingabe: lbn (16 Bit, wird auf 0 heruntergezaehlt), P6 = Quelle, P7 = Ziel. Byteweise, Z = 0; Quelle und Ziel duerfen
; nicht ueberlappen. Aendert A, Z, lbn, P6, P7 (jeweils nur die unteren 16 Bit).
l_bytes:
ls_lb1:    lda lbn
        ora lbn + 1
        beq lb9
        ldz #$00
        lda [P6],z
        sta [P7],z
        inc P6
        bne ls_lb2
        inc P6 + 1
ls_lb2:    inc P7
        bne ls_lb3
        inc P7 + 1
ls_lb3:    lda lbn                  ; lbn - 1 (16 Bit)
        bne ls_lb4
        dec lbn + 1
ls_lb4:    dec lbn
        jmp ls_lb1
lb9:    rts

; l_head: neuer Block lnew mit lcnt Elementen: Kopf schreiben, P7 = erste Elementstelle
; Eingabe: lcnt = Elementzahl. Ausgabe: lnew = Block, Kopf (Anzahl) geschrieben, P7 = Adresse des ersten Elements, das der
; Aufrufer anschliessend fuellt (l_put/l_bytes). Fehler ERR_E211 aus l_alloc. Aendert A, X, Z, S2T, P7.
l_head: jsr l_size
        jsr l_alloc
        lda lnew
        ldx lnew + 1
        jsr p7_load
        ldz #$00
        lda lcnt
        sta [P7],z
        inz
        lda lcnt + 1
        sta [P7],z
        clc
        lda P7
        adc #$02                    ; hinter den Kopf
        sta P7
        bcc lh1
        inc P7 + 1
lh1:    rts

; l_result: VAL = lnew, VTY = 2
; Macht den eben gebauten Block zum Wert: VAL = Versatz, VFR = 0, Art Liste. Aendert A.
l_result:
        lda lnew
        sta VAL
        lda lnew + 1
        sta VAL + 1
        lda #$00
        sta VAL + 2
        sta VAL + 3
        sta VFR
        sta VFR + 1
        sta VFR + 2
        sta VFR + 3
        lda #$02
        sta VTY
        rts

; ---- Listenliteral [a, b, ...]; SRC steht auf '['
; Die Elemente werden mit ex_expr (Mindestvorrang 1) ausgewertet und nacheinander auf den Argumentstapel gelegt (argpush,
; Zeiger asp). Der Stand von asp vor dem Literal liegt auf dem CPU-Stapel (Hi-Byte oben); am Ende ergibt sich die Anzahl aus
; (asp - Stand) / 9, der Block wird angelegt, die Elemente werden vom Argumentstapel hineinkopiert und asp zurueckgesetzt.
; Leere Liste [] und ein Komma vor ']' sind erlaubt. Ausgabe: VAL/VTY = neue Liste. Fehler: ERR_SYNTAX, ERR_E211 (Stapel/Heap).
lst_literal:
        jsr src_adv                 ; '[' verbrauchen
        lda asp                     ; asp vor den Elementen merken (CPU-Stapel, Reihenfolge: Low, High)
        pha
        lda asp + 1
        pha
        jsr skipws
        jsr src_peek
        cmp #$5d
        beq ll_done                 ; []
ll_l:   lda #$01
        jsr ex_expr                 ; ein Element (Wert in VTY/VAL/VFR)
        jsr argpush
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne ll_cl
        jsr src_adv
        jsr skipws
        jsr src_peek
        cmp #$5d                    ; Komma vor ] ist erlaubt
        beq ll_done
        jmp ll_l
ll_cl:  cmp #$5d
        beq ll_done
        lda #ERR_SYNTAX
        jmp ex_error
ll_done:
        jsr src_adv                 ; ']' verbrauchen
        pla
        sta lb + 1                  ; lb = asp-Stand vor dem Literal
        pla
        sta lb
        lda #$00                    ; Anzahl = (asp - lb) / 9
        sta lcnt
        sta lcnt + 1
        sec
        lda asp
        sbc lb
        sta S2T
        lda asp + 1
        sbc lb + 1
        sta S2T + 1
ll_c:   lda S2T                     ; durch wiederholtes Abziehen von 9 teilen (kein Divisionsbefehl)
        ora S2T + 1
        beq ll_cd
        sec
        lda S2T
        sbc #$09
        sta S2T
        lda S2T + 1
        sbc #$00
        sta S2T + 1
        inc lcnt
        bne ll_c
        inc lcnt + 1
        jmp ll_c
ll_cd:  jsr l_head                  ; Block anlegen, P7 = erste Elementstelle
        lda lb                      ; Elemente vom Argumentstapel kopieren
        ldx lb + 1
        jsr p6_load
        lda lcnt
        sta lbn
        lda lcnt + 1
        sta lbn + 1
        lda lbn                     ; lbn = lcnt * 9
        sta S2T
        lda lbn + 1
        sta S2T + 1
        asl lbn
        rol lbn + 1
        asl lbn
        rol lbn + 1
        asl lbn
        rol lbn + 1
        clc
        lda lbn
        adc S2T
        sta lbn
        lda lbn + 1
        adc S2T + 1
        sta lbn + 1
        jsr l_bytes
        lda lb                      ; Argumentstapel freigeben
        sta asp
        lda lb + 1
        sta asp + 1
        jmp l_result

; ---- Rechnen mit Listen (aus ex_apply_x): Liste + Liste, Liste * Zahl, Zahl * Liste
; Eingabe: LHS/LTY = linker, VAL/VTY = rechter Operand (mindestens einer ist eine Liste), OPID = Operator (14 = +, 16 = *).
; Ausgabe: VAL/VTY = neue Liste. Fehler ERR_E202 fuer jeden anderen Operator oder eine falsche Operandenart.
list_apply:
        lda OPID
        cmp #$0e
        beq lap_add
        cmp #$10
        beq lap_mul
lap_bad:
        lda #ERR_E202
        jmp ex_error
lap_add:
        lda LTY                     ; beide Seiten muessen Listen sein
        cmp #$02
        bne lap_bad
        lda VTY
        cmp #$02
        bne lap_bad
        lda VAL                     ; rechte Liste merken
        sta lr
        lda VAL + 1
        sta lr + 1
        lda LHS                     ; linke Liste nach VAL, damit l_open sie lesen kann
        sta VAL
        lda LHS + 1
        sta VAL + 1
        jsr l_open                  ; linke Liste: lptr, lcnt
        lda lptr
        sta ll1
        lda lptr + 1
        sta ll1 + 1
        lda lcnt
        sta lc1
        lda lcnt + 1
        sta lc1 + 1
        lda lr
        sta VAL
        lda lr + 1
        sta VAL + 1
        jsr l_open                  ; rechte Liste (VTY ist schon 2)
        lda lptr
        sta ll2
        lda lptr + 1
        sta ll2 + 1
        lda lcnt
        sta lc2
        lda lcnt + 1
        sta lc2 + 1
        clc                         ; Gesamtzahl
        lda lc1
        adc lc2
        sta lcnt
        lda lc1 + 1
        adc lc2 + 1
        sta lcnt + 1
        jsr l_head
        lda ll1                     ; linke Elemente
        clc
        adc #$02                    ; Quelle = Block + 2 (hinter dem Kopf)
        pha
        lda ll1 + 1
        adc #$00
        tax
        pla
        jsr p6_load
        lda lc1
        ldx lc1 + 1
        jsr l_times9                ; lbn = Bytezahl der linken Elemente
        jsr l_bytes
        lda ll2                     ; rechte Elemente (P7 steht schon hinter den linken)
        clc
        adc #$02
        pha
        lda ll2 + 1
        adc #$00
        tax
        pla
        jsr p6_load
        lda lc2
        ldx lc2 + 1
        jsr l_times9
        jsr l_bytes
        jmp l_result
lap_mul:
        lda LTY                     ; Liste * Zahl oder Zahl * Liste
        cmp #$02
        beq lm1
        lda VTY
        cmp #$02
        bne lap_bad                 ; weder links noch rechts eine Liste
        ldx #$03                    ; Zahl (LHS) steht links: tauschen
lm0:    lda LHS,x                   ; lr = Zahl (4 Byte)
        sta lr,x
        dex
        bpl lm0
        lda VAL                     ; LHS = Liste (nur die 2 niederwertigen Byte, mehr braucht l_open nicht)
        sta LHS
        lda VAL + 1
        sta LHS + 1
        lda lr                      ; VAL = Zahl
        sta VAL
        lda lr + 1
        sta VAL + 1
        lda lr + 2
        sta VAL + 2
        lda lr + 3
        sta VAL + 3
        lda LTY                     ; die Zahl darf keine Liste sein
        jmp lm2
lm1:    lda VTY
lm2:    cmp #$00
        bne lap_bad                 ; Festkomma-Wiederholung gibt es nicht
        lda VAL + 3
        bmi lap_bad                 ; negative Wiederholung
        lda VAL + 2
        ora VAL + 3
        bne lap_bad                 ; mehr als 65535
        lda VAL                     ; n = Wiederholungen
        sta lrep
        lda VAL + 1
        sta lrep + 1
        lda LHS                     ; Liste nach VAL fuer l_open
        sta VAL
        lda LHS + 1
        sta VAL + 1
        lda #$02
        sta VTY
        jsr l_open
        lda lcnt                    ; neue Anzahl = lcnt * n
        sta lc1                     ; lc1 = Anzahl der Originalliste (Kopiereinheit)
        lda lcnt + 1
        sta lc1 + 1
        lda #$00
        sta lcnt
        sta lcnt + 1
        lda lrep
        ora lrep + 1
        beq lm_go                   ; n = 0: leere Liste
lm_s:   clc                         ; lcnt += lc1, n-mal (Multiplikation durch Addition; Ueberlauf ueber 16 Bit wird nicht geprueft)
        lda lcnt
        adc lc1
        sta lcnt
        lda lcnt + 1
        adc lc1 + 1
        sta lcnt + 1
        lda lrep
        bne lm_d
        dec lrep + 1
lm_d:   dec lrep
        lda lrep
        ora lrep + 1
        bne lm_s
lm_go:  lda lptr
        sta ll1
        lda lptr + 1
        sta ll1 + 1
        lda VAL                     ; Wiederholungen neu lesen
        lda lcnt
        sta lc2                     ; lc2 = noch zu kopierende Elemente (Gesamtzahl)
        lda lcnt + 1
        sta lc2 + 1
        jsr l_head
        lda lc2                     ; nochmals n zaehlen: aus LHS-Zahl nicht mehr vorhanden -> ueber lcnt / lc1
        ora lc2 + 1
        beq lm_r
lm_cp:  lda ll1                     ; ein Durchgang: Quelle = Block + 2, lc1 Elemente
        clc
        adc #$02
        pha
        lda ll1 + 1
        adc #$00
        tax
        pla
        jsr p6_load
        lda lc1
        ldx lc1 + 1
        jsr l_times9
        jsr l_bytes
        sec                         ; lc2 -= lc1
        lda lc2
        sbc lc1
        sta lc2
        lda lc2 + 1
        sbc lc1 + 1
        sta lc2 + 1
        lda lc2
        ora lc2 + 1
        bne lm_cp                   ; bis alle lcnt Elemente geschrieben sind (n Durchgaenge)
lm_r:   jmp l_result

; l_times9: A/X = Anzahl -> lbn = Anzahl * 9
; Eingabe: A = Low-, X = High-Byte der Anzahl. Ausgabe: lbn (16 Bit). Aendert A, S2T. Kein Ueberlaufschutz.
l_times9:
        sta lbn
        stx lbn + 1
        sta S2T
        stx S2T + 1
        asl lbn                     ; * 8
        rol lbn + 1
        asl lbn
        rol lbn + 1
        asl lbn
        rol lbn + 1
        clc
        lda lbn
        adc S2T                     ; + * 1
        sta lbn
        lda lbn + 1
        adc S2T + 1
        sta lbn + 1
        rts

; ---- Index und Ausschnitt: nach einem Primaerausdruck folgt `[`
; ex_postfix: VAL/VTY = Wert (Liste), SRC steht auf '['
; Formen: t[i] (Element), t[a:b], t[:b], t[a:], t[:] (Ausschnitt [a, b), Python-Art). Negative Indizes zaehlen von hinten.
; Ausgabe: VTY/VAL/VFR = Element bzw. neue Teilliste. Fehler: ERR_E202 (kein Listenwert, Einzelindex ausserhalb),
; ERR_SYNTAX (Klammer). Arbeitszellen: lps = Liste, lia = Anfang, lib = Ende (exklusiv).
ex_postfix:
        lda VTY
        cmp #$02
        beq pf_l
        lda #ERR_E202               ; Indizieren nur bei Listen
        jmp ex_error
pf_l:   jsr src_adv                 ; '[' verbrauchen
        lda VAL                     ; Liste merken
        sta lps
        lda VAL + 1
        sta lps + 1
        jsr l_open                  ; lptr/lcnt (fuer die Indexpruefung)
        jsr skipws
        jsr src_peek
        cmp #$3a                    ; [:b]
        bne pf_i
        lda #$00                    ; Anfang fehlt: 0
        sta lia
        sta lia + 1
        jmp pf_colon
pf_i:   lda #$01
        jsr ex_expr
        jsr coerce_int
        jsr l_norm_index            ; lia = Index (0..lcnt, negativ von hinten)
        jsr skipws
        jsr src_peek
        cmp #$3a
        beq pf_colon
        cmp #$5d
        beq pf_one
        lda #ERR_SYNTAX
        jmp ex_error
pf_one: jsr src_adv                 ; Einzelindex: muss kleiner als lcnt sein
        lda lia + 1
        cmp lcnt + 1
        bcc pf_ok
        bne pf_oob
        lda lia
        cmp lcnt
        bcs pf_oob
pf_ok:  lda lia
        sta lidx
        lda lia + 1
        sta lidx + 1
        lda lps                     ; lptr zurueck auf die Liste (der Indexausdruck kann lptr veraendert haben)
        sta lptr
        lda lps + 1
        sta lptr + 1
        jsr l_get
        rts
pf_oob: lda #ERR_E202               ; Index ausserhalb der Liste
        jmp ex_error
pf_colon:
        jsr src_adv                 ; ':'
        jsr skipws
        jsr src_peek
        cmp #$5d
        bne pf_hi
        lda lcnt                    ; Ende fehlt: bis zum Ende der Liste
        sta lib
        lda lcnt + 1
        sta lib + 1
        jmp pf_close
pf_hi:  lda lia                     ; (lia ist durch den Ausdruck nicht gefaehrdet; trotzdem sichern)
        pha
        lda lia + 1
        pha
        lda #$01
        jsr ex_expr
        jsr coerce_int
        jsr l_norm_index
        lda lia
        sta lib
        lda lia + 1
        sta lib + 1
        pla
        sta lia + 1
        pla
        sta lia
pf_close:
        jsr skipws
        jsr src_peek
        cmp #$5d
        beq pf_c2
        lda #ERR_SYNTAX
        jmp ex_error
pf_c2:  jsr src_adv
        lda lps                     ; Ausschnitt [lia, lib)
        sta VAL
        lda lps + 1
        sta VAL + 1
        lda #$02
        sta VTY
        jsr l_open                  ; Liste neu oeffnen: lptr/lcnt koennen durch die Indexausdruecke veraendert sein
        lda lib + 1                 ; lib auf lcnt begrenzen
        cmp lcnt + 1
        bcc ps1
        bne ps0
        lda lib
        cmp lcnt
        bcc ps1
ps0:    lda lcnt
        sta lib
        lda lcnt + 1
        sta lib + 1
ps1:    lda lia + 1                 ; lia >= lib: leere Liste
        cmp lib + 1
        bcc ps2
        bne ps_e
        lda lia
        cmp lib
        bcc ps2
ps_e:   lda #$00
        sta lcnt
        sta lcnt + 1
        jsr l_head
        jmp l_result
ps2:    sec                         ; Anzahl = lib - lia
        lda lib
        sbc lia
        sta lc1
        lda lib + 1
        sbc lia + 1
        sta lc1 + 1
        lda lc1
        sta lcnt
        lda lc1 + 1
        sta lcnt + 1
        lda lptr
        sta ll1
        lda lptr + 1
        sta ll1 + 1
        jsr l_head
        lda lia                     ; Quelle = Block + 2 + lia * 9
        sta lidx
        lda lia + 1
        sta lidx + 1
        lda ll1
        sta lptr
        lda ll1 + 1
        sta lptr + 1
        jsr l_elem
        lda lc1
        ldx lc1 + 1
        jsr l_times9
        jsr l_bytes
        jmp l_result

; l_norm_index: VAL (ganz) -> lia: negativ zaehlt von hinten, Ergebnis begrenzt auf 0..lcnt (fuer Ausschnitte);
; ein Einzelindex wird danach auf < lcnt geprueft
; Tatsaechliches Verhalten: VAL >= 0 und <= 65535 -> lia = VAL; VAL negativ -> lia = lcnt + VAL (nur untere 16 Bit gerechnet),
; wird das Ergebnis dabei negativ, sowie bei VAL > 65535, setzt die Routine lia = $FFFF ("unmoegliche Grenze": beim
; Einzelindex Fehler E202, beim Ausschnitt ein leerer Bereich bzw. durch die Begrenzung lib <= lcnt erst im Aufrufer).
; Eingabe: VAL (32 Bit, vorzeichenbehaftet), lcnt. Aendert A, lia.
l_norm_index:
        lda VAL + 3
        bpl ni_pos
        clc                         ; lcnt + VAL (VAL negativ)
        lda VAL
        adc lcnt
        sta lia
        lda VAL + 1
        adc lcnt + 1
        sta lia + 1
        lda VAL + 3                 ; (ohne Wirkung) wird lia negativ, folgt unten lia = $FFFF (nicht 0)
        lda lia + 1
        bpl ni_ok
        lda #$ff                    ; weit ausserhalb: unmoegliche Grenze
        sta lia
        sta lia + 1
        rts
ni_pos: lda VAL + 2
        ora VAL + 3
        beq ni_c
        lda #$ff                    ; ueber 65535: ebenfalls unmoegliche Grenze
        sta lia
        sta lia + 1
        rts
ni_c:   lda VAL
        sta lia
        lda VAL + 1
        sta lia + 1
ni_ok:  rts

; ---- len(liste), range(...)
; bi_len: Funktion len(t): genau 1 Argument, das eine Liste ist (sonst ERR_E202). Ausgabe: VAL = Anzahl, VTY = 0 (Ganzzahl).
; Aufruf aus func.asm: fnargs = Argumentzahl, die Argumente stehen auf dem Argumentstapel (arg_get).
bi_len: lda fnargs
        cmp #$01
        beq bln1
        lda #ERR_E202
        jmp ex_error
bln1:   lda #$00
        jsr arg_get
        jsr l_open
        bcc bln2
        lda #ERR_E202
        jmp ex_error
bln2:   lda lcnt
        sta VAL
        lda lcnt + 1
        sta VAL + 1
        lda #$00
        sta VAL + 2
        sta VAL + 3
        sta VTY
        rts

; range(n) / range(a, b) / range(a, b, schritt) als Liste (hoechstens 65536 Elemente, aber auch durch den Listenspeicher begrenzt)
; Tatsaechliche Grenze: der Zaehler bricht bei 1024 Elementen mit ERR_E211 ab; durch den 8-KByte-Heap sind es real hoechstens
; 910. Ablauf: Argumente in rga (Anfang, Vorgabe 0), rgb (Ende), rgs (Schritt, Vorgabe 1) holen; Schritt 0 -> ERR_E202;
; zuerst die Elemente zaehlen (rgc = laufender Wert, bra_more/bra_step), dann Block anlegen und ein zweites Mal durchlaufen
; und mit l_put schreiben. Alle Werte sind 32-Bit-Ganzzahlen (coerce_int), das Ende ist ausgeschlossen (wie in Python).
; Ausgabe: VAL/VTY = Liste; Fehler ERR_E202 (Argumentzahl nicht 1..3, Schritt 0).
bi_range:
        lda fnargs
        beq bra_bad
        cmp #$04
        bcs bra_bad
        sta fi
        lda #$00                    ; Anfang 0, Schritt 1
        ldx #$03
br0:    sta rga,x
        sta rgs,x
        dex
        bpl br0
        lda #$01
        sta rgs
        lda fi
        cmp #$01
        bne ls_br1
        lda #$00                    ; range(n): Ende = Argument 0
        jsr bra_arg
        ldx #$03
ls_br2:    lda VAL,x
        sta rgb,x
        dex
        bpl ls_br2
        jmp bra_go
ls_br1:    lda #$00                 ; range(a, b [, s]): Argument 0 = Anfang, 1 = Ende, 2 = Schritt
        jsr bra_arg
        ldx #$03
br3:    lda VAL,x
        sta rga,x
        dex
        bpl br3
        lda #$01
        jsr bra_arg
        ldx #$03
ls_br4:    lda VAL,x
        sta rgb,x
        dex
        bpl ls_br4
        lda fi
        cmp #$03
        bne bra_go
        lda #$02
        jsr bra_arg
        ldx #$03
br5:    lda VAL,x
        sta rgs,x
        dex
        bpl br5
bra_go: lda rgs
        ora rgs + 1
        ora rgs + 2
        ora rgs + 3
        bne br6
        lda #ERR_E202               ; Schritt 0
        jmp ex_error
br6:    lda #$00                    ; Elemente zaehlen: cur = a; solange (s > 0 ? cur < b : cur > b)
        sta lcnt
        sta lcnt + 1
        ldx #$03
br7:    lda rga,x
        sta rgc,x
        dex
        bpl br7
br8:    jsr bra_more
        bcs ls_br9                  ; Bereich erschoepft
        inc lcnt
        bne br8a
        inc lcnt + 1
br8a:   lda lcnt + 1
        cmp #$04                    ; Obergrenze: Listenspeicher
        bcs bra_big
        jsr bra_step
        jmp br8
ls_br9:    jsr l_head               ; Block fuer lcnt Elemente, P7 = erste Elementstelle
        ldx #$03
br10:   lda rga,x                   ; zweiter Durchlauf von vorn
        sta rgc,x
        dex
        bpl br10
br11:   jsr bra_more
        bcs br12
        ldx #$03
br13:   lda rgc,x                   ; Element = rgc (Ganzzahl, Art 0, Nachkommateil 0 bleibt VFR)
        sta VAL,x
        dex
        bpl br13
        lda #$00
        sta VTY
        jsr l_put
        jsr bra_step
        jmp br11
br12:   jmp l_result
bra_big:
        lda #ERR_E211
        jmp ex_error
bra_bad:
        lda #ERR_E202
        jmp ex_error

bra_arg:                            ; Argument A als Ganzzahl nach VAL
        jsr arg_get
        jmp coerce_int

bra_step:                           ; rgc += rgs
        clc
        ldx #$00
        ldy #$04
bs_l:   lda rgc,x
        adc rgs,x
        sta rgc,x
        inx
        dey
        bne bs_l
        rts

bra_more:                           ; Carry geloescht, wenn rgc noch im Bereich liegt
        ldx #$03                    ; LHS = rgc, VAL = rgb; vorzeichenbehafteter Vergleich ueber ex_apply (OPID 5 bzw. 7)
ls_bm_l:   lda rgc,x
        sta LHS,x
        lda rgb,x
        sta VAL,x
        dex
        bpl ls_bm_l
        lda #$00
        sta LTY
        sta VTY
        lda rgs + 3
        bmi bm_neg
        lda #$05                    ; < : weiter solange cur < b
        bne ls_bm_go
bm_neg: lda #$07                    ; > : bei negativem Schritt weiter solange cur > b
ls_bm_go:  sta OPID
        jsr ex_apply
        lda VAL                     ; Ergebnis 0/1
        beq bm_end
        clc
        rts
bm_end: sec
        rts

; ---- flache Ausgabe (.byte, .word, .dword): Elemente in Reihenfolge, Unterlisten werden aufgeloest
; fl_start: VAL = Liste. fl_next: Carry geloescht = naechstes Blattelement in VTY/VAL/VFR; gesetzt = fertig
; Zustand: ein Stapel von bis zu 8 Listen (fl_d = oberste Tiefe 0..7); je Tiefe ls_fl_lo/fl_hi = Blockversatz,
; fl_ixl/fl_ixh = naechster Index, fl_cl/fl_ch = Anzahl. Ein Element der Art 2 (Unterliste) wird eine Tiefe hoeher gelegt,
; ist eine Liste erschoepft, geht es eine Tiefe zurueck (Tiefensuche). Mehr als 8 Ebenen: ERR_E211 (ueber as_error,
; weil fl_next in Direktiven, nicht in Ausdruecken, laeuft). Aendert A, X, Z, P6, lptr, lidx, S2T.
fl_start:
        lda #$00
        sta fl_d
fl_push:
        ldx fl_d                    ; Liste VAL auf der Tiefe fl_d anmelden
        lda VAL
        sta ls_fl_lo,x
        sta lptr
        lda VAL + 1
        sta fl_hi,x
        sta lptr + 1
        lda #$00
        sta fl_ixl,x
        sta fl_ixh,x
        jsr l_ptr6
        ldz #$00
        ldx fl_d                    ; (l_ptr6/p6_load hat X veraendert)
        lda [P6],z                  ; Anzahl aus dem Blockkopf
        sta fl_cl,x
        inz
        lda [P6],z
        sta fl_ch,x
        rts

fl_next:
fn_l:   ldx fl_d
        lda fl_ixh,x                ; Index < Anzahl ? sonst Liste erschoepft
        cmp fl_ch,x
        bcc fn_have
        bne fn_pop
        lda fl_ixl,x
        cmp fl_cl,x
        bcs fn_pop
fn_have:
        lda ls_fl_lo,x              ; Element lesen: lptr/lidx setzen, Index weiterzaehlen
        sta lptr
        lda fl_hi,x
        sta lptr + 1
        lda fl_ixl,x
        sta lidx
        lda fl_ixh,x
        sta lidx + 1
        inc fl_ixl,x
        bne fn_i
        inc fl_ixh,x
fn_i:   jsr l_get
        lda VTY
        cmp #$02
        bne fn_leaf                 ; Blattelement: liefern
        lda fl_d                    ; Unterliste: eine Ebene tiefer
        cmp #$07
        bcc fn_dn
        lda #ERR_E211
        jmp as_error
fn_dn:  inc fl_d
        jsr fl_push
        jmp fn_l
fn_leaf:
        clc
        rts
fn_pop: lda fl_d                    ; Liste erschoepft: bei Tiefe 0 ganz fertig, sonst eine Ebene zurueck
        beq fn_end
        dec fl_d
        jmp fn_l
fn_end: sec
        rts

; ---- Daten
ht:     .word 0                     ; Heapstand (naechste freie Stelle)
lnew:   .word 0                     ; zuletzt angelegter Block
lptr:   .word 0                     ; Block der geoeffneten Liste
lcnt:   .word 0                     ; Elementzahl der geoeffneten bzw. neuen Liste
lidx:   .word 0                     ; Elementnummer fuer l_elem/l_get
lbn:    .word 0                     ; Bytezahl fuer l_bytes
lb:     .word 0                     ; Argumentstapel-Stand vor einem Listenliteral
lr:     .fill 4, 0                  ; rechter Operand / Zahl beim Tauschen (list_apply)
ll1:    .word 0                     ; Block der ersten (linken) Liste
ll2:    .word 0                     ; Block der zweiten (rechten) Liste
lc1:    .word 0                     ; Elementzahl der ersten Liste
lc2:    .word 0                     ; Elementzahl der zweiten Liste (bzw. Restzahl bei Liste * n)
lps:    .word 0                     ; ex_postfix: die indizierte Liste
lia:    .word 0                     ; Anfangsindex
lib:    .word 0                     ; Endindex (exklusiv)
lrep:   .word 0                     ; Wiederholungszahl bei Liste * n
rga:    .fill 4, 0                  ; range: Anfang
rgb:    .fill 4, 0                  ; range: Ende (ausgeschlossen)
rgs:    .fill 4, 0                  ; range: Schritt
rgc:    .fill 4, 0                  ; range: laufender Wert
fl_d:   .byte 0                     ; flache Ausgabe: aktuelle Tiefe 0..7
ls_fl_lo:  .fill 8, 0               ; je Tiefe: Blockversatz (Low)
fl_hi:  .fill 8, 0                  ;             Blockversatz (High)
fl_ixl: .fill 8, 0                  ;             naechster Index (Low)
fl_ixh: .fill 8, 0                  ;             naechster Index (High)
fl_cl:  .fill 8, 0                  ;             Anzahl (Low)
fl_ch:  .fill 8, 0                  ;             Anzahl (High)
