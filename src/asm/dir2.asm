; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; dir2.asm - weitere Direktiven der Stufe 2: .page, .pseudopc/.endpseudopc/.realpc, .fill und .lohifill mit Laufvariable,
; .struct/.endstruct, .enum/.endenum. Die Erweiterungen von .rta (Liste) und .basicstub (Zeilennummer, Kommentar)
; stehen in asm.asm.
;
; Rolle im Assembler:
;   Die Direktiven werden von asm.asm ueber die Namenstabelle (dir_build/dir_find) in eine Kennung uebersetzt und ueber die
;   Sprungtabelle dirjmp aufgerufen (d_page, d_pseudopc, d_endpseudopc, d_fill, d_lohifill, d_struct, d_endstruct, d_enum,
;   d_endenum, d_assert, d_error, d_warning). Beim Einsprung steht SRC hinter dem Direktivennamen; jede Direktive endet
;   mit "jmp d_end" (prueft das Zeilenende und geht zur naechsten Zeile) oder "jmp al_line" (Zeilenschleife).
;   Fehler gehen ueber as_error (kehrt nicht zurueck; Fehlercode in A) bzw. soft_err (weicher Fehler, es geht weiter).
;   .page rechnet den neuen Programmzaehler und springt nach do1 (asm.asm, gemeinsamer Teil von .org: setzt PC, fuellt auf).
;   Konstanten und Variablen legt das Modul ueber sym_define (sym.asm: Konstanten, Wert pro Durchlauf) bzw. var_new/var_setval
;   (stage2.asm: .var-Variablen in Bank S2BANK, Tabelle ab VARBASE bis vare) an.
;
; Datenstrukturen:
;   Symboltabelle (sym.asm, Attic $0810_0000): Eintrag = Namenslaenge, Name, alter Wert (4), neuer Wert (4), Flags (1), also
;     Laenge + 10 Byte. struct_fields geht sie mit P7 durch.
;   .struct Name: legt "Name.feld" = Versatz, bei Strukturfeldern auch "Name.feld.unterfeld" und am Ende "Name.size" an.
;   .enum Name:   legt "Name.eintrag" = laufende Nummer (oder expliziter Wert, danach zaehlt es dort weiter) an.
;   nb/nbl: Namenspuffer (bis 31 Zeichen) zum Zusammensetzen qualifizierter Namen aus Teilen.
;
; Zeropage/Speicher: benutzt VAL, LHS, TMP2, OPID (Rechenwerk ex_apply), SRC, NAMEBUF/NAMELEN, LNAME/LLEN (Name der aktuellen
;   .struct/.enum/Laufvariable), P6/P7 (32-Bit-Zeiger [zp],z), S2T (16-Bit-Hilfszelle), PC, OUTP, FILLN ($9c/$9d, asm.asm).
;   Alle Hilfsvariablen stehen am Dateiende unter "Daten". Z-Register: Byteindex in Symbol- und Variableneintraegen.
; Invarianten: SRC wird nach jedem Blocklesen (.fill, .enum, .struct) auf eine definierte Stelle gesetzt (fvend bzw. Zeilenanfang);
;   .pseudopc kann nicht verschachtelt werden (psreal/psout gelten nur fuer eine Ebene; pson wird je Durchlauf in s2_pass geloescht).
; =====================================================================================================================
DID_ENDSTRUCT = 48                  ; Direktivenkennungen (Index in der Tabelle von asm.asm), fuer das Blockende beim Zeilenlesen
DID_ENDENUM   = 50

; ---- .page [n]: naechstes Vielfaches von n (Vorgabe 256), ohne Sonderbehandlung wie .org
; Eingabe: SRC hinter ".page", optional ein Ausdruck n. Wirkung: PC := PC aufgerundet auf ein Vielfaches von n, wie .org
; (vorwaerts mit Nullbytes aufgefuellt; do1 in asm.asm). Rechnung (32 Bit, ueber ex_apply mit OPID 18 = %, 15 = -, 14 = +):
; Rest = PC % n; ist er 0, bleibt PC; sonst neuer PC = PC + (n - Rest). n = 0 ergibt Division durch 0 (Fehler im Rechenwerk).
d_page: jsr skipws
        jsr at_eol
        beq pg_def                  ; kein Argument: Vorgabe 256
        jsr eval_val
        jmp pg_go
pg_def: lda #$00
        sta VAL
        lda #$01
        sta VAL + 1
        lda #$00
        sta VAL + 2
        sta VAL + 3
pg_go:  lda VAL                     ; .page 0 (und > 16 Bit): E203 wie vcc, nicht Division durch 0
        ora VAL + 1
        beq pg_bad
        lda VAL + 2
        ora VAL + 3
        beq pg_ok
pg_bad: lda #ERR_E203
        jmp as_error
