; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; disp.asm - Anzeigeschicht des Editors (N1): bringt den Bildpuffer des Kerns (ed_scr/ed_attr) auf den MEGA65-Bildschirm,
; liest die Tastatur, uebersetzt Tasten und fuehrt die Eingabezeile fuer Suchen und Gehe-zu. Binden nach ed.asm; der
; Aufrufer legt ed_scr und ed_attr fest (je 2000 Byte, Bank 0).
; Bildschirm: Textmodus 80 x 25 (Bildschirmcodes ab $0800) oder, mit ED_SCRPHYS, 80 x 50 (VIC-IV V400, siehe disp_mode), Farb-RAM ueber den 32-Bit-Zeiger $0FF8_0000 (siehe
; Spike N0). Das Attributbit SELF ($40) bedeutet im Farb-RAM "Umkehrdarstellung" (Attributmodus $D031 Bit 5); der Textcursor
; ist dasselbe Bit auf der Cursorzelle (umgeschaltet, sodass er in einer Auswahl sichtbar bleibt).
; Tastatur: KERNAL GETIN (PETSCII), ueber den Zeiger disp_keyv austauschbar (Tests). Die Belegung steht in kmap_in/kmap_out.
; Die Hardwarebelegung (F-Tasten, Umkehrbit) ist in Xemu nicht pruefbar und wartet auf den Handtest am echten MEGA65.
;
; Hinweis zu SELF: im Quelltext steht SELF = $20 (ed.asm), nicht $40 wie weiter oben im Text genannt; massgeblich ist ed.asm.
; Rolle: Die Datei ist der einzige Teil des Editors, der Hardware kennt (VIC-IV, Tastatur). Der Editorkern (ed.asm) rechnet nur
; im Bildpuffer (ed_scr = Bildschirmcodes, Attribute ueber EA/ed_abase) und kennt keine Tasten ausser den K_*-Codes.
; Speicherplan: Bildschirm 25 Zeilen $0800 (Bank 0, SCRADDR), 50 Zeilen $0004_D000 (ED_SCRPHYS, CPU $D000, 4000 Byte); Farb-RAM $0FF8_0000.
; VIC-IV-Register werden nicht ueber $D0xx (dort ist in der IDE-Abbildung RAM), sondern ueber die flache Adresse $0FFD_30xx
; angesprochen: CP (32-Bit-Zeiger, dm_cp setzt CP+1..CP+3) mit [CP],z.
; Zeropage: CP..CP+3 (32-Bit-Zeiger), ET..ET+7 (Arbeitszellen des Editors), EA (Attribute), E0.. (Textstelle), ed_rp (Bildzeile).
; Tastenablauf: disp_getkey (jmp (disp_keyv), in der IDE die Bruecke kernal_getin) -> disp_map (kmap_in/kmap_out, kpass,
; Buchstaben PETSCII->ASCII) -> ed_run entscheidet: SP_*-Steuercode (Dialog/Haken) oder Editortaste (ed_key).
; Haken (disp_*v): jede IDE-Funktion ist ein Vektor, der ohne IDE auf disp_noop zeigt; ide_init setzt sie (ide.asm).
; Tastenbelegung der IDE (PETSCII-Code -> Befehl, siehe kmap_in): STOP Ende, F1 Suchen, F2 weiter, F3 Gehe zu, F4 zurueck,
; F5-F8 Markieren/Kopieren/Ausschneiden/Einfuegen, Strg+P/U Rueckgaengig/Wiederholen, Strg+V/W Seite hoch/runter; Strg+O laden, Strg+K speichern,
; Strg+E uebersetzen, Strg+F Programm speichern, Strg+R starten, Strg+D Debugger, Strg+G Haltepunkt, Strg+A Laufwerk, HELP/ESC Menue.
; =====================================================================================================================
SCRADDR = $0800
SP_QUIT = $f0                       ; Steuercodes der Tastenuebersetzung (keine Editortasten)
SP_FIND = $f1
SP_NEXT = $f2
SP_GOTO = $f3
SP_PREV = $f4
SP_LOAD = $f5
SP_SAVE = $f6
SP_ASM  = $f7                       ; uebersetzen / Programm speichern: Haken fuer die IDE (ide.asm)
SP_PRG  = $f8
SP_RUN  = $f9                       ; Programm starten: Haken der IDE
SP_DBG  = $fa                       ; Programm im Debugger starten
SP_BP   = $fb                       ; Haltepunkt in der Cursorzeile umschalten
SP_CALC = $e5                       ; Hex-Rechner, Daten einfuegen (Werkzeug-Overlay, nur ueber das Menue)
SP_DATA = $e6
SP_ABOUT = $e4                      ; Logo und Version zeigen (Werkzeug 10, nur ueber das Menue File)
SP_LAB  = $e7                       ; Label suchen (Eingabezeile), Marke setzen / anspringen (Ziffer 1-9); nur ueber das Menue
SP_MGO  = $e8
SP_MSET = $e9
SP_FMT  = $ec                       ; Zeile formatieren (Menue)
SP_FMTA = $eb                       ; ganzen Text formatieren (Menue)
SP_REPL = $ed                       ; Ersetzen (Eingabezeilen Suche/Ersatz, dann alles ab dem Cursor ersetzen); nur ueber das Menue
SP_MENU = $ee                       ; Menue oeffnen (HELP-Taste, Haken disp_menuv: liefert den gewaehlten Befehl oder 0)
SP_DEV  = $ef                       ; Projektlaufwerk 8/9 umschalten (Haken disp_devv)
MSG_SAVED = 1                      ; Meldungen in der Statuszeile (ab Spalte 20), bis zur naechsten Taste
MSG_LOADERR = 2
MSG_SAVEERR = 3
MSG_DYN = 4                         ; freier Text in dz_mbuf (hoechstens 59 Zeichen, mit 0 beendet)
MSGCOL  = 20
PROMPTW = 7                         ; Breite der Beschriftung der Eingabezeile

