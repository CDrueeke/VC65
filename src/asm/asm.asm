; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; asm.asm - Assembler-Treiber (Etappe N2): Durchlaeufe, Zeilen, Marken, Direktiven, Befehle.
; Aufruf: SRCBASE = 32-Bit-Adresse des nullterminierten Quelltexts, OUTBASE = 32-Bit-Adresse der Ausgabe.
;         jsr asm_run   ->  Carry geloescht: Ausgabe steht ab OUTBASE, Laenge = OUTP - OUTBASE;
;                           Carry gesetzt: ERR = Fehlercode, SRC steht an der Fehlerstelle.
; Es wird so oft uebersetzt, bis sich kein Symbolwert mehr aendert (wie vcc, hoechstens 16 Durchlaeufe).
; Unterstuetzt: Marken `name:`, Konstanten `name = ausdruck`, Kommentare `;` und `//`, alle Befehle des 45GS02, anonyme Marken,
;   Direktiven (Tabelle dirtab unten: Daten, Text, .org, .align, .basicstub, .if-Familie, ...);
;   Stufe 2 (Variablen, Schleifen, Makros, Scopes) steht in stage2.asm und dir2.asm.
;
; Aufbau des Assemblers (alle Dateien in src/asm/; sie werden zu einem Programm zusammengebunden):
;   asm.asm    Treiber: asm_run (Durchlaufschleife), as_pass/al_line (Zeilenschleife),
;              Direktiven .org/.byte/.word/.text/.align/.if ...,
;              Zeilentabelle fuer den Debugger (ln_hook), Tabelle der langen Spruenge (bits_*), Fehlerbehandlung (as_error, as_fail)
;   src.asm    Quelltextzugriff: src_peek/src_peek1/src_adv/skipws (SRC ist ein 32-Bit-Zeiger, Zugriff per [SRC],z)
;   expr.asm   Ausdrucksrechner (ex_eval; Rangfolge, Funktionen); numx.asm/math.asm/mathtab.asm Festkomma 32.32;
;              list.asm Listen; func.asm Funktionen
;   sym.asm    Symboltabelle (Marken, Konstanten), Werte alt/neu je Durchlauf          err.asm   Fehler- und Warnungsliste
;   enc.asm    Operanden erkennen, Adressierungsart waehlen, Bytes ausgeben
;   optab.asm/mnfind.asm  Befehlstabelle und binaere Suche
;   stage2.asm Stufe 2: Variablen (.var), Schleifen (.repeat/.for), Makros, Scopes ({ }), Zuweisungen; dir2.asm weitere Direktiven
;   inc.asm    .include/.incbin ueber eine Dateitabelle im Attic (curfile, filebase); loader.asm holt fehlende Dateien vom Laufwerk
;   text2.asm/charnames.asm Sonderzeichen in Zeichenketten, .encoding            cyc.asm  Zyklenzaehlung (.cycles/.endcycles)
; Hinweis: Dies ist eine Uebersicht fuer Neulinge; die massgebliche Beschreibung steht im jeweiligen Dateikopf.
;
; Ablauf (asm_run): Die Symbolwerte werden ueber mehrere Durchlaeufe stabilisiert. Jeder Durchlauf (ar_pass) setzt den Zustand
; zurueck (Zaehler, Scopes, Fehlerliste), uebersetzt den ganzen Quelltext von vorn (as_pass: je Zeile al_line) und ruft am Ende
; sym_end_pass. Aendert sich dabei kein Symbolwert (CHG = 0), ist das Ergebnis stabil und gilt: die Ausgabe des LETZTEN Durchlaufs
; steht ab OUTBASE, die Fehler- und Warnungsliste (err.asm) gehoert ebenfalls nur diesem Durchlauf. Vorwaertsreferenzen erhalten
; im ersten Durchlauf den Wert 0 und UNK = 1 (unbekannt; es wird absolut/gross angenommen) und stimmen ab dem zweiten.
; Hoechstens 16 Durchlaeufe (PASS), danach Fehler $09 "Symbole konvergieren nicht".
;
; Zeilenschleife (al_line): Zeilenanfang -> Leerraum ueberspringen -> je nach erstem Zeichen: Zeilenende/Kommentar, '*=' (.org),
; '#include', '{' '}' (Scope), '-' '+' (anonyme Marke), Bezeichner (Marke "name:", Konstante "name = ...", Zuweisung "name op= ...",
; Direktive ".name" oder Befehl). Befehle: mn_find -> parse_operand -> encode (enc.asm). Ueberschuessige Zeichen am Zeilenende
; meldet at_eol_chk als Syntaxfehler.
;
; Fehlerbehandlung: as_error (A = Code) / as_fail (Code in ERR) melden den Fehler mit err_add und setzen im Durchlauf (inpass = 1) den
; Stapel auf den Stand von as_pass (asp2) zurueck, ueberspringen den Rest der Zeile (bei einem Makroaufruf: hinter die Aufrufzeile)
; und lesen ab al_line weiter. Ausserhalb eines Durchlaufs (z. B. "Symbole konvergieren nicht") bricht as_abort mit Carry = 1 ab.
; Alle Routinen duerfen deshalb "jmp as_error" benutzen, ohne Aufraeumen; Routinen, die waehrenddessen Stapelinhalt anlegen, muessen
; damit leben koennen (der Stapel wird abgeschnitten). Weiche Fehler (soft_err in sym.asm) laufen weiter.
;
; Zeropage: siehe zp.asm (SRC, PC, OUTP, OUTBASE, SRCBASE, PASS, CHG, ERR, ASP u. a.). Quelltext, Ausgabe und Symbole werden ueber
; 32-Bit-Zeiger angesprochen (Hauptquelltext im Attic ab $0800_0000, Symbole ab $0810_0000, Dateitabelle ab $0820_0000);
; Variablen, Makros, Fehlerlisten und die Hash-Tabelle liegen in der Stufe-2-Bank S2BANK (siehe stage2.asm).
; =====================================================================================================================
; asm_run: Einstieg. Eingabe: SRCBASE (32 Bit) = Quelltext (0-terminiert), OUTBASE (32 Bit) = Ausgabebereich.
;   Ausgabe: C=0: fertig, Ausgabe ab OUTBASE, Laenge = OUTP - OUTBASE; C=1: Fehler, ERR = Code des ERSTEN Fehlers, SRC = seine Stelle
;   (die komplette Liste steht in err.asm). Zerstoert alle Register. Merkt sich den Stapelstand in ASP fuer as_abort.
asm_run:
        ; Stapelstand merken: as_abort kehrt damit direkt zum Aufrufer von asm_run zurueck
        tsx
        stx ASP
        lda #$00
        sta ldadr
        sta ldadr + 1
        ; Einmalige Initialisierung vor dem ersten Durchlauf: Symboltabelle leer, Tabelle der langen Spruenge leer, Include-Stand
        jsr sym_init
        jsr bits_clear
        lda #$00
        sta fcnt
        sta IFSP
        sta ISKIP
        sta segon                   ; .segment-Bereich gilt erst ab seiner Direktive (je Durchlauf neu)
        sta segwrap
        jsr i_pass
        jsr s2_init                 ; Stufe 2: Makros sammeln
        lda #$00
        sta PASS
        ; ---- Beginn eines Durchlaufs ----
ar_pass:
        inc PASS
        lda #$00
        sta CHG
        sta ERR
        sta ercnt
        sta wcnt
        sta inmc
        sta lt_cnt                    ; Zeilentabelle neu
        sta lt_cnt + 1
        sta lt_pend
        ; SRC := SRCBASE und OUTP := OUTBASE (je 4 Byte, X laeuft 3..0)
        ldx #$03                    ; Quelltext, Ausgabe und Programmzaehler an den Anfang
ar_i:   lda SRCBASE,x
        sta SRC,x
        lda OUTBASE,x
        sta OUTP,x
        dex
        bpl ar_i
        ; Programmzaehler und alle Zaehler/Zustaende auf Anfang (anonyme Marken, .branchlong, aktuelle globale Marke, .encoding, .if)
        lda #$00
        sta PC
        sta PC + 1
        sta NEGN
        sta POSN
        sta BLONG
        sta BIDX
        sta BIDX + 1
        sta CURGL
        sta ENC
        sta IFSP
        sta ISKIP
        ; Module melden sich fuer den neuen Durchlauf an (Stufe 2, Funktionen, Listen, Include, Zyklen)
        jsr s2_pass
        jsr f_pass
        jsr l_pass
        jsr i_pass
        jsr cy_pass
        ; inpass = 1: Fehler brechen die Zeile ab (as_error springt in die Zeilenschleife zurueck)
        lda #$01
        sta inpass
        jsr as_pass
        lda #$00
        sta inpass
        ldx IFSP                    ; Quelltextende mit offenen .if-Bloecken: je Ebene E210 an der Stelle der Eroeffnung (innerste zuerst, wie vcc)
        beq ifu_dn
ifu_l:  stx ifu_x
        dex
        txa
        asl
        asl
        tay
        lda ifpos,y
        sta SRC
        lda ifpos + 1,y
        sta SRC + 1
        lda ifpos + 2,y
        sta SRC + 2
        lda ifpos + 3,y
        sta SRC + 3
        lda #ERR_E210
        jsr err_add
        ldx ifu_x
        dex
        bne ifu_l
        lda #$00
        sta IFSP
ifu_dn: jsr sym_end_pass            ; neue Werte werden zu den alten; CHG = 1 bei Aenderung (wie vcc)
        lda CHG
        bne ar_more
        ; Es ist kein weiterer Durchlauf noetig. Gab es Fehler im letzten Durchlauf? Dann den ersten melden (ERR, SRC)
        lda ercnt                   ; stabil: die Fehler dieses (letzten) Durchlaufs gelten
        beq ar_done
        lda #$00                    ; erster Fehler nach ERR/SRC (die ganze Liste: ELIST)
        jsr err_ptr
        ldz #$00
        lda [P6],z
        sta ERR
        ldz #$04
        ldx #$00
ar_sp:  lda [P6],z
        sta SRC,x
        inz
        inx
        cpx #$04
        bne ar_sp
        sec
        rts
        ; CHG = 1: nochmal, aber hoechstens 15 weitere Durchlaeufe ($10 = Obergrenze)
ar_more:
        lda PASS
        cmp #$10
        bcc ar_pass
        lda #$09                    ; Symbole konvergieren nicht (zu viele Durchlaeufe)
        jmp as_error
ar_done:
        clc
        rts

; as_error: A = Fehlercode (ERR_*), as_fail: Code steht schon in ERR. Beide kehren NICHT zurueck.
;   Im Durchlauf (inpass = 1): Fehler in die Liste, Stapel auf asp2 zuruecksetzen, Rest der Zeile ueberspringen (al_recover),
;   weiter bei al_line. Ausserhalb eines Durchlaufs: Fehler in die Liste, Stapel auf ASP, C=1, Rueckkehr zum Aufrufer von asm_run.
as_error:
        sta ERR
as_fail:
        lda ERR
        jsr err_add                 ; Fehler vermerken
        lda inpass
        beq as_abort
        ldx asp2                    ; im Durchlauf: Rest der Zeile ueberspringen und weiter
        txs