pg_ok:  ldx #$03                    ; n merken (die Division benutzt TMP2)
pg_n:   lda VAL,x
        sta pgn,x
        dex
        bpl pg_n
        lda PC                      ; LHS = PC (16 Bit, obere Bytes 0)
        sta LHS
        lda PC + 1
        sta LHS + 1
        lda #$00
        sta LHS + 2
        sta LHS + 3
        lda #$12                    ; PC % n
        sta OPID
        jsr ex_apply
        lda VAL                     ; Rest = 0 ?
        ora VAL + 1
        ora VAL + 2
        ora VAL + 3
        bne pg_up
        lda PC                      ; schon passend
        sta VAL
        lda PC + 1
        sta VAL + 1
        lda #$00
        sta VAL + 2
        sta VAL + 3
        jmp do1                     ; neuer PC = alter PC (do1 setzt PC und fuellt auf)
pg_up:  ldx #$03                    ; n - Rest
pg_u:   lda pgn,x                   ; LHS = n, VAL = Rest -> VAL = n - Rest
        sta LHS,x
        dex
        bpl pg_u
        lda #$0f
        sta OPID
        jsr ex_apply
        jsr cp_val_lhs              ; LHS = n - Rest
        lda PC                      ; VAL = PC; PC + (n - Rest) = neue Adresse
        sta VAL
        lda PC + 1
        sta VAL + 1
        lda #$00
        sta VAL + 2
        sta VAL + 3
        lda #$0e
        sta OPID
        jsr ex_apply
        jmp do1

; cp_tmp2_lhs: LHS := TMP2 (4 Byte). Aendert A, X.
cp_tmp2_lhs:
        ldx #$03
c2l1:   lda TMP2,x
        sta LHS,x
        dex
        bpl c2l1
        rts

; ---- .pseudopc adresse / .endpseudopc / .realpc
; .pseudopc: ab hier wird Code fuer die Adresse VAL uebersetzt (PC = VAL), liegt aber weiter fortlaufend in der Ausgabe.
; Gemerkt werden die echte PC (psreal) und der Ausgabestand (psout), je 16 Bit; pson = 1 solange die Region offen ist.
; Eingabe: SRC hinter der Direktive (Ausdruck = pseudo-Adresse). Aendert A, VAL-Auswertung (eval_val).
d_pseudopc:
        jsr eval_val
        lda PC
        sta psreal
        lda PC + 1
        sta psreal + 1
        lda OUTP
        sta psout
        lda OUTP + 1
        sta psout + 1
        lda #$01
        sta pson
        lda VAL
        sta PC
        lda VAL + 1
        sta PC + 1
        jmp d_end

; d_endpseudopc: (auch .realpc) beendet die Region. Ohne offene Region geschieht nichts. Aendert A, S2T.
d_endpseudopc:
        lda pson
        beq pe_done
        lda #$00
        sta pson
        lda OUTP                    ; echte Adresse = gemerkte + Anzahl der seither ausgegebenen Bytes
        sec
        sbc psout
        sta S2T                     ; S2T = ausgegebene Bytes (16 Bit)
        lda OUTP + 1
        sbc psout + 1
        sta S2T + 1
        lda psreal
        clc
        adc S2T
        sta PC
        lda psreal + 1
        adc S2T + 1
        sta PC + 1
pe_done:
        jmp d_end

; ---- Hilfsvariable fuer .fill/.lohifill (ohne Rahmen): Name in LNAME/LLEN, VAL = Anfangswert
; Die Laufvariable ist eine normale .var-Variable (Tabelle ab VARBASE). Gab es sie schon, wird ihr Wert gemerkt und am Ende
; wiederhergestellt (tvex = 1); sonst wird sie neu angelegt und am Ende wieder entfernt (tvex = 0). tvp = Versatz des Eintrags.
; tv_begin: Eingabe LNAME/LLEN, VAL = Anfangswert (Ganzzahl). Aendert A, X, Z, P6, P7, TMP2, VTY, VFR, VAL.
tv_begin:
        ldx #$1f
tb1:    lda LNAME,x                 ; Name nach NAMEBUF (32 Byte)
        sta NAMEBUF,x
        dex
        bpl tb1
        lda LLEN
        sta NAMELEN
        jsr qualify                 ; im aktuellen Scope qualifizieren
        jsr var_find_exact
        bcs tb_new                  ; gibt es noch nicht
        lda P6                      ; vorhanden: Versatz merken, alten Wert sichern, neuen Anfangswert setzen
        sta tvp
        lda P6 + 1
        sta tvp + 1
        jsr cp_val_tmp2             ; TMP2 = Anfangswert (var_getval ueberschreibt VAL)
        jsr var_getval
        ldx #$03
tb2:    lda VAL,x                   ; alten Wert merken
        sta tvold,x
        dex
        bpl tb2
        jsr cp_tmp2_val             ; VAL = Anfangswert zurueck
        jsr set_vint                ; Art = Ganzzahl
        jsr var_setval
        lda #$01
        sta tvex                    ; "war schon vorhanden"
        rts
tb_new: jsr set_vint
        lda vare                    ; neuer Eintrag entsteht an der Stelle vare
        sta tvp
        lda vare + 1
        sta tvp + 1
        jsr var_new
        lda #$00
        sta tvex
        rts

; tv_set: Laufvariable := VAL (Ganzzahl). Aendert A, X, Z, P6.
tv_set: jsr set_vint
        lda tvp
        ldx tvp + 1
        jsr p6_load                 ; P6 = Eintrag (Bank S2BANK)
        jmp var_setval