; disp_init: Farben und Attributmodus; in der IDE zusaetzlich Zeichensatz (Gross-/Kleinschreibung, PETSCII $0E ueber das KERNAL),
; 50-Zeilen-Bild (disp_mode) und Farbschema (Werkzeug 5, Palette). Aendert alle Register. Wird auch nach jedem Testprogramm gerufen.
disp_init:
.ifdef IDE_BUILD
        jsr kvic                    ; in der IDE-Abbildung ist die Ein-/Ausgabe nicht sichtbar (Bruecke: Rahmen/Hintergrund 0, Attributmodus)
.else
        lda #$00
        sta $d020
        sta $d021
        lda $d031
        ora #$20
        sta $d031
.endif
        lda #$ff
        sta disp_cur                ; Cursorzelle ungueltig, bis disp_show sie neu berechnet
.ifdef IDE_BUILD
        tba                         ; Zeichensatz Gross-/Kleinschreibung (PETSCII $0E) ueber das KERNAL
        pha
        lda #$00
        tab
        lda #$0e                    ; PETSCII $0E = Kleinschrift-Zeichensatz
        jsr KCHROUT
        pla
        tab
.endif
.ifdef ED_SCRPHYS
        lda ed_rows                 ; 50-Zeilen-Bild: VIC-IV umschalten (nach kvic, das $D031 beschreibt)
        jsr disp_mode
.endif
        lda #$05                    ; Werkzeug 5: Farbschema der IDE (Palette, Haken disp_xv)
        jmp da_x

.ifdef ED_SCRPHYS
; disp_mode: A = 50 oder 25: Zeilenzahl des Bildes am VIC-IV einstellen. Die Register werden ueber die flache Adresse $0FFD30xx
; angesprochen (32-Bit-Zeiger CP), sodass die Abbildung der Ein-/Ausgabe bei $D000 nicht gebraucht wird. V400 ($D031 Bit 3) ein: das
; "heisse" Register $D031 laesst den VIC-IV DISPROWS ($D07B) auf 49 (50 Zeilen) bzw. 24 setzen, ebenso Zeichenhoehe und Rahmen, und stellt
; SCRNPTR ($D060-$D062) auf den Standard zurueck und COLPTR auf 0; darum danach (nur bei 50 Zeilen) SCRNPTR auf ED_SCRPHYS (disp_vic).
; Der Farb-RAM-Zeiger bleibt 0: das Farb-RAM ab $0FF8_0000 (3999 Byte). Quelle: MEGA65 Chipset Reference, Abschnitt "Hot registers" (S. 28 bis 30).
disp_mode:
        sta dm_rows
        jsr dm_cp
        lda #$2f                    ; VIC-IV freischalten ($D02F = $47, $53; ueber CP = $0FFD_302F, Z = 0 aus dm_cp)
        sta CP
        lda #$47
        sta [CP],z
        lda #$53
        sta [CP],z
        lda #$31                    ; $D031: V400 (Bit 3) ein oder aus
        sta CP
        lda [CP],z
        and #$f7
        ldx dm_rows
        cpx #50
        bne dm_w
        ora #$08
dm_w:   sta [CP],z                  ; $D031 zurueckschreiben (heisses Register: setzt DISPROWS usw., siehe oben)
        cpx #50
        bne dm_x
        jmp dm_scr
dm_x:   rts

; disp_vic: SCRNPTR auf den Bildschirm der IDE stellen, wenn das Bild 50 Zeilen hat. Jeder Zugriff auf die Diskette (Hypervisor, Abbild D81)
; und jedes heisse Register setzt SCRNPTR auf den Standard zurueck (in Xemu gemessen: Strg+E mit Zugriff auf das D81 aendert $D061); darum
; vor jedem Neuzeichnen (disp_flush) und vor dem Merken des IDE-Zustands im Debugger (dv_start) aufrufen.
disp_vic:
        lda ed_rows
        cmp #50
        bne dm_x
        jsr dm_cp
dm_scr: lda #$60                    ; SCRNPTR = ED_SCRPHYS ($D060 tief, $D061 hoch, $D062 Bank)
        sta CP
        ldz #$00
        lda #<ED_SCRPHYS
        sta [CP],z
        inz
        lda #>ED_SCRPHYS
        sta [CP],z
        inz
        lda #<(ED_SCRPHYS >> 16)
        sta [CP],z
        rts