al_recover:
        lda inmc                    ; Fehler im Makroaufruf: hinter der Aufrufzeile weiterlesen
        beq rc1
        lda #$00
        sta inmc
        ldx #$03
rc0:    lda mret,x
        sta SRC,x
        dex
        bpl rc0
rc1:    jsr src_peek
        beq rc2
        cmp #$0a
        beq rc2
        jsr src_adv
        jmp rc1
rc2:    jmp al_line
        ; Abbruch ausserhalb des Durchlaufs: Stapel auf den Stand von asm_run, C=1
as_abort:
        ldx ASP
        txs
        sec
        rts

; as_pass: ein Durchlauf ueber den Quelltext. Merkt den Stapelstand in asp2 (as_error setzt ihn bei jedem Fehler wieder ein),
;   loescht orgs ("noch kein .org") und springt in die Zeilenschleife (ueber chips_enter, das die Chip-Datei einbindet). Kehrt
;   erst am Quelltextende zurueck (in stage2.asm al_eos), Rueckkehrziel = der jsr in asm_run.
; as_pass: ein Durchlauf ueber den Quelltext
as_pass:
        tsx
        stx asp2
        lda #$00
        sta orgs
        jmp chips_enter             ; (endet bei al_line)
        ; ---- Zeilenschleife: eine Quelltextzeile je Durchlauf durch al_line ----
al_line:
        ; Debugger-Zeilentabelle: schliesst die vorige Zeile ab, wenn Ausgabe entstand
        jsr ln_hook                 ; Zeilentabelle (Debugger): Zeile mit Ausgabe merken
        jsr skipws
        jsr src_peek
        bne al_1
        jmp al_eos                  ; Ende des Quelltexts oder des Makropuffers
        ; ISKIP <> 0: wir sind in einem nicht genommenen .if-Zweig; nur Direktiven pruefen (al_skip)
al_1:   ldx ISKIP
        beq al_2
        jmp al_skip                 ; uebersprungener Zweig eines .if
        ; Erstes Zeichen der Zeile entscheidet:
al_2:   cmp #$0a
        beq al_nl
        cmp #$0d
        beq al_nl
        cmp #$3b                    ; ;
        beq al_cm
        cmp #$2f                    ; //
        bne al_nc2
        jsr is_cmt2
        beq al_cm
        lda #ERR_SYNTAX
        jmp as_error
        ; (nur ein einzelner '/' gefolgt von Nicht-'/': kein Kommentar, daher Fehler)
al_nc2:
        cmp #$2a                    ; *= : wie .org
        beq al_star
        cmp #$23                    ; #include
        bne al_nh
        jsr src_adv
        jsr read_ident
        lda NAMELEN
        cmp #$07
        bne al_hs
        lda NAMEBUF
        ora #$20
        cmp #$69
        bne al_hs
        jmp d_hinclude
al_hs:  lda #ERR_SYNTAX
        jmp as_error
        ; '{' und '}' stehen auch ohne Marke allein auf der Zeile (Scope)
al_nh:  cmp #$7b                    ; { : Scope oeffnen
        bne al_nb1
        jmp al_open
al_nb1: cmp #$7d                    ; } : Scope schliessen
        bne al_nb2
        jmp al_close
        ; '-' oder '+' am Zeilenanfang: anonyme Marke (z. B. "- lda ..."); sonst muss ein Bezeichner folgen
al_nb2: cmp #$2d                    ; - oder + allein: anonyme Marke
        beq al_anon
        cmp #$2b
        beq al_anon
        jsr is_identchar
        bcc al_id
        lda #ERR_SYNTAX
        jmp as_error
        ; Zeilenende: Zeichen verbrauchen und naechste Zeile; lblflag loeschen