; tv_end: Laufvariable abraeumen: neu angelegte entfernen (vare zurueck), alte wieder auf ihren Wert setzen.
; (die Art der alten Variablen wird dabei auf Ganzzahl gesetzt)
tv_end: lda tvex
        bne te_r
        lda tvp                     ; Eintrag war der letzte: Tabellenende zuruecksetzen
        sta vare
        lda tvp + 1
        sta vare + 1
        rts
te_r:   jsr set_vint
        ldx #$03
te1:    lda tvold,x
        sta VAL,x
        dex
        bpl te1
        jmp tv_set

; ---- .fill anzahl [, ausdruck [, laufvariable]] und .lohifill anzahl, ausdruck [, laufvariable]
; Der Ausdruck wird je Element ausgewertet; die Laufvariable (Vorgabe i) zaehlt von 0.
; Ablauf: Anzahl (16 Bit) -> FILLN; Quelltextstelle des Ausdrucks -> fvpos (der Ausdruck wird je Element neu gelesen);
; scan_comma ueberspringt ihn bis zum Komma auf Klammertiefe 0; Name der Laufvariable -> LNAME/LLEN; Zeilenende -> fvend.
; .fill ohne Ausdruck gibt FILLN Nullbytes. Mit Ausdruck: je Element Laufvariable setzen, Ausdruck auswerten, Low-Byte ausgeben.
; .lohifill gibt zwei Durchgaenge aus (fpass 0: alle Low-Bytes, fpass 1: alle High-Bytes), z. B. fuer geteilte Tabellen.
; fmode: 0 = .fill, 1 = .lohifill. Fehler: ERR_SYNTAX (Komma ohne Name). Aendert alle Register.
d_fill: lda #$00
        sta fmode
        beq fl_go
d_lohifill:
        lda #$01
        sta fmode
fl_go:  lda #$00
        sta UNK                     ; UNK = 1 meldet, dass der Ausdruck ein noch unbekanntes Symbol benutzt
        jsr eval_op                 ; Anzahl
        lda OPVAL + 3               ; negative Anzahl: E203 (wie vcc)
        bpl fl_pos
        lda #ERR_E203
        jmp as_error
fl_pos: lda OPVAL
        sta FILLN
        lda OPVAL + 1
        sta FILLN + 1
        ldx #$03                    ; ohne Ausdruck: fvpos zeigt auf "0"
        lda #$00
fl0:    sta fvpos,x
        dex
        bpl fl0
        lda #$00
        sta fvhas
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne fl_nv                   ; kein Komma: weder Ausdruck noch Laufvariable
        jsr src_adv
        jsr skipws
        ldx #$03
d2_fl1:    lda SRC,x                ; Anfang des Ausdrucks merken
        sta fvpos,x
        dex
        bpl d2_fl1
        lda #$01
        sta fvhas
        jsr scan_comma              ; hinter den Ausdruck laufen (bis zum Komma oder Zeilenende)
        jsr src_peek
        cmp #$2c
        bne fl_nv
        jsr src_adv
        jsr skipws
        jsr read_ident              ; Name der Laufvariable
        lda NAMELEN
        beq fl_syn
        ldx #$1f
fl2:    lda NAMEBUF,x
        sta LNAME,x
        dex
        bpl fl2
        lda NAMELEN
        sta LLEN
        jmp fl_run
fl_syn: lda #ERR_SYNTAX
        jmp as_error
fl_nv:  lda #$69                    ; Vorgabe: i
        sta LNAME
        lda #$01
        sta LLEN
fl_run: lda fmode                   ; .lohifill/.lohitable ohne Ausdruck: E208 (wie vcc)
        beq fl_rn
        lda fvhas
        bne fl_rn
        lda #ERR_E208
        jmp as_error
fl_rn:  ldx #$03                    ; Ende der Zeile merken
fl3:    lda SRC,x
        sta fvend,x
        dex
        bpl fl3
        lda FILLN
        ora FILLN + 1
        bne fl_some
        jmp fl_fin                  ; Anzahl 0: nichts auszugeben
fl_some:
        lda fvhas                   ; .fill ohne Ausdruck: einfache Nullbytes
        bne fl_eval
        lda fmode
        bne fl_eval
fl_zero:
        lda #$00
        jsr emit_byte
        lda FILLN                   ; FILLN - 1 (16 Bit)
        bne fl_zd
        dec FILLN + 1
fl_zd:  dec FILLN
        lda FILLN
        ora FILLN + 1
        bne fl_zero
        jmp fl_fin
fl_eval:
        lda #$00                    ; Anfangswert der Laufvariablen 0
        sta VAL
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        jsr tv_begin
        lda #$00
        sta fpass
fl_pass:
        lda #$00                    ; fidx = Elementnummer (16 Bit)
        sta fidx
        sta fidx + 1
fl_el:  lda fidx                    ; Laufvariable := fidx
        sta VAL
        lda fidx + 1
        sta VAL + 1
        lda #$00
        sta VAL + 2
        sta VAL + 3
        jsr tv_set
        lda fvhas
        bne fl_ev
        lda #$00                    ; .lohifill ohne Ausdruck gibt es nicht; Nullen
        sta VAL
        sta VAL + 1
        jmp fl_em