; dm_cp: CP+1..CP+3 = $30,$FD,$0F (VIC-IV-Fenster $0FFD_30xx), Z = 0. Aendert A, Z.
dm_cp:  lda #$30                    ; CP = $0FFD30xx, tiefes Byte setzt der Aufrufer
        sta CP + 1
        lda #$fd
        sta CP + 2
        lda #$0f
        sta CP + 3
        ldz #$00
        rts
dm_rows: .byte 25
.else
disp_vic: rts                       ; 25 Zeilen: nichts zu tun (Stellvertreter, damit das Overlay des Debuggers den Namen findet)
.endif

; ed_run: Hauptschleife. Rueckkehr bei STOP. Der Aufrufer hat ed_init/ed_load gemacht (Zeilenzahl 25).
; Pro Taste: disp_getkey (wartet) -> disp_map -> Steuercode: Dialog (disp_prompt A = Art) / Haken (da_*) / Suchen / Werkzeug;
; sonst ed_key (Editortaste) -> automatische Pruefung (da_auto) -> disp_show. Jeder Zweig kehrt mit "jmp ed_run" zum Neuzeichnen
; zurueck (Meldungen dz_msg sind einmalig). Die Kette aus cmp/bne ist bewusst linear (kleine, einfache Verteilung).
ed_run: jsr ed_view
        jsr disp_show
dr_k:   jsr disp_getkey
        jsr disp_map
        beq dr_k
        cmp #SP_MENU
        bne dr_nm
        jsr da_menu                 ; A = gewaehlter Befehl (wie eine Taste) oder 0 (Z=0: Befehl, fallt durch auf dr_nm)
        bne dr_nm
        jmp ed_run                  ; abgebrochen: neu zeichnen
dr_nm:  cmp #SP_QUIT
        beq dr_q
        cmp #SP_FIND
        bne dr_1r
        lda #$00                    ; Eingabeart 0 = Suchen (siehe disp_prompt)
        jsr disp_prompt
        jmp ed_run
dr_1r:  cmp #SP_REPL
        bne dr_1f
        lda #$05
        jsr disp_prompt
        jmp ed_run
dr_1f:  cmp #SP_FMT
        bne dr_1g
        lda #$00                    ; Werkzeug 0: Zeile ausrichten (Haken disp_xv)
        jsr da_x
        jmp ed_run
dr_1g:  cmp #SP_FMTA
        bne dr_1m
        lda #$01                    ; Werkzeug 1: alles ausrichten
        jsr da_x
        jmp ed_run
dr_1m:  cmp #SP_MSET
        bne dr_1n
        lda #$07
        jsr disp_prompt
        jmp ed_run
dr_1n:  cmp #SP_MGO
        bne dr_1o
        lda #$08
        jsr disp_prompt
        jmp ed_run
dr_1o:  cmp #SP_LAB
        bne dr_1p
        lda #$09
        jsr disp_prompt
        jmp ed_run
dr_1p:  cmp #SP_CALC
        bne dr_1q
        lda #$0a
        jsr disp_prompt
        jmp ed_run
dr_1q:  cmp #SP_DATA
        bne dr_1a
        lda #$0b
        jsr disp_prompt
        jmp ed_run
dr_1a:  cmp #SP_ABOUT
        bne dr_1
        lda #$0a                    ; Werkzeug 10: Logo und Version (Haken disp_xv)
        jsr da_x
        jmp ed_run
dr_1:   cmp #SP_GOTO
        bne dr_2
        lda #$01
        jsr disp_prompt
        jmp ed_run
dr_2:   cmp #SP_NEXT
        bne dr_3
        jsr ed_find_next
        jmp ed_run
dr_3:   cmp #SP_PREV
        bne dr_4
        jsr ed_find_prev
        jmp ed_run
dr_4:   cmp #SP_LOAD
        bne dr_5
        lda #$02
        jsr disp_prompt
        jmp ed_run
dr_5:   cmp #SP_SAVE
        bne dr_6
        lda #$03
        jsr disp_prompt
        jmp ed_run
dr_6:   cmp #SP_ASM
        bne dr_7
        lda #$08                    ; Werkzeug 8: Hinweis "Building ..." (Haken disp_xv)
        jsr da_x
        jsr da_asm
        jmp ed_run
dr_7:   cmp #SP_PRG
        bne dr_8
        lda #$04
        jsr disp_prompt
        jmp ed_run
dr_8:   cmp #SP_RUN
        bne dr_9
        jsr da_run
        jmp ed_run
dr_9:   cmp #SP_DBG
        bne dr_10
        jsr da_dbg
        jmp ed_run
dr_10:  cmp #SP_BP
        bne dr_14
        jsr da_bp
        jmp ed_run
dr_14:  cmp #SP_DEV
        bne dr_15
        jsr da_dev
        jmp ed_run
dr_15:  jsr ed_key                  ; zeichnet selbst in den Puffer (A = Editortaste oder Zeichen)
        jsr da_auto                 ; Zeilenwechsel nach einer Aenderung: automatisch pruefen (Haken der IDE)
        bcc dr_16
        jsr ed_view                 ; Fehlerzeilen neu faerben