al_nl:  jsr src_adv
        lda #$00
        sta lblflag                 ; eine Marke gilt nur fuer ein { in derselben Zeile
        jmp al_line
        ; "*= wert": wie .org
al_star:
        jsr src_adv
        jsr skipws
        jsr src_peek
        cmp #$3d
        beq as_st1
        lda #ERR_SYNTAX
        jmp as_error
as_st1: jsr src_adv
        jmp d_org
        ; Anonyme Marke "-" oder "+": das Folgezeichen muss Leerraum/Zeilenende sein; NAMEBUF = [Vorzeichen][Nummer], Laenge 2.
        ; Gegenstueck: anon_ref in enc.asm (gleiches Namensformat; NEGN/POSN zaehlen die Marken in diesem Durchlauf)
al_anon:
        jsr src_peek1               ; danach muss Leerraum oder Zeilenende folgen
        beq aa_ok
        cmp #$20
        beq aa_ok
        cmp #$09
        beq aa_ok
        cmp #$0a
        beq aa_ok
        cmp #$0d
        beq aa_ok
        lda #ERR_SYNTAX
        jmp as_error
aa_ok:  jsr src_peek
        cmp #$2d
        bne aa_plus
        inc NEGN
        lda NEGN
        sta NAMEBUF + 1
        lda #$2d
        jmp aa_def
aa_plus:
        inc POSN
        lda POSN
        sta NAMEBUF + 1
        lda #$2b
aa_def: sta NAMEBUF
        lda #$02
        sta NAMELEN
        jsr src_adv
        jmp al_define
        ; Kommentar bis Zeilenende ueberlesen (LF bleibt stehen); hinter dem Zeilenende (0) -> al_eos
al_cm:  jsr src_adv
        jsr src_peek
        beq al_end
        cmp #$0a
        bne al_cm
        jmp al_line
al_end: jmp al_eos
        ; Bezeichner am Zeilenanfang: Name lesen, dann entscheidet das folgende Zeichen ueber die Art der Zeile
al_id:  jsr read_ident
        jsr skipws
        jsr src_peek
        cmp #$3a                    ; :
        beq al_label
        cmp #$3d                    ; = (Konstante)
        beq al_const
        ; fuehrender Punkt = Direktive
        lda NAMEBUF                 ; .name = Direktive
        cmp #$2e
        beq al_dir
        ; "name op= wert" (z. B. +=): Z gesetzt = kein Zuweisungsoperator, dann ist es ein Befehl; sonst Operator in A
        jsr compound_op             ; name op= ausdruck: Zuweisung an eine Variable
        beq al_nocmp
        sta aop
        jsr asg_apply
        jsr at_eol_chk
        jmp al_line
al_nocmp:
        jmp al_insn
        ; Marke "name:": nur nach einem .org erlaubt (sonst ist der Programmzaehler undefiniert)
al_label:
        lda orgs
        bne alb0
        lda #ERR_E300               ; Marke vor dem ersten .org
        jmp as_error
alb0:   jsr src_adv
        ; Lokale Marke (".name"): mit der aktuellen globalen Marke zu "global.name" verbinden
        lda NAMEBUF
        cmp #$2e
        beq al_loc
        ; Name fuer ein folgendes '{' in derselben Zeile merken (lastlab/lastlen/lblflag), danach im aktuellen Scope qualifizieren
        ldx #$1f                    ; Name fuer ein folgendes { in dieser Zeile merken
alq:    lda NAMEBUF,x
        sta lastlab,x
        dex
        bpl alq
        lda NAMELEN
        sta lastlen
        lda #$01
        sta lblflag
        jsr qualify                 ; Name im aktuellen Scope
        ; Globale Marke: Name (hoechstens 30 Zeichen) in CURG/CURGL; lokale Marken haengen daran
        ldx #$1e                    ; globale Marke: Name als aktuellen Geltungsbereich merken
alg:    lda NAMEBUF,x
        sta CURG,x
        dex
        bpl alg
        lda NAMELEN
        cmp #$1f
        bcc alg2
        lda #$1e
alg2:   sta CURGL
        jmp al_define
al_loc: jsr mangle                  ; .name -> <globale Marke>.name
        ; Marke definieren: Wert = PC (16 Bit); Aufrufer haben NAMEBUF/NAMELEN vorbereitet
al_define:
        lda PC
        sta VAL
        lda PC + 1
        sta VAL + 1
        lda #$00
        sta VAL + 2
        sta VAL + 3
        jsr sym_define
        jmp al_line                 ; Rest der Zeile
        ; "name = ausdruck": existiert schon eine Variable (.var), ist es eine Zuweisung; sonst eine Konstante (Symbol)
al_const:
        jsr var_find                ; gibt es eine Variable dieses Namens, ist es eine Zuweisung
        bcs ac_c
        jsr src_adv
        lda #$00
        sta aop
        jsr asg_apply
        jsr at_eol_chk
        jmp al_line
ac_c:   jsr src_adv
        ldx #$1f                    ; Name sichern: der Ausdruck liest selbst Bezeichner nach NAMEBUF
ac0:    lda NAMEBUF,x
        sta LNAME,x
        dex
        bpl ac0
        lda NAMELEN
        sta LLEN
        jsr ex_eval
        bcc ac1
        jmp as_fail
ac1:    ldx #$1f
ac2:    lda LNAME,x
        sta NAMEBUF,x
        dex
        bpl ac2
        lda LLEN
        sta NAMELEN
        jsr qualify                 ; Konstante im aktuellen Scope
        jsr sym_define
        jsr at_eol_chk
        jmp al_line

; at_eol_chk: nach Befehl oder Direktive muss das Zeilenende folgen (Kommentar erlaubt), sonst ERR_SYNTAX. Zerstoert A.
; at_eol_chk: nach Befehl oder Direktive muss das Zeilenende folgen
at_eol_chk:
        jsr skipws
        jsr at_eol
        beq aec1
        lda #ERR_SYNTAX
        jmp as_error
aec1:   rts

; ---- Befehl
; al_insn: Zeile mit Bezeichner am Anfang, der weder Marke noch Konstante noch Direktive ist: Befehl (oder Makroaufruf).
;   Eingabe : NAMEBUF/NAMELEN = Name (ausserdem steht SRC hinter dem Namen, Leerraum schon uebersprungen)
;   Ablauf  : Suffix .z/.a abtrennen (SUF) -> Name in Grossbuchstaben nach MN_TOK (4 Byte) -> mn_find (mnfind.asm) -> QUAD aus dem
;   Flagbyte des Eintrags -> parse_operand + encode (enc.asm) -> Zeilenende pruefen. Kein Befehl? Dann Makroaufruf versuchen (mac_find,
;   stage2.asm); sonst E205 (unbekannter Befehl). Verlaesst die Routine ueber jmp al_line (kehrt nicht zurueck).
al_insn:
        lda #$00
        ; SUF = 0 kein Suffix, 1 = ".z" (Zeropage erzwingen), 2 = ".a" (absolut erzwingen); steht nur am Namensende ("lda.z")
        sta SUF
        ldx NAMELEN                 ; Suffix .zp (wie .z) und .abs (wie .a): vor den kurzen Formen pruefen
        cpx #$05
        bcc ai_s2
        lda NAMEBUF - 3,x
        cmp #$2e
        bne ai_s3
        lda NAMEBUF - 2,x
        ora #$20
        cmp #$7a                    ; z
        bne ai_s3
        lda NAMEBUF - 1,x
        ora #$20
        cmp #$70                    ; p
        bne ai_s3
        lda #$01
        sta SUF
        lda NAMELEN
        sec
        sbc #$03
        sta NAMELEN
        jmp ai_nosuf
ai_s3:  cpx #$06
        bcc ai_s2
        lda NAMEBUF - 4,x
        cmp #$2e
        bne ai_s2
        lda NAMEBUF - 3,x
        ora #$20
        cmp #$61                    ; a
        bne ai_s2
        lda NAMEBUF - 2,x
        ora #$20
        cmp #$62                    ; b
        bne ai_s2
        lda NAMEBUF - 1,x
        ora #$20
        cmp #$73                    ; s
        bne ai_s2
        lda #$02
        sta SUF
        lda NAMELEN
        sec
        sbc #$04
        sta NAMELEN
        jmp ai_nosuf
ai_s2:  lda NAMELEN
        cmp #$04
        bcc ai_nosuf
        tax
        ; X = Laenge; NAMEBUF - 2,x = vorletztes Zeichen (die Zeropage-Adressierung zp,x ist B-relativ, NAMEBUF liegt in der Zeropage)
        lda NAMEBUF - 2,x           ; vorletztes Zeichen = '.' ?
        cmp #$2e
        bne ai_nosuf
        lda NAMEBUF - 1,x
        ora #$20
        cmp #$7a                    ; z
        bne ai_sa
        lda #$01
        sta SUF
        bne ai_cut
ai_sa:  cmp #$61                    ; a
        bne ai_nosuf
        lda #$02
        sta SUF
        ; Suffix abschneiden (2 Zeichen weniger): der Rest ist der eigentliche Mnemonikname
ai_cut: dec NAMELEN
        dec NAMELEN
ai_nosuf:
        ; Ein Mnemonik hat hoechstens 4 Zeichen (ADCQ): laenger -> kein Befehl (vielleicht Makro)
        lda NAMELEN
        cmp #$05
        bcs ai_unk
        ; Name nach MN_TOK kopieren, a-z -> A-Z (and #$df loescht Bit 5); Rest bis 4 Byte mit 0 auffuellen
        ldx #$00
ai_c:   cpx NAMELEN
        beq ai_pad
        lda NAMEBUF,x
        cmp #$61
        bcc ai_s
        cmp #$7b
        bcs ai_s
        and #$df                    ; Grossbuchstabe
ai_s:   sta MN_TOK,x
        inx
        bne ai_c
ai_pad: cpx #$04
        beq ai_f
        lda #$00
        sta MN_TOK,x
        inx
        bne ai_pad
ai_f:   lda MN_TOK                  ; 45GS02: NOP ist ein anderer Name fuer EOM ($EA), wie in vcc
        cmp #$4e
        bne ai_g
        lda MN_TOK + 1
        cmp #$4f
        bne ai_g
        lda MN_TOK + 2
        cmp #$50
        bne ai_g
        lda MN_TOK + 3
        bne ai_g
        lda #$45                    ; E
        sta MN_TOK
        lda #$4f                    ; O
        sta MN_TOK + 1
        lda #$4d                    ; M
        sta MN_TOK + 2
ai_g:   jsr mn_find
        bcs ai_unk
        ; Flags des Tabelleneintrags (Byte 4): Bit0 = Q-Befehl -> QUAD (enc.asm gibt dann das Praefix $42 $42 aus)
        ldy #$04
        lda (MN_PTR),y
        sta QUAD
        jsr parse_operand
        jsr encode
        jsr at_eol_chk
        jmp al_line
ai_unk: jsr mac_find                ; kein Befehl: vielleicht ein Makro
        bcs ai_e205
        jmp macro_call
ai_e205:
        lda #ERR_E205
        jmp as_error

; ---- Direktiven
; Direktiven: al_dir sucht ".name" (kleingeschrieben, mit Punkt) in dirtab und springt ueber dirjmp. dirtab-Eintrag = 13 Byte: Name
; (12 Byte, mit 0 aufgefuellt, a-z klein) und Kennung (1 Byte, 1 = erste Direktive). Mehrere Namen duerfen dieselbe Kennung haben
; (Aliasnamen, z. B. .db = .byte). Zu lange Namen (> 12 Zeichen) sind unbekannt. Neue Direktive: Eintrag in dirtab UND Zeiger in dirjmp
; an der Stelle Kennung (Reihenfolge der .word-Liste = Kennungen aufsteigend; Kennung 24..29 sind die .if-Familie, siehe al_skip).
DNAME  = $90                        ; $90-$9b (12 Byte)
FILLN  = $9c                        ; $9c/$9d
FILLV  = $9e                        ; Fuellwert von .fill
SZ     = $9f                        ; Elementgroesse der Datenliste (1, 2, 4)
        ; al_dir: Direktive (Name beginnt mit '.', steht in NAMEBUF)
al_dir: jsr dir_build
        bcs ad_unk
        jmp ad_srch

; dir_build: NAMEBUF/NAMELEN -> DNAME (12 Byte, klein, mit 0 aufgefuellt). C=0 ok, C=1 Name laenger als 12 Zeichen. Zerstoert A, X.
dir_build:
        ; (Kleinschreibung: nur A-Z ($41-$5a) werden mit ora #$20 in a-z verwandelt, andere Zeichen bleiben)
        ldx #$00
ad_cp:  cpx NAMELEN
        beq ad_pad
        cpx #$0c
        bcs ad_toolong              ; zu lang
        lda NAMEBUF,x
        cmp #$41
        bcc ad_st
        cmp #$5b
        bcs ad_st
        ora #$20                    ; klein
ad_st:  sta DNAME,x
        inx
        bne ad_cp
ad_pad: cpx #$0c
        beq ad_built
        lda #$00
        sta DNAME,x
        inx
        bne ad_pad
ad_built:
        clc
        rts
ad_toolong:
        sec
        rts

; dir_find: sucht DNAME in der Tabelle; A = Kennung oder 0
; Ausgabe: A = Kennung (0 = unbekannt), DPTR (Zeiger in dirtab) zerstoert; Eintraege je 13 Byte (daher adc #$0d). Zerstoert X, Y.
dir_find:
        lda #<(dirtab)
        sta DPTR
        lda #>(dirtab)
        sta DPTR + 1
df_e:   ldy #$00
        lda (DPTR),y
        beq df_none
        ldx #$00
df_m:   lda (DPTR),y
        cmp DNAME,x
        bne df_nx
        iny
        inx
        cpx #$0c
        bne df_m
        lda (DPTR),y
        rts
df_nx:  clc
        lda DPTR
        adc #$0d
        sta DPTR
        bcc df_e
        inc DPTR + 1
        jmp df_e
df_none:
        lda #$00
        rts

; ad_srch: Direktive suchen und anspringen. Kennung K (1..): Sprung ueber (dirjmp - 2 + 2*K); Kennung 0: E208 (unbekannte Direktive).
ad_srch:
        jsr dir_find
        beq ad_unk
        asl
        tax
        jmp (dirjmp - 2,x)
        ; (Kehrt nicht zurueck: jede d_*-Routine endet ueber d_end/al_line bzw. as_error)
ad_unk: lda #ERR_E208
        jmp as_error

orgs:   .byte 0                     ; 1 = .org gesehen (in diesem Durchlauf)
; dirtab: Eintrag = 12 Byte Name + 1 Byte Kennung (siehe oben); Ende: Byte 0 als Namensanfang. Kennung 2 = .byte/.db/.dw ..., usw.
dirtab: .byte ".org", 0, 0, 0, 0, 0, 0, 0, 0, 1
        .byte ".byte", 0, 0, 0, 0, 0, 0, 0, 2
        .byte ".word", 0, 0, 0, 0, 0, 0, 0, 3
        .byte ".dword", 0, 0, 0, 0, 0, 0, 4
        .byte ".text", 0, 0, 0, 0, 0, 0, 0, 5
        .byte ".fill", 0, 0, 0, 0, 0, 0, 0, 6
        .byte ".target", 0, 0, 0, 0, 0, 7
        .byte ".cpu", 0, 0, 0, 0, 0, 0, 0, 0, 8
        .byte ".const", 0, 0, 0, 0, 0, 0, 9
        .byte ".equ", 0, 0, 0, 0, 0, 0, 0, 0, 10
        .byte ".basicstub", 0, 0, 11
        .byte ".align", 0, 0, 0, 0, 0, 0, 12
        .byte ".branchlong", 0, 13
        .byte ".be16", 0, 0, 0, 0, 0, 0, 0, 14
        .byte ".be32", 0, 0, 0, 0, 0, 0, 0, 15
        .byte ".hex", 0, 0, 0, 0, 0, 0, 0, 0, 16
        .byte ".petscii", 0, 0, 0, 0, 17
        .byte ".screen", 0, 0, 0, 0, 0, 18
        .byte ".null", 0, 0, 0, 0, 0, 0, 0, 19
        .byte ".ptext", 0, 0, 0, 0, 0, 0, 20
        .byte ".shift", 0, 0, 0, 0, 0, 0, 21
        .byte ".encoding", 0, 0, 0, 22
        .byte ".rta", 0, 0, 0, 0, 0, 0, 0, 0, 23
        .byte ".if", 0, 0, 0, 0, 0, 0, 0, 0, 0, 24
        .byte ".elseif", 0, 0, 0, 0, 0, 25
        .byte ".else", 0, 0, 0, 0, 0, 0, 0, 26
        .byte ".endif", 0, 0, 0, 0, 0, 0, 27
        .byte ".ifdef", 0, 0, 0, 0, 0, 0, 28
        .byte ".ifndef", 0, 0, 0, 0, 0, 29
        .byte ".repeat", 0, 0, 0, 0, 0, 30
        .byte ".endrepeat", 0, 0, 31
        .byte ".for", 0, 0, 0, 0, 0, 0, 0, 0, 32
        .byte ".next", 0, 0, 0, 0, 0, 0, 0, 33
        .byte ".break", 0, 0, 0, 0, 0, 0, 34
        .byte ".continue", 0, 0, 0, 35
        .byte ".macro", 0, 0, 0, 0, 0, 0, 36
        .byte ".endmacro", 0, 0, 0, 37
        .byte ".exitmacro", 0, 0, 38
        .byte ".var", 0, 0, 0, 0, 0, 0, 0, 0, 39
        .byte ".set", 0, 0, 0, 0, 0, 0, 0, 0, 40
        .byte ".namespace", 0, 0, 41
        .byte ".pseudopc", 0, 0, 0, 42
        .byte ".endpseudopc", 43
        .byte ".realpc", 0, 0, 0, 0, 0, 44
        .byte ".page", 0, 0, 0, 0, 0, 0, 0, 45
        .byte ".lohifill", 0, 0, 0, 46
        .byte ".struct", 0, 0, 0, 0, 0, 47
        .byte ".endstruct", 0, 0, 48
        .byte ".enum", 0, 0, 0, 0, 0, 0, 0, 49
        .byte ".endenum", 0, 0, 0, 0, 50
        .byte ".assert", 0, 0, 0, 0, 0, 51
        .byte ".error", 0, 0, 0, 0, 0, 0, 52
        .byte ".warning", 0, 0, 0, 0, 53
        .byte ".include", 0, 0, 0, 0, 54
        .byte ".incbin", 0, 0, 0, 0, 0, 55
        .byte ".cycles", 0, 0, 0, 0, 0, 56
        .byte ".endcycles", 0, 0, 57
        .byte ".run", 0, 0, 0, 0, 0, 0, 0, 0, 58
        .byte ".db", 0, 0, 0, 0, 0, 0, 0, 0, 0, 2
        .byte ".dw", 0, 0, 0, 0, 0, 0, 0, 0, 0, 3
        .byte ".dbyt", 0, 0, 0, 0, 0, 0, 0, 14
        .byte ".long", 0, 0, 0, 0, 0, 0, 0, 4
        .byte ".function", 0, 0, 0, 59
        .byte ".relocate", 0, 0, 0, 42
        .byte ".endrelocate", 43
        .byte ".retaddr", 0, 0, 0, 0, 23
        .byte ".lohitable", 0, 0, 46
        .byte ".screencode", 0, 18
        .byte ".textnull", 0, 0, 0, 19
        .byte ".textlen", 0, 0, 0, 0, 20
        .byte ".textshift", 0, 0, 21
        .byte ".addr", 0, 0, 0, 0, 0, 0, 0, 3
        .byte ".endfor", 0, 0, 0, 0, 0, 33
        .byte ".scope", 0, 0, 0, 0, 0, 0, 60
        .byte ".endscope", 0, 0, 0, 61
        .byte ".segment", 0, 0, 0, 0, 62
        .byte ".bank", 0, 0, 0, 0, 0, 0, 0, 63
        .byte 0
; dirjmp: Sprungtabelle, Eintrag fuer Kennung K bei dirjmp + 2*(K-1). Gleiche Kennungen wie in dirtab (z. B. d_endrep fuer .endrepeat
; und .next/.endfor; d_pseudopc fuer .relocate; d_endpseudopc fuer .endrelocate; d_const fuer .const und .equ).
dirjmp: .word d_org, d_byte, d_word, d_dword, d_text, d_fill, d_target, d_cpu, d_const, d_const
        .word d_basicstub, d_align, d_branchlong, d_be16, d_be32, d_hex, d_petscii, d_screen, d_null, d_ptext, d_shift
        .word d_encoding, d_rta, d_if, d_elseif, d_else, d_endif, d_ifdef, d_ifndef
        .word d_repeat, d_endrep, d_for, d_endrep, d_break, d_continue, d_macro, d_endmacro, d_exitmacro, d_var, d_set, d_namespace
        .word d_pseudopc, d_endpseudopc, d_endpseudopc, d_page, d_lohifill, d_struct, d_endstruct, d_enum, d_endenum
        .word d_assert, d_error, d_warning, d_include, d_incbin, d_cycles, d_endcycles, d_run
        .word d_function, d_scope, d_endscope, d_segment, d_bank

; d_end: Normales Ende jeder Direktive und jedes Befehls: Zeilenende pruefen, naechste Zeile.
d_end:  jsr at_eol_chk
        jmp al_line

WARN_W204 = $24                     ; .basicstub nicht an der BASIC-Startadresse ($2001)
WARN_W206 = $26                     ; .run hat auf dem MEGA65 keine Wirkung (PRG ohne Startvektor)
; d_run: .run <ausdruck>: nur eine Warnung (W206), der Rest der Zeile wird uebersprungen (d_skipline in stage2.asm/dir2.asm)
d_run:  lda #WARN_W206
        jsr warn_add
        jmp d_skipline

; .scope / .endscope: Aliasnamen fuer { und } (al_open2/al_close2 in stage2.asm)
d_scope:    jmp al_open2            ; .scope = {
d_endscope: jmp al_close2           ; .endscope = }

; d_org: .org wert (auch "*= wert"). Setzt den Programmzaehler PC. Regeln:
;   - merkt orgs = 1 (Voraussetzung fuer jede Ausgabe und Marke, E300 sonst);
;   - wurde schon etwas ausgegeben und liegt der neue Wert ueber PC: Luecke mit 0 auffuellen (Rohformat wie vcc);
;   - liegt er darunter oder ist noch nichts ausgegeben: nur PC setzen (kein Zurueckspringen im Ausgabepuffer);
;   - das erste .org vor jeder Ausgabe liefert ldadr = Ladeadresse (fuer PRG-Dateien der IDE).
;   Ausgabe: PC (16 Bit) = Wert; endet ueber d_end. Zerstoert A, X, Y u. a. Vergleich "nichts ausgegeben": OUTP = OUTBASE (3 Byte)
;   - das vierte Byte (Bank) aendert sich nie und wird nicht verglichen.
d_org:  jsr ex_eval
        ; (orgs wird auch bei Fehler gesetzt: lda/sta aendern das Carry nicht, bcc prueft das Ergebnis von ex_eval)
        lda #$01
        sta orgs
        bcc do1
        jmp as_fail
do1:    lda VAL + 2                 ; Adresse hoechstens 16 Bit, sonst E203 (wie vcc)
        ora VAL + 3
        beq do1b
        lda #ERR_E203
        jmp as_error
do1b:   lda OUTP                    ; noch nichts ausgegeben: nur den Programmzaehler setzen
        cmp OUTBASE
        bne do2
        lda OUTP + 1
        cmp OUTBASE + 1
        bne do2
        lda OUTP + 2
        cmp OUTBASE + 2
        beq do4
        ; Wert (VAL) mit PC vergleichen: kleiner -> do4 (nichts auffuellen); gleich -> do4; sonst do5 (Fuellschleife)
do2:    lda segwrap                 ; PC war ueber $FFFF hinaus: neuer Wert liegt davor, keine Luecke fuellen
        bne do4
        lda VAL + 1                 ; vorwaerts: bis zur neuen Adresse mit 0 auffuellen (wie vcc im Rohformat)
        cmp PC + 1
        bcc do4
        bne do3
        lda VAL
        cmp PC
        bcc do4
do3:    lda VAL
        cmp PC
        bne do5
        lda VAL + 1
        cmp PC + 1
        beq do4
        ; do5: ein Nullbyte (emit_byte erhoeht PC) und erneut vergleichen, bis PC = Wert
do5:    lda segon                   ; Luecke zwischen Segmenten: nicht gegen den Bereich pruefen (vcc fuellt sie im Rohformat mit 0)
        pha
        lda #$00
        sta segon
        jsr emit_byte
        pla
        sta segon
        jmp do3
do4:    lda OUTP                    ; erstes .org vor jeder Ausgabe = Ladeadresse (fuer PRG-Dateien der IDE)
        cmp OUTBASE
        bne do6
        lda OUTP + 1
        cmp OUTBASE + 1
        bne do6
        lda OUTP + 2
        cmp OUTBASE + 2
        bne do6
        lda VAL
        sta ldadr
        lda VAL + 1
        sta ldadr + 1
do6:    lda #$00
        sta segwrap                 ; neues .org: Ueberlauf aufgehoben
        jsr ln_skip                 ; Fuellbytes zaehlen nicht als Ausgabe der Zeile
        lda VAL
        sta PC
        lda VAL + 1
        sta PC + 1
        jmp d_end
; ldadr: Ladeadresse (PRG-Kopf); wird vom ersten .org vor jeder Ausgabe gesetzt, in asm_run mit 0 belegt
ldadr:  .word 0
; ---- Datenlisten: .byte/.word/.dword/.text/.petscii/.screen/.null/.ptext/.shift. Jede setzt TM (Textkodierung 0 ASCII, 1 PETSCII,
; 2 Bildschirmcode) und SF (Textform: Bit0 .null = Nullbyte anhaengen, Bit1 .ptext = Laengenbyte voran, Bit2 .shift = Bit 7 am
; letzten Zeichen) und SZ (Elementgroesse 1, 2, 4), dann gemeinsame Schleife d_list. .text benutzt die mit .encoding gewaehlte ENC.
d_byte: lda #$00
        sta TM
        sta SF
        sta tonly                   ; .byte nimmt Zahlen und Zeichenketten
        beq d_list1
d_text: lda #$01                    ; Textanweisungen nehmen nur Zeichenketten in Anfuehrungszeichen (sonst E208, wie vcc)
        sta tonly
        lda ENC
        sta TM
        lda #$00
        sta SF
        beq d_list1
d_petscii:
        jsr need_arg
        lda #$01
        sta tonly
        lda #$01
        sta TM
        lda #$00
        sta SF
        beq d_list1
d_screen:
        jsr need_arg
        lda #$01
        sta tonly
        lda #$02
        sta TM
        lda #$00
        sta SF
        beq d_list1
d_null: lda #$01
        sta tonly
        lda ENC
        sta TM
        lda #$01
        sta SF
        bne d_list1
d_ptext:
        lda #$01
        sta tonly
        lda ENC
        sta TM
        lda #$02
        sta SF
        bne d_list1
d_shift:
        lda #$01
        sta tonly
        lda ENC
        sta TM
        lda #$04
        sta SF
        ; d_list1/d_word/d_dword: SZ setzen (1/2/4) und in die Listenschleife
d_list1:
        lda #$01
        bne d_list
d_word: lda #$00
        sta tonly
        lda #$02
        bne d_list
d_dword:
        lda #$00
        sta tonly
        lda #$04
        ; d_list: Schleife ueber die durch Komma getrennten Elemente. Zeichenketten ("...") nur bei SZ = 1 (emit_str). Ausdruecke
        ; (ex_eval_any: auch Listenwerte) werden mit range_byte/range_word geprueft (E203 weich) und little-endian ausgegeben.
d_list: sta SZ
        jsr skipws                  ; leere Liste (.byte ohne Operanden): wie vcc nichts ausgeben, kein Fehler
        jsr at_eol
        beq dl_empty
        jmp dl_next
dl_empty: jmp d_end
dbe_e:  jmp d_end
tonly:  .byte 0                     ; 1 = Textanweisung (nur Zeichenketten)
dl_next:
        jsr skipws
        jsr src_peek
        cmp #$22                    ; "
        bne dl_expr
        lda SZ
        cmp #$01
        beq dl_str
        lda #ERR_SYNTAX
        jmp as_error
dl_str: jsr src_adv
        jsr emit_str
        jmp dl_sep
dl_unterm:
        lda #ERR_SYNTAX
        jmp as_error
dl_expr:
        lda tonly                   ; nur Zeichenketten erlaubt: E208
        beq dl_ex2
        lda #ERR_E208
        jmp as_error
dl_ex2: lda #$00
        sta UNK
        jsr ex_eval_any
        bcc dl_e1
        jmp as_fail
dl_e1:  lda VTY
        cmp #$02
        beq dl_lst
        jsr coerce_int
        jsr opval_from_val
        jsr dl_one
        jmp dl_sep
        ; Liste: alle Elemente flach ausgeben (fl_start/fl_next in list.asm; C=1 am Ende); coerce_int macht Kommazahlen zu Ganzzahlen
dl_lst: jsr fl_start                ; Liste: alle Elemente flach ausgeben
dl_ln:  jsr fl_next
        bcs dl_sep
        jsr coerce_int
        jsr opval_from_val
        jsr dl_one
        jmp dl_ln
        ; dl_one: OPVAL in der Elementgroesse SZ ausgeben (little-endian: tiefes Byte zuerst)
dl_one: lda SZ
        cmp #$01
        beq dl_b
        cmp #$02
        beq dl_w
        lda OPVAL                   ; .dword
        jsr emit_byte
        lda OPVAL + 1
        jsr emit_byte
        lda OPVAL + 2
        jsr emit_byte
        lda OPVAL + 3
        jmp emit_byte
dl_w:   jsr range_word
        lda OPVAL
        ldx OPVAL + 1
        jmp emit_word
dl_b:   jsr range_byte
        lda OPVAL
        jmp emit_byte
        ; Trennzeichen: ',' -> naechstes Element, sonst Zeilenende pruefen
dl_sep: jsr skipws
        jsr src_peek
        cmp #$2c
        bne d_end
        jsr src_adv
        jmp dl_next

; d_const: .const / .equ name = ausdruck: wie "name = ausdruck" (al_const); der Name muss ein Bezeichner sein
d_const:
        jsr skipws
        jsr src_peek
        jsr is_identchar
        bcc dc1
        lda #ERR_SYNTAX
        jmp as_error
dc1:    jsr read_ident
        jsr skipws
        jsr src_peek
        cmp #$3d
        beq dc2
        lda #ERR_SYNTAX
        jmp as_error
dc2:    jmp al_const

; d_target: .target mega65 - einziger erlaubter Name (sonst ERR_TARGET). Der Name steht in tgtname (0-terminiert).
d_target:
        jsr skipws
        jsr at_eol                  ; .target ohne Operanden: ohne Wirkung (wie vcc)
        beq dtg_e
        jsr read_ident
        ldx #$00
dt1:    lda tgtname,x
        beq dt2
        cmp NAMEBUF,x
        bne dt_bad
        inx
        bne dt1
dt2:    cpx NAMELEN
        bne dt_bad
        jmp d_end
dtg_e:  jmp d_end
dt_bad: lda #ERR_TARGET             ; VC65 uebersetzt nur fuer den MEGA65
        jmp as_error
tgtname: .byte "mega65", 0

; d_cpu: .cpu name [{ ... }] - wird gelesen und ignoriert, damit Quelltexte aus anderen Assemblern uebersetzbar bleiben
d_cpu:  jsr skipws                  ; .cpu <name> [{ ... }]: Name und Block werden gelesen und ignoriert
        jsr read_ident
        jsr skipws
        jsr src_peek
        cmp #$7b
        bne d_end
dcp1:   jsr src_peek
        beq d_end
        cmp #$7d
        beq dcp2
        jsr src_adv
        jmp dcp1
dcp2:   jsr src_adv
        jmp d_end

; d_branchlong: .branchlong auto|on|off - BLONG = 1 (auto/on/sonst) oder 0 (off). Bei BLONG verlaengert encode (long_check) zu weite
; Spruenge zu LBxx; der Zustand gilt bis zur naechsten .branchlong-Zeile (wird pro Durchlauf zu Beginn auf 0 gesetzt).
d_branchlong:
        jsr skipws
        jsr read_ident
        lda NAMELEN                 ; erlaubt sind auto, jmp und off (Gross-/Kleinschreibung egal), sonst E208 wie vcc
        cmp #$04
        bne dbl_3
        ldy #$00                    ; auto
        jsr dbl_try
        bcs dbl_bad
        bcc dbl_on
dbl_3:  cmp #$03
        bne dbl_bad
        ldy #$07                    ; off
        jsr dbl_try
        bcc dbl_off
        ldy #$04                    ; jmp
        jsr dbl_try
        bcs dbl_bad
dbl_on: lda #$01
        sta BLONG
        jmp d_end
dbl_off: lda #$00
        sta BLONG
        jmp d_end
dbl_bad: lda #ERR_E208
        jmp as_error
; dbl_try: NAMEBUF (NAMELEN Zeichen, klein) mit dem Wort ab bl_tab + Y vergleichen; Carry geloescht = gleich
dbl_try: ldx #$00
dt_l:   cpx NAMELEN
        beq dt_ok
        lda NAMEBUF,x
        ora #$20
        cmp bl_tab,y
        bne dt_no
        inx
        iny
        bne dt_l
dt_ok:  clc
        rts
dt_no:  sec
        rts
bl_tab: .byte "auto", "jmp", "off"

; d_segment: .segment "name" [, anfang [, ende]] - Bereich fuer die folgende Ausgabe (emit_byte prueft PC gegen seglo..seghi, sonst E301).
; Nur mit Anfang und Ende gilt eine Pruefung (segon = 1); Anfang hinter Ende: E203; Name ohne Anfuehrungszeichen: E208 (wie vcc).
; Ein neues .segment ersetzt das vorige. Zerstoert A, X, Y u. a.
d_segment:
        lda #$00
        sta segon
        jsr skipws                  ; .segment ohne Operanden: ohne Wirkung (wie vcc)
        jsr at_eol
        beq dsg_end
        jsr dsg_name
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne dsg_end                 ; nur der Name: kein Bereich
        jsr src_adv
        jsr skipws
        lda #$00
        sta UNK
        jsr eval_op
        lda OPVAL
        sta seglo
        lda OPVAL + 1
        sta seglo + 1
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne dsg_end                 ; Name und Anfang: kein Bereich
        jsr src_adv
        jsr skipws
        lda #$00
        sta UNK
        jsr eval_op
        lda OPVAL
        sta seghi
        lda OPVAL + 1
        sta seghi + 1
        lda seghi + 1               ; Anfang <= Ende? sonst E203
        cmp seglo + 1
        bcc dsg_rev
        bne dsg_ok
        lda seghi
        cmp seglo
        bcs dsg_ok
dsg_rev: lda #ERR_E203
        jmp as_error
dsg_ok: lda #$01
        sta segon
dsg_end: jmp d_end

; dsg_name: Name in Anfuehrungszeichen ueberlesen (.segment, .cartridge): ohne " E208, ohne schliessendes " Syntaxfehler
dsg_name:
        jsr skipws
        jsr src_peek
        cmp #$22
        beq dsg_n
        lda #ERR_E208
        jmp as_error
dsg_n:  jsr src_adv
dsg_l:  jsr src_peek
        beq dsg_bad
        cmp #$0a
        beq dsg_bad
        cmp #$22
        beq dsg_c
        jsr src_adv
        jmp dsg_l
dsg_bad: lda #ERR_SYNTAX
        jmp as_error
dsg_c:  jmp src_adv                 ; schliessendes " verbrauchen

; need_arg: ohne Operanden E208 (.petscii/.screen/.screencode ohne Text, wie vcc); sonst Rueckkehr
need_arg:
        jsr skipws
        jsr at_eol
        bne na_ok
        lda #ERR_E208
        jmp as_error
na_ok:  rts

; d_bank: .bank n - n muss 0..1023 sein (sonst E203); PRG-Ausgabe kennt nur Bank 0: jede andere Bank E901 (vcc meldet dort ohne Code
; "mehrere Baenke gibt es nur in den Modulformaten crt/car/rom"). Unbekannter Wert (UNK) im ersten Durchlauf: keine Pruefung.
d_bank: lda #$00
        sta UNK
        jsr eval_op
        lda UNK
        bne dbk_ok
        lda OPVAL + 2
        ora OPVAL + 3
        bne dbk_bad
        lda OPVAL + 1
        cmp #$04
        bcs dbk_bad
        ora OPVAL
        beq dbk_ok
        lda #ERR_E901
        jmp as_error
dbk_bad: lda #ERR_E203
        jmp as_error
dbk_ok: jmp d_end

; d_align: .align n [, fuellbyte | skip] - PC auf ein Vielfaches von n bringen (n = Zweierpotenz, sonst E203). Fuellbyte (Standard 0)
; auffuellen; mit "skip" wird die Luecke nicht als Ausgabe der Zeile gezaehlt. aln_msk = n - 1; Zerstoert A, X, Y u. a.
d_align:
        lda #$00
        sta UNK
        jsr eval_op
        lda OPVAL + 2               ; n hoechstens 16 Bit (wie vcc: .align 256 ist erlaubt)
        ora OPVAL + 3
        bne da_bad
        lda OPVAL
        ora OPVAL + 1
        beq da_bad
        sec                         ; Maske = n - 1 (16 Bit); Zweierpotenz genau dann, wenn n AND (n - 1) = 0
        lda OPVAL
        sbc #$01
        sta aln_msk
        lda OPVAL + 1
        sbc #$00
        sta aln_msk + 1
        lda aln_msk
        and OPVAL
        sta aln_t
        lda aln_msk + 1
        and OPVAL + 1
        ora aln_t
        bne da_bad                  ; n muss eine Zweierpotenz sein
        ; Der Operand hinter dem Komma ist entweder das Schluesselwort "skip" (4 Zeichen, vergleicht mit aln_skipw) oder ein Ausdruck
        lda #$00                    ; optional , skip | Fuellbyte (skip: wie ohne Angabe, die Luecke ist im Rohformat 0)
        sta aln_fil
        sta aln_isk
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne da_l
        jsr src_adv
        jsr skipws
        ldx #$03
da_sv:  lda SRC,x
        sta aln_sav,x
        dex
        bpl da_sv
        ; SRC ist in aln_sav gesichert: der Bezeichner koennte der Anfang eines Ausdrucks sein (z. B. ein Symbol)
        jsr src_peek                ; beginnt der Ausdruck mit einem Bezeichner, ist es vielleicht das Schluesselwort skip
        jsr is_identchar
        bcs da_ex
        jsr read_ident
        lda NAMELEN
        cmp #$04
        bne da_rs
        ldx #$03
da_kw:  lda NAMEBUF,x
        ora #$20
        cmp aln_skipw,x
        bne da_rs
        dex
        bpl da_kw
        lda #$01                    ; skip: die Luecke zaehlt nicht als Ausgabe der Zeile (Zeilentabelle wie vcc)
        sta aln_isk
        jmp da_l
da_rs:  ldx #$03                    ; kein skip: Ausdruck von vorn lesen
da_r1:  lda aln_sav,x
        sta SRC,x
        dex
        bpl da_r1
da_ex:  lda #$00
        sta UNK
        jsr eval_op
        lda OPVAL
        jsr range_byte
        lda OPVAL
        sta aln_fil
        ; Fuellschleife: solange PC AND Maske <> 0 ein Fuellbyte ausgeben
da_l:   lda PC
        and aln_msk
        sta aln_t
        lda PC + 1
        and aln_msk + 1
        ora aln_t
        beq da_dn
        lda aln_fil
        jsr emit_byte
        jmp da_l
da_dn:  lda aln_isk
        beq da_de
        jsr ln_skip
da_de:  jmp d_end
        ; (da_bad) Alignment 0, > 255 oder keine Zweierpotenz: E203
da_bad: lda #ERR_E203
        jmp as_error

; .basicstub: ergaenzt in zwei Schritten: Warnung bei falscher Startadresse, dann Ziffern des Ziels, dann Zeilenaufbau.
; Aufbau der Ausgabe: Verbindungszeiger (2), Zeilennummer (2), $9E (SYS), Ziffern des Ziels, [:REM text = $3A $8F $20 text], $00
; (Zeilenende), $00 $00 (Programmende). Das Ziel wird in 5 Dezimalziffern zerlegt (Abzug von 10000/1000/100/10/1, pow10lo/hi).
; .basicstub <ziel>: BASIC-Zeile "10 SYS <ziel>" (12 Byte bei vierstelligem Ziel)
d_basicstub:
        lda orgs                    ; ohne vorheriges .org beginnt das Programm bei $2001 (wie vcc)
        bne dbs_o
        lda #$01
        sta orgs
        lda #<$2001
        sta PC
        sta ldadr
        lda #>$2001
        sta PC + 1
        sta ldadr + 1
dbs_o:  lda #$00                    ; W204 erst nach der E218-Pruefung melden (E218 geht vor); nicht in einer .pseudopc-Region (wie vcc)
        sta dbs_wf
        lda pson
        bne dbs_n204
        lda PC                      ; nicht an der BASIC-Startadresse $2001: Warnung W204 (wie vcc)
        cmp #<$2001
        bne dbs_w204
        lda PC + 1
        cmp #>$2001
        beq dbs_n204
dbs_w204:  lda #$01
        sta dbs_wf
        ; E218: .basicstub muss vor allen anderen Ausgaben stehen
dbs_n204: lda OUTP                    ; davor wurden schon Bytes ausgegeben: E218
        cmp OUTBASE
        bne dbs_e218
        lda OUTP + 1
        cmp OUTBASE + 1
        bne dbs_e218
        lda OUTP + 2
        cmp OUTBASE + 2
        beq dbs_e0
dbs_e218:
        lda #ERR_E218
        jmp as_error
dbs_e0: lda dbs_wf
        beq dbs_nw
        lda #WARN_W204
        jsr warn_add
dbs_nw: lda #$00
        sta UNK
        jsr eval_op
        lda UNK                     ; Ziel noch unbekannt (erster Durchlauf): wie vcc 2061 annehmen
        beq dbs_kn
        lda #<2061
        sta OPVAL
        lda #>2061
        sta OPVAL + 1
        lda #$00
        sta OPVAL + 2
        sta OPVAL + 3
dbs_kn:
        ; Dezimalziffern des Ziels (Abziehen der Zehnerpotenzen); TMP2 <> 0 sobald die erste Ziffer ungleich 0 ausgegeben wurde,
        ; fuehrende Nullen entfallen ausser der letzten Stelle (Y = 4). Ziffern landen als ASCII in LNAME, Anzahl in LLEN
        ldx #$00                    ; Ziffern nach LNAME (ohne fuehrende Nullen)
        stx TMP2
        ldy #$00
dbs_p:  lda OPVAL
        sta TMP
        lda OPVAL + 1
        sta TMP + 1
        lda #$00
        ; (TMP+2 = Ziffer des aktuellen Zehnerpotenz-Durchlaufs)
        sta TMP + 2                 ; Ziffernzaehler
dbs_s:  lda TMP
        sec
        sbc pow10lo,y
        pha
        lda TMP + 1
        sbc pow10hi,y
        bcc dbs_u
        sta TMP + 1
        pla
        sta TMP
        inc TMP + 2
        jmp dbs_s
dbs_u:  pla
        lda TMP2
        ora TMP + 2
        bne dbs_w
        cpy #$04
        bne dbs_n                   ; fuehrende Null (ausser letzter Stelle)
dbs_w:  lda TMP + 2
        clc
        adc #$30
        sta LNAME,x
        inx
        lda #$01
        sta TMP2
dbs_n:  lda TMP
        sta OPVAL
        lda TMP + 1
        sta OPVAL + 1
        iny
        cpy #$05
        bne dbs_p
        ; Anzahl der Ziffern merken; Standard: Zeilennummer 10, kein Kommentar
        stx LLEN                    ; Anzahl der Ziffern
        lda #$0a                    ; Zeilennummer 10, kein Kommentar
        sta bline
        lda #$00
        sta bline + 1
        sta bclen
        ; Optionen hinter dem Ziel: , zeilennummer (hoechstens 63999) und , "kommentar" (hoechstens 30 Zeichen, Grossbuchstaben)
        jsr skipws                  ; [, zeilennummer] [, "kommentar"]
        jsr src_peek
        cmp #$2c
        bne dbs_nc
        jsr src_adv
        jsr skipws
        jsr src_peek
        cmp #$22
        beq dbs_str
        jsr eval_op
        lda OPVAL + 2
        ora OPVAL + 3
        bne dbs_bad
        lda OPVAL + 1               ; hoechstens 63999
        cmp #$fa
        bcs dbs_bad
        sta bline + 1
        lda OPVAL
        sta bline
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne dbs_nc
        jsr src_adv
        jsr skipws
        jsr src_peek
        cmp #$22
        bne dbs_syn
dbs_str:
        jsr src_adv
dbs_c:  jsr src_peek
        beq dbs_syn
        cmp #$0a
        beq dbs_syn
        cmp #$22
        beq dbs_ce
        ldx bclen
        cpx #$1e
        bcs dbs_bad
        cmp #$7b                    ; {$hh}: Bytewert (wie vcc), sonst { wie jedes Zeichen
        bne dbs_nb
        jsr src_peek1
        cmp #$24
        bne dbs_lit
        jsr src_adv                 ; { und $ verbrauchen
        jsr src_adv
        jsr dbs_hex                 ; erste Hexziffer
        bcs dbs_syn
        asl
        asl
        asl
        asl
        sta bcom_t
        jsr src_adv
        jsr dbs_hex                 ; zweite Hexziffer
        bcs dbs_syn
        ora bcom_t
        sta bcom_t
        jsr src_adv
        jsr src_peek                ; schliessende }
        cmp #$7d
        bne dbs_syn
        ldx bclen
        lda bcom_t
        jmp dbs_cu
dbs_lit: lda #$7b
dbs_nb: cmp #$61                    ; Kleinbuchstaben -> Grossbuchstaben (wie vcc)
        bcc dbs_cu
        cmp #$7b
        bcs dbs_cu
        and #$df
dbs_cu: sta bcom,x
        inc bclen
        jsr src_adv
        jmp dbs_c
dbs_ce: jsr src_adv
        jmp dbs_nc
; dbs_hex: Zeichen bei SRC als Hexziffer: A = Wert 0-15, C=0; sonst C=1
dbs_hex: jsr src_peek
        cmp #$30
        bcc dh_bad
        cmp #$3a
        bcc dh_d
        and #$df
        cmp #$41
        bcc dh_bad
        cmp #$47
        bcs dh_bad
        sec
        sbc #$37
        clc
        rts
dh_d:   sec
        sbc #$30
        clc
        rts
dh_bad: sec
        rts
bcom_t: .byte 0

dbs_syn:
        lda #ERR_SYNTAX
        jmp as_error
dbs_bad:
        lda #ERR_E203
        jmp as_error
        ; Verbindungszeiger = Adresse des Zeilenendes + 1, relativ PC (PC steht am Zeilenanfang): Ziffern + 4 (Zeilennr. gibt es nicht
        ; im Zaehler: zaehlt nach dem Verbindungszeiger) bzw. + (3 + Kommentar) fuer ":REM "
dbs_nc: lda LLEN                    ; Laenge hinter dem Verbindungszeiger: 2 + 1 + n + 1 (+ 3 + Kommentar)
        clc
        adc #$04
        sta TMP2
        lda bclen
        beq dbs_k
        lda TMP2
        clc
        adc bclen
        adc #$03
        sta TMP2
dbs_k:  lda PC                      ; Verbindungszeiger = PC + 2 + TMP2
        clc
        adc TMP2
        sta TMP
        lda PC + 1
        adc #$00
        sta TMP + 1
        lda TMP
        clc
        adc #$02
        sta TMP
        bcc dbs_l
        inc TMP + 1
dbs_l:  lda TMP
        jsr emit_byte
        lda TMP + 1
        jsr emit_byte
        lda bline
        jsr emit_byte
        lda bline + 1
        jsr emit_byte
        ; Zeilenaufbau: Verbindungszeiger, Zeilennummer, SYS-Token, Ziffern, ggf. Kommentar, drei Nullbytes
        lda #$9e                    ; SYS
        jsr emit_byte
        ldx #$00
dbs_e:  cpx LLEN
        beq dbs_z
        lda LNAME,x
        jsr emit_byte
        inx
        bne dbs_e
dbs_z:  lda bclen
        beq dbs_z2
        lda #$3a                    ; :REM text
        jsr emit_byte
        lda #$8f
        jsr emit_byte
        lda #$20
        jsr emit_byte
        ldx #$00
dbs_t:  cpx bclen
        beq dbs_z2
        lda bcom,x
        jsr emit_byte
        inx
        bne dbs_t
dbs_z2: lda #$00
        jsr emit_byte               ; Zeilenende
        lda #$00
        jsr emit_byte               ; Programmende
        lda #$00
        jsr emit_byte
        jmp d_end
dbs_wf: .byte 0                     ; 1 = W204 melden (nach der E218-Pruefung)
pow10lo: .byte <10000, <1000, <100, <10, <1
pow10hi: .byte >10000, >1000, >100, >10, >1

; bits_clear: Tabelle der langen Spruenge (siehe long_check in enc.asm) leeren: 4096 Byte ab $0812_0000 im Attic (BITP, 32-Bit-Zeiger),
; ein Byte je Verzweigung in Quelltextreihenfolge (Index BIDX, 16 Bit). Zerstoert A, X, Z, BITP. Wird einmal je asm_run gerufen.
; Beachte: Die Tabelle ist 4096 Byte gross, BIDX zaehlt aber bis 65535 (mehr als 4096 Verzweigungen waeren nicht abgesichert).
bits_clear:
        lda #$00
        sta BITP
        sta BITP + 1
        lda #$08
        sta BITP + 3
        lda #$12
        sta BITP + 2                ; Tabelle der langen Spruenge im Attic: $0812_0000
        ; 16 Seiten zu 256 Byte; Z laeuft 0..255 (45GS02: Z-indizierter 32-Bit-Zeiger [BITP],z)
        ldx #$10                    ; 16 Seiten
bc_p:   ldz #$00
        lda #$00
bc_l:   sta [BITP],z
        inz
        bne bc_l
        inc BITP + 1
        dex
        bne bc_p
        rts

; bit_ptr: BITP = $0812_0000 + BIDX
bit_ptr:
        lda BIDX
        sta BITP
        lda BIDX + 1
        sta BITP + 1
        lda #$12
        sta BITP + 2
        lda #$08
        sta BITP + 3
        rts

; emit_str: Zeichenkette (Anfuehrungszeichen am Anfang schon gelesen) mit Kodierung TM und Form SF ausgeben
        ; Ausgabe der Zeichenkette (SRC steht hinter dem '"'). SF Bit1 (.ptext): zuerst Laenge als Byte, ermittelt durch Trockenlauf
        ; mit cntmode = 1 (es_out zaehlt nur, cntb); dann nochmal wirklich. SF Bit0: Nullbyte am Ende. Zerstoert A, X, Y u. a.
emit_str:
        lda SF                      ; .shift/.textshift mit leerem Text: E203 (wie vcc: .textshift: leerer Text)
        and #$04
        beq es_sh0
        jsr src_peek
        cmp #$22
        bne es_sh0
        lda #ERR_E203
        jmp as_error
es_sh0: lda SF
        and #$02
        beq es_go0
        ldx #$03                    ; .ptext: Laenge vorab zaehlen (Trockenlauf, SRC wird zurueckgesetzt)
es1:    lda SRC,x
        sta TMP2,x
        dex
        bpl es1
        lda #$01
        sta cntmode
        lda #$00
        sta cntb
        jsr es_body
        ldx #$03
es4:    lda TMP2,x
        sta SRC,x
        dex
        bpl es4
        lda #$00
        sta cntmode
        lda cntb
        jsr emit_byte
es_go0: jsr es_body
        lda SF
        and #$01
        beq es_ret
        lda #$00                    ; .null: abschliessendes Nullbyte je Kette
        jmp emit_byte
es_ret: rts

        ; es_body: Zeichen bis zum schliessenden '"' lesen; '{' leitet eine Sonderzeichen-Folge ein (es_brace, text2.asm); Zeilenende
        ; oder 0 vor dem schliessenden '"': Syntaxfehler (unterminierte Kette)
es_body:
es_go:  jsr src_peek
        beq es_bad
        cmp #$0a
        beq es_bad
        cmp #$22
        beq es_close
        cmp #$7b
        bne es_chr
        ldx TM                      ; ASCII (.text, .byte): { ist ein gewoehnliches Zeichen (wie vcc); nur PETSCII/Bildschirmcode kennen {name}
        beq es_chr
        jmp es_brace
es_chr: jsr conv_char
        pha
        lda SF
        and #$04
        beq es_n
        ; .shift: das letzte Zeichen (hinter dem kein weiteres vor '"') mit gesetztem Bit 7
        jsr src_peek1               ; .shift: letztes Zeichen der Kette mit gesetztem Bit 7
        cmp #$22
        bne es_n
        pla
        ora #$80
        pha
es_n:   pla
        jsr es_out
        jsr src_adv
        jmp es_go
es_close:
        jmp src_adv                 ; schliessendes " verbrauchen
es_bad: lda #ERR_SYNTAX
        jmp as_error

; conv_char: A = Quellzeichen -> Zielzeichen nach TM (0 unveraendert, 1 PETSCII, 2 Bildschirmcode)
conv_char:
        ldx TM
        beq cc_ret
        cpx #$02
        beq cc_scr
        cmp #$61                    ; PETSCII: a-z -> $41-$5a, A-Z -> $c1-$da
        bcc cc_up
        cmp #$7b
        bcs cc_ret
        sec
        sbc #$20
        rts
cc_up:  cmp #$41
        bcc cc_ret
        cmp #$5b
        bcs cc_ret
        clc
        adc #$80
cc_ret: rts
cc_scr: cmp #$40                    ; Bildschirmcode: @ -> 0, a-z -> 1-26, A-Z unveraendert, [ \ ] ^ _ -> $1b-$1f
        bne cs1
        lda #$00
        rts
cs1:    cmp #$61
        bcc cs2
        cmp #$7b
        bcs cc_ret
        sec
        sbc #$60
        rts
cs2:    cmp #$5b
        bcc cc_ret
        cmp #$60
        bcs cc_ret
        sec
        sbc #$40
        rts

        ; d_encoding: .encoding "name" [{ ... }]: legt die Kodierung fuer .text fest (ENC); der alte Wert wird in encold gesichert,
        ; folgt '{', wird der alte Wert auf den Scope-Stapel gelegt (de_fin/encblk_push, text2.asm) und am Blockende wiederhergestellt.
        ; Erlaubt: "ascii" (0), "petscii" (1), "screen" (2); der erste Buchstabe entscheidet (p -> 1, s -> 2).
d_encoding:
        lda ENC
        sta encold
        jsr skipws
        jsr src_peek
        cmp #$22
        bne de_bad
        jsr src_adv
        ldx #$00
de1:    jsr src_peek
        beq de_bad
        cmp #$22
        beq de2
        sta NAMEBUF,x
        inx
        jsr src_adv
        jmp de1
de2:    jsr src_adv
        stx NAMELEN
        lda #$00                    ; ascii
        sta ENC
        ; (enc_check, text2.asm: prueft den Namen, sonst Fehler)
        jsr enc_check               ; nur ascii, petscii, screen
        lda NAMEBUF
        ora #$20
        cmp #$70                    ; p(etscii)
        bne de3
        lda #$01
        sta ENC
        jmp de_fin
de3:    cmp #$73                    ; s(creen)
        bne de4
        lda #$02
        sta ENC
de4:    jmp de_fin
de_bad: lda #ERR_SYNTAX
        jmp as_error

        ; (Big Endian: hoechstes Byte zuerst. Werte bis 32 Bit; es erfolgt keine Bereichspruefung der Zeichenbreite)
; .be16 / .be32: grosse Zahlen zuerst (Big Endian); .rta: Wert - 1 als Wort (Return-Adresse fuer RTS)
d_be16: lda #$02
        bne dbe0
d_be32: lda #$04
dbe0:   sta SZ
        jsr skipws                  ; ohne Operanden: nichts ausgeben (wie vcc)
        jsr at_eol
        beq dbe_e
dbe1:   lda #$00
        sta UNK
        jsr eval_op
        lda SZ                      ; .be16/.dbyt: 16-Bit-Wert, sonst E203 (weich)
        cmp #$02
        bne dbe_nr
        jsr range_word
dbe_nr:
        lda SZ
        cmp #$04
        bne dbe2
        lda OPVAL + 3
        jsr emit_byte
        lda OPVAL + 2
        jsr emit_byte
dbe2:   lda OPVAL + 1
        jsr emit_byte
        lda OPVAL
        jsr emit_byte
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne dbe3
        jsr src_adv
        jmp dbe1
dbe3:   jmp d_end

        ; d_rta: Komma-getrennte Liste; je Wert Wert - 1 als Wort ausgeben (Rueckkehradresse fuer RTS: RTS erhoeht den Stapelwert)
d_rta:  jsr skipws
        jsr at_eol                  ; ohne Operanden: nichts ausgeben (wie vcc)
        beq dbe_e
        lda #$00
        sta UNK
        jsr eval_op
        jsr range_word              ; 16-Bit-Wert, sonst E203 (weich, wie vcc)
        sec
        lda OPVAL
        sbc #$01
        sta OPVAL
        lda OPVAL + 1
        sbc #$00
        sta OPVAL + 1
        lda OPVAL
        ldx OPVAL + 1
        jsr emit_word
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne rta_e
        jsr src_adv
        jsr skipws
        jmp d_rta
rta_e:  jmp d_end

; .hex "de ad be ef", ... : Bytepaare in Hexschreibweise
        ; Hexadezimalpaare in "..." , Leerzeichen erlaubt; je zwei Hexziffern ein Byte (digval liefert den Wert 0..15, C=1 sonst)
d_hex:  jsr skipws
        jsr at_eol                  ; ohne Operanden: nichts ausgeben (wie vcc)
        beq dbe_e
        jsr src_peek
        cmp #$22
        beq dx1
        lda #ERR_SYNTAX
        jmp as_error
dx1:    jsr src_adv
dx2:    jsr src_peek
        beq dx_bad
        cmp #$22
        beq dx_end
        cmp #$20
        bne dx3
        jsr src_adv
        jmp dx2
dx3:    jsr digval
        bcs dx_bad
        asl
        asl
        asl
        asl
        sta TMP
        jsr src_adv
        jsr src_peek
        jsr digval
        bcs dx_bad
        ora TMP
        jsr emit_byte
        jsr src_adv
        jmp dx2
dx_end: jsr src_adv
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne dx4
        jsr src_adv
        jmp d_hex
dx4:    jmp d_end
dx_bad: lda #ERR_SYNTAX
        jmp as_error

; ---- bedingte Uebersetzung
; Zustand je Ebene (IFSTK): Bit0 aktiv, Bit1 Zweig schon genommen, Bit2 Eltern aktiv
; al_skip: Zeile im nicht genommenen .if-Zweig (ISKIP = 1). Nur .if/.elseif/.else/.endif/.ifdef/.ifndef (Kennungen 24..29) werden
; ausgefuehrt (damit die Verschachtelung stimmt); alles andere wird ignoriert. Danach wie sk_line: Rest der Zeile ueberspringen.
al_skip:
        jsr src_peek
        cmp #$2e                    ; nur Direktiven .if/.elseif/.else/.endif/... sind im uebersprungenen Zweig wichtig
        bne sk_line
        jsr read_ident
        jsr dir_build
        bcs sk_line
        jsr dir_find
        ; Kennung 24..29 = .if .elseif .else .endif .ifdef .ifndef
        cmp #24
        bcc sk_line
        cmp #30
        bcs sk_line
        asl
        tax
        jmp (dirjmp - 2,x)
sk_line:
        jsr src_peek                ; Rest der Zeile ueberspringen
        beq sk_end
        cmp #$0a
        beq sk_nl
        jsr src_adv
        jmp sk_line
sk_nl:  jsr src_adv
        jmp al_line
sk_end: jmp al_line

; if_eval: Ausdruck lesen; A = 1 wenn ungleich 0
if_eval:
        lda #$00
        sta UNK
        jsr eval_op
        lda OPVAL
        ora OPVAL + 1
        ora OPVAL + 2
        ora OPVAL + 3
        beq ie1
        lda #$01
ie1:    rts

; parent_active: A = 1 wenn die umgebende Ebene aktiv ist (oder es keine gibt)
parent_active:
        ldx IFSP
        beq pa1
        lda IFSTK - 1,x
        and #$01
        rts
pa1:    lda #$01
        rts

; if_push: A = neuer Zustand (Bits siehe oben) auf IFSTK legen. Hoechstens 16 Ebenen, sonst E203. Zerstoert A, X.
if_push:                            ; A = neuer Zustand
        ldx IFSP
        cpx #$10
        bcs ip_deep
        sta IFSTK,x
        txa                         ; Quelltextstelle der Eroeffnung merken (fuer E210 "ohne .endif", Fehlerzeile = Beginn des Blocks wie vcc)
        asl
        asl
        tay
        lda SRC
        sta ifpos,y
        lda SRC + 1
        sta ifpos + 1,y
        lda SRC + 2
        sta ifpos + 2,y
        lda SRC + 3
        sta ifpos + 3,y
        inc IFSP
        jmp if_skipflag
ip_deep:
        lda #ERR_E203
        jmp as_error

; if_skipflag: ISKIP = 1 wenn die oberste Ebene nicht aktiv ist
if_skipflag:
        lda #$00
        sta ISKIP
        ldx IFSP
        beq isf1
        lda IFSTK - 1,x
        and #$01
        bne isf1
        lda #$01
        sta ISKIP
isf1:   rts

; d_if: .if ausdruck. Zustand 7 (aktiv, Zweig genommen, Eltern aktiv), 4 (inaktiv, Eltern aktiv) oder 2 (Eltern inaktiv: Ausdruck nicht
; gelesen und die Bedingung gilt als "schon genommen", damit .else/.elseif nichts aktivieren). Endet ueber sk_line bzw. d_end.
d_if:   jsr parent_active
        beq di_dead
        jsr if_eval
        beq di_false
        lda #$07                    ; aktiv, genommen, Eltern aktiv
        jsr if_push
        jmp d_end
di_false:
        lda #$04                    ; inaktiv, Eltern aktiv
        jsr if_push
        jmp d_end
di_dead:
        lda #$02                    ; Eltern inaktiv: Ausdruck wird nicht gelesen
        jsr if_push
        jmp sk_line

; d_ifdef / d_ifndef: A = 0 / 1 (Umkehr) auf den Stapel; Name lesen; Symbol gilt als definiert, wenn es in DIESEM Durchlauf schon
; definiert wurde (sym_defined_new; wie vcc: kein Vorwaertsbezug). Lokale Namen (.x) werden vorher mit mangle erweitert.
d_ifdef:
        lda #$00
        beq dd_go
d_ifndef:
        lda #$01
dd_go:  pha
        jsr skipws
        jsr read_ident
        jsr parent_active
        beq dd_dead
        lda NAMEBUF
        cmp #$2e
        bne dd_f
        jsr mangle
dd_f:   jsr sym_defined_new         ; Carry geloescht = in diesem Durchlauf schon definiert (wie vcc)
        lda #$00
        ; Carry = 1 wenn nicht gefunden; A = 0/1, danach eor 1 -> A = 1 gefunden; mit dem Umkehrmerker (ifndef) verknuepfen
        rol                         ; A = 1 wenn nicht gefunden
        eor #$01                    ; A = 1 wenn gefunden
        sta TMP
        pla
        eor TMP                     ; ifndef kehrt um
        beq di_false2
        lda #$07
        jsr if_push
        jmp d_end
di_false2:
        lda #$04
        jsr if_push
        jmp d_end
dd_dead:
        pla
        lda #$02
        jsr if_push
        jmp sk_line

; d_elseif: nur gueltig innerhalb eines .if (sonst E-Syntaxfehler). Aktiviert den Zweig, wenn die Eltern aktiv sind, noch kein Zweig
; genommen wurde und der Ausdruck wahr ist. Andernfalls Ebene auf inaktiv (Bit0 loeschen), Zeile ueberspringen.
d_elseif:
        ldx IFSP
        bne ei1
        lda #ERR_SYNTAX
        jmp as_error
ei1:    lda IFSTK - 1,x
        and #$04
        beq ei_off                  ; Eltern inaktiv
        lda IFSTK - 1,x
        and #$02
        bne ei_off                  ; Zweig schon genommen
        jsr if_eval
        beq ei_off
        ldx IFSP
        lda #$07
        sta IFSTK - 1,x
        jsr if_skipflag
        jmp d_end
ei_off: ldx IFSP
        lda IFSTK - 1,x
        and #$fe                    ; inaktiv
        sta IFSTK - 1,x
        jsr if_skipflag
        jmp sk_line

; d_else: wie d_elseif ohne Ausdruck. Wurde kein Zweig genommen: aktivieren (Zustand 7); sonst inaktiv und "genommen" (Bit1) setzen.
d_else: ldx IFSP
        bne el1
        lda #ERR_SYNTAX
        jmp as_error
el1:    lda IFSTK - 1,x
        and #$04
        beq el_off
        lda IFSTK - 1,x
        and #$02
        bne el_off
        lda #$07
        sta IFSTK - 1,x
        jsr if_skipflag
        jmp d_end
el_off: lda IFSTK - 1,x
        and #$fe
        ora #$02
        sta IFSTK - 1,x
        jsr if_skipflag
        jmp sk_line

; d_endif: Ebene entfernen (IFSP - 1) und ISKIP neu berechnen; ohne .if: Syntaxfehler. Weiter bei sk_line (Rest ignorieren).
d_endif:
        ldx IFSP
        bne en1x
        lda #ERR_SYNTAX
        jmp as_error
en1x:   dec IFSP
        jsr if_skipflag
        jmp sk_line

; Arbeitszellen von d_align: aln_msk = Maske, aln_isk = "skip", aln_fil = Fuellbyte, aln_sav = gesicherter SRC, aln_skipw = "skip"
aln_msk: .word 0
ifpos:  .fill 64, 0                  ; Quelltextstelle (32 Bit) der Eroeffnung je .if-Ebene
ifu_x:  .byte 0
aln_t:  .byte 0
aln_isk: .byte 0
aln_fil: .byte 0
aln_sav:  .fill 4, 0
aln_skipw: .byte "skip"

; ---- Zeilentabelle fuer den Debugger (Attic LT_B2/LT_B3 = $0860_0000): je Zeile des Hauptprogramms, die Bytes ausgibt, ein
; Eintrag zu 8 Byte: Quelltextstelle (32 Bit, Zeilenanfang), Adresse (16 Bit), Laenge (16 Bit). Zeilen in Makros und in
; Include-Dateien gehen auf die Aufrufzeile; es gilt der letzte Durchlauf (die Tabelle wird je Durchlauf neu aufgebaut).
LT_B2   = $60
LT_B3   = $08
LT_MAX  = 8192

; ln_hook: an jedem Zeilenanfang und nach jeder Anweisung (jmp al_line) sowie am Quelltextende aufgerufen. Nur im Hauptprogramm
; ($0800_0000 bis $080F_FFFF): eine offene Zeile mit neu ausgegebenen Bytes abschliessen; steht SRC am Zeilenanfang, eine neue
; Zeile oeffnen. Ausgabe aus Makros und Include-Dateien landet so bei der Aufrufzeile.
ln_hook:
        ; Nur Quelltext im Hauptprogramm (Attic $0800_0000-$080F_FFFF) wird in die Zeilentabelle aufgenommen (SRC+3 = $08, SRC+2 < $10)
        lda SRC + 3
        cmp #$08
        bne lt_lh_r
        lda SRC + 2
        cmp #$10
        bcs lt_lh_r
        ; Offene Zeile (lt_pend = 1) abschliessen, falls seit ihrem Beginn Bytes ausgegeben wurden (OUTP <> lt_out, drei Byte)
        lda lt_pend
        beq lt_lh_ns
        lda OUTP
        cmp lt_out
        bne lt_lh_rec
        lda OUTP + 1
        cmp lt_out + 1
        bne lt_lh_rec
        lda OUTP + 2
        cmp lt_out + 2
        beq lt_lh_ns
lt_lh_rec: jsr ln_rec
        lda #$00
        sta lt_pend
        ; Beginnt hier eine neue Zeile? (Zeichen davor ist Zeilenende): dann Zeile oeffnen: Quelltextstelle, PC und OUTP merken
lt_lh_ns:  jsr ln_atstart              ; Carry gesetzt: SRC steht am Zeilenanfang
        bcc lt_lh_r
        lda #$01
        sta lt_pend
        ldx #$03
lt_lh_c:   lda SRC,x
        sta lt_pos,x
        dex
        bpl lt_lh_c
        lda PC
        sta lt_pc
        lda PC + 1
        sta lt_pc + 1
        lda OUTP
        sta lt_out
        lda OUTP + 1
        sta lt_out + 1
        lda OUTP + 2
        sta lt_out + 2
lt_lh_r:   rts

; ln_atstart: Carry gesetzt, wenn das Zeichen vor SRC ein Zeilenende ist (oder SRC der Anfang des Quelltexts)
ln_atstart:
        ldx #$03
lt_la_c:   lda SRC,x
        cmp SRCBASE,x
        bne lt_la_n
        dex
        bpl lt_la_c
        sec                         ; Anfang des Quelltexts
        rts
        ; P6 = SRC - 1 (32 Bit, mit Borrow ueber die Bytes); Zeichen mit [P6],z lesen; Z (phz/plz) und P6 (lt_sv) werden gerettet
lt_la_n:   ldx #$03                    ; P6 = SRC - 1 (P6 und Z werden gerettet)
lt_la_s:   lda P6,x
        sta lt_sv,x
        lda SRC,x
        sta P6,x
        dex
        bpl lt_la_s
        lda P6
        bne lt_la_1
        lda P6 + 1
        bne lt_la_2
        dec P6 + 2
lt_la_2:   dec P6 + 1
lt_la_1:   dec P6
        phz
        ldz #$00
        lda [P6],z
        plz
        pha
        ldx #$03
lt_la_r:   lda lt_sv,x
        sta P6,x
        dex
        bpl lt_la_r
        pla
        cmp #$0a
        beq lt_la_y
        cmp #$0d
        beq lt_la_y
        clc
        rts
lt_la_y:   sec
        rts

; ln_skip: bisher ausgegebene Bytes der offenen Zeile nicht zaehlen (Fuellbytes von .org und .page; vcc zaehlt .align mit)
ln_skip:
        lda lt_pend
        beq lt_lk_r
        lda OUTP
        sta lt_out
        lda OUTP + 1
        sta lt_out + 1
        lda OUTP + 2
        sta lt_out + 2
lt_lk_r:   rts

; ln_rec: Eintrag (lt_pos, lt_pc, Laenge = OUTP - lt_out) in die Tabelle
ln_rec: lda lt_cnt + 1
        cmp #>LT_MAX
        bcs lt_lr_x
        ldx #$03                    ; P6 retten
lt_lr_s:   lda P6,x
        sta lt_sv,x
        dex
        bpl lt_lr_s
        ; Tabelle (Attic LT_B3:LT_B2:0000 = $0860_0000) + lt_cnt * 8: 16-Bit-Multiplikation mit drei asl/rol
        lda lt_cnt                    ; P6 = Tabelle + lt_cnt * 8
        asl
        sta P6
        lda lt_cnt + 1
        rol
        sta P6 + 1
        asl P6
        rol P6 + 1
        asl P6
        rol P6 + 1
        lda #LT_B2
        sta P6 + 2
        lda #LT_B3
        sta P6 + 3
        phz
        ldz #$00
        ldx #$00
        ; Eintrag: Quelltextstelle (4), PC (2), Laenge (2) = 8 Byte; Z laeuft durch den Eintrag
lt_lr_p:   lda lt_pos,x
        sta [P6],z
        inz
        inx
        cpx #$04
        bne lt_lr_p
        lda lt_pc
        sta [P6],z
        inz
        lda lt_pc + 1
        sta [P6],z
        inz
        sec
        lda OUTP
        sbc lt_out
        sta [P6],z
        inz
        lda OUTP + 1
        sbc lt_out + 1
        sta [P6],z
        plz
        inc lt_cnt
        bne lt_lr_n
        inc lt_cnt + 1
lt_lr_n:   ldx #$03
lt_lr_r:   lda lt_sv,x
        sta P6,x
        dex
        bpl lt_lr_r
lt_lr_x:   rts

; Daten der Zeilentabelle: lt_cnt = Anzahl Eintraege, lt_pend = 1 wenn eine Zeile offen ist, lt_pos/lt_pc/lt_out = Beginn der Zeile
lt_cnt:   .word 0
lt_pend:  .byte 0
lt_pos: .fill 4, 0
lt_pc:  .word 0
lt_out: .fill 3, 0
lt_sv:  .fill 4, 0