fl_ev:  ldx #$03                    ; SRC an den Anfang des Ausdrucks, auswerten
fl4:    lda fvpos,x
        sta SRC,x
        dex
        bpl fl4
        jsr eval_val
fl_em:  lda fmode                   ; .lohifill/.lohitable: Wert muss in 16 Bit passen, sonst E203 (weich, einmal je Element, wie vcc)
        beq fl_nr
        lda fpass
        bne fl_nr
        ldx #$03
fl_cv:  lda VAL,x
        sta OPVAL,x
        dex
        bpl fl_cv
        jsr range_word
fl_nr:  lda fpass
        beq fl_lo
        lda VAL + 1                 ; zweiter Durchgang: Hi-Byte
        jmp fl_st
fl_lo:  lda VAL
fl_st:  jsr emit_byte
        inc fidx
        bne fl5
        inc fidx + 1
fl5:    lda fidx                    ; fidx = FILLN ? (16-Bit-Vergleich)
        cmp FILLN
        bne fl_el
        lda fidx + 1
        cmp FILLN + 1
        bne fl_el
        lda fmode                   ; .lohifill: zweiter Durchgang fuer die Hi-Bytes
        beq fl_end
        lda fpass
        bne fl_end
        lda #$01
        sta fpass
        jmp fl_pass
fl_end: jsr tv_end                  ; Laufvariable abraeumen
fl_fin: ldx #$03                    ; SRC = Zeilenende (hinter Ausdruck und Variablenname)
fl6:    lda fvend,x
        sta SRC,x
        dex
        bpl fl6
        jmp d_end

; ---- Namenspuffer (nb/nbl): aus Teilen zusammensetzen
; Dient dazu, qualifizierte Namen wie "Name.feld.rest" aufzubauen: nb_from_lname (Anfang), nb_dot (Punkt), nb_add_name
; (NAMEBUF anhaengen), danach nb_to_name / sym_define_nb. Hoechstens 31 Zeichen (Puffer nb: 32 Byte).
; nb_from_lname: nb := LNAME (LLEN Zeichen), nbl := LLEN. Aendert A, X.
nb_from_lname:
        ldx #$00
nf1:    cpx LLEN
        beq nf2
        lda LNAME,x
        sta nb,x
        inx
        bne nf1
nf2:    stx nbl
        rts

; nb_dot: ein "." an nb anhaengen (keine Laengenpruefung: der Aufrufer prueft in nb_add_name). Aendert A, Y.
nb_dot: lda #$2e
        ldy nbl
        sta nb,y
        iny
        sty nbl
        rts

nb_add_name:                        ; NAMEBUF/NAMELEN anhaengen
        ldx #$00                    ; Fehler ERR_E211 bei mehr als 31 Zeichen insgesamt. Aendert A, X, Y.
na1:    cpx NAMELEN
        beq na2
        ldy nbl
        cpy #$1f
        bcs na_long
        lda NAMEBUF,x
        sta nb,y
        iny
        sty nbl
        inx
        bne na1
na2:    rts
na_long:
        lda #ERR_E211
        jmp as_error

; nb_to_name: NAMEBUF/NAMELEN := nb (nbl Zeichen). Aendert A, X.
nb_to_name:
        ldx #$00
nt1:    cpx nbl
        beq nt2
        lda nb,x
        sta NAMEBUF,x
        inx
        bne nt1
nt2:    stx NAMELEN
        rts

; sym_define_nb: Name aus nb (qualifiziert im aktuellen Scope) mit dem Wert VAL als Konstante anlegen
; VAL wird ueber TMP2 gerettet, weil nb_to_name/qualify es nicht schonen. Aendert alle Register (und was sym_define aendert).
sym_define_nb:
        jsr cp_val_tmp2
        jsr nb_to_name
        jsr qualify
        jsr cp_tmp2_val
        jmp sym_define

; ---- .enum Name ... .endenum
; Syntax: Zeilen "eintrag [= wert] [, eintrag ...]" bis .endenum; Kommentarzeilen und Leerzeilen sind erlaubt. Jeder Eintrag
; definiert "Name.eintrag" als Konstante; ecnt (32 Bit) zaehlt ab 0 (oder ab dem letzten expliziten Wert) hoch.
; Der Block wird zeilenweise gelesen: line_dir pruft, ob die Zeile .endenum ist; lpos = Zeilenanfang (SRC wird danach
; zurueckgesetzt). Fehler: ERR_SYNTAX (kein Name), ERR_E210 (Quelltextende vor .endenum).
d_enum: ldx #$08
        jsr blk_sv                  ; Zeile der Direktive merken (E210 am Ende wie vcc)
        jsr skipws
        jsr read_ident
        lda NAMELEN
        bne en0
        lda #ERR_SYNTAX
        jmp as_error
en0:    jsr save_lname              ; Enum-Name -> LNAME/LLEN (NAMEBUF wird ueberschrieben)
        lda #$00
        sta ecnt
        sta ecnt + 1
        sta ecnt + 2
        sta ecnt + 3
        jsr next_line               ; Rest der Kopfzeile ueberspringen