dr_16:  jsr disp_show
        jmp dr_k
dr_q:   rts

; da_*: Sprungstuecke zu den Haken (jmp (Vektor)): ein JSR auf da_x liefert so einen "indirekten JSR"; der RTS des Ziels kehrt zum Aufrufer.
da_asm: jmp (disp_asmv)
da_prg: jmp (disp_prgv)
da_run: jmp (disp_runv)
da_dev: jmp (disp_devv)
da_menu: jmp (disp_menuv)
da_auto: jmp (disp_autov)
da_x:   jmp (disp_xv)
da_dbg: jmp (disp_dbgv)
da_bp:  jmp (disp_bpv)
da_tabdraw: jmp (disp_tabdv)
disp_noop: rts                      ; Vorgabe fuer alle Haken ohne IDE
disp_noauto: clc                    ; ohne IDE keine automatische Pruefung
        rts
disp_nomenu: lda #$00               ; ohne IDE-Rahmen kein Menue
        rts
disp_asmv: .word disp_noop          ; Haken: uebersetzen (setzt ggf. dz_msg)
disp_prgv: .word disp_noop          ; Haken: Programm unter ed_oname speichern
disp_runv: .word disp_noop          ; Haken: Programm starten
disp_xv: .word disp_noop              ; Haken: Werkzeug A des Werkzeug-Overlays (IDE: ide_xcall)
disp_autov: .word disp_noauto          ; Haken: automatische Pruefung bei Zeilenwechsel (C = 1: es wurde uebersetzt)
disp_menuv: .word disp_nomenu         ; Haken: Menue (chrome.asm)
disp_devv: .word disp_noop          ; Haken: Projektlaufwerk umschalten
disp_dbgv: .word disp_noop          ; Haken: Programm im Debugger starten
disp_bpv: .word disp_noop           ; Haken: Haltepunkt umschalten
disp_tabdv: .word disp_noop         ; Haken: Rahmen der IDE zeichnen (chrome_draw)
; disp_getkey: wartet auf eine Taste. Ausgabe A = PETSCII-Code. Springt ueber disp_keyv (Vorgabe kernal_getin; Tests setzen eigene Quelle).
disp_getkey:
        jmp (disp_keyv)

.ifndef IDE_BUILD                    ; in der IDE liegt kernal_getin in der Bruecke (boot.asm)
; kernal_getin: wartet auf eine Taste (KERNAL, Basisseite 0, Interrupts nur waehrenddessen frei)
kernal_getin:
        tba
        sta kg_b
        lda #$00
        tab
        cli
kg_l:   jsr $ffe4
        beq kg_l
        sei
        sta kg_k
        lda kg_b
        tab
        lda kg_k
        rts

.endif
; disp_map: A = Taste (PETSCII) -> A = Editortaste, Steuercode (SP_*) oder 0 (ignorieren). Z = 1 bei "ignorieren". Aendert X.
; Reihenfolge der Entscheidung: 1. Tabelle kmap_in -> kmap_out, 2. Buchstaben PETSCII -> ASCII ($41-$5A -> Kleinbuchstaben,
; $C1-$DA = Umschalt-Buchstaben -> Grossbuchstaben), 3. druckbare ASCII-Zeichen $20-$7E unveraendert, 4. Steuertasten aus kpass
; (Return, Tab, Backspace, Cursor, Home), 5. sonst 0.
disp_map:
        jsr dm_body
        cmp #$00                    ; Z gesetzt = ignorieren
        rts
dm_body:
        ldx #$00
dm_t:   cmp kmap_in,x
        beq dm_f
        inx
        cpx #KMAPN
        bne dm_t
        cmp #$41                    ; Buchstaben: PETSCII -> ASCII (im Kleinschrift-Zeichensatz liefert die Tastatur $41-$5A = a-z)
        bcc dm_u
        cmp #$5b
        bcs dm_u
        ora #$20
        bne dm_c
dm_u:   cmp #$c1
        bcc dm_c
        cmp #$db
        bcs dm_c
        and #$7f
dm_c:   cmp #$20
        bcc dm_s
        cmp #$7f
        bcs dm_s
        rts                         ; druckbares Zeichen
dm_s:   ldx #$00                    ; Steuertasten, die der Kern selbst kennt
dm_l:   cmp kpass,x
        beq dm_ok
        inx
        cpx #KPASSN
        bne dm_l
        lda #$00
dm_ok:  rts
dm_f:   lda kmap_out,x
        rts

