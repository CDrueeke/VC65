; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; stage2.asm - Stufe 2 des Assemblers: Variablen (.var, .set, name = ..., name += ...), Wiederholungen (.repeat, .for,
; .next, .break, .continue), Makros (.macro, .endmacro, .exitmacro, Textersetzung der Parameter, @Marken) und Scopes
; ({ }, .namespace) samt Namensaufloesung.
;
; ROLLE IM ASSEMBLER
;   asm.asm   : Zeilenschleife (al_line), Direktiventabelle; ruft von hier d_var, d_set, d_repeat, d_for, d_break, d_continue,
;               d_endrep, d_macro, d_endmacro, d_exitmacro, d_namespace, al_open/al_close und macro_call. Hier ruecksprung
;               zur Zeilenschleife per `jmp al_line` bzw. zum Zeilenende per `jmp d_end` (d_end prueft das Zeilenende).
;   expr.asm / numx.asm : Ausdruecke (ex_eval, ex_eval_any, ex_apply, ex_apply_x); sie rufen von hier sym_resolve, wenn ein
;               Name in einem Ausdruck steht. Ergebnisse in VAL (32 Bit) mit Art VTY und Nachkommateil VFR (numx.asm).
;   list.asm  : Listenwerte (VTY = 2); .for ... in liste benutzt l_open / l_get; Listenbloecke liegen im Heap ab $2000.
;   sym.asm   : Symboltabelle (Marken, Hash ab HBASE); sym_resolve faellt auf sym_known_old zurueck, wenn es keine Variable gibt.
;   inc.asm   : .include; FT_INC-Rahmen werden hier in al_eos beendet (inc_return); mac_scan folgt Includes der Vorabsuche.
;   func.asm  : Funktionen und Argumente (Bank 4 ab FUNBASE $4800 / ARGBASE $4C00).
;   text2.asm : Scopes und Kodierung (sflag, encsave: ein Scope kann ein .encoding-Block sein, scope_pop stellt ENC wieder her).
;
; SPEICHERPLAN BANK 4 (S2BANK; Versatze im 32-Bit-Zeiger [P6],z mit Bank-Byte in P6+2; Bank-Byte+3 immer 0)
;   $0000-$1FFF  Variablen (VARBASE..VAREND): Eintraege [Laenge][Name][Art 1][Wert 4][Nachkommateil 4] = Laenge + 10 Byte,
;                lueckenlos aneinandergereiht bis vare (Ende); der LETZTE gleichnamige Eintrag gilt (var_find_exact). Eine
;                Laufvariable wird beim Schleifenende durch Zuruecksetzen von vare wieder entfernt.
;   $2000-$3FFF  Listen-Heap (list.asm, HEAPBASE)
;   $4000-$47FF  Rahmen (FRBASE): 64 Rahmen zu je 32 Byte, Stapel fuer Makroaufrufe, Schleifen und Includes (fcnt = Anzahl)
;   $4800-$5FFF  Funktionen und Argumente (func.asm)
;   $6800-$6FFF  Makrotabelle (MACBASE..MACEND): [Laenge][Name klein][Kopfzeiger 4]; mace = Ende (Vorabsuche mac_scan)
;   $7000-$BFFF  Expansionspuffer (EXPBASE ..): je Makroaufruf der eingesetzte Rumpf; expt = Stand (Stapel, siehe unten)
;   $C000-$FFFF  Hash-Tabelle der Symbole (HBASE, 8192 Plaetze zu 2 Byte; sym.asm)
;   (Bank 6 und hoeher gibt es im Chip-RAM nicht; mit IDE_BUILD liegt das Programm in Bank 5, daher S2BANK = 5.)
;   Die Zuordnung der Bereiche richtet sich nach den Konstanten unten und in den anderen Modulen; im Zweifel gelten diese.
;
; ZEIGER UND NULLSEITE (zp.asm): P6 ($00-$03) und P7 ($04-$07) sind 32-Bit-Zeiger in Bank 4: [P6],z adressiert mit dem
;   45GS02-Z-Register als Index (Befehle ldz/inz/dez/taz/phz/plz) bis 256 Byte ab P6. FP ($08-$0b) zeigt auf den obersten
;   Rahmen. S2T ($0c/$0d) ist eine 16-Bit-Hilfszelle. MP ($fc/$fd) ist ein gewoehnlicher 16-Bit-Zeiger auf die Parametertabelle
;   ptbl (im Hauptspeicher, Zugriff mit (MP),y). SRC ($60-$63) ist der Lesezeiger des Quelltexts (32 Bit; im Makroaufruf zeigt
;   er in den Expansionspuffer). VAL/LHS/TMP/TMP2 sind 32-Bit-Arbeitswerte.
;
; RAHMEN (32 Byte, Felder F_*): F_TYPE Art (FT_*), F_IFSP .if-Tiefe beim Eintritt, F_FLAGS (Bit0 Laufvariable vorhanden,
;   Bit1 sie existierte schon vorher), F_STARTED (Bedingungsschleife begonnen), F_A Rueckkehrstelle (Makro) bzw. Rumpfanfang
;   (Schleife), F_B/F_C/F_D je 4 Byte (Bedeutung je nach Art), F_VPTR Versatz des Variableneintrags, F_EXPT Puffer-Stand vor
;   dem Makroaufruf, F_OLD (4 Byte) alter Wert der Laufvariablen, davor F_OLD-5 alte Art und F_OLD-4..-1 alter Nachkommateil.
;   F_EXPT (22/23) und F_OLD-5 (23) ueberlappen sich; das ist erlaubt, weil F_EXPT nur in Makro- und F_OLD nur in Schleifenrahmen
;   benutzt wird.
;
; ABLAUF MAKROAUFRUF: macro_call zerlegt die Argumente (tok_args -> argtbl), liest den Kopf des Makros (hdr_parse -> ptbl),
;   bindet Argumente und Vorgabewerte (bind_args), kopiert den Rumpf zeilenweise in den Expansionspuffer (copy_line: Parameter
;   ersetzen, @name -> .zqNNNNname, Kommentare weglassen), legt einen FT_MAC-Rahmen an und setzt SRC auf den Pufferanfang. Das
;   Zeichen 0 am Pufferende loest in al_eos die Rueckkehr (macro_return) aus: SRC := Aufrufstelle, expt := alter Stand.
; ABLAUF SCHLEIFE: d_repeat schreibt direkt in einen neuen Rahmen, d_for fuellt erst ftmp (32 Byte) und kopiert es (df_open);
;   loop_open bestimmt den ersten Durchlauf (loop_fetch), .endrepeat/.next (d_endrep -> loop_end) laesst SRC auf den Rumpfanfang (F_A) zurueckspringen.
;
; KONVENTIONEN: Fehler werden mit `lda #ERR_xxx` / `jmp as_error` gemeldet (kehrt nicht zurueck). Routinen mit Ergebnis
;   "gefunden / nicht gefunden" liefern Carry geloescht = gefunden/weiter, Carry gesetzt = nicht gefunden/fertig (je Routine
;   angegeben). Namen stehen in NAMEBUF (bis 31 Zeichen) mit der Laenge NAMELEN; LNAME/LLEN halten einen gesicherten Namen.
;   Fehler: E203 Bereich/Argument, E202 Listenwert erwartet, E209 Makro/Parameter, E210 Struktur (Block ohne Ende, Rahmenart),
;   E211 Tabelle/Puffer voll, E213 Scope nicht geschlossen/ueberzaehlig, E216 .set/Zuweisung auf unbekannte Variable,
;   E900 zu viele Makroparameter.
; INVARIANTEN: fcnt <= 64; die Rahmen werden strikt als Stapel benutzt; expt wird beim Verlassen eines Makros auf den Stand vor
;   dem Aufruf zurueckgesetzt; sdep <= 7 (plen hat 9 Eintraege); vare/mace/expt sind Versatze (16 Bit) in Bank 4.
; =====================================================================================================================
; ---- Konstanten
; Bank 4 und Bereichsgrenzen (siehe Kopf). HMASK = Plaetze - 1 (Maske fuer den Hash-Index, sym.asm).
HBASE   = $c000                     ; Hash-Tabelle der Symbole (Bank 4, 8192 Plaetze zu 2 Byte)
HMASK   = $1fff
.ifdef IDE_BUILD
S2BANK = $05                        ; IDE-Build: Bank 5 (der Kommentar "Bank 4" im Bestand war veraltet)
.else
S2BANK = $04                        ; Bank fuer Variablen, Rahmen, Makros und Puffer
.endif
; Direktivenkennungen (Nummern der Direktiventabelle in dir2.asm/asm.asm), die skip_block und line_dir vergleichen
DID_REPEAT   = 30
DID_ENDREP   = 31
DID_FOR      = 32
DID_NEXT     = 33
DID_MACRO    = 36
DID_ENDMACRO = 37

; Bereichsgrenzen in Bank 4 (Versatze): Variablen VARBASE..VAREND-1, Rahmen ab FRBASE, Makrotabelle MACBASE..MACEND-1,
; Expansionspuffer ab EXPBASE (reicht bis HBASE-1, das prueft em_byte)
VARBASE = $0000
VAREND  = $2000
FRBASE  = $4000
MACBASE = $6800
MACEND  = $7000
EXPBASE = $7000