en_line:
        ldx #$03
d2_en1:    lda SRC,x                ; Zeilenanfang merken
        sta lpos,x
        dex
        bpl d2_en1
        jsr line_dir
        cmp #DID_ENDENUM
        beq en_end
        ldx #$03
d2_en2:    lda lpos,x               ; keine Endezeile: SRC zurueck an den Zeilenanfang
        sta SRC,x
        dex
        bpl d2_en2
en_item:
        jsr skipws
        jsr src_peek
        bne en3
        ldx #$08
        jsr blk_ld
        lda #ERR_E210               ; Quelltextende
        jmp as_error
en3:    cmp #$0a
        beq en_nl                   ; Zeilenende (LF/CR) oder Kommentar: naechste Zeile
        cmp #$0d
        beq en_nl
        cmp #$3b
        beq en_nl
        jsr read_ident
        lda NAMELEN
        bne en4
        lda #ERR_SYNTAX
        jmp as_error
en4:    ldx #$1f                    ; Eintragsname sichern (der Ausdruck liest Bezeichner)
en5:    lda NAMEBUF,x
        sta isave,x
        dex
        bpl en5
        lda NAMELEN
        sta ilen
        jsr skipws
        jsr src_peek
        cmp #$3d                    ; "=": expliziter Wert
        bne en6
        jsr src_adv
        jsr eval_val
        ldx #$03
en7:    lda VAL,x                   ; ecnt := Wert
        sta ecnt,x
        dex
        bpl en7
en6:    jsr nb_from_lname           ; Name = "Enumname.eintrag"
        jsr nb_dot
        ldx #$1f
en8:    lda isave,x
        sta NAMEBUF,x
        dex
        bpl en8
        lda ilen
        sta NAMELEN
        jsr nb_add_name
        ldx #$03
en9:    lda ecnt,x                  ; Wert = ecnt
        sta VAL,x
        dex
        bpl en9
        jsr sym_define_nb
        inc ecnt                    ; ecnt + 1 (32 Bit)
        bne ena
        inc ecnt + 1
        bne ena
        inc ecnt + 2
        bne ena
        inc ecnt + 3
ena:    jsr skipws
        jsr src_peek
        cmp #$2c                    ; Komma: weiterer Eintrag in derselben Zeile
        bne enb
        jsr src_adv
        jmp en_item
enb:    jsr at_eol_chk              ; sonst muss die Zeile zu Ende sein
en_nl:  jsr next_line
        bcc en_line
        ldx #$08
        jsr blk_ld
        lda #ERR_E210               ; Quelltext zu Ende, ohne dass .endenum kam
        jmp as_error
en_end: jmp d_end

; save_lname: LNAME/LLEN := NAMEBUF/NAMELEN (32 Byte). Aendert A, X.
save_lname:
        ldx #$1f
sl1x:   lda NAMEBUF,x
        sta LNAME,x
        dex
        bpl sl1x
        lda NAMELEN
        sta LLEN
        rts

; .endstruct/.endenum ohne zugehoerigen Anfang (der Anfang liest sie selbst im Block): Fehler "Block nicht abgeschlossen"
d_endstruct:
d_endenum:
        lda #ERR_E210
        jmp as_error

; ---- .struct Name ... .endstruct
; Syntax: Zeilen "feld typ [anzahl]" bis .endstruct. typ = .byte (1), .word/.addr (2), .dword/.long (4) oder der Name einer
; frueher definierten Struktur. soff (32 Bit) = Versatz des naechsten Feldes. Je Feld wird "Name.feld" = soff definiert;
; bei Strukturtyp zusaetzlich "Name.feld.unterfeld" (struct_fields); soff waechst um Groesse * Anzahl. Am Ende "Name.size".
; Fehler: ERR_SYNTAX, ERR_E208 (unbekannter Typ), ERR_E210 (Quelltextende), ERR_E211 (Name zu lang).
d_struct:
        ldx #$08
        jsr blk_sv                  ; Zeile der Direktive merken (E210 am Ende wie vcc)
        jsr skipws
        jsr read_ident
        lda NAMELEN
        bne ss0
        lda #ERR_SYNTAX
        jmp as_error
ss0:    jsr save_lname              ; Strukturname -> LNAME/LLEN
        jsr nb_from_lname           ; schon in diesem Durchlauf als Struktur definiert (NAME.size)? E204 wie vcc
        jsr nb_dot
        ldx #$03
ssdx:   lda sizename,x
        sta NAMEBUF,x
        dex
        bpl ssdx
        lda #$04
        sta NAMELEN
        jsr nb_add_name
        jsr nb_to_name
        jsr qualify
        jsr sym_defined_new
        bcs ssd_ok
        lda #ERR_E204
        jmp as_error
ssd_ok:
        lda #$00
        sta soff
        sta soff + 1
        sta soff + 2
        sta soff + 3
        jsr next_line
ss_line:
        ldx #$03
ss1:    lda SRC,x                   ; Zeilenanfang merken (lpos)
        sta lpos,x
        dex
        bpl ss1
        jsr line_dir
        cmp #DID_ENDSTRUCT
        bne ss_nx
        jmp ss_end