; kmap_in / kmap_out: Tastencode der Tastatur (PETSCII/Strg-Code) -> Editorcode (K_*) oder Steuercode (SP_*), gleiche Reihenfolge:
; STOP $03; F1 $85 Suchen, F2 $89 weiter suchen, F3 $86 Gehe zu, F4 $8A zurueck suchen, F5 $87 Markieren, F6 $8B Kopieren, F7 $88 Ausschneiden,
; F8 $8C Einfuegen (Funktionstasten nach der KERNAL-Belegung, siehe fk_new in ide.asm); ^P $10 Rueckgaengig, ^U $15 Wiederholen,
; ^V $16 Seite hoch, ^W $17 Seite runter, CLR $93 Textende, INS/DEL $94 Zeichen rechts loeschen; ^O $0F laden, ^K $0B speichern,
; ^E $05 uebersetzen, ^F $06 Programm speichern, ^R $12 starten, ^D $04 Debugger, ^G $07 Haltepunkt, ^A $01 Laufwerk,
; HELP $84 und ESC $1B = Menue.
kmap_in:  .byte $03, $85, $89, $86, $8a, $87, $8b, $88, $8c, $10, $15, $16, $17, $93, $94, $0f, $0b, $05, $06, $12, $04, $07, $01, $84, $1b
kmap_out: .byte SP_QUIT, SP_FIND, SP_NEXT, SP_GOTO, SP_PREV, K_MARK, K_COPY, K_CUT, K_PASTE, K_UNDO, K_REDO, K_PGUP, K_PGDN, K_END, K_DEL, SP_LOAD, SP_SAVE, SP_ASM, SP_PRG, SP_RUN, SP_DBG, SP_BP, SP_DEV, SP_MENU, SP_MENU
KMAPN = 25                          ; Anzahl der Eintraege in kmap_in / kmap_out
kpass:    .byte K_RET, K_TAB, K_BS, K_UP, K_DOWN, K_LEFT, K_RIGHT, K_HOME
KPASSN = 8

; disp_row80: A = Zeile -> disp_cur = Zeile * 80 (16 Bit). Rechnung: A*16 + A*64 = A*80 (erst vier Linksschiebungen, dann zwei weitere
; dazu addiert). Aendert A, X, ET+4, ET+5.
disp_row80:
        sta ET + 4
        lda #$00
        sta ET + 5
        ldx #$04
dq_a:   asl ET + 4
        rol ET + 5
        dex
        bne dq_a
        lda ET + 4
        sta disp_cur
        lda ET + 5
        sta disp_cur + 1
        asl ET + 4
        rol ET + 5
        asl ET + 4
        rol ET + 5
        clc
        lda disp_cur
        adc ET + 4
        sta disp_cur
        lda disp_cur + 1
        adc ET + 5
        sta disp_cur + 1
        rts

; disp_show: Cursorzelle aus dem Kern berechnen und den Puffer auf den Bildschirm bringen. disp_cur = Offset der Cursorzelle im Bild
; = (Cursorzeile - Topzeile + Kopfzeilen) * 80 + (Spalte - linker Rand) + GUTTER (Zeilennummernspalte). Aendert alle Register.
disp_show:
        jsr da_tabdraw
        jsr dz_ovl
        lda ed_curline
        sec
        sbc ed_topline
        clc
        adc ed_hdr
        jsr disp_row80
        lda ed_colv
        sec
        sbc ed_left
        clc
        adc #GUTTER
        clc
        adc disp_cur
        sta disp_cur
        bcc ds_f
        inc disp_cur + 1
ds_f:   jmp disp_flush

; dz_ovl: Meldung dz_msg (einmalig) in die Statuszeile des Puffers schreiben: Nummer (1..4) -> Zeichenkette ueber mtab_lo/mtab_hi
; (4 = dz_mbuf, frei), ab Spalte MSGCOL der letzten Zeile (ed_rows - 1). dz_msg wird danach auf 0 gesetzt. Aendert alle Register.
dz_ovl: lda dz_msg
        beq do_r
        tax
        lda #$00
        sta dz_msg
        lda ed_rows
        sec
        sbc #$01
        phx
        jsr disp_row80
        plx
        clc
        lda disp_cur
        adc #<ed_scr
        sta ET + 2
        lda disp_cur + 1
        adc #>ed_scr
        sta ET + 3
        clc
        lda ET + 2
        adc #MSGCOL
        sta ET + 2
        bcc do_a
        inc ET + 3
do_a:   lda mtab_lo - 1,x
        sta ET + 6
        lda mtab_hi - 1,x
        sta ET + 7
        ldy #$00
do_l:   lda (ET + 6),y
        beq do_r
        jsr asc2scr
        sta (ET + 2),y
        iny
        bne do_l
do_r:   rts

; disp_flush: ed_scr -> $0800, ed_attr -> Farb-RAM (entfaellt bei DISP_DIRECT = 1: der Kern zeichnet dann direkt auf den
; Bildschirm ($0800 = ed_scr) und ins Farb-RAM (ED_ATTR32 = $0FF8_0000)), Cursorzelle disp_cur umschalten
; (Cursor: das Attribut der Cursorzelle wird mit SELF umgeschaltet (eor); disp_cur ist zugleich Offset im Farb-RAM. Beim naechsten
; Neuzeichnen wird die Zelle ohnehin vom Kern neu geschrieben, darum muss das Umschalten nicht rueckgaengig gemacht werden.)
disp_flush:
        jsr disp_vic                ; SCRNPTR wieder auf den IDE-Bildschirm (Diskettenzugriffe setzen ihn zurueck)
.if DISP_DIRECT == 0
        lda #<ed_scr
        sta ET + 2
        lda #>ed_scr
        sta ET + 3
        lda #<SCRADDR
        sta ET + 4
        lda #>SCRADDR
        sta ET + 5
        ldx #$07