; Rahmenarten (Wert in F_TYPE). Der Wert 2 wird hier nicht benutzt; FT_INC = 7 gehoert zu inc.asm. loop_end/loop_top akzeptieren genau
; FT_COND..FT_LIST2 als Schleifenrahmen (Bereichspruefung cmp #FT_COND / cmp #FT_LIST2 + 1) - die Werte muessen
; daher lueckenlos aufeinander folgen.
FT_MAC   = 1                        ; Rahmenarten
FT_COND  = 3                        ; .for name = start, bedingung, schritt
FT_RANGE = 4                        ; .repeat und .for ... in range(...)
FT_LIST  = 5                        ; .for ... in [liste] (Text, nicht mehr benutzt)
FT_LIST2 = 6                        ; .for ... in Listenwert

; Rahmenfelder (Versatz im 32-Byte-Rahmen, adressiert mit [FP],z). Je Art:
;   Makro    : F_A = Aufrufstelle (SRC hinter dem Aufruf), F_EXPT = Puffer-Stand vor dem Aufruf
;   Bereich  : F_A Rumpfanfang, F_B naechster Wert, F_C Grenze, F_D Schritt (je 32 Bit)
;   Bedingung: F_B Zeiger auf Text der Bedingung, F_C Zeiger auf Text des Schritts, F_STARTED = erster Test schon gelaufen
;   Liste    : F_B Zeiger auf Listenblock-Elemente (FT_LIST2: Zeiger), F_C Anzahl, F_D Index des naechsten Elements
F_TYPE    = 0                       ; Rahmenfelder (32 Byte)
F_IFSP    = 1                       ; .if-Tiefe beim Eintritt
F_FLAGS   = 2                       ; Bit0 Laufvariable vorhanden, Bit1 sie gab es schon vorher
F_STARTED = 3
F_A       = 4                       ; Makro: Rueckkehrstelle; Schleife: Rumpfanfang
F_B       = 8                       ; Bereich: naechster Wert; Bedingungsschleife: Text der Bedingung; Liste: Zeiger
F_C       = 12                      ; Bereich: Grenze; Bedingungsschleife: Text des Schritts
F_D       = 16                      ; Bereich: Schritt
F_VPTR    = 20                      ; Versatz des Variableneintrags (16 Bit)
F_EXPT    = 22                      ; Makro: Puffer-Stand vor dem Aufruf (16 Bit)
F_OLD     = 28                      ; alter Wert der Laufvariablen

; -----------------------------------------------------------------------------------------------------------------------
; s2_init: einmal vor dem ersten Durchlauf. Makrotabelle leeren (mace := MACBASE) und alle .macro-Zeilen vorab suchen
; (mac_scan), damit ein Makro schon vor seiner Definition aufgerufen werden kann. Veraendert A, X, Y, Z.
; -----------------------------------------------------------------------------------------------------------------------
; ---- Initialisierung
s2_init:
        lda #<MACBASE
        sta mace
        lda #>MACBASE
        sta mace + 1
        jmp mac_scan

; -----------------------------------------------------------------------------------------------------------------------
; s2_pass: Zustand fuer einen neuen Durchlauf (Pass) ueber den Quelltext zuruecksetzen: keine Rahmen (fcnt), keine Variablen
; (vare), Makroaufrufzaehler mcall = 0 (fuer die eindeutigen @Marken), Scope-Tiefe sdep = 0, keine Marke in der Zeile,
; Expansionspuffer leer (expt := EXPBASE). Die Makrotabelle bleibt erhalten. Veraendert A.
; -----------------------------------------------------------------------------------------------------------------------
s2_pass:
        lda #$00
        sta fcnt
        sta vare
        sta vare + 1
        sta mcall
        sta mcall + 1
        sta sdep
        sta pson
        sta anoncnt
        sta anoncnt + 1
        sta lblflag
        sta plen
        lda #<EXPBASE
        sta expt
        lda #>EXPBASE
        sta expt + 1
        rts

; p6_load / p7_load: 32-Bit-Zeiger P6 bzw. P7 := Bank S2BANK, Versatz X:A. Das oberste Byte ($00) ist bei jedem [zp],z-Zugriff
; Teil der 32-Bit-Adresse (Bank-Byte P+2, Megabyte-Byte P+3 = 0). Veraendert A.
; ---- Zeiger in Bank 4 (A = niederwertig, X = hoeherwertig)
p6_load:
        sta P6
        stx P6 + 1
        lda #S2BANK
        sta P6 + 2
        lda #$00
        sta P6 + 3
        rts

p7_load:
        sta P7
        stx P7 + 1
        lda #S2BANK
        sta P7 + 2
        lda #$00
        sta P7 + 3
        rts

; Kopierhilfen fuer 32-Bit-Werte (4 Byte, X zaehlt 3..0, bpl endet bei X = $ff). Namensschema cp_<von>_<nach>.
; Veraendern A, X; Flags undefiniert; kehren immer zurueck.
; ---- Kopierhilfen (vier Byte)
cp_val_tmp:
        ldx #$03
cvt1:   lda VAL,x
        sta TMP,x
        dex
        bpl cvt1
        rts
cp_tmp_val:
        ldx #$03
ctv1:   lda TMP,x
        sta VAL,x
        dex
        bpl ctv1
        rts
cp_tmp_lhs:
        ldx #$03
ctl1:   lda TMP,x
        sta LHS,x
        dex
        bpl ctl1
        rts
cp_val_lhs:
        ldx #$03
cvl1:   lda VAL,x
        sta LHS,x
        dex
        bpl cvl1
        rts
cp_val_tmp2:
        ldx #$03
cv21:   lda VAL,x
        sta TMP2,x
        dex
        bpl cv21
        rts
cp_tmp2_val:
        ldx #$03
c2v1:   lda TMP2,x
        sta VAL,x
        dex
        bpl c2v1
        rts
cp_tmp_src:
        ldx #$03
cts1:   lda TMP,x
        sta SRC,x
        dex
        bpl cts1
        rts
cp_src_tmp:
        ldx #$03
cst1:   lda SRC,x
        sta TMP,x
        dex
        bpl cst1
        rts

; -----------------------------------------------------------------------------------------------------------------------
; Variablentabelle. Eintrag: [Laenge n][Name n Byte][Art VTY][Wert 4 Byte][Nachkommateil VFR 4 Byte]  (n + 10 Byte).
; Die Eintraege folgen lueckenlos; Ende = vare. Neue Eintraege kommen hinten an; ein spaeter angelegter Eintrag desselben
; Namens verdeckt den frueheren (das Verlassen einer Schleife mit Laufvariable entfernt ihn wieder).
; -----------------------------------------------------------------------------------------------------------------------
; ---- Variablen
; var_find_exact: NAMEBUF/NAMELEN (genau diese Schreibung, ohne Scope-Aufloesung) suchen. Es wird die ganze Tabelle von
; VARBASE bis vare durchlaufen und der LETZTE Treffer gemerkt (vm = Versatz, vmf = Treffer vorhanden).
; Ausgabe: Carry geloescht = gefunden, P6 = Eintrag; Carry gesetzt = nicht gefunden (P6 undefiniert).
; Verwendet P7 als Laufzeiger; veraendert A, X, Z, P6, P7. Z indiziert Laenge und Name im Eintrag (Name <= 31 Zeichen,
; der Index bleibt unter 256).
var_find_exact:
        lda #$00
        sta vmf                     ; vmf = 0: noch kein Treffer
        sta P7
        sta P7 + 1
        lda #S2BANK
        sta P7 + 2
        lda #$00
        sta P7 + 3
vf_l:   lda P7                      ; Ende erreicht? P7 (16 Bit) mit vare vergleichen
        cmp vare
        bne vf_go
        lda P7 + 1
        cmp vare + 1
        beq vf_done
vf_go:  ldz #$00                    ; Z = 0: Laengenbyte des Eintrags
        lda [P7],z
        cmp NAMELEN                 ; Laenge verschieden: Eintrag kann nicht passen
        bne vf_n
        inz
        ldx #$00
vf_c:   cpx NAMELEN
        beq vf_hit
        lda [P7],z
        cmp NAMEBUF,x
        bne vf_n
        inz
        inx
        bne vf_c
vf_hit: lda P7                      ; Treffer: Versatz merken, aber weitersuchen (der letzte gewinnt)
        sta vm
        lda P7 + 1
        sta vm + 1
        lda #$01
        sta vmf
vf_n:   ldz #$00                    ; naechster Eintrag: P7 += Laenge + 10
        lda [P7],z
        clc
        adc #$0a
        clc
        adc P7
        sta P7
        bcc vf_l
        inc P7 + 1
        jmp vf_l
vf_done:
        lda vmf
        beq vf_no
        lda vm
        ldx vm + 1
        jsr p6_load
        clc
        rts
vf_no:  sec
        rts

; var_getval: Eintrag P6 lesen: VTY = Art, VAL = Ganzzahlwert (4 Byte), VFR = Nachkommateil (4 Byte).
; Z := Laenge + 1 springt hinter den Namen (taz uebertraegt A nach Z). Veraendert A, X, Z, VTY, VAL, VFR.
var_getval:
        ldz #$00
        lda [P6],z
        clc
        adc #$01
        taz
        lda [P6],z                  ; Art
        sta VTY
        inz
        ldx #$00
vg1:    lda [P6],z
        sta VAL,x
        inz
        inx
        cpx #$04
        bne vg1
        ldx #$00
vg2:    lda [P6],z
        sta VFR,x
        inz
        inx
        cpx #$04
        bne vg2
        rts

; var_setval: Gegenstueck zu var_getval: Eintrag P6 := VTY, VAL, VFR (Name und Laenge bleiben). Veraendert A, X, Z.
var_setval:
        ldz #$00
        lda [P6],z
        clc
        adc #$01
        taz
        lda VTY
        sta [P6],z
        inz
        ldx #$00
vs1:    lda VAL,x
        sta [P6],z
        inz
        inx
        cpx #$04
        bne vs1
        ldx #$00
vs2:    lda VFR,x
        sta [P6],z
        inz
        inx
        cpx #$04
        bne vs2
        rts

; var_new: Neuen Eintrag aus NAMEBUF/NAMELEN, VTY, VAL, VFR hinten an die Tabelle anhaengen (vare waechst um Laenge + 10).
; Ausgabe: P6 = neuer Eintrag. Fehler E211, wenn der Bereich VAREND ueberschritten wuerde (kehrt nicht zurueck).
; Veraendert A, X, Z, S2T, P6.
var_new:
        lda vare
        ldx vare + 1
        jsr p6_load
        lda NAMELEN
        clc
        adc #$0a
        clc
        adc vare
        sta S2T
        lda vare + 1
        adc #$00
        sta S2T + 1
        cmp #>VAREND                ; Ende hinter VAREND? dann Tabelle voll (Vergleich nur der Hochbytes, grosszuegig)
        bcs vn_full
        ldz #$00
        lda NAMELEN
        sta [P6],z
        inz
        ldx #$00
vn_n:   cpx NAMELEN
        beq vn_v
        lda NAMEBUF,x
        sta [P6],z
        inz
        inx
        bne vn_n
vn_v:   lda VTY
        sta [P6],z
        inz
        ldx #$00
vn_w:   lda VAL,x
        sta [P6],z
        inz
        inx
        cpx #$04
        bne vn_w
        ldx #$00
vn_f:   lda VFR,x
        sta [P6],z
        inz
        inx
        cpx #$04
        bne vn_f
        lda S2T
        sta vare
        lda S2T + 1
        sta vare + 1
        rts
vn_full:
        lda #ERR_E211
        jmp as_error

; eval_any: Ausdruck lesen (beliebige Art: Zahl, Zeichenkette, Liste), Ergebnis VAL/VTY/VFR; Fehler -> as_fail
; eval_val: Ausdruck lesen, der eine Zahl sein muss (ex_eval), Ergebnis VAL; Fehler -> as_fail
; (as_fail meldet den in der Ausdrucksroutine gesetzten Fehler und kehrt nicht zurueck.)
eval_any:
        jsr ex_eval_any
        bcc ea1
        jmp as_fail
ea1:    rts

eval_val:
        jsr ex_eval
        bcc ev1
        jmp as_fail
ev1:    rts

; compound_op: SRC steht auf einem Operator. A = Operatorkennung, wenn `op=` folgt (Operator und '=' werden verbraucht);
; sonst A = 0 (Z gesetzt), SRC unveraendert.
; Ablauf: Zuerst wird das einzelne Zeichen in cotab (Paare Zeichen/Operatorkennung, Ende 0) gesucht (+ - * / % & | ^); passt
; eines und folgt '=', gilt der Operator. Findet sich keines, werden die Schiebeoperatoren geprueft: `<<=` (Kennung $0c) und
; `>>=` (Kennung $0d); dazu muss das Zeichen doppelt und danach '=' stehen (3 Zeichen werden verbraucht).
; Veraendert A, X, Y, Z, S2T; bei Misserfolg Z gesetzt (A = 0) und SRC unveraendert.
compound_op:
        jsr src_peek
        sta S2T
        ldx #$00
co_l:   lda cotab,x
        beq co_sh
        cmp S2T
        beq co_one
        inx
        inx
        bne co_l
co_one: jsr src_peek1
        cmp #$3d
        bne co_no
        lda cotab + 1,x
        pha
        jsr src_adv
        jsr src_adv
        pla
        rts
co_sh:  lda S2T
        cmp #$3c
        beq co_s1
        cmp #$3e
        bne co_no
        ldy #$0d                    ; Y = Kennung >> (Schieben rechts)
        bne co_s2
co_s1:  ldy #$0c                    ; Y = Kennung << (Schieben links)
co_s2:  jsr src_peek1               ; zweites gleiches Zeichen, danach '=' (Versatz 2)
        cmp S2T
        bne co_no
        ldz #$02
        lda [SRC],z
        cmp #$3d
        bne co_no
        jsr src_adv
        jsr src_adv
        jsr src_adv
        tya
        rts
co_no:  lda #$00
        rts
; cotab: Tabelle Zeichen -> Operatorkennung (OPID von ex_apply): + $0e, - $0f, * $10, / $11, % $12, & $0b, | $09, ^ $0a; Ende 0
cotab:  .byte $2b, $0e, $2d, $0f, $2a, $10, $2f, $11, $25, $12, $26, $0b, $7c, $09, $5e, $0a, $00

; asg_apply: Zuweisung an die Variable NAMEBUF; aop = 0 (name = ausdruck) oder Operatorkennung (name op= ausdruck).
; SRC steht auf dem Ausdruck. Der Name wird vor dem Auswerten in LNAME/LLEN gerettet (die Ausdrucksauswertung benutzt NAMEBUF
; selbst), danach zurueckgeholt. Die Variable muss existieren (sonst E216). Bei op= wird der alte Wert als LHS und die rechte
; Seite als VAL an ex_apply_x uebergeben (Rechnung wie in einem Ausdruck, inklusive Art und Nachkommateil); das Ergebnis wird
; in den Eintrag zurueckgeschrieben. Veraendert alles Uebliche (A, X, Y, Z, VAL, LHS, P6, ...).
asg_apply:
        ldx #$1f
aa1:    lda NAMEBUF,x
        sta LNAME,x
        dex
        bpl aa1
        lda NAMELEN
        sta LLEN
        jsr eval_any
        ldx #$1f
aa2:    lda LNAME,x
        sta NAMEBUF,x
        dex
        bpl aa2
        lda LLEN
        sta NAMELEN
        jsr var_find
        bcc aa3
        lda #ERR_E216
        jmp as_error
aa3:    lda aop                     ; aop = 0: einfache Zuweisung, Wert steht schon in VAL
        beq aa_set
        ldx #$03                    ; rechte Seite (Wert, Nachkommateil, Art) sichern
aa4:    lda VAL,x
        sta arhs,x
        lda VFR,x
        sta arhf,x
        dex
        bpl aa4
        lda VTY
        sta arht
        jsr var_getval
        ldx #$03                    ; LHS = alter Wert
aa5:    lda VAL,x
        sta LHS,x
        lda VFR,x
        sta LFR,x
        lda arhs,x
        sta VAL,x
        lda arhf,x
        sta VFR,x
        dex
        bpl aa5
        lda VTY
        sta LTY
        lda arht
        sta VTY
        lda aop
        sta OPID
        jsr ex_apply_x
aa_set: jsr var_find
        jmp var_setval

; asg_stmt: SRC steht auf `name op= ausdruck` oder `name = ausdruck` (Schleifenschritt und Zuweisungszeilen).
; Liest den Namen, bestimmt den Operator (aop) und ruft asg_apply. Syntaxfehler -> ERR_SYNTAX.
asg_stmt:
        jsr skipws
        jsr read_ident
        jsr skipws
        jsr src_peek
        cmp #$3d
        bne as_c
        jsr src_adv
        lda #$00
        beq as_go
as_c:   jsr compound_op
        bne as_go
        lda #ERR_SYNTAX
        jmp as_error
as_go:  sta aop
        jmp asg_apply

; d_var / d_set: .var name = ausdruck legt eine Variable an oder setzt sie (lhv = 1); .set name = ausdruck setzt nur eine
; bestehende (lhv = 0, sonst E216). Der Name wird mit qualify dem aktuellen Scope zugeordnet; var_find_exact (nicht var_find)
; sorgt dafuer, dass in einem Scope eine NEUE lokale Variable entsteht statt eine aeussere zu ueberschreiben.
d_var:  lda #$01                    ; lhv = 1: anlegen erlaubt
        bne dv_go
d_set:  lda #$00
dv_go:  sta lhv
        jsr skipws
        jsr read_ident
        lda NAMELEN
        bne s2_dv1
dv_syn: lda #ERR_SYNTAX
        jmp as_error
s2_dv1:    ldx #$1f
dv2:    lda NAMEBUF,x
        sta LNAME,x
        dex
        bpl dv2
        lda NAMELEN
        sta LLEN
        jsr skipws
        jsr src_peek
        cmp #$3d
        bne dv_syn
        jsr src_adv
        jsr eval_any
        ldx #$1f
dv3:    lda LNAME,x
        sta NAMEBUF,x
        dex
        bpl dv3
        lda LLEN
        sta NAMELEN
        jsr qualify                 ; die Variable gehoert zum aktuellen Scope
        jsr var_find_exact
        bcc dv_have
        lda lhv                     ; .set auf eine nicht angelegte Variable
        bne dv_mk
        lda #ERR_E216
        jmp as_error
dv_mk:  jsr var_new
        jmp d_end
dv_have:
        jsr var_setval
        jmp d_end

; -----------------------------------------------------------------------------------------------------------------------
; Rahmen (Stapel fuer Makros, Schleifen, Includes). 64 Rahmen zu 32 Byte ab FRBASE in Bank 4; fcnt = Anzahl belegter Rahmen,
; der oberste ist Nummer fcnt - 1. FP ist immer ein 32-Bit-Zeiger auf den zuletzt mit fr_addr/fr_top/fr_push bestimmten Rahmen.
; -----------------------------------------------------------------------------------------------------------------------
; ---- Rahmen (Quelltext-Stapel)
; FP := FRBASE + Nummer * 32 (32-Bit-Zeiger in Bank 4; A = Nummer 0..63). Nummer*32 = (Nummer << 5): Tiefbyte aus fuenf
; Linksschiebungen, Hochbyte aus den oberen drei Bits (lsr x3). Veraendert A.
fr_addr:                            ; A = Rahmennummer -> FP
        pha
        asl
        asl
        asl
        asl
        asl
        sta FP
        pla
        lsr
        lsr
        lsr
        clc
        adc #>FRBASE
        sta FP + 1
        lda #S2BANK
        sta FP + 2
        lda #$00
        sta FP + 3
        rts

; fr_top: FP := oberster Rahmen. Ausgabe: Carry gesetzt, wenn fcnt = 0 (FP unveraendert), sonst Carry geloescht. Veraendert A.
fr_top:                             ; FP = oberster Rahmen; Carry gesetzt wenn keiner da ist
        lda fcnt
        bne ft1
        sec
        rts
ft1:    sec
        sbc #$01
        jsr fr_addr
        clc
        rts

; fr_push: neuen Rahmen oben anlegen: FP zeigt darauf, alle 32 Byte sind 0 (Z zaehlt $1f..0, dez/bpl), F_IFSP = aktuelle
; .if-Tiefe (IFSP), damit .break/.exitmacro/Rueckkehr sie wiederherstellen koennen. Ist fcnt = 64, Fehler E211.
fr_push:                            ; neuer, geloeschter Rahmen: FP; IFSP wird gemerkt
        lda fcnt
        cmp #$40
        bcs fp_full
        jsr fr_addr
        inc fcnt
        ldz #$1f
        lda #$00
fp_z:   sta [FP],z
        dez
        bpl fp_z
        lda IFSP
        ldz #F_IFSP
        sta [FP],z
        rts
fp_full:
        lda #ERR_E211
        jmp as_error

; fr_pop: obersten Rahmen verwerfen (nur der Zaehler zaehlt; der Inhalt bleibt liegen). Veraendert fcnt, Flags.
fr_pop: dec fcnt
        rts

; fr_ldt / fr_stt: 32-Bit-Feld des Rahmens FP bei Z nach TMP laden bzw. aus TMP speichern. Eingabe Z = Feldversatz (F_*).
; Z wird um 4 erhoeht; veraendern A, X.
fr_ldt:                             ; TMP = 4 Byte ab [FP],Z
        ldx #$00
fl1:    lda [FP],z
        sta TMP,x
        inz
        inx
        cpx #$04
        bne fl1
        rts

fr_stt:                             ; [FP],Z = TMP
        ldx #$00
fs1:    lda TMP,x
        sta [FP],z
        inz
        inx
        cpx #$04
        bne fs1
        rts

; -----------------------------------------------------------------------------------------------------------------------
; Zeilenhilfen zum Ueberlesen von Quelltext (Schleifenrumpf, Makrodefinition). Quelltextzugriff nur ueber src_peek/src_adv
; (asm.asm); src_peek liefert das Zeichen an SRC (0 = Ende, Z gesetzt), src_peek1 das uebernaechste, src_adv rueckt vor.
; -----------------------------------------------------------------------------------------------------------------------
; ---- Zeilenhilfen
; next_line: Rest der Zeile samt LF ueberspringen. Ausgabe: Carry geloescht = SRC steht auf dem Anfang der naechsten Zeile;
; Carry gesetzt = der Quelltext (Zeichen 0) endete vorher. Veraendert A.
next_line:
nl1:    jsr src_peek
        beq nl_end
        jsr src_adv
        cmp #$0a
        bne nl1
        clc
        rts
nl_end: sec
        rts

; line_dir: SRC am Zeilenanfang. Liest Leerraum, eine Marke `name:` und eine Direktive. A = Kennung (0 = keine),
; SRC hinter dem Direktivennamen.  Ist die Zeile keine Direktivenzeile (Befehl, Zuweisung, leer), liefert sie A = 0 und
; SRC steht irgendwo in der Zeile (die Aufrufer setzen SRC selbst zurueck oder lesen per next_line weiter). Eine Marke vor der
; Direktive (`name: .directive`) wird mit uebersprungen. Eingabe: nichts ausser SRC; veraendert A, X, Y, NAMEBUF/NAMELEN.
; Wichtig fuer alle Block-Suchen: so erkennt der Ueberleser .repeat/.endrepeat usw. auch hinter einer Marke.
line_dir:
        jsr skipws
        jsr src_peek
        cmp #$2e
        beq ld_dir
        jsr is_identchar
        bcs ld_none
        jsr read_ident
        jsr src_peek
        cmp #$3a
        bne ld_none
        jsr src_adv
        jsr skipws
        jsr src_peek
        cmp #$2e
        bne ld_none
ld_dir: jsr read_ident              ; Name der Direktive nach NAMEBUF lesen (der Punkt gehoert dazu)
        jsr dir_build               ; Kennung des gelesenen Namens bilden (dir2.asm); Carry gesetzt = kein Direktivenname
        bcs ld_none
        jmp dir_find
ld_none:
        lda #$00
        rts

; Quelltextstellen offener Bloecke (E210/E213 wie vcc an der Zeile des Blockanfangs): blk_sv: SRC nach blkp + X sichern (X = 0 Rumpf/skip_block,
; 4 .macro, 8 .struct/.enum); blk_ld: SRC aus blkp + X zurueck; src_dec: SRC (32 Bit) um 1 verringern. Zerstoeren A.
blk_sv: lda SRC
        sta blkp,x
        lda SRC + 1
        sta blkp + 1,x
        lda SRC + 2
        sta blkp + 2,x
        lda SRC + 3
        sta blkp + 3,x
        rts
blk_ld: lda blkp,x
        sta SRC
        lda blkp + 1,x
        sta SRC + 1
        lda blkp + 2,x
        sta SRC + 2
        lda blkp + 3,x
        sta SRC + 3
        rts
src_dec: lda SRC
        bne sdc_a
        lda SRC + 1
        bne sdc_b
        lda SRC + 2
        bne sdc_c
        dec SRC + 3
sdc_c:   dec SRC + 2
sdc_b:   dec SRC + 1
sdc_a:   dec SRC
        rts
blkp:   .fill 12, 0
mk_st:  .byte 0
mk_cu:  .byte 0
mk_dp:  .byte 0
mk_er:  .byte 0
; mk_chk: Parameter zu Ende: mit Vorgabewert -> merken; ohne, aber nach einem mit: E210 (SRC steht dabei auf der Direktivenzeile)
mk_chk: lda mk_cu
        bne mc_set
        lda mk_st
        beq mc_r
        lda #$01                    ; Verstoss merken: der Fehler wird nach dem Kopf weich gemeldet (der Rumpf bleibt gueltig)
        sta mk_er
        bne mc_r
mc_set: lda #$01
        sta mk_st
mc_r:   lda #$00
        sta mk_cu
        rts

; skip_block: SRC am Zeilenanfang; A = 0 Schleife (bis zum passenden .endrepeat/.next), 1 Makro (bis .endmacro).
; SRC steht danach hinter dem Namen der schliessenden Direktive. Schleifen werden verschachtelt gezaehlt (skdepth: .repeat/.for
; erhoehen, .endrepeat/.next senken, bei 0 ist das passende Ende erreicht); Makros kennen keine Verschachtelung (.endmacro genuegt).
; Endet der Quelltext vorher, Fehler E210. Veraendert A, X, skmode, skdepth, NAMEBUF.
skip_block:
        sta skmode
        ldx #$00                    ; Rumpfanfang merken (E210 am Ende: Zeile der Direktive = Rumpfanfang - 1)
        jsr blk_sv
        lda #$01
        sta skdepth
sb_l:   jsr line_dir
        ldx skmode
        bne sb_mac
        cmp #DID_REPEAT
        beq sb_up
        cmp #DID_FOR
        beq sb_up
        cmp #DID_ENDREP
        beq sb_dn
        cmp #DID_NEXT
        beq sb_dn
        bne sb_nx
sb_mac: cmp #DID_ENDMACRO
        beq sb_done
sb_nx:  jsr next_line
        bcc sb_l
        ldx #$00
        jsr blk_ld
        jsr src_dec
        lda #ERR_E210
        jmp as_error
sb_up:  inc skdepth                 ; innere Schleife beginnt (inc ist nie 0: bne ist immer wahr)
        bne sb_nx
sb_dn:  dec skdepth                 ; Z gesetzt, wenn die aeusserste Schleife endet: dann Rueckkehr
        bne sb_nx
sb_done:
        rts

; -----------------------------------------------------------------------------------------------------------------------
; Schleifen (.repeat, .for). Der Rahmen enthaelt den Rumpfanfang (F_A) und die Zaehlinformation; loop_fetch bestimmt jeweils
; den naechsten Durchlauf, loop_end springt am .endrepeat/.next dorthin zurueck. FT_RANGE: Zaehlschleife (naechster Wert,
; Grenze, Schritt; Schritt negativ zaehlt abwaerts), FT_COND: .for v = start, bedingung, schritt, FT_LIST2: Listenwert,
; FT_LIST: Textliste [a, b] (nicht mehr benutzt, siehe lf_list).
; -----------------------------------------------------------------------------------------------------------------------
; ---- Schleifen
; loop_setvar: Laufvariable des obersten Schleifenrahmens := VAL (VTY/VFR sind bereits passend gesetzt). F_FLAGS Bit0 sagt, ob
; der Rahmen eine Laufvariable hat; F_VPTR ist der Versatz ihres Eintrags (16 Bit, nach P6 geladen). Veraendert A, X, Z, P6, FP.
loop_setvar:                        ; Laufvariable := VAL (falls es eine gibt)
        jsr fr_top
        ldz #F_FLAGS
        lda [FP],z
        and #$01
        beq ls_no
        ldz #F_VPTR
        lda [FP],z
        pha
        inz
        lda [FP],z
        tax
        pla
        jsr p6_load
        jmp var_setval
ls_no:  rts

; loop_fetch: naechsten Durchlauf bestimmen. Carry geloescht = noch ein Durchlauf (Laufvariable gesetzt), gesetzt = fertig.
; Verzweigt nach F_TYPE: FT_COND -> lf_cond, FT_LIST -> lf_list, FT_LIST2 -> lf_l2, sonst (FT_RANGE) -> lf_range.
; (Die langen Spruenge jmp lf_list/lf_l2 sind noetig, weil bne/beq nur +-127 Byte reichen.)
loop_fetch:
        jsr fr_top
        ldz #F_TYPE
        lda [FP],z
        cmp #FT_COND
        beq lf_cond
        cmp #FT_LIST
        bne lf_n1
        jmp lf_list
lf_n1:  cmp #FT_LIST2
        bne lf_range
        jmp lf_l2
; Zaehlschleife: durchlaufen, solange naechster Wert < Grenze (Schritt > 0) bzw. > Grenze (Schritt < 0). Der Vergleich wird
; mit ex_apply ausgefuehrt: LHS = Wert, VAL = Grenze, OPID $05 (<) oder $07 (>); VAL = 0 heisst Vergleich falsch = fertig.
; Das Vorzeichen des Schritts steht im obersten Byte von F_D (F_D + 3, Bit 7).
lf_range:                           ; B = naechster Wert, C = Grenze, D = Schritt
        ldz #F_C
        jsr fr_ldt
        jsr cp_tmp_val              ; VAL = Grenze
        ldz #F_B
        jsr fr_ldt
        jsr cp_tmp_lhs              ; LHS = naechster Wert
        ldz #F_D + 3
        lda [FP],z
        bmi lf_neg
        lda #$05                    ; Schritt positiv: weiter solange Wert < Grenze
        bne lf_cmp
lf_neg: lda #$07                    ; Schritt negativ: weiter solange Wert > Grenze
lf_cmp: sta OPID
        jsr ex_apply
        lda VAL
        bne lf_go
        sec
        rts
lf_go:  ldz #F_B
        jsr fr_ldt
        jsr cp_tmp_val
        jsr set_vint                ; VTY = 0: die Laufvariable ist eine Ganzzahl
        jsr loop_setvar             ; Laufvariable = aktueller Wert
        ldz #F_B
        jsr fr_ldt
        jsr cp_tmp_lhs
        ldz #F_D
        jsr fr_ldt
        jsr cp_tmp_val
        lda #$0e                    ; + : naechster Wert = Wert + Schritt
        sta OPID
        jsr ex_apply
        jsr cp_val_tmp
        ldz #F_B
        jsr fr_stt
        clc
        rts
; Bedingungsschleife `.for v = start, bedingung, schritt`: beim ersten Mal (F_STARTED = 0) wird nur die Bedingung getestet
; (die Laufvariable hat schon den Startwert aus loop_var); danach wird zuerst der Schritt als Zuweisung (asg_stmt) ausgefuehrt, dann
; wieder die Bedingung. Bedingung und Schritt stehen als Quelltext (F_B, F_C = Zeiger in den Kopf der .for-Zeile) und werden
; bei jedem Durchlauf neu ausgewertet, indem SRC dorthin gesetzt wird. Wert <> 0 (alle vier Byte ODER-verknuepft): weiter.
lf_cond:
        ldz #F_STARTED
        lda [FP],z
        bne lf_step
        lda #$01
        sta [FP],z
        bne lf_test
lf_step:
        ldz #F_C
        jsr fr_ldt
        jsr cp_tmp_src              ; SRC = Text des Schritts
        jsr asg_stmt
lf_test:
        jsr fr_top
        ldz #F_B
        jsr fr_ldt
        jsr cp_tmp_src              ; SRC = Text der Bedingung
        jsr eval_val
        lda VAL
        ora VAL + 1
        ora VAL + 2
        ora VAL + 3                 ; alle vier Byte 0 = Bedingung falsch
        beq lf_exh
        clc
        rts
lf_exh: sec
        rts
; Listenschleife ueber einen Listenwert (FT_LIST2): F_B = Zeiger auf die Elemente (lptr), F_C = Anzahl (16 Bit), F_D = Index des
; naechsten Elements (lidx). Ist lidx >= Anzahl (16-Bit-Vergleich, Hochbyte zuerst), Ende. Sonst liefert l_get (list.asm) das
; Element lidx von lptr nach VAL/VTY/VFR, lidx wird erhoeht und in F_D zurueckgeschrieben.
lf_l2:  ldz #F_B                    ; Listenwert: Element lidx von lptr
        jsr fr_ldt
        lda TMP
        sta lptr
        lda TMP + 1
        sta lptr + 1
        ldz #F_D
        jsr fr_ldt
        lda TMP
        sta lidx
        lda TMP + 1
        sta lidx + 1
        ldz #F_C
        jsr fr_ldt
        lda lidx + 1
        cmp TMP + 1
        bcc l2_ok
        bne l2_end
        lda lidx
        cmp TMP
        bcs l2_end
l2_ok:  jsr l_get
        inc lidx
        bne l2_i
        inc lidx + 1
l2_i:   lda lidx
        sta TMP
        lda lidx + 1
        sta TMP + 1
        lda #$00
        sta TMP + 2
        sta TMP + 3
        ldz #F_D
        jsr fr_stt
        jsr loop_setvar
        clc
        rts
l2_end: sec
        rts
; Textliste `.for v in [a, b, c]` (FT_LIST, wird von d_for nicht mehr angelegt; der Zweig bleibt erhalten): F_B zeigt auf das
; naechste Element im Quelltext; 0 (alle vier Byte) heisst Ende. Ein Element wird bis ',' oder ']' ausgewertet, danach merkt
; F_B die Stelle hinter dem Komma bzw. 0 nach dem letzten Element.
lf_list:
        ldz #F_B
        jsr fr_ldt
        lda TMP
        ora TMP + 1
        ora TMP + 2
        ora TMP + 3
        beq lf_exh
        jsr cp_tmp_src
        jsr skipws
        jsr src_peek
        cmp #$5d                    ; ]
        beq lf_exh
        jsr eval_any
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne lf_last
        jsr src_adv
        jsr cp_src_tmp
        jmp lf_st
lf_last:
        lda #$00
        sta TMP
        sta TMP + 1
        sta TMP + 2
        sta TMP + 3
lf_st:  jsr fr_top
        ldz #F_B
        jsr fr_stt
        jsr loop_setvar
        clc
        rts

; loop_finish: Schleife beenden: Laufvariable wiederherstellen und den Rahmen entfernen. Gab es die Variable vorher nicht
; (F_FLAGS Bit1 = 0), wird ihr Eintrag durch Zuruecksetzen von vare entfernt (sie war der letzte der Tabelle, solange die
; Rahmen sauber geschachtelt sind). Sonst wird der im Rahmen gesicherte alte Wert (F_OLD, Art bei F_OLD-5, Nachkommateil bei
; F_OLD-4) zurueckgeschrieben. Hat der Rahmen keine Laufvariable, wird nur der Rahmen verworfen. Veraendert A, X, Z, P6, VAL.
loop_finish:
        jsr fr_top
        ldz #F_FLAGS
        lda [FP],z
        and #$01
        beq lfi_pop
        lda [FP],z
        and #$02
        bne lfi_rest
        ldz #F_VPTR                 ; Variable gab es vorher nicht: Eintrag wieder entfernen
        lda [FP],z
        sta vare
        inz
        lda [FP],z
        sta vare + 1
        jmp lfi_pop
lfi_rest:
        ldz #F_OLD
        jsr fr_ldt
        jsr cp_tmp_val
        ldz #F_OLD - 5              ; alte Art und Nachkommateil
        lda [FP],z
        sta VTY
        ldz #F_OLD - 4
        ldx #$00
lfr1:   lda [FP],z
        sta VFR,x
        inz
        inx
        cpx #$04
        bne lfr1
        ldz #F_VPTR
        lda [FP],z
        pha
        inz
        lda [FP],z
        tax
        pla
        jsr p6_load
        jsr var_setval
lfi_pop:
        jmp fr_pop

; loop_var: Laufvariable (Name in LNAME/LLEN) anlegen oder, wenn es sie schon gibt, den alten Wert im Rahmen sichern.
; VAL = Anfangswert. Rahmen FP (oberster Rahmen, soeben angelegt). Der Name wird qualifiziert (Scope!). Neue Variable:
; F_FLAGS = 1. Bereits vorhandene (auch im umgebenden Scope gleichen Namens): alter Wert, Art und Nachkommateil kommen nach F_OLD,
; der Anfangswert wird eingetragen, F_FLAGS = 3. F_VPTR = Versatz des Eintrags. Veraendert A, X, Z, S2T, TMP, TMP2, VAL.
loop_var:
        jsr set_vint
        ldx #$1f
lv1:    lda LNAME,x
        sta NAMEBUF,x
        dex
        bpl lv1
        lda LLEN
        sta NAMELEN
        jsr qualify
        jsr var_find_exact
        bcs lv_new
        jsr cp_val_tmp2             ; Anfangswert merken
        jsr var_getval
        jsr cp_val_tmp
        ldz #F_OLD
        jsr fr_stt
        ldz #F_OLD - 5              ; alte Art und Nachkommateil im Rahmen merken
        lda VTY
        sta [FP],z
        ldz #F_OLD - 4
        ldx #$00
lv2:    lda VFR,x
        sta [FP],z
        inz
        inx
        cpx #$04
        bne lv2
        jsr cp_tmp2_val
        jsr set_vint
        jsr var_setval
        lda P6
        sta S2T
        lda P6 + 1
        sta S2T + 1
        lda #$03
        bne lv_rec
lv_new: jsr var_new
        lda P6
        sta S2T
        lda P6 + 1
        sta S2T + 1
        lda #$01
lv_rec: ldz #F_FLAGS
        sta [FP],z
        ldz #F_VPTR
        lda S2T
        sta [FP],z
        inz
        lda S2T + 1
        sta [FP],z
        rts

; loop_open: Rahmen ist gefuellt (FP), SRC egal. Ersten Durchlauf bestimmen: laeuft er, am Rumpfanfang weiterlesen,
; sonst den Rumpf ueberspringen (skip_block bis zum passenden Ende) und die Schleife beenden; weiter bei d_end bzw. al_line.
; Kehrt nicht zurueck, sondern springt in die Zeilenschleife.
loop_open:
        jsr loop_fetch
        bcs lo_empty
        jsr fr_top
        ldz #F_A
        jsr fr_ldt
        jsr cp_tmp_src
        jmp al_line
lo_empty:
        jsr fr_top
        ldz #F_A
        jsr fr_ldt
        jsr cp_tmp_src
        lda #$00
        jsr skip_block
        jsr loop_finish
        jmp d_end

; loop_end: Ende eines Schleifenrumpfs (SRC steht hinter .endrepeat/.next). Carry gesetzt = weiter (SRC am Rumpfanfang),
; geloescht = Schleife beendet (SRC bleibt hinter der Endedirektive). Der oberste Rahmen muss ein Schleifenrahmen sein, sonst E210
; (z. B. .endrepeat innerhalb eines Makros ohne zugehoerige Schleife). Wegen loop_fetch (Bedingungen werten Text aus und
; verstellen SRC) wird die Stelle hinter dem Ende in lsave gerettet und bei Schleifenende zurueckgeschrieben.
loop_end:
        jsr fr_top
        bcs le_err
        ldz #F_TYPE
        lda [FP],z
        cmp #FT_COND
        bcc le_err
        cmp #FT_LIST2 + 1
        bcs le_err
        ldx #$03                    ; Stelle hinter .endrepeat/.next merken: das Auswerten der Bedingung verstellt SRC
le_s:   lda SRC,x
        sta lsave,x
        dex
        bpl le_s
        jsr loop_fetch
        bcs le_done
        jsr fr_top
        ldz #F_A
        jsr fr_ldt
        jsr cp_tmp_src
        sec
        rts
le_done:
        ldx #$03
le_r:   lda lsave,x
        sta SRC,x
        dex
        bpl le_r
        jsr loop_finish
        clc
        rts
le_err: lda #ERR_E210
        jmp as_error

; d_endrep: Direktive .endrepeat / .next: Rumpfende. loop_end entscheidet, ob am Rumpfanfang weitergelesen (al_line) oder nach
; dem Ende der Zeile fortgefahren wird (d_end).
d_endrep:
        jsr loop_end
        bcs de_more
        jmp d_end
de_more:
        jmp al_line

; loop_top: gemeinsamer Teil von .break/.continue. Die innere Schleife muss der oberste Rahmen sein (ein Makro dazwischen
; ist ein Fehler E210); die .if-Tiefe wird auf den Stand beim Schleifeneintritt zurueckgesetzt (IFSP := F_IFSP, if_skipflag setzt
; das Ueberspringflag neu), weil .break mitten in einem offenen .if stehen kann.
loop_top:
        jsr fr_top
        bcs lt_err
        ldz #F_TYPE
        lda [FP],z
        cmp #FT_COND
        bcc lt_err
        cmp #FT_LIST2 + 1
        bcs lt_err
        ldz #F_IFSP
        lda [FP],z
        sta IFSP
        jmp if_skipflag
lt_err: lda #ERR_E210
        jmp as_error

; d_break: .break - Rest des Rumpfs ueberspringen (skip_block bis zum Ende der Schleife), Schleife beenden (loop_finish).
d_break:
        jsr loop_top
        jsr next_line
        lda #$00
        jsr skip_block
        jsr loop_finish
        jmp d_end

; d_continue: .continue - Rest des Rumpfs ueberspringen und wie bei .endrepeat zum naechsten Durchlauf springen (d_endrep).
d_continue:
        jsr loop_top
        jsr next_line
        lda #$00
        jsr skip_block
        jmp d_endrep

; d_repeat: `.repeat anzahl [, variable]`. Die Anzahl muss in 16 Bit passen (VAL+2/+3 = 0, sonst E203). Der Rahmen bekommt
; Art FT_RANGE: naechster Wert 0, Grenze = Anzahl, Schritt 1; mit variable wird eine Laufvariable 0..Anzahl-1 angelegt (lhv = 1,
; Name in LNAME/LLEN, loop_var). Der Rumpf beginnt in der naechsten Zeile (SRC wird nach F_A gelegt).
d_repeat:
        jsr eval_val
        lda VAL + 2
        ora VAL + 3
        beq dr1
        lda #ERR_E203
        jmp as_error
dr1:    jsr cp_val_tmp2             ; Anzahl
        lda #$00
        sta lhv
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne dr2
        jsr src_adv
        jsr skipws
        jsr read_ident
        lda NAMELEN
        bne dr3
        lda #ERR_SYNTAX
        jmp as_error
dr3:    ldx #$1f
dr4:    lda NAMEBUF,x
        sta LNAME,x
        dex
        bpl dr4
        lda NAMELEN
        sta LLEN
        lda #$01
        sta lhv
dr2:    jsr at_eol_chk
        jsr next_line
        bcc dr5
        lda #ERR_E210
        jmp as_error
dr5:    jsr fr_push
        lda #FT_RANGE
        ldz #F_TYPE
        sta [FP],z
        jsr cp_src_tmp
        ldz #F_A
        jsr fr_stt
        lda #$00                    ; naechster Wert = 0, Grenze = Anzahl, Schritt = 1
        sta TMP
        sta TMP + 1
        sta TMP + 2
        sta TMP + 3
        ldz #F_B
        jsr fr_stt
        ldz #F_C
        lda TMP2
        sta [FP],z
        inz
        lda TMP2 + 1
        sta [FP],z
        lda #$01
        sta TMP
        ldz #F_D
        jsr fr_stt
        lda lhv
        beq dr6
        lda #$00
        sta VAL
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        jsr loop_var
dr6:    jmp loop_open

; d_for: `.for name = start, bedingung, schritt`  /  `.for name in range(...)`  /  `.for name in liste`.
; Alle Formen fuellen zuerst den 32-Byte-Hilfsbereich ftmp (eigenes Layout, nicht gleich dem Rahmen): +0 Art, +4 -> F_B,
; +8 -> F_C, +12 Grenze (Bereich, ersetzt dann F_C), +16 Schritt -> F_D, +20 Anfangswert der Laufvariable; df_open kopiert das in
; einen neuen Rahmen und legt die Laufvariable an.
; Der Name (LNAME/LLEN) kommt zuerst; folgt kein '=', muss `in` stehen (Name genau 2 Zeichen i,n), sonst ERR_SYNTAX.
d_for:  jsr skipws
        jsr read_ident
        lda NAMELEN
        bne df1
df_syn: lda #ERR_SYNTAX
        jmp as_error
df1:    ldx #$1f
df2:    lda NAMEBUF,x
        sta LNAME,x
        dex
        bpl df2
        lda NAMELEN
        sta LLEN
        jsr skipws
        jsr src_peek
        cmp #$3d
        beq df_cond
        jsr read_ident              ; "in"
        lda NAMELEN
        cmp #$02
        bne df_syn
        lda NAMEBUF
        cmp #$69
        bne df_syn
        lda NAMEBUF + 1
        cmp #$6e
        bne df_syn
        jsr skipws
        jsr src_peek
        cmp #$72                    ; r(ange)
        bne df_gen
        jsr src_peek1
        cmp #$61
        bne df_gen
        jmp df_range
; Listenform: der Ausdruck muss eine Liste sein (VTY = 2, sonst E202). l_open (list.asm) liefert Elementzeiger lptr und
; Anzahl lcnt; ftmp: +4 = Zeiger (F_B), +8 = Anzahl (F_C), +20 = 0, Art FT_LIST2. F_D (Index) ist im neuen Rahmen 0.
df_gen: jsr eval_any                ; beliebiger Listenwert: [a, b], Liste, Liste + Liste ...
        lda VTY
        cmp #$02
        beq dg_ok
        lda #ERR_E202
        jmp as_error
dg_ok:  jsr l_open
        lda lptr
        sta ftmp + 4
        lda lptr + 1
        sta ftmp + 5
        lda #$00
        sta ftmp + 6
        sta ftmp + 7
        lda lcnt
        sta ftmp + 8
        lda lcnt + 1
        sta ftmp + 9
        lda #$00
        sta ftmp + 10
        sta ftmp + 11
        sta ftmp + 20
        sta ftmp + 21
        sta ftmp + 22
        sta ftmp + 23
        lda #FT_LIST2
        sta ftmp
        jmp df_open
; Bedingungsschleife: Startwert auswerten (-> ftmp+20), dann die Texte von Bedingung und Schritt nur ZEIGERWEISE merken
; (ftmp+4 bzw. +8): scan_comma ueberliest sie bis zum Komma/Zeilenende ohne sie auszuwerten (Auswertung je Durchlauf in loop_fetch).
df_cond:
        jsr src_adv
        jsr eval_val
        ldx #$03
df3:    lda VAL,x
        sta ftmp + 20,x
        dex
        bpl df3
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne df_syn
        jsr src_adv
        jsr skipws
        ldx #$03                    ; Text der Bedingung
df4:    lda SRC,x
        sta ftmp + 4,x
        dex
        bpl df4
        jsr scan_comma
        jsr src_peek
        cmp #$2c
        bne df_syn
        jsr src_adv
        jsr skipws
        ldx #$03                    ; Text des Schritts
df5:    lda SRC,x
        sta ftmp + 8,x
        dex
        bpl df5
        lda #FT_COND
        sta ftmp
        jmp df_open
; Textliste `[a, b]` (alte Form, wird von d_for nicht mehr angesprungen; df_gen behandelt Listen jetzt als Listenwert).
df_list:
        jsr src_adv
        jsr skipws
        ldx #$03                    ; Zeiger auf das erste Element
dl1x:   lda SRC,x
        sta ftmp + 4,x
        dex
        bpl dl1x
        lda #FT_LIST
        sta ftmp
        lda #$00
        sta ftmp + 20
        sta ftmp + 21
        sta ftmp + 22
        sta ftmp + 23
        jmp df_open
; range(ende), range(anfang, ende) oder range(anfang, ende, schritt). Die Stelle vor `range` wird in dfsv gemerkt: heisst der
; Bezeichner nicht genau `range` (Laenge 5, erster Buchstabe r, letzter e) oder fehlt '(', gilt der Text als Listenausdruck (df_gen).
; Argumente (jeweils mit eval_val): das erste ist zunaechst die Grenze (ftmp+12), das zweite verschiebt es zum Anfang (ftmp+20) und
; wird selbst die Grenze, das dritte ist der Schritt (ftmp+16, Vorgabe 1). Schritt 0 -> E203. ftmp+4 (naechster Wert) := Anfang.
df_range:
        ldx #$03                    ; Stelle merken: ist es doch kein range(, dann ein Listenausdruck
dfr0:   lda SRC,x
        sta dfsv,x
        dex
        bpl dfr0
        jsr read_ident              ; "range" (
        lda NAMELEN
        cmp #$05
        beq dfr1
dfr_nm: ldx #$03
dfr00:  lda dfsv,x
        sta SRC,x
        dex
        bpl dfr00
        jmp df_gen
dfr_s:  jmp df_syn
dfr1:   lda NAMEBUF
        cmp #$72
        bne dfr_nm
        lda NAMEBUF + 4
        cmp #$65
        bne dfr_nm
        jsr skipws
        jsr src_peek
        cmp #$28
        bne dfr_nm
        jsr src_adv
        jsr eval_val                ; erstes Argument
        ldx #$03
dfr2:   lda VAL,x
        sta ftmp + 12,x             ; vorlaeufig als Grenze
        lda #$00
        sta ftmp + 20,x
        dex
        bpl dfr2
        lda #$01                    ; Schritt 1
        sta ftmp + 16
        lda #$00
        sta ftmp + 17
        sta ftmp + 18
        sta ftmp + 19
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne dfr_e
        jsr src_adv
        jsr eval_val                ; zweites Argument: das erste war der Anfang
        ldx #$03
dfr3:   lda ftmp + 12,x
        sta ftmp + 20,x
        lda VAL,x
        sta ftmp + 12,x
        dex
        bpl dfr3
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne dfr_e
        jsr src_adv
        jsr eval_val                ; drittes Argument: Schritt
        ldx #$03
dfr4:   lda VAL,x
        sta ftmp + 16,x
        dex
        bpl dfr4
        jsr skipws
dfr_e:  jsr src_peek
        cmp #$29
        bne dfr_s
        jsr src_adv
        jsr at_eol_chk
        lda ftmp + 16               ; Schritt 0 ist ein Fehler
        ora ftmp + 17
        ora ftmp + 18
        ora ftmp + 19
        bne dfr5
        lda #ERR_E203
        jmp as_error
dfr5:   ldx #$03                    ; naechster Wert = Anfang
dfr6:   lda ftmp + 20,x
        sta ftmp + 4,x
        dex
        bpl dfr6
        lda #FT_RANGE
        sta ftmp
; df_open: gemeinsamer Abschluss: Rumpf beginnt in der naechsten Zeile (Ende des Quelltexts -> E210); neuen Rahmen anlegen,
; Art, Rumpfanfang (F_A = SRC), F_B, F_C (und bei Bereich F_C = Grenze, F_D = Schritt) aus ftmp uebernehmen, die Laufvariable
; mit Startwert ftmp+20 anlegen (loop_var) und loop_open aufrufen.
df_open:
        jsr next_line
        bcc dfo1
        lda #ERR_E210
        jmp as_error
dfo1:   jsr fr_push
        lda ftmp
        ldz #F_TYPE
        sta [FP],z
        jsr cp_src_tmp
        ldz #F_A
        jsr fr_stt
        ldx #$03
dfo2:   lda ftmp + 4,x
        sta TMP,x
        dex
        bpl dfo2
        ldz #F_B
        jsr fr_stt
        ldx #$03
dfo3:   lda ftmp + 8,x
        sta TMP,x
        dex
        bpl dfo3
        ldz #F_C
        jsr fr_stt
        lda ftmp
        cmp #FT_RANGE
        bne dfo5
        ldx #$03                    ; Bereich: C = Grenze, D = Schritt
dfo4:   lda ftmp + 12,x
        sta TMP,x
        dex
        bpl dfo4
        ldz #F_C
        jsr fr_stt
        ldx #$03
dfo6:   lda ftmp + 16,x
        sta TMP,x
        dex
        bpl dfo6
        ldz #F_D
        jsr fr_stt
dfo5:   ldx #$03
dfo7:   lda ftmp + 20,x
        sta VAL,x
        dex
        bpl dfo7
        jsr loop_var
        jmp loop_open

; scan_comma: SRC bis zum naechsten Komma auf Klammertiefe 0 (runde und eckige Klammern, tdepth) oder zum Zeilenende
; (0, LF, CR, ';' oder Kommentarbeginn nach '/' (is_cmt2)) vorruecken; SRC bleibt auf dem Komma/Endezeichen.
; Zeichenketten werden hier NICHT besonders behandelt (anders als scan_tok). Veraendert A, X, tdepth.
scan_comma:
        lda #$00
        sta tdepth
sc_l:   jsr src_peek
        beq sc_end
        cmp #$0a
        beq sc_end
        cmp #$0d
        beq sc_end
        cmp #$3b
        beq sc_end
        cmp #$2f
        bne sc_n2
        jsr is_cmt2
        beq sc_end
        jsr src_peek
sc_n2:  cmp #$28
        beq sc_up
        cmp #$5b
        beq sc_up
        cmp #$29
        beq sc_dn
        cmp #$5d
        beq sc_dn
        cmp #$2c
        bne sc_nx
        ldx tdepth
        beq sc_end
sc_nx:  jsr src_adv
        jmp sc_l
sc_up:  inc tdepth
        bne sc_nx
sc_dn:  dec tdepth
        jmp sc_nx
sc_end: rts

; -----------------------------------------------------------------------------------------------------------------------
; Makros. Definition: `.macro name(param1, param2 = vorgabe, ...)` ... `.endmacro`. Die Makrotabelle (Bank 4, MACBASE..MACEND)
; enthaelt je Makro [Laenge][Name in Kleinbuchstaben][Kopfzeiger 4]; der Kopf ist der Quelltext hinter dem Namen (Parameterliste).
; Der Rumpf wird erst beim Aufruf gelesen (macro_call); die Namensuche ist unabhaengig von Gross-/Kleinschreibung (mlow).
; -----------------------------------------------------------------------------------------------------------------------
; ---- Makros
; mac_scan: vor dem ersten Durchlauf alle .macro-Zeilen suchen (ein Makro darf vor seiner Definition aufgerufen werden).
; Liest den ganzen Quelltext ab SRCBASE zeilenweise (line_dir), traegt jedes .macro mit mac_add ein und ueberspringt den
; Makrorumpf (skip_block). Zeilen mit .include bzw. #include werden verfolgt (ms_inc), damit auch Makros eingebundener Dateien
; gefunden werden. ms_run ist der rekursiv aufrufbare Teil (SRC muss gesetzt sein). Veraendert A, X, Y, Z, SRC, mace.
mac_scan:
        ldx #$03
ms0:    lda SRCBASE,x
        sta SRC,x
        dex
        bpl ms0
        jmp ms_run
ms_run:
ms_l:   jsr line_dir
        cmp #DID_INCLUDE
        beq ms_inc
        cmp #DID_MACRO
        bne ms_nd
        jsr mac_add
        jsr next_line
        bcc ms1
        lda #ERR_E210
        jmp as_error
ms1:    lda #$01
        jsr skip_block
ms_nx:  jsr next_line
        bcc ms_l
        rts

; ms_nd: keine Direktive erkannt. Beginnt die Zeile mit '#', pruefen, ob es `#include` ist (Name genau 7 Zeichen, erster Buchstabe
; i/I per ora #$20); dann wie .include behandeln (Makros der Datei sammeln), sonst naechste Zeile.
ms_nd:  jsr src_peek
        cmp #$23
        bne ms_nx
        jsr src_adv
        jsr read_ident
        lda NAMELEN
        cmp #$07
        bne ms_nx
        lda NAMEBUF
        ora #$20
        cmp #$69
        bne ms_nx
        jmp ms_inc

; ms_inc: .include in der Vorabsuche: Makros der eingebundenen Datei sammeln. Tiefe hoechstens 6 (msdepth), hoechstens 16
; Dateien (nfiles). Dateiname lesen (inc_getname), im Dateisystem aufloesen (fs_resolve, Carry gesetzt = nicht gefunden: still
; uebergehen; Fehler meldet der echte Durchlauf). Die Rueckkehrstelle (SRC, 4 Byte) und curfile werden auf dem Stapel gesichert,
; die neue Datei bekommt die naechste Nummer: Basiszeiger in filebase[Nummer * 4], Pfadname ueber fn_ptr (MP),y; danach liest
; ms_run die Datei rekursiv. Danach holt ms_skip curfile und SRC vom Stapel
; zurueck (SRC+3..+0 wurden mit fallendem X gelegt, daher wird SRC+0..+3 mit steigendem X zurueckgeschrieben).
ms_inc: lda msdepth
        cmp #$06
        bcs ms_nx
        jsr inc_getname
        jsr fs_resolve
        bcs ms_nx
        ldx #$03                    ; Rueckkehrstelle und Dateinummer sichern
ms_p:   lda SRC,x
        pha
        dex
        bpl ms_p
        lda curfile
        pha
        lda nfiles
        cmp #$10
        bcs ms_skip
        sta curfile
        asl
        asl
        tax
        ldy #$00
ms_b:   lda ifp,y
        sta filebase,x
        inx
        iny
        cpy #$04
        bne ms_b
        lda curfile
        jsr fn_ptr
        ldy #$00
ms_f:   cpy ip2len
        beq ms_f2
        lda inpath2,y
        sta (MP),y
        iny
        bne ms_f
ms_f2:  lda #$00
        sta (MP),y
        inc nfiles
        inc msdepth
        ldx #$03
ms_s:   lda ifp,x
        sta SRC,x
        dex
        bpl ms_s
        jsr ms_run
        dec msdepth
        dec nfiles
ms_skip:
        pla
        sta curfile
        ldx #$00
ms_r:   pla
        sta SRC,x
        inx
        cpx #$04
        bne ms_r
        jmp ms_nx

; mac_add: SRC hinter `.macro`: Namen lesen, Eintrag [Laenge][Name klein][Kopf 4] anhaengen. Leerer Name -> E209; ueberlaeuft
; die Tabelle MACEND -> E211. Gross- werden in Kleinbuchstaben gewandelt ($41..$5a -> ora #$20). Kopfzeiger = SRC (Text direkt
; hinter dem Namen: die Parameterliste). mace waechst um Laenge + 5. Veraendert A, X, Z, S2T, P6, mace.
mac_add:
        jsr skipws
        jsr read_ident
        lda NAMELEN
        bne ma1
        lda #ERR_E209
        jmp as_error
ma1:    lda mace
        ldx mace + 1
        jsr p6_load
        lda NAMELEN
        clc
        adc #$05
        clc
        adc mace
        sta S2T
        lda mace + 1
        adc #$00
        sta S2T + 1
        cmp #>MACEND
        bcc ma2
        lda #ERR_E211
        jmp as_error
ma2:    ldz #$00
        lda NAMELEN
        sta [P6],z
        inz
        ldx #$00
ma3:    cpx NAMELEN
        beq ma5
        lda NAMEBUF,x
        cmp #$41
        bcc ma4
        cmp #$5b
        bcs ma4
        ora #$20
ma4:    sta [P6],z
        inz
        inx
        bne ma3
ma5:    ldx #$00                    ; Kopfzeiger = SRC (Text hinter dem Namen)
ma6:    lda SRC,x
        sta [P6],z
        inz
        inx
        cpx #$04
        bne ma6
        lda S2T
        sta mace
        lda S2T + 1
        sta mace + 1
        rts

; mac_find: NAMEBUF (beliebige Schreibung) -> P6 = Eintrag; Carry gesetzt = kein Makro dieses Namens. NAMEBUF wird in Kleinbuchstaben
; nach mlow gewandelt und linear gegen die Tabelle verglichen (von MACBASE bis mace, P7 als Laufzeiger; Treffer wird nach P6
; kopiert, vier Byte). Veraendert A, X, Z, P6, P7, mlow.
mac_find:
        ldx #$00
mf1:    cpx NAMELEN
        beq mf2
        lda NAMEBUF,x
        cmp #$41
        bcc mf1s
        cmp #$5b
        bcs mf1s
        ora #$20
mf1s:   sta mlow,x
        inx
        bne mf1
mf2:    lda #<MACBASE
        ldx #>MACBASE
        jsr p7_load
mf_l:   lda P7
        cmp mace
        bne mf_go
        lda P7 + 1
        cmp mace + 1
        bne mf_go
        sec
        rts
mf_go:  ldz #$00
        lda [P7],z
        cmp NAMELEN
        bne mf_n
        inz
        ldx #$00
mf_c:   cpx NAMELEN
        beq mf_hit
        lda [P7],z
        cmp mlow,x
        bne mf_n
        inz
        inx
        bne mf_c
mf_hit: ldx #$03
mf_h1:  lda P7,x
        sta P6,x
        dex
        bpl mf_h1
        clc
        rts
mf_n:   ldz #$00
        lda [P7],z
        clc
        adc #$05
        clc
        adc P7
        sta P7
        bcc mf_l
        inc P7 + 1
        jmp mf_l

; d_macro: .macro im echten Durchlauf: die Definition wurde schon von mac_scan eingetragen, hier wird der Rumpf nur uebersprungen
; (skip_block A = 1 bis .endmacro). Fehlt das Ende des Quelltexts -> E210.
d_macro:
        ldx #$04
        jsr blk_sv                  ; Zeile der Direktive merken (E210 ohne Rumpf)
        ; Kopf pruefen: hinter einem Parameter mit Vorgabewert (a=1) darf keiner ohne Vorgabewert folgen (E210 an der Zeile, wie vcc)
        lda #$00
        sta mk_st                   ; 1 = schon ein Parameter mit Vorgabewert gesehen
        sta mk_cu                   ; 1 = laufender Parameter hat einen Vorgabewert
        sta mk_dp                   ; Klammertiefe innerhalb eines Vorgabewerts
        sta mk_er
mk_f:   jsr src_peek                ; bis zur oeffnenden Klammer suchen
        beq mk_x
        cmp #$0a
        beq mk_x
        cmp #$28
        beq mk_o
        jsr src_adv
        jmp mk_f
mk_o:   jsr src_adv
mk_l:   jsr src_peek
        beq mk_x
        cmp #$0a
        beq mk_x
        cmp #$28
        beq mk_in
        cmp #$29
        beq mk_cl
        cmp #$2c
        beq mk_cm
        cmp #$3d
        bne mk_n
        ldx mk_dp
        bne mk_n
        lda #$01                    ; '=' auf Ebene 0: Parameter hat einen Vorgabewert
        sta mk_cu
        bne mk_n
mk_in:  inc mk_dp
        bne mk_n
mk_cl:  lda mk_dp
        beq mk_end                  ; schliessende Klammer des Kopfes: letzten Parameter pruefen
        dec mk_dp
        jmp mk_n
mk_cm:  lda mk_dp
        bne mk_n
        jsr mk_chk                  ; Komma auf Ebene 0: Parameter zu Ende
mk_n:   jsr src_adv
        jmp mk_l
mk_end: jsr mk_chk
mk_x:   ldx #$04
        jsr blk_ld                  ; SRC zurueck an die Direktivenzeile
        lda mk_er
        beq mk_ok
        lda #ERR_E210               ; Parameter ohne Vorgabewert hinter einem mit Vorgabewert
        jsr soft_err
mk_ok:
        jsr next_line
        bcc s2_dm1
        ldx #$04
        jsr blk_ld
        lda #ERR_E210
        jmp as_error
s2_dm1:    lda #$01
        jsr skip_block
        jmp d_end

; d_endmacro: ein .endmacro, das nicht durch skip_block/copy_line verbraucht wurde, ist ein Strukturfehler (E210).
d_endmacro:
        lda #ERR_E210
        jmp as_error

; d_exitmacro: .exitmacro - offene Schleifen im Makro abbauen (loop_finish je Schleifenrahmen), bis der Makrorahmen oben liegt, dann
; zur Aufrufzeile zurueck (macro_return). Ohne Makrorahmen (Stapel leer) E210. Rueckkehr in die Zeilenschleife (al_line).
d_exitmacro:
dx_l:   jsr fr_top
        bcs dx_err
        ldz #F_TYPE
        lda [FP],z
        cmp #FT_MAC
        beq dx_mac
        jsr loop_finish
        jmp dx_l
dx_mac: jsr macro_return
        jmp al_line
dx_err: lda #ERR_E210
        jmp as_error

; macro_return: Makro-Rahmen (oben, FP) entfernen: SRC := F_A (Aufrufstelle), expt := F_EXPT (Puffer-Stand vor dem Aufruf, gibt den
; Expansionstext frei), IFSP := F_IFSP (mit if_skipflag), dann fr_pop. Veraendert A, X, Z, SRC, expt, IFSP.
macro_return:
        ldz #F_A
        jsr fr_ldt
        jsr cp_tmp_src
        ldz #F_EXPT
        lda [FP],z
        sta expt
        inz
        lda [FP],z
        sta expt + 1
        ldz #F_IFSP
        lda [FP],z
        sta IFSP
        jsr if_skipflag
        jmp fr_pop

; al_eos: Ende des Quelltexts (Zeichen 0) - von al_line angesprungen. Ruft zuerst ln_hook (Zeilenabschluss, Listing). Dann je nach
; oberstem Rahmen: kein Rahmen (fcnt = 0) -> Dateiende: ist ein Scope offen (sdep <> 0) E213 (inpass := 0 verhindert eine
; Endlosschleife der Fehlerbehandlung), sonst cy_close (Durchlauf zu Ende). FT_MAC -> Makrorueckkehr; FT_INC -> inc_return (Rueckkehr
; aus der eingebundenen Datei); alles andere (Schleife ohne Ende) E210.
al_eos: jsr ln_hook
        lda fcnt
        bne eos1
        lda sdep                    ; Quelltext zu Ende: alle Scopes muessen geschlossen sein
        beq eos0
        jsr src_dec                 ; E213 an der letzten Zeile (vcc), nicht hinter dem abschliessenden Zeilenvorschub
        lda #ERR_E213
        ldx #$00
        stx inpass                  ; Block nicht geschlossen: Abbruch (sonst Endlosschleife am Quelltextende)
        jmp as_error
eos0:   jmp cy_close
eos1:   jsr fr_top
        ldz #F_TYPE
        lda [FP],z
        cmp #FT_MAC
        beq eos2
        cmp #FT_INC
        bne eos4
        jsr inc_return
        jmp al_line
eos4:   ldz #F_A                    ; Schleife ohne Ende: E210 an der Direktivenzeile (Rumpfanfang - 1 = Zeilenende der Direktive, wie vcc)
        ldx #$00
eos5:   lda [FP],z
        sta SRC,x
        inz
        inx
        cpx #$04
        bne eos5
        lda SRC
        bne eos6
        lda SRC + 1
        bne eos7
        lda SRC + 2
        bne eos8
        dec SRC + 3
eos8:   dec SRC + 2
eos7:   dec SRC + 1
eos6:   dec SRC
        lda #ERR_E210
        ldx #$00
        stx inpass
        jmp as_error
eos2:   jsr macro_return
        jmp al_line

; at_endp: Z gesetzt, wenn SRC = endp (32-Bit-Vergleich; endp = Ende des Argumenttexts, siehe scan_eol). Veraendert A, X.
at_endp:
        ldx #$03
ae_l:   lda SRC,x
        cmp endp,x
        bne ae_r
        dex
        bpl ae_l
        lda #$00
ae_r:   rts

; scan_eol: SRC bis zum Zeilenende (0, LF, CR oder ; ausserhalb von Zeichenketten); endp = Ende des Argumenttexts
; (ein abschliessendes ')' gehoert nicht dazu, wie in vcc). lastc = letztes Zeichen, das kein Leerraum ist, lastp = seine Stelle;
; steht dort ')', wird endp auf diese Stelle gesetzt, sonst auf das Zeilenende. Zeichenketten in "..." werden ganz ueberlesen
; (damit ein ';' oder ')' darin nichts beendet). Veraendert A, X, SRC, endp, lastc, lastp.
scan_eol:
        lda #$00
        sta lastc
se_l:   jsr src_peek
        beq se_d
        cmp #$0a
        beq se_d
        cmp #$0d
        beq se_d
        cmp #$3b
        beq se_d
        cmp #$2f
        bne se_n2
        jsr is_cmt2
        beq se_d
        jsr src_peek
se_n2:  cmp #$20
        beq se_w
        cmp #$09
        beq se_w
        sta lastc
        ldx #$03
s2_se_p:   lda SRC,x
        sta lastp,x
        dex
        bpl s2_se_p
        cmp #$22
        bne se_w
        jsr src_adv                 ; Zeichenkette ueberspringen
se_s:   jsr src_peek
        beq se_d
        cmp #$0a
        beq se_d
        cmp #$22
        beq se_w
        jsr src_adv
        jmp se_s
se_w:   jsr src_adv
        jmp se_l
se_d:   lda lastc
        cmp #$29
        bne se_e
        ldx #$03
se_q:   lda lastp,x
        sta endp,x
        dex
        bpl se_q
        rts
se_e:   ldx #$03
se_r:   lda SRC,x
        sta endp,x
        dex
        bpl se_r
        rts

; scan_tok: ein Argument/Vorgabewert ab SRC: bis zum Komma auf Tiefe 0, einer unpaarigen ')' , dem Zeilenende oder
; (usend = 1) endp. tcnt = Laenge ohne Leerzeichen am Ende. SRC bleibt am Endezeichen. Ausgabe: tlast = Laenge bis zum letzten
; Nicht-Leerzeichen (also ohne abschliessenden Leerraum); tcnt zaehlt jedes uebernommene Zeichen. Klammern () und [] erhoehen die
; Tiefe (tdepth); Zeichenketten werden ganz uebernommen. Veraendert A, X, SRC, tcnt, tlast, tdepth.
scan_tok:
        lda #$00
        sta tcnt
        sta tlast
        sta tdepth
st_l:   lda usend
        beq st_1
        jsr at_endp
        beq st_end
st_1:   jsr src_peek
        beq st_end
        cmp #$0a
        beq st_end
        cmp #$0d
        beq st_end
        cmp #$3b
        beq st_end
        cmp #$2f
        bne st_n2
        jsr is_cmt2
        beq st_end
        jsr src_peek
st_n2:  cmp #$28
        beq st_up
        cmp #$5b
        beq st_up
        cmp #$29
        beq st_dn
        cmp #$5d
        beq st_dn
        cmp #$2c
        bne st_2
        ldx tdepth
        beq st_end
st_2:   cmp #$22
        bne st_c
        jsr src_adv                 ; Zeichenkette ganz uebernehmen
        inc tcnt
st_q:   jsr src_peek
        beq st_end
        cmp #$0a
        beq st_end
        inc tcnt
        cmp #$22
        beq st_qe
        jsr src_adv
        jmp st_q
st_qe:  jsr src_adv
        lda tcnt
        sta tlast
        jmp st_l
st_up:  inc tdepth
        jmp st_c
st_dn:  ldx tdepth
        beq st_end                  ; unpaarige Klammer zu: Ende
        dec tdepth
st_c:   jsr src_peek
        inc tcnt
        cmp #$20
        beq st_w
        cmp #$09
        beq st_w
        ldx tcnt
        stx tlast
st_w:   jsr src_adv
        jmp st_l
st_end: rts

; tok_args: Argumenttext (ap .. endp) in argtbl zerlegen: je Argument Zeiger (4) und Laenge (1); na = Anzahl
; Ausgabe argtbl: je Argument 5 Byte (Zeiger auf den Text 4, Laenge 1), Index = Nummer * 5 (<= MAXPAR * 5 = 80 Byte).
; Eine fuehrende '(' wird abgeschnitten. Mehr als MAXPAR Argumente werden nur gezaehlt (na steigt weiter), nicht gespeichert;
; bind_args meldet dann E209. Veraendert A, X, Y, S2T, SRC, na, usend, tcnt, tlast, tdepth.
tok_args:
        lda #$00
        sta na
        lda #$01
        sta usend
        ldx #$03
ta0:    lda ap,x
        sta SRC,x
        dex
        bpl ta0
        jsr skipws
        jsr src_peek
        cmp #$28                    ; fuehrende ( abschneiden
        bne ta1
        jsr at_endp
        beq ta1
        jsr src_adv
ta1:    jsr skipws
        jsr at_endp
        bne ta_tok
        rts                         ; leerer Text: keine Argumente
ta_tok: lda na
        cmp #MAXPAR
        bcc ta2
        jsr scan_tok                ; mehr Argumente als MAXPAR: nur ueberlesen und zaehlen (zu viele fuer das Makro: E209 beim Binden;
        inc na                      ; mehr Parameter als MAXPAR meldet hdr_parse als E900)
        beq ta_d
        jmp ta_nx
ta2:    asl                         ; Eintrag na * 5
        asl
        clc
        adc na
        tay
        ldx #$00
ta3:    lda SRC,x
        sta argtbl,y
        iny
        inx
        cpx #$04
        bne ta3
        sty S2T                     ; Y = Platz der Laenge
        jsr scan_tok
        ldx S2T
        lda tlast
        sta argtbl,x
        inc na
ta_nx:  jsr at_endp
        beq ta_d
        jsr src_peek
        cmp #$2c
        bne ta_d
        jsr src_adv
        jsr skipws
        jmp ta_tok
ta_d:   rts

; hdr_parse: Kopf des Makros (mhdr) lesen: Parameternamen und Vorgabewerte in ptbl (je 32 Byte: Laenge, Name 26,
; Zeiger 4, Laenge des Texts; $FF = kein Vorgabewert); np = Anzahl. Eintragsaufbau: +0 Namenslaenge (1..26), +1.. Name,
; +$1b..+$1e Zeiger auf den Text (bei Vorgabewert: der Vorgabetext, nach bind_args: der Ersatztext), +$1f Textlaenge (bei
; noch nicht gebundenem Eintrag $ff = kein Vorgabewert). Die Liste darf in '(' ... ')' stehen. Leere Namen oder Namen
; > 26 Zeichen -> E209, mehr als MAXPAR Parameter -> E900. Veraendert A, X, Y, MP, SRC, np, usend, NAMEBUF.
hdr_parse:
        lda #$00
        sta np
        sta usend
        ldx #$03
hp0:    lda mhdr,x
        sta SRC,x
        dex
        bpl hp0
        jsr skipws
        jsr src_peek
        cmp #$28
        bne hp_l
        jsr src_adv
hp_l:   jsr skipws
        jsr src_peek
        beq hp_done
        cmp #$0a
        beq hp_done
        cmp #$0d
        beq hp_done
        cmp #$29
        beq hp_done
        cmp #$3b
        beq hp_done
        jsr read_ident
        lda NAMELEN
        beq hp_bad
        cmp #$1b
        bcs hp_bad
        lda np
        cmp #MAXPAR
        bcs hp_many
        jsr mp_entry
        ldy #$00
        lda NAMELEN
        sta (MP),y
        iny
        ldx #$00
hp1:    cpx NAMELEN
        beq hp2
        lda NAMEBUF,x
        sta (MP),y
        iny
        inx
        bne hp1
hp2:    ldy #$1f
        lda #$ff
        sta (MP),y
        jsr skipws
        jsr src_peek
        cmp #$3d
        bne hp3
        jsr src_adv
        jsr skipws
        ldy #$1b
        ldx #$00
hp4:    lda SRC,x
        sta (MP),y
        iny
        inx
        cpx #$04
        bne hp4
        jsr scan_tok
        ldy #$1f
        lda tlast
        sta (MP),y
hp3:    inc np
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne hp_done
        jsr src_adv
        jmp hp_l
hp_done:
        rts
hp_many: lda #ERR_E900            ; mehr Parameter als MAXPAR
        jmp as_error
hp_bad: lda #ERR_E209
        jmp as_error

; mp_entry: MP := ptbl + np * 32 (Adresse des Eintrags mit der Nummer np im Hauptspeicher; np < 16 => np*32 < 512, daher
; Uebertrag ins Hochbyte). Veraendert A.
mp_entry:
        lda np
        lsr
        lsr
        lsr
        clc
        adc #>ptbl
        sta MP + 1
        lda np
        asl
        asl
        asl
        asl
        asl
        clc
        adc #<ptbl
        sta MP
        bcc me1
        inc MP + 1
me1:    rts

; bind_args: Argumente und Vorgabewerte an die Parameter binden (Zeiger und Laenge im Eintrag). S2T = Nummer des Parameters,
; S2T+1 = Byteversatz in argtbl (5 je Argument, wird mit kopiert). Ist fuer Parameter k ein Argument da (k < na), werden dessen 5
; Byte nach +$1b..+$1f des Eintrags kopiert; sonst muss der Parameter einen Vorgabewert haben (+$1f <> $ff), sonst E209. Zuletzt:
; mehr Argumente als Parameter (na > np) -> E209. Veraendert A, X, Y, MP, S2T.
bind_args:
        lda #$00
        sta S2T
        sta S2T + 1
        lda #<ptbl
        sta MP
        lda #>ptbl
        sta MP + 1
        lda np
        beq ba_chk
ba_l:   lda S2T
        cmp na
        bcs ba_def
        ldx S2T + 1
        ldy #$1b
ba_c:   lda argtbl,x
        sta (MP),y
        inx
        iny
        cpy #$20
        bne ba_c
        stx S2T + 1
        jmp ba_n
ba_def: ldy #$1f
        lda (MP),y
        cmp #$ff
        bne ba_n
        lda #ERR_E209
        jmp as_error
ba_n:   clc
        lda MP
        adc #$20
        sta MP
        bcc ba_n1
        inc MP + 1
ba_n1:  inc S2T
        lda S2T
        cmp np
        bne ba_l
ba_chk: lda na
        cmp np
        beq ba_ok
        bcc ba_ok
        lda #ERR_E209
        jmp as_error
ba_ok:  rts

; param_match: Carry geloescht, wenn NAMEBUF ein Parametername ist (MP = Eintrag, fuer em_repl); sonst Carry gesetzt. Linear ueber
; np Eintraege (Schrittweite $20); der Vergleich ist exakt (Gross-/Kleinschreibung zaehlt). Veraendert A, X, Y, MP, S2T.
param_match:
        lda np
        beq pm_no
        sta S2T
        lda #<ptbl
        sta MP
        lda #>ptbl
        sta MP + 1
pm_l:   ldy #$00
        lda (MP),y
        cmp NAMELEN
        bne pm_n
        iny
        ldx #$00
pm_c:   cpx NAMELEN
        beq pm_hit
        lda (MP),y
        cmp NAMEBUF,x
        bne pm_n
        iny
        inx
        bne pm_c
pm_hit: clc
        rts
pm_n:   clc
        lda MP
        adc #$20
        sta MP
        bcc pm_n1
        inc MP + 1
pm_n1:  dec S2T
        bne pm_l
pm_no:  sec
        rts

; -----------------------------------------------------------------------------------------------------------------------
; Expansionspuffer schreiben (P7 = Schreibzeiger in Bank 4, Versatz ab EXPBASE). em_* haengen Zeichen an und erhoehen P7;
; reicht der Puffer bis HBASE (Hochbyte >= $c0), Fehler E211.
; -----------------------------------------------------------------------------------------------------------------------
; em_byte: A an [P7] schreiben, P7 += 1. Z wird mit phz/plz gerettet (der Aufrufer nutzt es als Index in [P6],z); veraendert
; A nicht, X und Y bleiben.
em_byte:
        phz
        ldz #$00
        sta [P7],z
        plz
        inc P7
        bne emb1
        inc P7 + 1
        lda P7 + 1
        cmp #>HBASE                 ; der Puffer reicht bis zur Hash-Tabelle
        bcc emb1
        lda #ERR_E211               ; Puffer voll
        jmp as_error
emb1:   rts

; em_name: NAMEBUF (NAMELEN Zeichen) in den Puffer schreiben. X wird um den Aufruf von em_byte herum auf dem Stapel gerettet
; (em_byte aendert X nicht, trotzdem defensiv). Veraendert A, X.
em_name:                            ; NAMEBUF (NAMELEN Zeichen)
        ldx #$00
emn1:   cpx NAMELEN
        beq emn2
        txa
        pha
        lda NAMEBUF,x
        jsr em_byte
        pla
        tax
        inx
        bne emn1
emn2:   rts

; em_repl: Ersatztext des Parameters MP in den Puffer schreiben. Zeiger (4 Byte) nach P6 laden (Versatz $1b, Bank-Byte aus dem
; Eintrag), Laenge in S2T; Z zaehlt durch den Text ([P6],z; Texte sind < 256 Byte). Veraendert A, X, Y, Z, P6, S2T.
em_repl:                            ; Ersatztext des Parameters MP (Zeiger ab Versatz $1B, Laenge $1F)
        ldy #$1b
        ldx #$00
emr1:   lda (MP),y
        sta P6,x
        iny
        inx
        cpx #$04
        bne emr1
        ldy #$1f
        lda (MP),y
        sta S2T
        ldz #$00
emr2:   lda S2T
        beq emr3
        lda [P6],z
        jsr em_byte
        inz
        dec S2T
        bne emr2
emr3:   rts

; em_nib: unteres Halbbyte von A als Hexziffer ('0'-'9','A'-'F') in den Puffer. Carry ist nach cmp #$0a bei >= 10 gesetzt:
; adc #$06 addiert damit 7 ($0a + 7 = $11, + $30 = $41 'A'). Veraendert A.
em_nib: and #$0f
        cmp #$0a
        bcc emi1
        adc #$06
emi1:   adc #$30
        jmp em_byte

; em_uq: schreibt den Vorsatz `.zqNNNN` (NNNN = Nummer des Makroaufrufs mcall, vierstellig hex). So wird @name in jedem Aufruf zu
; einem anderen Namen (.zq0001name, .zq0002name, ...): lokale Marken eines Makros bleiben je Aufruf eindeutig. Der Punkt macht
; daraus einen lokalen Namensraum der Marke (`.zq...` kann im Quelltext nicht vorkommen). $2e = '.', $7a = 'z', $71 = 'q'.
em_uq:                              ; .zq<Aufrufnummer 4 Stellen hex> : Vorsatz der @-Marken dieses Aufrufs
        lda #$2e
        jsr em_byte
        lda #$7a
        jsr em_byte
        lda #$71
        jsr em_byte
        lda mcall + 1
        lsr
        lsr
        lsr
        lsr
        jsr em_nib
        lda mcall + 1
        jsr em_nib
        lda mcall
        lsr
        lsr
        lsr
        lsr
        jsr em_nib
        lda mcall
        jmp em_nib

; copy_line: eine Zeile des Makrorumpfs ab SRC in den Puffer (P7): Parameter ersetzen, @name -> .zqNNNNname, Kommentare weglassen
; (';' bis Zeilenende). Zeichenketten "..." werden unveraendert kopiert (kein Ersatz darin). Bezeichner werden gelesen (read_ident)
; und, wenn sie ein Parametername sind, durch den gebundenen Ersatztext ersetzt, sonst unveraendert uebernommen; alle anderen Zeichen
; einzeln. Das LF der Zeile wird mitkopiert und beendet die Routine (jmp src_adv als Endsprung). Das Textende (Zeichen 0) vor dem
; LF ist ein Fehler E210. Veraendert A, X, Y, Z, SRC, P7, NAMEBUF.
copy_line:
cl_next:
        jsr src_peek
        bne cl_1
        lda #ERR_E210
        jmp as_error
cl_1:   cmp #$0a
        beq cl_nl
        cmp #$3b
        beq cl_cmt
        cmp #$22
        beq cl_str
        cmp #$40
        beq cl_at
        jsr is_identchar
        bcs cl_raw
        jsr read_ident
        jsr param_match
        bcs cl_nm
        jsr em_repl
        jmp cl_next
cl_nm:  jsr em_name
        jmp cl_next
cl_raw: jsr src_peek
        jsr em_byte
        jsr src_adv
        jmp cl_next
cl_cmt: jsr src_adv                 ; Kommentar: bis LF ueberlesen (das LF selbst wird bei cl_next wieder behandelt)
        jsr src_peek
        beq cl_next
        cmp #$0a
        bne cl_cmt
        jmp cl_next
cl_nl:  jsr em_byte
        jmp src_adv
cl_str: jsr src_peek
        jsr em_byte
        jsr src_adv
cl_s1:  jsr src_peek
        beq cl_next
        cmp #$0a
        beq cl_next
        jsr em_byte
        pha
        jsr src_adv
        pla
        cmp #$22
        bne cl_s1
        jmp cl_next
cl_at:  jsr src_adv
        jsr em_uq
        jsr read_ident
        jsr em_name
        jmp cl_next

; macro_call: Makroaufruf. Eingabe P6 = Makroeintrag (von mac_find), SRC hinter dem Namen in der Aufrufzeile.
; Schritte: (1) Kopfzeiger mhdr aus dem Eintrag lesen; (2) Argumenttext ab SRC merken (ap) und mit scan_eol bis zum Zeilenende
; (endp) bestimmen, Stelle hinter der Zeile in mret merken (dorthin kehrt macro_return zurueck); inmc = 1 laesst Fehler auf die
; Aufrufzeile zeigen; (3) tok_args / hdr_parse / bind_args; mcall hochzaehlen (neue Nummer fuer .zq-Marken); (4) Pufferstand
; expt als mstart merken, P7 := dort; (5) Rumpf Zeile fuer Zeile aus dem Quelltext hinter dem Kopf in den Puffer kopieren (copy_line),
; bis line_dir ein .endmacro findet; (6) 0-Byte als Pufferende, Makrorahmen anlegen (F_A = mret, F_EXPT = mstart), expt := P7
; (Puffer ist jetzt belegt), (7) SRC := Pufferanfang (Bank S2BANK) und weiter in der Zeilenschleife. Veraendert (fast) alles.
macro_call:
        ldz #$00
        lda [P6],z
        clc
        adc #$01
        taz
        ldx #$00
mc1:    lda [P6],z
        sta mhdr,x
        inz
        inx
        cpx #$04
        bne mc1
        jsr skipws
        ldx #$03
mc2:    lda SRC,x
        sta ap,x
        dex
        bpl mc2
        jsr scan_eol
        ldx #$03
mc3:    lda SRC,x
        sta mret,x
        dex
        bpl mc3
        lda #$01                    ; ab hier gilt bei einem Fehler die Aufrufzeile (mret) als Stelle
        sta inmc
        jsr tok_args
        jsr hdr_parse
        jsr bind_args
        inc mcall
        bne mc4
        inc mcall + 1
mc4:    lda expt
        sta mstart
        ldx expt + 1
        stx mstart + 1              ; mstart = Pufferstand vor diesem Aufruf (Anfang der Expansion)
        jsr p7_load
        ldx #$03                    ; Rumpf lesen: Zeile hinter dem Kopf
mc5:    lda mhdr,x
        sta SRC,x
        dex
        bpl mc5
        jsr next_line
        bcc mc6
        lda #ERR_E210
        jmp as_error
; Schleife je Rumpfzeile: Stelle in lpos merken, per line_dir pruefen, ob die Zeile .endmacro ist (sonst SRC zurueck und die
; Zeile kopieren).
mc6:    ldx #$03
mc7:    lda SRC,x
        sta lpos,x
        dex
        bpl mc7
        jsr line_dir
        cmp #DID_ENDMACRO
        beq mc8
        ldx #$03
mc9:    lda lpos,x
        sta SRC,x
        dex
        bpl mc9
        jsr copy_line
        jmp mc6
mc8:    lda #$00                    ; Ende des Puffers
        jsr em_byte
        jsr fr_push
        lda #FT_MAC
        ldz #F_TYPE
        sta [FP],z
        ldx #$03
mca:    lda mret,x
        sta TMP,x
        dex
        bpl mca
        ldz #F_A
        jsr fr_stt
        ldz #F_EXPT
        lda mstart
        sta [FP],z
        inz
        lda mstart + 1
        sta [FP],z
        lda P7
        sta expt
        lda P7 + 1
        sta expt + 1
        lda #$00
        sta inmc
        lda mstart
        sta SRC
        lda mstart + 1
        sta SRC + 1
        lda #S2BANK
        sta SRC + 2
        lda #$00
        sta SRC + 3
        jmp al_line


; -----------------------------------------------------------------------------------------------------------------------
; Scopes ({ }, .namespace) und Namensaufloesung.
; Der Pfad der offenen Scopes steht als Text `a.b.` in spath; plen[k] = Pfadlaenge nach k Scopes (plen[0] = 0).
; Namen im Scope heissen `pfad + name`; beim Nachschlagen gewinnt der innerste Scope, dann die aeusseren, zuletzt global.
; sdep = Tiefe (0 = global, hoechstens 7); curgstk sichert pro Tiefe die Namen der aktuellen globalen Marke (CURG, 31 Byte).
; Ein Scope kann auch ein .encoding-Block sein (sflag <> 0): er hat keinen Pfad und keine Marken-Aenderung, nur die Kodierung.
; -----------------------------------------------------------------------------------------------------------------------
; qualify: NAMEBUF := Pfad des aktuellen Scopes + NAMEBUF (Laenge NAMELEN waechst). Eingang qual_n: A = Laenge des Pfadvorsatzes
; (0 = nichts zu tun). Ergibt der Name mehr als 31 Zeichen (cmp #$20), E211. Der Zusammenbau laeuft ueber qbuf. Veraendert A, X, Y,
; qlen, qtot, qbuf, NAMEBUF, NAMELEN.
qualify:
        ldx sdep
        lda plen,x
; qual_n: A = Laenge des Pfadvorsatzes
qual_n: sta qlen
        beq qn_done
        clc
        adc NAMELEN
        cmp #$20
        bcc qn0
        lda #ERR_E211
        jmp as_error
qn0:    sta qtot
        ldx #$00
qn1:    cpx qlen
        beq qn2
        lda spath,x
        sta qbuf,x
        inx
        bne qn1
qn2:    ldx #$00
qn3:    cpx NAMELEN
        beq qn4
        txa
        clc
        adc qlen
        tay
        lda NAMEBUF,x
        sta qbuf,y
        inx
        bne qn3
qn4:    ldx #$00
qn5:    cpx qtot
        beq qn6
        lda qbuf,x
        sta NAMEBUF,x
        inx
        bne qn5
qn6:    lda qtot
        sta NAMELEN
qn_done:
        rts

; var_find: Variable mit Scope-Aufloesung. Carry geloescht: gefunden (P6), NAMEBUF bleibt der Originalname.
; Suche vom innersten Scope (vlev = sdep) nach aussen bis zum globalen (Pfadlaenge plen[0] = 0): je Stufe wird der Pfadvorsatz
; vorangestellt (qual_n), mit var_find_exact gesucht, der Name aus vsave zurueckgeholt. Tiefe 0 = direkter Aufruf von
; var_find_exact. Carry gesetzt = nirgends gefunden.
var_find:
        lda sdep
        bne vfr0
        jmp var_find_exact
vfr0:   jsr name_save
        lda sdep
        sta vlev
vfr_l:  ldx vlev
        lda plen,x
        jsr qual_n
        jsr var_find_exact
        bcc vfr_ok
        jsr name_restore
        lda vlev
        beq vfr_no
        dec vlev
        jmp vfr_l
vfr_ok: jsr name_restore
        clc
        rts
vfr_no: sec
        rts

; name_save / name_restore: NAMEBUF (32 Byte) und NAMELEN nach vsave/vslen sichern bzw. zurueckholen, weil qual_n NAMEBUF veraendert.
name_save:
        ldx #$1f
ns1:    lda NAMEBUF,x
        sta vsave,x
        dex
        bpl ns1
        lda NAMELEN
        sta vslen
        rts

name_restore:
        ldx #$1f
nr1:    lda vsave,x
        sta NAMEBUF,x
        dex
        bpl nr1
        lda vslen
        sta NAMELEN
        rts

; sym_resolve: Name NAMEBUF in Variablen und Symbolen suchen (Scope-Aufloesung). Carry geloescht: gefunden, VAL = Wert
; (Variable: aktueller Wert, Symbol: Wert des vorigen Durchlaufs). Stufe fuer Stufe (innerster Scope zuerst): erst die Variablen
; der Stufe, dann die Symbole (sym_known_old, sym.asm); bei Treffer wird NAMEBUF zurueckgeholt. Eine Variable gewinnt gegenueber
; einer Marke gleicher Stufe. Carry gesetzt = unbekannt. Wird von der Ausdrucksauswertung gerufen.
sym_resolve:
        lda sdep
        bne sr0
        jsr var_find_exact
        bcs sr_f1
        jmp var_getval_c
sr_f1:  jmp sym_known_old
sr0:    jsr name_save
        lda sdep
        sta vlev
sr_l:   ldx vlev
        lda plen,x
        jsr qual_n
        jsr var_find_exact
        bcs sr_s
        jsr name_restore
        jmp var_getval_c
sr_s:   jsr sym_known_old
        bcs sr_n
        jsr name_restore
        clc
        rts
sr_n:   jsr name_restore
        lda vlev
        beq sr_no
        dec vlev
        jmp sr_l
sr_no:  sec
        rts

; var_getval_c: wie var_getval, dazu Carry geloescht (Ergebnis "gefunden" von sym_resolve).
var_getval_c:
        jsr var_getval
        clc
        rts

; scope_push: Name in NAMEBUF/NAMELEN oeffnet einen Scope; die aktuelle globale Marke wird gemerkt, lokale Labels
; des Scopes haengen am Scope-Namen. Ablauf: Tiefe pruefen (< 7, sonst E211) und neue Pfadlaenge (alter Pfad + Name + '.') < 32
; pruefen (sonst E211); CURG (31 Byte) nach curgstk + sdep * 32 sichern; Name und Punkt an spath anhaengen; sdep erhoehen,
; sflag[sdep] = 0 (kein Kodierungsblock), plen[sdep] = neue Pfadlaenge; CURG := Pfad ohne den letzten Punkt (CURGL = Laenge),
; damit lokale Marken am Scope-Namen haengen. Veraendert A, X, Y, spath, plen, sflag, CURG, CURGL, curgstk.
scope_push:
        ldx sdep
        cpx #$07
        bcc sp0
        lda #ERR_E211
        jmp as_error
sp0:    lda plen,x
        clc
        adc NAMELEN
        adc #$01
        cmp #$20
        bcc sp1
        lda #ERR_E211
        jmp as_error
sp1:    sta qtot
        txa                         ; CURG sichern: Platz x * 32
        asl
        asl
        asl
        asl
        asl
        tay
        ldx #$00
sp2:    lda CURG,x
        sta curgstk,y
        iny
        inx
        cpx #$1f
        bne sp2
        ldx sdep
        lda plen,x
        tay                         ; Pfad erweitern
        ldx #$00
sp5:    cpx NAMELEN
        beq sp6
        lda NAMEBUF,x
        sta spath,y
        iny
        inx
        bne sp5
sp6:    lda #$2e
        sta spath,y
        inc sdep
        ldx sdep
        lda #$00
        sta sflag,x
        lda qtot
        sta plen,x
        sec                         ; CURG = Pfad ohne den letzten Punkt
        sbc #$01
        sta CURGL
        tay
        ldx #$00
sp7:    cpx CURGL
        beq sp8
        lda spath,x
        sta CURG,x
        inx
        bne sp7
sp8:    rts

; scope_pop: innersten Scope schliessen (E213, wenn keiner offen ist). Kodierungsblock (sflag <> 0): nur ENC aus encsave
; zurueckholen. Sonst CURG aus curgstk zurueckholen (die vor dem Scope aktuelle globale Marke gilt wieder). Der Pfad in spath
; bleibt stehen; er wird durch plen[sdep] begrenzt. Veraendert A, X, Y, sdep, ENC bzw. CURG.
scope_pop:
        lda sdep
        bne spo1
        lda #ERR_E213
        jmp as_error
spo1:   ldx sdep                    ; Kodierungsblock: Kodierung zurueck, Marken bleiben
        lda sflag,x
        beq spo0
        lda encsave,x
        sta ENC
        dec sdep
        rts
spo0:   dec sdep
        lda sdep
        asl
        asl
        asl
        asl
        asl
        tay
        ldx #$00
spo2:   lda curgstk,y
        sta CURG,x
        iny
        inx
        cpx #$1f
        bne spo2
        rts

; al_open / al_open2: '{' - Scope oeffnen. Der Name ist die Marke in dieser Zeile (lblflag <> 0, lastlab/lastlen), sonst anonym:
; `#hhhh` mit der laufenden Nummer anoncnt (4 Hexziffern, die '#' lassen sich nicht als Bezeichner eintippen, damit kollidiert
; kein Anwendername). al_open2 ist der Einsprung fuer .scope (Name schon gelesen). Danach scope_push und weiter in der Zeile.
al_open:
        jsr src_adv
al_open2:                           ; Einsprung fuer .scope (der Name steht schon hinter uns)
        lda lblflag
        beq ao_anon
        ldx #$1f
s2_ao1:    lda lastlab,x
        sta NAMEBUF,x
        dex
        bpl s2_ao1
        lda lastlen
        sta NAMELEN
        jmp ao_go
ao_anon:
        inc anoncnt
        bne ao2
        inc anoncnt + 1
ao2:    lda #$23                    ; #hhhh
        sta NAMEBUF
        lda anoncnt + 1
        lsr
        lsr
        lsr
        lsr
        jsr hexch
        sta NAMEBUF + 1
        lda anoncnt + 1
        jsr hexch
        sta NAMEBUF + 2
        lda anoncnt
        lsr
        lsr
        lsr
        lsr
        jsr hexch
        sta NAMEBUF + 3
        lda anoncnt
        jsr hexch
        sta NAMEBUF + 4
        lda #$05
        sta NAMELEN
ao_go:  lda #$00
        sta lblflag
        jsr scope_push
        jmp al_line

; hexch: A (unteres Halbbyte) -> ASCII-Hexziffer in A (wie em_nib, aber ohne Ausgabe in den Puffer). Veraendert A.
hexch:  and #$0f
        cmp #$0a
        bcc hx1
        adc #$06
hx1:    adc #$30
        rts

; al_close / al_close2: '}' bzw. .endscope - Scope schliessen. lblflag := 0 (die Marke vor einer schliessenden Klammer zaehlt nicht
; als Scope-Name), scope_pop, weiter in der Zeile. al_close2 ist der Einsprung fuer .endscope.
al_close:
        jsr src_adv
al_close2:                          ; Einsprung fuer .endscope
        lda #$00
        sta lblflag
        jsr scope_pop
        jmp al_line

; d_namespace: `.namespace name {` - Name lesen (fehlt er oder fehlt '{': ERR_SYNTAX), Scope mit diesem Namen oeffnen. Geschlossen
; wird mit '}' (al_close).
d_namespace:
        jsr skipws
        jsr read_ident
        lda NAMELEN
        bne dn1
        lda #ERR_SYNTAX
        jmp as_error
dn1:    jsr skipws
        jsr src_peek
        cmp #$7b
        beq dn2
        lda #ERR_SYNTAX
        jmp as_error
dn2:    jsr src_adv
        jsr scope_push
        jmp al_line

; -----------------------------------------------------------------------------------------------------------------------
; Daten des Stufe-2-Teils (Hauptspeicher des Assemblers; alle mit 0 initialisiert, ausser wo s2_pass sie zuruecksetzt)
; -----------------------------------------------------------------------------------------------------------------------
fcnt:   .byte 0                     ; Anzahl belegter Rahmen (0..64)
msdepth: .byte 0                    ; Tiefe der Include-Verfolgung in mac_scan (max. 6)
inmc:   .byte 0                     ; 1 waehrend eines Makroaufrufs: Fehlerstelle ist die Aufrufzeile (mret)
dfsv:   .fill 4, 0                  ; gemerkte SRC-Stelle in d_for (hinter `in`)
arhs:   .fill 4, 0                  ; asg_apply: rechte Seite (Wert) bei op=
arhf:   .fill 4, 0                  ; asg_apply: rechte Seite (Nachkommateil)
arht:   .byte 0                     ; asg_apply: rechte Seite (Art)
vare:   .word 0                     ; Ende der Variablentabelle (Versatz in Bank 4)
mace:   .word 0                     ; Ende der Makrotabelle (Versatz in Bank 4)
expt:   .word 0                     ; Stand des Expansionspuffers (naechste freie Stelle)
mcall:  .word 0                     ; Zaehler der Makroaufrufe (fuer .zqNNNN)
vm:     .word 0                     ; var_find_exact: Versatz des letzten Treffers
vmf:    .byte 0                     ; var_find_exact: 1 = Treffer vorhanden
skmode: .byte 0                     ; skip_block: 0 = Schleife, 1 = Makro
skdepth: .byte 0                    ; skip_block: Schachtelungstiefe
aop:    .byte 0                     ; Operatorkennung der Zuweisung (0 = einfaches '=')
lhv:    .byte 0                     ; 1 = .var/.repeat mit Laufvariable, 0 = .set bzw. ohne
tdepth: .byte 0                     ; Klammertiefe in scan_comma/scan_tok
tcnt:   .byte 0                     ; scan_tok: Anzahl uebernommener Zeichen
tlast:  .byte 0                     ; scan_tok: Laenge bis zum letzten Nicht-Leerzeichen
usend:  .byte 0                     ; scan_tok: 1 = auch bei endp anhalten
lastc:  .byte 0                     ; scan_eol: letztes Zeichen ausser Leerraum
na:     .byte 0                     ; Anzahl der Argumente eines Aufrufs
np:     .byte 0                     ; Anzahl der Parameter des Makros
mstart: .word 0                     ; Pufferstand zu Beginn der Expansion
lastp:  .fill 4, 0                  ; scan_eol: Stelle des letzten Nicht-Leerzeichens
endp:   .fill 4, 0                  ; Ende des Argumenttexts (siehe scan_eol, at_endp)
ap:     .fill 4, 0                  ; Anfang des Argumenttexts
mret:   .fill 4, 0                  ; Rueckkehrstelle hinter der Aufrufzeile
mhdr:   .fill 4, 0                  ; Zeiger auf den Kopf des Makros (Text hinter dem Namen)
lpos:   .fill 4, 0                  ; Stelle der aktuellen Rumpfzeile in macro_call
lsave:  .fill 4, 0                  ; loop_end: gerettete SRC-Stelle hinter dem Schleifenende
spath:  .fill 32, 0                 ; Pfad der offenen Scopes als Text `a.b.`
plen:   .fill 9, 0                  ; Pfadlaenge je Scope-Tiefe (plen[0] = 0)
sdep:   .byte 0                     ; aktuelle Scope-Tiefe (0 = global, hoechstens 7)
anoncnt: .word 0                    ; Zaehler fuer anonyme Scopes (#hhhh)
lblflag: .byte 0                    ; <> 0: in dieser Zeile steht eine Marke (lastlab/lastlen)
lastlen: .byte 0                    ; Laenge der letzten Marke der Zeile
lastlab: .fill 32, 0                ; Name der letzten Marke der Zeile
curgstk = $1200                    ; 224 Byte im freien Bereich $1200-$17FF
qbuf:   .fill 32, 0                 ; qualify: Arbeitspuffer
qlen:   .byte 0                     ; qualify: Laenge des Pfadvorsatzes
qtot:   .byte 0                     ; qualify/scope_push: Gesamtlaenge
vsave:  .fill 32, 0                 ; name_save: gesicherter Name
vslen:  .byte 0                     ; name_save: gesicherte Namenslaenge
vlev:   .byte 0                     ; aktuelle Suchstufe in var_find/sym_resolve
argtbl: .fill MAXPAR * 5, 0         ; Argumente: je 5 Byte (Zeiger 4, Laenge 1)
ftmp:   .fill 32, 0                 ; d_for: Hilfsbereich fuer den neuen Rahmen (Layout siehe d_for)
mlow:   .fill 32, 0                 ; mac_find: Name in Kleinbuchstaben
MAXPAR  = 16                        ; Parameter je Makro (VC65-Grenze; vcc kennt keine, die Kachel-Bibliothek braucht 10; mehr gibt E900)
ptbl:   .fill MAXPAR * 32, 0        ; Parametertabelle (im Abbild: der freie Bereich $1800-$1EFF ist voll)