ss_nx:  ldx #$03
ss2:    lda lpos,x                  ; keine Endezeile: SRC zurueck an den Zeilenanfang
        sta SRC,x
        dex
        bpl ss2
        jsr skipws
        jsr src_peek
        bne ss3
        ldx #$08
        jsr blk_ld
        lda #ERR_E210
        jmp as_error
ss3:    cmp #$0a
        beq ss_nl                   ; leere Zeile oder Kommentar
        cmp #$0d
        beq ss_nl
        cmp #$3b
        beq ss_nl
        jsr read_ident              ; Feldname
        lda NAMELEN
        bne ss4
        lda #ERR_SYNTAX
        jmp as_error
ss4:    ldx #$1f                    ; Feldname sichern (isave/ilen), weil der Typ NAMEBUF ueberschreibt
ss5:    lda NAMEBUF,x
        sta isave,x
        dex
        bpl ss5
        lda NAMELEN
        sta ilen
        jsr skipws
        jsr read_ident              ; Typ: .byte .word .addr .dword .long oder Strukturname
        lda NAMELEN
        bne ss6
        lda #ERR_SYNTAX
        jmp as_error
ss6:    jsr type_size               ; VAL = Groesse; sstruct = 1 bei Strukturtyp (tq = qualifizierter Name)
        ldx #$03
ss6a:   lda VAL,x
        sta ssize,x
        dex
        bpl ss6a
        jsr skipws                  ; Anzahl (Vorgabe 1)
        jsr at_eol
        beq ss7
        jsr eval_val
        jmp ss8
ss7:    lda #$01
        sta VAL
        lda #$00
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
ss8:    jsr cp_val_lhs              ; LHS = Anzahl, VAL = Groesse
        ldx #$03
ss8a:   lda ssize,x
        sta VAL,x
        dex
        bpl ss8a
        lda #$10                    ; Groesse * Anzahl
        sta OPID
        jsr ex_apply
        ldx #$03
ss9:    lda VAL,x                   ; sprod = Groesse * Anzahl (Platz des Feldes)
        sta sprod,x
        dex
        bpl ss9
        ; Feld: NAME.feld = soff
        jsr nb_from_lname
        jsr nb_dot
        ldx #$1f
ssa:    lda isave,x
        sta NAMEBUF,x
        dex
        bpl ssa
        lda ilen
        sta NAMELEN
        jsr nb_add_name
        ldx #$03
ssb:    lda soff,x
        sta VAL,x
        dex
        bpl ssb
        jsr sym_define_nb
        lda sstruct
        beq ssc
        jsr struct_fields           ; Felder des Strukturtyps: NAME.feld.unterfeld
ssc:    ldx #$03                    ; soff += Groesse * Anzahl
ssd:    lda soff,x
        sta LHS,x
        lda sprod,x
        sta VAL,x
        dex
        bpl ssd
        lda #$0e
        sta OPID
        jsr ex_apply
        ldx #$03
sse:    lda VAL,x
        sta soff,x
        dex
        bpl sse
ss_nl:  jsr next_line
        bcs ss_eof
        jmp ss_line
ss_eof: ldx #$08
        jsr blk_ld
        lda #ERR_E210
        jmp as_error
ss_end: jsr nb_from_lname           ; NAME.size
        jsr nb_dot
        ldx #$03
ssf:    lda sizename,x
        sta NAMEBUF,x
        dex
        bpl ssf
        lda #$04
        sta NAMELEN
        jsr nb_add_name
        ldx #$03
ssg:    lda soff,x                  ; Gesamtgroesse = soff
        sta VAL,x
        dex
        bpl ssg
        jsr sym_define_nb
        jmp d_end
sizename: .byte "size"

; type_size: Typname in NAMEBUF -> VAL = Groesse; sstruct = 0/1
; Eingabe: NAMEBUF/NAMELEN (bei eingebauten Typen mit fuehrendem Punkt). Ausgabe: VAL = Groesse in Byte; sstruct = 1, wenn
; es eine Struktur ist (dann tq/tql = qualifizierter Name der Struktur). Eingebaute Typen werden nur an Laenge und dem
; zweiten Zeichen erkannt (.b = byte, .w = word, .a = addr, .l = long, .d = dword). Fehler: ERR_E208 (unbekannt),
; ERR_E211 (Name zu lang). Aendert A, X, Y und was qualify/sym_find aendern.
type_size:
        lda #$00
        sta sstruct
        lda NAMEBUF
        cmp #$2e
        bne ts_struct               ; kein Punkt: Name einer Struktur
        lda NAMELEN                 ; .byte .word .addr .dword .long (klein)
        cmp #$05
        bne ts6
        lda NAMEBUF + 1
        ora #$20
        cmp #$62                    ; .byte
        bne ts5a
        lda #$01
        jmp ts_ret
ts5a:   cmp #$77                    ; .word
        beq ts_two
        cmp #$61                    ; .addr
        beq ts_two
        cmp #$6c                    ; .long
        beq ts_four
ts_bad: lda #ERR_E208
        jmp as_error