fl_p:   ldy #$00
fl_b:   lda (ET + 2),y
        sta (ET + 4),y
        iny
        bne fl_b
        inc ET + 3
        inc ET + 5
        dex
        bne fl_p
fl_t:   lda (ET + 2),y
        sta (ET + 4),y
        iny
        cpy #208
        bne fl_t
        lda #<ed_attr
        sta ET + 2
        lda #>ed_attr
        sta ET + 3
        jsr fl_cp0
        ldx #$07
fc_p:   ldy #$00
        ldz #$00
fc_b:   lda (ET + 2),y
        sta [CP],z
        iny
        inz
        bne fc_b
        inc ET + 3
        inc CP + 1
        dex
        bne fc_p
fc_t:   lda (ET + 2),y
        sta [CP],z
        iny
        inz
        cpy #208
        bne fc_t
.endif
        jsr fl_cp0                  ; Cursorzelle umschalten (CP = $0FF8_0000 + disp_cur)
        lda disp_cur
        sta CP
        lda disp_cur + 1
        sta CP + 1
        ldz #$00
        lda [CP],z
        eor #SELF
        sta [CP],z
        rts
; fl_cp0: CP = $0FF8_0000 (Farb-RAM, 32 Bit). Aendert A.
fl_cp0: lda #$00
        sta CP
        sta CP + 1
        lda #$f8
        sta CP + 2
        lda #$0f
        sta CP + 3
        rts

; disp_prompt: Eingabezeile in der Statuszeile. A = 0 Suchen, 1 Gehe-zu. Eingabe mit RETURN, STOP bricht ab.
; Alle Arten (pr_kind): 0 Suchen, 1 Gehe zu (Ziffern), 2 Laden, 3 Speichern, 4 Programm speichern (Ausgabename), 5 Ersetzen
; (Suchmuster), 6 Ersatztext, 7 Marke setzen (Ziffer 1-9), 8 Marke anspringen, 9 Label suchen, 10 Hex-Rechner, 11 Daten einfuegen.
; Die Eingabe steht in pbuf (pcnt Zeichen); je nach Art wird sie vorbelegt (letztes Muster/Namen zum Bearbeiten) und danach
; ausgewertet (pr_ok). Zeichenzahlgrenzen: Datei 16, Gehe-zu 4, Marke 1, sonst 32. Eingabe der Taste ueber disp_map (alle Tastencodes
; von ed_run gelten hier ebenfalls; STOP bricht ab, BS loescht das letzte Zeichen).
disp_prompt:
        sta pr_kind
        lda #$00
        sta pcnt
        ldx pr_kind                 ; Beschriftung: Offset in lbl_all (0 Suche, 7 Zeile, 14 Datei, 21 Ersatz ...), siehe pr_lot
        lda pr_lot,x
        sta pr_lbo
        lda pr_kind
        beq pr_fp
        cmp #$05                    ; 5 = Suche (Ersetzen), 6 = Ersatz
        beq pr_fp
        cmp #$06
        beq pr_fr
        cmp #$07
        bcc pr_f2
        jmp pr_l                    ; Marke, Label: leere Eingabe
pr_f2:  cmp #$02
        bcs pr_fn
        jmp pr_l
pr_fp:  lda ed_patn                 ; Suchen: das letzte Muster bearbeiten
        sta pcnt
        ldx #$1f
pr_c:   lda ed_pat,x
        sta pbuf,x
        dex
        bpl pr_c
        jmp pr_l
pr_fr:  lda ed_repn                 ; Ersetzen: den letzten Ersatz bearbeiten
        sta pcnt
        ldx #$1f
pr_cr:  lda ed_rep,x
        sta pbuf,x
        dex
        bpl pr_cr
        jmp pr_l
pr_fn:  lda pr_kind
        cmp #$04
        beq pr_fo
        lda ed_fnl                  ; Laden/Speichern: den letzten Dateinamen bearbeiten
        sta pcnt
        ldx #$0f
pr_c2:  lda ed_fname,x
        sta pbuf,x
        dex
        bpl pr_c2
        jmp pr_l
pr_fo:  lda ed_onl                  ; Programm speichern: den letzten Ausgabenamen bearbeiten
        sta pcnt
        ldx #$0f
pr_c3:  lda ed_oname,x
        sta pbuf,x
        dex
        bpl pr_c3
pr_l:   jsr pr_draw
pr_k:   jsr disp_getkey
        jsr disp_map
        beq pr_k
        cmp #SP_QUIT
        beq pr_x
        cmp #K_RET
        beq pr_ok
        cmp #K_BS
        bne pr_ch
        lda pcnt
        beq pr_k
        dec pcnt
        jmp pr_l
pr_ch:  cmp #$20
        bcc pr_k
        cmp #$7f
        bcs pr_k
        ldx pr_kind
        beq pr_f
        cpx #$01
        beq pr_gd
        cpx #$07
        beq pr_md
        cpx #$08
        beq pr_md
        cpx #$05
        bcs pr_f
        ldx pcnt                    ; Dateiname: hoechstens 16 Zeichen
        cpx #$10
        bcs pr_k
        bcc pr_a