ts6:    cmp #$06                    ; .dword
        bne ts_bad
        lda NAMEBUF + 1
        ora #$20
        cmp #$64
        bne ts_bad
ts_four:
        lda #$04
        jmp ts_ret
ts_two: lda #$02
ts_ret: sta VAL                     ; VAL = Groesse (32 Bit)
        lda #$00
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        rts
ts_struct:
        lda #$01
        sta sstruct
        jsr qualify                 ; Name des Strukturtyps im aktuellen Scope
        ldx #$00                    ; merken (tq/tql)
ts1:    cpx NAMELEN
        beq ts2
        lda NAMEBUF,x
        sta tq,x
        inx
        bne ts1
ts2:    stx tql
        cpx #$1b                    ; Platz fuer ".size" (5 Zeichen) in 31 Zeichen
        bcs ts_long
        lda #$2e                    ; <Typ>.size suchen
        sta NAMEBUF,x
        inx
        ldy #$00
ts3:    lda sizename,y
        sta NAMEBUF,x
        inx
        iny
        cpy #$04
        bne ts3
        stx NAMELEN
        jsr sym_find
        bcs ts_bad                  ; keine solche Struktur
        jmp sym_getnew              ; VAL = Wert (Gesamtgroesse); kehrt zum Aufrufer zurueck
ts_long:
        lda #ERR_E211
        jmp as_error

; struct_fields: fuer jedes Symbol `<Typ>.rest` (ausser .size) NAME.feld.rest = soff + Wert anlegen
; Eingabe: tq/tql = Typname (qualifiziert), LNAME/LLEN = Name der Struktur im Bau, isave/ilen = Feldname, soff = Versatz des
; Feldes. Die Symboltabelle (Attic) wird von Anfang bis zur beim Eintritt gemerkten Obergrenze sfend durchlaufen (neu
; angelegte Symbole liegen dahinter und werden nicht erneut betrachtet). Eintrag: Laenge, Name, alt (4), neu (4), Flags (1),
; Gesamtlaenge Laenge + 10; der neue Wert liegt bei Z = Laenge + 5. Aendert alle Register, P7, VAL, LHS, isave2.
struct_fields:
        lda SYME + 2                ; Obergrenze jetzt festhalten (sym_define haengt neue Eintraege an)
        sta sfend + 2
        lda SYME + 1
        sta sfend + 1
        lda SYME
        sta sfend
        lda #$00                    ; P7 = Tabellenanfang $0810_0000
        sta P7
        sta P7 + 1
        lda #SYM_B3
        sta P7 + 3
        lda #SYM_B2
        sta P7 + 2
sf_l:   lda P7                      ; P7 = sfend ? (24 Bit) -> fertig
        cmp sfend
        bne d2_sf_go
        lda P7 + 1
        cmp sfend + 1
        bne d2_sf_go
        lda P7 + 2
        cmp sfend + 2
        bne d2_sf_go
        rts
d2_sf_go:  ldz #$00
        lda [P7],z                  ; Namenslaenge dieses Symbols
        sta sflen
        cmp tql                     ; Name muss laenger sein als Typname + Punkt
        bcc d2_sf_nx
        beq d2_sf_nx
        ldx #$00
        inz
d2_sf_c:   cpx tql                  ; beginnt der Name mit dem Typnamen?
        beq sf_dot
        lda [P7],z
        cmp tq,x
        bne d2_sf_nx
        inz
        inx
        bne d2_sf_c
sf_dot: lda [P7],z                  ; danach muss ein Punkt folgen
        cmp #$2e
        bne d2_sf_nx
        inz
        ldx #$00                    ; Rest nach NAMEBUF holen
sf_r:   lda sflen                   ; Restlaenge = Laenge - tql - 1
        sec
        sbc tql
        sbc #$01
        sta sfrest
        cpx sfrest
        beq sf_rd
        lda [P7],z
        sta isave2,x
        inz
        inx
        bne sf_r
sf_rd:  stx sfrest                  ; Laenge des Rests
        cpx #$04                    ; .size?
        bne sf_use
        lda isave2
        cmp #$73
        bne sf_use
        lda isave2 + 1
        cmp #$69
        bne sf_use
        lda isave2 + 2
        cmp #$7a
        bne sf_use
        lda isave2 + 3
        cmp #$65
        beq d2_sf_nx                ; "size" wird nicht uebernommen
sf_use: lda sflen                   ; neuer Wert (Versatz + Wert) lesen: Z hinter dem Namen + 4 (alter Wert)
        clc
        adc #$05
        taz
        ldx #$00
sf_v:   lda [P7],z
        sta VAL,x
        inz
        inx
        cpx #$04
        bne sf_v
sf_a:   ldx #$03                    ; VAL = soff + Wert (LHS = Wert, VAL = soff)
sf_a1:  lda VAL,x
        sta LHS,x
        lda soff,x
        sta VAL,x
        dex
        bpl sf_a1
        lda #$0e
        sta OPID
        jsr ex_apply
        ldx #$03
sf_a2:  lda VAL,x
        sta svalbuf,x
        dex
        bpl sf_a2
        jsr nb_from_lname           ; NAME.feld.rest
        jsr nb_dot
        ldx #$1f