pr_gd:  cmp #$30                    ; Gehe-zu: nur Ziffern, hoechstens 4
        bcc pr_k
        cmp #$3a
        bcs pr_k
        ldx pcnt
        cpx #$04
        bcs pr_k
        bcc pr_a
pr_md:  cmp #$31                    ; Marke: eine Ziffer 1-9
        bcc pr_k
        cmp #$3a
        bcs pr_k
        ldx pcnt
        cpx #$01
        bcs pr_k
        bcc pr_a
pr_f:   ldx pcnt
        cpx #$20
        bcs pr_k
pr_a:   sta pbuf,x
        inc pcnt
        jmp pr_l
pr_ok:  lda pr_kind                 ; Eingabe mit RETURN abgeschlossen: je nach Art auswerten
        cmp #$05
        bcc pr_ok1
        jmp pr_rp
pr_ok1: cmp #$02
        bcs pr_file
        lda pr_kind
        bne pr_go
        ldx #$1f                    ; Muster uebernehmen und suchen
pr_m:   lda pbuf,x
        sta ed_pat,x
        dex
        bpl pr_m
        lda pcnt
        sta ed_patn
        jmp ed_find_next
pr_go:  lda pcnt
        beq pr_x
        lda #$00                    ; Zahl aus den Ziffern
        sta ed_garg
        sta ed_garg + 1
        ldx #$00
pr_n:   lda ed_garg                 ; garg * 10 + Ziffer (x10 = x4 + x1, dann x2: (a*4 + a)*2; Zwischensumme in ET+4/5)
        sta ET + 4
        lda ed_garg + 1
        sta ET + 5
        asl ed_garg
        rol ed_garg + 1
        asl ed_garg
        rol ed_garg + 1
        clc
        lda ed_garg
        adc ET + 4
        sta ed_garg
        lda ed_garg + 1
        adc ET + 5
        sta ed_garg + 1
        asl ed_garg
        rol ed_garg + 1
        lda pbuf,x
        sec
        sbc #$30
        clc
        adc ed_garg
        sta ed_garg
        bcc pr_n1
        inc ed_garg + 1
pr_n1:  inx
        cpx pcnt
        bne pr_n
        jmp ed_goto
pr_x:   rts                         ; gemeinsamer Ausstieg (Abbruch oder fertig)
; pr_rp: Eingabe beim Ersetzen: 5 = Suchmuster uebernehmen und den Ersatz abfragen, 6 = Ersatz uebernehmen und ersetzen
pr_rp:  lda pr_kind
        cmp #$06
        beq pr_r6
        bcs pr_mk
        lda pcnt
        beq pr_x
        ldx #$1f
pr_m5:  lda pbuf,x
        sta ed_pat,x
        dex
        bpl pr_m5
        lda pcnt
        sta ed_patn
        lda #$06
        jmp disp_prompt
pr_r6:  ldx #$1f
pr_m6:  lda pbuf,x
        sta ed_rep,x
        dex
        bpl pr_m6
        lda pcnt
        sta ed_repn
        jsr ed_repl_all             ; ersetzt ab dem Cursor alles; Anzahl in rp_cnt
        lda #<dz_mbuf               ; Meldung "nnnn replaced" (put_num4: vierstellige Zahl nach dz_mbuf, dann " replaced" ab Byte 4)
        sta ET + 2
        lda #>dz_mbuf
        sta ET + 3
        lda rp_cnt
        sta ET + 4
        lda rp_cnt + 1
        sta ET + 5
        ldy #$00
        jsr put_num4
        ldx #$00
pr_t6:  lda pr_s6,x
        sta dz_mbuf + 4,x
        beq pr_d6
        inx
        bne pr_t6
pr_d6:  lda #MSG_DYN
        sta dz_msg
        rts
; pr_mk: Marke setzen (7), Marke anspringen (8), Label suchen (9); 10/11 gehen als Werkzeug 2/3 an das Overlay (Rechner/Daten).
pr_mk:  lda pcnt
        beq pr_x
        lda pr_kind
        cmp #$09
        beq pr_lb9
        bcs pr_xt                   ; 10, 11: Werkzeug 2 (Rechner) / 3 (Daten) mit der Eingabe in pbuf
        lda pbuf                    ; Ziffer 1-9 -> Index * 2 (ed_mk: 9 Zeilennummern zu 2 Byte)
        sec
        sbc #$31
        asl
        tax
        lda pr_kind
        cmp #$08
        beq pr_mg
        lda ed_curline              ; Marke = Zeilennummer
        sta ed_mk,x
        lda ed_curline + 1
        sta ed_mk + 1,x
        lda #<pr_s7
        ldx #>pr_s7
        jmp pr_say
pr_mg:  lda ed_mk,x
        ora ed_mk + 1,x
        beq pr_mn
        lda ed_mk,x
        sta ed_garg
        lda ed_mk + 1,x
        sta ed_garg + 1
        jmp ed_goto
pr_xt:  sec                         ; Art 10 -> Werkzeug 2, Art 11 -> Werkzeug 3 (Eingabe liegt in pbuf)
        sbc #$08
        jmp da_x
pr_mn:  lda #<pr_s8
        ldx #>pr_s8
        jmp pr_say
pr_lb9: ldx #$1f
pr_l9:  lda pbuf,x
        sta ed_pat,x
        dex
        bpl pr_l9
        lda pcnt
        sta ed_patn
        jsr ed_find_label
        bcs pr_x
        lda #<pr_s9
        ldx #>pr_s9
; pr_say: A/X = Meldung (ASCII, mit 0) in die Statuszeile
pr_say: sta ET + 6
        stx ET + 7
        ldy #$00
ps_l:   lda (ET + 6),y
        sta dz_mbuf,y
        beq ps_d
        iny
        bne ps_l
ps_d:   lda #MSG_DYN
        sta dz_msg
        rts
pr_s7:  .byte "Mark set", 0
pr_s8:  .byte "Mark not set", 0
pr_s9:  .byte "Label not found", 0
ed_mk:  .fill 18, 0                 ; Marken 1-9: Zeilennummern (0 = nicht gesetzt)
pr_s6:  .byte " replaced", 0
pr_lot: .byte 0, 7, 14, 14, 14, 0, 21, 28, 28, 35, 42, 49
pr_file: lda pcnt                   ; Dateiname uebernehmen, laden oder speichern
        beq pr_x
        lda pr_kind
        cmp #$04
        bne pr_nf
        lda pcnt                    ; Ausgabename merken, Haken aufrufen
        sta ed_onl
        ldx #$0f
pr_no:  lda pbuf,x
        sta ed_oname,x
        dex
        bpl pr_no
        jmp da_prg
pr_nf:  lda pcnt
        sta ed_fnl
        ldx #$0f
pr_nm:  lda pbuf,x
        sta ed_fname,x
        dex
        bpl pr_nm
        lda pr_kind
        cmp #$02
        bne pr_sv
        lda #$04                    ; Werkzeug 4: Hinweis "Loading file ..." (Haken disp_xv)
        jsr da_x
        jsr ed_fload
        bcc pr_x
        lda #MSG_LOADERR
        sta dz_msg
        rts
pr_sv:  jsr ed_fsave
        bcs pr_se
        lda #MSG_SAVED
        sta dz_msg
        rts
pr_se:  lda #MSG_SAVEERR
        sta dz_msg
        rts

; pr_draw: Kern zeichnen, letzte Zeile durch die Eingabezeile ersetzen, auf den Bildschirm bringen. Die Beschriftung (PROMPTW = 7
; Zeichen aus lbl_all ab pr_lbo) steht in Spalte 0, die Eingabe ab Spalte 7; der Cursor (disp_cur) steht hinter dem Eingegebenen.
pr_draw:
        jsr ed_view
        lda ed_rows
        sec
        sbc #$01
        jsr disp_row80
        clc
        lda disp_cur
        adc #<ed_scr
        sta ed_rp
        lda disp_cur + 1
        adc #>ed_scr
        sta ed_rp + 1
        jsr dw_clear
        ldx #$00
dz_pd_l:   txa
        clc
        adc pr_lbo
        tay
        lda lbl_all,y
pd_w:   jsr asc2scr                 ; (asc2scr veraendert X nicht)
        sta pd_c
        txa
        tay
        lda pd_c
        sta (ET + 2),y
        inx
        cpx #PROMPTW
        bne dz_pd_l
        ldx #$00
pd_t:   cpx pcnt
        beq pd_d
        lda pbuf,x
        jsr asc2scr
        sta pd_c
        txa
        clc
        adc #PROMPTW
        tay
        lda pd_c
        sta (ET + 2),y
        inx
        jmp pd_t
pd_d:   clc                         ; Cursor hinter dem Eingegebenen
        lda disp_cur
        adc #PROMPTW
        sta disp_cur
        bcc pd_e
        inc disp_cur + 1
pd_e:   clc
        lda disp_cur
        adc pcnt
        sta disp_cur
        bcc pd_f
        inc disp_cur + 1
pd_f:   jmp disp_flush

mtab_lo:  .byte <msg1, <msg2, <msg3, <dz_mbuf
mtab_hi:  .byte >msg1, >msg2, >msg3, >dz_mbuf
msg1:     .byte "Saved", 0
msg2:     .byte "Error loading", 0
msg3:     .byte "Error saving", 0
; Beschriftungen der Eingabezeile, je 7 Zeichen (PROMPTW), Reihenfolge = Offsets in pr_lot
lbl_all:  .byte "Find:  "
          .byte "Line:  "
          .byte "File:  "
          .byte "Replace"
          .byte "Mark:  "
          .byte "Label: "
          .byte "Calc:  "
          .byte "Range: "

; ---- Variablen und Tabellen ----
disp_keyv: .word kernal_getin       ; Tastenquelle (austauschbar)
disp_cur:  .word 0
kg_b:      .byte 0
kg_k:      .byte 0
pr_kind:   .byte 0
ed_onl:    .byte 0
ed_oname:  .fill 16, 0
.ifndef IDE_BSS
dz_mbuf:   .fill 60, 0
.endif
pr_lbo:    .byte 0
dz_msg:    .byte 0
pcnt:      .byte 0
pd_c:      .byte 0
.ifndef IDE_BSS
pbuf:      .fill 32, 0
.endif