sf_a3:  lda isave,x
        sta NAMEBUF,x
        dex
        bpl sf_a3
        lda ilen
        sta NAMELEN
        jsr nb_add_name
        jsr nb_dot
        ldx #$00
sf_a4:  cpx sfrest
        beq sf_a5
        lda isave2,x
        sta NAMEBUF,x
        inx
        bne sf_a4
sf_a5:  stx NAMELEN
        jsr nb_add_name
        ldx #$03
sf_a6:  lda svalbuf,x
        sta VAL,x
        dex
        bpl sf_a6
        jsr sym_define_nb
d2_sf_nx:  ldz #$00                    ; naechster Eintrag: Laenge + 10
        lda [P7],z
        clc
        adc #$0a
        clc
        adc P7
        sta P7
        bcc sf_nxx
        inc P7 + 1
        bne sf_nxx
        inc P7 + 2
sf_nxx: jmp sf_l

; ---- Daten
bline:  .word 0                     ; .basicstub: Zeilennummer (benutzt von asm.asm)
bclen:  .byte 0                     ; .basicstub: Laenge des Kommentars
bcom:   .fill 32, 0                 ; .basicstub: Kommentartext
pgn:    .fill 4, 0                  ; .page: n
psreal: .word 0                     ; .pseudopc: echte PC beim Eintritt
psout:  .word 0                     ; .pseudopc: Ausgabestand (OUTP, 16 Bit) beim Eintritt
pson:   .byte 0                     ; 1 = .pseudopc-Region offen
tvp:    .word 0                     ; Laufvariable: Versatz des Eintrags in der Variablentabelle
tvex:   .byte 0                     ; 1 = Laufvariable gab es schon (Wert wird am Ende zurueckgesetzt)
tvold:  .fill 4, 0                  ; alter Wert einer schon vorhandenen Laufvariablen
fmode:  .byte 0                     ; 0 = .fill, 1 = .lohifill
fvhas:  .byte 0                     ; 1 = Ausdruck angegeben
fpass:  .byte 0                     ; .lohifill: 0 = Low-Bytes, 1 = High-Bytes
fidx:   .word 0                     ; Elementnummer
fvpos:  .fill 4, 0                  ; SRC am Anfang des Ausdrucks
fvend:  .fill 4, 0                  ; SRC am Zeilenende (nach Ausdruck und Variablenname)
nb:     .fill 32, 0                 ; Namenspuffer
nbl:    .byte 0                     ; Laenge in nb
ecnt:   .fill 4, 0                  ; .enum: laufender Wert
isave:  .fill 32, 0                 ; gemerkter Eintrags-/Feldname
isave2: .fill 32, 0                 ; Rest eines Unterfeldnamens (struct_fields)
ilen:   .byte 0                     ; Laenge von isave
soff:   .fill 4, 0                  ; .struct: Versatz des naechsten Feldes
ssize:  .fill 4, 0                  ; Groesse des Feldtyps
sprod:  .fill 4, 0                  ; Groesse * Anzahl
svalbuf: .fill 4, 0                 ; Zwischenspeicher des Werts soff + Unterfeldwert
sstruct: .byte 0                    ; 1 = Feldtyp ist eine Struktur
tq:     .fill 32, 0                 ; qualifizierter Name des Strukturtyps
tql:    .byte 0                     ; seine Laenge
sfend:  .fill 4, 0                  ; Obergrenze der Symboltabelle fuer struct_fields
sflen:  .byte 0                     ; Namenslaenge des betrachteten Symbols
sfrest: .byte 0                     ; Laenge des Rests nach "<Typ>."

; ---- .assert bedingung [, "meldung"] / .error "text" / .warning "text" / .cycles / .endcycles / .run
; Ein Fehlschlag zaehlt wie ein weicher Fehler (erst im letzten, stabilen Durchlauf); .warning, .cycles und .run haben
; keine Wirkung auf die Ausgabe.
; d_assert: Bedingung auswerten; 0 = Fehler E207 (soft_err), der Rest der Zeile (Meldung) wird ueberlesen. d_error meldet
; immer E207; d_warning und d_skipline ueberlesen nur den Rest der Zeile (bis LF/Ende, ohne es zu verbrauchen) und fahren
; mit al_line fort. Die Meldungstexte werden nicht ausgewertet. .cycles/.endcycles/.run stehen in cyc.asm.
d_assert:
        jsr eval_val
        lda VAL
        ora VAL + 1
        ora VAL + 2
        ora VAL + 3
        bne d_skipline              ; wahr: nichts zu melden
        lda #ERR_E207
        jsr soft_err
        jmp d_skipline
d_error:
        lda #ERR_E207
        jsr soft_err
        jmp d_skipline
d_warning:
        lda #WARN_W200              ; .warning: Warnung W200 mit der Zeile (der Text steht nur im Quelltext)
        jsr warn_add
d_skipline:
dsk1:   jsr src_peek
        beq dsk2
        cmp #$0a
        beq dsk2
        jsr src_adv
        jmp dsk1
dsk2:   jmp al_line

