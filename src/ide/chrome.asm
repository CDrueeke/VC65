; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; chrome.asm - Rahmen der IDE um den Editor (nur im Programm VC65): Kopfzeilen und Probleme-Leiste, wie in den Entwuerfen
; (docs/mockups). Bild (50 Zeilen):  Zeile 0 Befehlsleiste (umgekehrt), Zeile 1 Dateiname und Projektlaufwerk, dann der Text,
; darunter vier Zeilen Probleme-Leiste (Kopf + bis zu drei Eintraege des letzten Durchlaufs), zuletzt die Statuszeile. Im 25-Zeilen-Bild
; fehlt die Probleme-Leiste. Der Editorkern kennt nur ed_hdr/ed_ftr (ed_layout); gezeichnet wird hier, nach jedem ed_view
; ueber den Haken disp_tabdv (chrome_draw). Die Eintraege der Probleme-Leiste fuellt ide_plist (ide.asm) nach jedem Uebersetzen.
;
; Rolle/Aufbau: (1) Rahmenzeichnung chrome_draw/ch_*, (2) Menue (HELP/ESC) mr_*/chrome_menu mit den Tabellen mn_*.
; Bildpuffer: Textzeile r liegt bei ed_scr + 80 * r (SCRW = 80), die Farb-/Attributbytes (Farb-RAM $0FF8_0000, ED_ATTR32) werden
; ueber den 32-Bit-Zeiger EA angesprochen ([EA],z); der Bildschirmcode-Zeiger ist ET+2 ((ET+2),y), ed_rp die Zeilenadresse.
; Attribut = Farbe (0-15) + SELF (Umkehrdarstellung, Attributmodus). Zeichen werden per asc2scr von ASCII in Bildschirmcodes gewandelt.
; Zeropage: ET+2/ET+3 Bildzeile, ET+6/ET+7 Zeiger auf Menueeintraege, EA..EA+3 Attributzeiger, E2..E2+3 Textzeiger (32 Bit).
; Reihenfolge: chrome_init (nach ed_init, vor disp_init) setzt die Haken und die Aufteilung (ed_layout); chrome_draw wird danach
; bei jedem Neuzeichnen vom Editor aufgerufen. Palette der Farben: Farbschema der IDE (xtools.asm, Werkzeug 5).
; Menue-Tastenbelegung: Pfeile links/rechts waehlen den Eintrag der Leiste, auf/ab den Befehl, Return fuehrt aus, STOP/HELP/ESC schliessen.
; =====================================================================================================================
CH_HDR = 2                          ; Zeilen oberhalb des Textes (Befehlsleiste, Dateizeile)
CH_FTR = 4                          ; Zeilen unterhalb (Probleme-Leiste: Kopf + 3 Eintraege); die Statuszeile zaehlt der Editor selbst
COL_ERR = 2                         ; rot
COL_WARN = 7                        ; gelb
COL_OKC = 5                         ; gruen
COL_BAR = 14 | SELF                 ; umgekehrte Leiste (hellblau)

; chrome_init: nach ed_init (ed_init stellt die Standardaufteilung her). Schaltet den Rahmen ein (ed_deco), setzt die Haken
; disp_menuv/disp_tabdv und legt mit ed_layout fest: A = Zeilen oben (CH_HDR), X = Zeilen unten (CH_FTR nur bei 50 Zeilen, sonst 0).
; Aendert A, X, Y.
chrome_init:
        lda #$01
        sta ed_deco
        lda #<chrome_menu
        sta disp_menuv
        lda #>chrome_menu
        sta disp_menuv + 1
        lda #<chrome_draw
        sta disp_tabdv
        lda #>chrome_draw
        sta disp_tabdv + 1
        lda #CH_HDR
        ldx #$00
        ldy ed_rows
        cpy #50                     ; erst ab 50 Zeilen ist Platz fuer die Probleme-Leiste
        bcc ci_l
        ldx #CH_FTR
ci_l:   jmp ed_layout

; chrome_draw: Rahmen zeichnen (Haken disp_tabdv, nach jedem ed_view). Keine Eingabe; aendert alle Register, ch_*-Variablen.
; Zeile 0 Befehlsleiste, Zeile 1 Dateiname + Laufwerk, im 50-Zeilen-Bild zusaetzlich Probleme-Leiste (ed_ftr > 0).
chrome_draw:
        lda #$00                    ; Zeile 0: Befehlsleiste
        jsr ch_row
        lda #COL_BAR
        jsr ch_bar
        lda #$00
        sta ch_c
        lda #COL_BAR
        ldx #<s_menu
        ldy #>s_menu
        jsr ch_put
        lda #$01                    ; Zeile 1: Dateiname und Projektlaufwerk
        jsr ch_row
        lda #$01
        sta ch_c
        ldx #<s_noname
        ldy #>s_noname
        lda ed_fnl
        beq cd_fn
        tax                         ; Name (ed_fnl Zeichen) mit 0 beendet nach ch_nm (ed_fname ist nicht abgeschlossen; Rueckwaertskopie)
        lda #$00
        sta ch_nm,x
cd_fc:  dex
        bmi cd_fe
        lda ed_fname,x
        sta ch_nm,x
        jmp cd_fc
cd_fe:  ldx #<ch_nm
        ldy #>ch_nm
cd_fn:  lda #COL_CURNUM             ; X/Y zeigen auf den Namen oder auf "(no name)"
        jsr ch_put
        lda #$3c                    ; Laufwerk rechts (Spalte 60)
        sta ch_c
        ldx #<s_drv
        ldy #>s_drv
        lda #COL_GUTTER
        jsr ch_put
        lda ed_fdev
        clc
        adc #$30
        jsr asc2scr                 ; Laufwerksziffer als Bildschirmcode direkt hinter "Project drive "
        ldy ch_c
        sta (ET + 2),y
        lda #COL_GUTTER
        ldz ch_c
        sta [EA],z                  ; Attribut der Ziffer (Z = Spalte)
        lda ed_ftr                  ; Probleme-Leiste vorhanden?
        beq cd_r
        lda ed_rows                 ; Probleme-Leiste ab Zeile rows - 1 - ftr: Kopf, dann drei Eintraege
        sec
        sbc #$01
        sbc ed_ftr                  ; (das Carry bleibt nach dem ersten sbc gesetzt: rows - 1 - ftr)
        sta ch_r
        jsr ch_row
        lda #COL_STAT | SELF        ; Kopfzeile "Problems" umgekehrt wie die Statuszeile
        jsr ch_bar
        lda #$01
        sta ch_c
        lda #COL_STAT | SELF
        ldx #<s_prob
        ldy #>s_prob
        jsr ch_put
        lda #$00
        sta ch_i
cd_l:   inc ch_r                    ; naechste Eintragszeile (drei Durchlaeufe)
        lda ch_r
        jsr ch_row
        lda ch_i
        cmp pq_n                    ; pq_n = Zahl der gefuellten Eintraege (ide_plist)
        bcs cd_nm
        tax                         ; Eintrag ch_i aus dem Attic
        lda pq_kind,x               ; 0 Fehler, 1 Warnung -> Farbe aus cd_col
        tay
        lda ch_i
        jsr pq_ptr                  ; E2 = Zeiger auf die Zeile im Attic (PQ_BASE)
        lda #$01
        sta ch_c
        lda cd_col,y
        jsr ch_putf                 ; Zeichenkette ueber den 32-Bit-Zeiger E2 (Attic)
        jmp cd_nx
cd_nm:  lda ch_i                    ; ohne Eintraege: in der ersten Zeile "No problems"
        bne cd_nx
        lda #$01
        sta ch_c
        ldx #<s_clean
        ldy #>s_clean
        lda #COL_GUTTER
        jsr ch_put
cd_nx:  inc ch_i
        lda ch_i
        cmp #$03
        bne cd_l
cd_r:   rts
cd_col: .byte COL_ERR, COL_WARN     ; Farbe je Eintragsart (pq_kind)

; ch_row: A = Bildzeile -> ed_rp, ET+2 = Zeilenanfang im Bildpuffer, EA = Attribute der Zeile; Zeile geleert
ch_row:
        jsr disp_row80              ; disp_cur = Zeile * 80
        clc
        lda disp_cur
        adc #<ed_scr
        sta ed_rp
        lda disp_cur + 1
        adc #>ed_scr
        sta ed_rp + 1
        jmp dw_clear                ; (ed.asm) leert Zeichen (Leerzeichen) und Attribute der Zeile und setzt ET+2 sowie EA

; ch_bar: A = Attribut fuer alle 80 Spalten der mit ch_row gewaehlten Zeile. Aendert Z.
ch_bar: ldz #SCRW - 1
cb_l:   sta [EA],z
        dez
        bpl cb_l
        rts

; ch_put: A = Attribut, X/Y = Zeichenkette im Abbild (ASCII, mit 0 beendet, Adresse X/Y: Bank 4 = $0004_xxxx), ch_c = Startspalte;
; ch_putf: wie ch_put, die Zeichenkette steht ueber den 32-Bit-Zeiger E2 (zum Beispiel im Attic). Zeile mit ch_row gewaehlt.
; Aendert A, X, Y, Z, E2, ch_c (ch_c = naechste freie Spalte); Zeichen jenseits Spalte 79 werden verworfen.
ch_put:
        stx E2
        sty E2 + 1
        ldx #$04                    ; Bank 4: die Zeichenketten liegen im IDE-Abbild ($0004_xxxx)
        stx E2 + 2
        ldx #$00
        stx E2 + 3
ch_putf:
        sta ch_a
cp_l:   ldz #$00
        lda [E2],z                  ; Z = 0 nur fuer den Textzeiger; unten wird Z fuer die Spalte des Attributs umgenutzt
        beq cp_r
        jsr asc2scr
        ldy ch_c
        cpy #SCRW
        bcs cp_r
        sta (ET + 2),y
        lda ch_a
        ldz ch_c
        sta [EA],z                  ; Attribut der Spalte
        inc ch_c
        inc E2
        bne cp_l
        inc E2 + 1
        jmp cp_l
cp_r:   rts

ch_c:   .byte 0                     ; aktuelle Spalte beim Schreiben
ch_a:   .byte 0                     ; Attribut fuer ch_put
ch_r:   .byte 0                     ; aktuelle Bildzeile der Probleme-Leiste
ch_i:   .byte 0                     ; Eintragsnummer der Probleme-Leiste
s_menu: .byte "VC65  File  Edit  Search  Build  Debug    ESC or HELP: Menu", 0
s_noname: .byte "(no name)", 0
s_drv:  .byte "Project drive ", 0
ch_nm:  .fill 17, 0
s_prob: .byte "Problems", 0
s_clean: .byte "No problems", 0

; ---- Menue (HELP-Taste): Aufklappfelder zu den Befehlen der Leiste. Links/rechts waehlt den Eintrag der Leiste, auf/ab den Befehl,
; Return fuehrt aus (der Befehl geht wie eine Taste an die Hauptschleife), STOP/HELP schliesst.
MN_N    = 5                         ; Eintraege der Leiste
MN_W    = 20                        ; Breite der Aufklappfelder

; chrome_menu: A = gewaehlter Befehl (SP_*- oder Editortaste, wie eine Taste an die Hauptschleife) oder 0 bei Abbruch.
; Haken disp_menuv. Zustand: mn_t = Menue der Leiste (0..MN_N-1), mn_i = Eintrag darin. Aendert alle Register.
chrome_menu:
        lda #$00
        sta mn_t
        sta mn_i
mr_l:   jsr mr_draw
        jsr disp_getkey
        cmp #$03                    ; STOP
        beq mr_x
        cmp #$84                    ; HELP (Taste liefert in der IDE genau $84, siehe fk_new in ide.asm)
        beq mr_x
        cmp #$1b                    ; ESC
        beq mr_x
        cmp #$0d
        beq mr_go
        cmp #K_RIGHT
        beq mr_r
        cmp #K_LEFT
        beq mr_lf
        cmp #K_DOWN
        beq mr_d
        cmp #K_UP
        bne mr_l
        ldx mn_i                    ; hoch: vom ersten Eintrag zum letzten
        bne mr_u1
        jsr mr_cnt
        tax
mr_u1:  dex
        stx mn_i
        jmp mr_l
mr_d:   jsr mr_cnt                  ; runter: nach dem letzten Eintrag wieder zum ersten
        ldx mn_i
        inx
        stx mn_i
        cmp mn_i
        bne mr_l
        lda #$00
        sta mn_i
        beq mr_l
mr_r:   ldx mn_t                    ; rechts: naechstes Menue (nach dem letzten wieder das erste)
        inx
        cpx #MN_N
        bne mr_t
        ldx #$00
        beq mr_t
mr_lf:  ldx mn_t                    ; links: vorheriges Menue (vor dem ersten das letzte)
        bne mr_l1
        ldx #MN_N
mr_l1:  dex
mr_t:   stx mn_t
        lda #$00
        sta mn_i
        beq mr_l
mr_x:   lda #$00
        rts
mr_go:  jsr mr_ent                  ; Return: Byte 0 des Eintrags = Befehl (A)
        ldy #$00
        lda (ET + 6),y
        rts

; mr_blk: ET+6 = Block des gewaehlten Menues (Anzahl, dann Eintraege: Befehl, Name, 0)
mr_blk: lda mn_t
        asl
        tax
        lda mn_tab,x
        sta ET + 6
        lda mn_tab + 1,x
        sta ET + 7
        rts

; mr_cnt: A = Zahl der Eintraege des Menues
mr_cnt: jsr mr_blk
        ldy #$00
        lda (ET + 6),y
        rts

; mr_ent: ET+6 = Eintrag mn_i (Byte 0 = Befehl, ab Byte 1 der Name)
mr_ent: jsr mr_blk
        inc ET + 6
        bne me_a
        inc ET + 7
me_a:   ldx mn_i
me_l:   beq me_d
        ldy #$01                    ; Eintrag ueberspringen (Befehl, Name, 0)
me_s:   lda (ET + 6),y
        iny
        cmp #$00
        bne me_s
        tya
        clc
        adc ET + 6
        sta ET + 6
        bcc me_n
        inc ET + 7
me_n:   dex
        jmp me_l
me_d:   rts

; mr_draw: Bild neu zeichnen, dann der gewaehlte Eintrag der Leiste hell und das Aufklappfeld darunter. Es wird nur das Attribut der
; Leiste umgefaerbt (7 Spalten ab mn_col) und je Eintrag eine Zeile MN_W breit mit Leerzeichen und Name ueberschrieben; der
; Editorinhalt darunter bleibt erhalten und wird beim naechsten ed_view neu gezeichnet. Aendert alle Register.
mr_draw:
        jsr ed_view
        jsr disp_show
        lda #$00
        jsr ch_rowp
        ldx mn_t
        lda mn_col,x                ; Spalte des Menuenamens in der Leiste (Tabelle mn_col)
        taz                         ; als Z-Index fuer [EA],z
        ldx #$07                    ; Breite der Hervorhebung
mr_h:   lda #COL_TEXT | SELF
        sta [EA],z
        inz
        dex
        bne mr_h
        jsr mr_cnt
        sta mr_n
        lda #$00
        sta mr_zr
mr_rl:  lda mr_zr
        clc
        adc #$01                    ; Bildzeile 1 + Eintrag
        jsr ch_rowp
        lda #COL_BAR
        ldx mr_zr
        cpx mn_i
        bne mr_nl
        lda #COL_TEXT | SELF
mr_nl:  sta ch_a                    ; Attribut dieser Zeile (gewaehlter Eintrag hell, sonst Leistenfarbe)
        ldx mn_t
        ldy mn_col,x                ; Y = Spalte (fuer (ET+2),y), Z = dieselbe Spalte (fuer [EA],z)
        tya
        taz
        ldx #MN_W
mr_f:   lda #$20
        sta (ET + 2),y
        lda ch_a
        sta [EA],z
        iny
        inz
        dex
        bne mr_f
        lda mn_i                    ; Name des Eintrags mr_zr holen (mn_i vorubergehend ersetzen; mr_ent arbeitet mit mn_i)
        pha
        lda mr_zr
        sta mn_i
        jsr mr_ent
        pla
        sta mn_i
        ldx mn_t
        lda mn_col,x
        clc
        adc #$01
        sta ch_c
        clc
        lda ET + 6
        adc #$01
        tax
        lda ET + 7
        adc #$00
        tay
        lda ch_a
        jsr ch_put
        inc mr_zr
        lda mr_zr
        cmp mr_n
        bne mr_rl
        rts

; ch_rowp: A = Bildzeile -> ed_rp, ET+2 = Zeilenanfang, EA = Attribute (die Zeile bleibt unveraendert; im Gegensatz zu ch_row)
ch_rowp:
        jsr disp_row80
        clc
        lda disp_cur
        adc #<ed_scr
        sta ed_rp
        sta ET + 2
        lda disp_cur + 1
        adc #>ed_scr
        sta ed_rp + 1
        sta ET + 3
        jmp dw_attrptr

mn_t:   .byte 0
mn_i:   .byte 0
mr_c:   .byte 0
mr_zr:  .byte 0
mr_n:   .byte 0
mn_col: .byte 5, 11, 17, 25, 32     ; Spalte jedes Menuenamens in der Befehlsleiste s_menu ("VC65  File  Edit ..."; Spalte 0 beginnt "VC65")
mn_tab: .word mn_m0, mn_m1, mn_m2, mn_m3, mn_m4
; Menueblock: erst die Zahl der Eintraege, dann je Eintrag Byte 0 = Befehlscode, danach Name (Zeichenkette, mit 0 beendet; Name
; enthaelt die Tastenangabe, in gleicher Breite aufgefuellt). Die Befehlscodes sind die SP_*/K_*-Werte aus disp.asm/ed.asm.
mn_m0:  .byte 6                     ; File
        .byte SP_LOAD, "Load          ^O  ", 0
        .byte SP_SAVE, "Save          ^K  ", 0
        .byte SP_PRG, "Save program  ^F  ", 0
        .byte SP_DEV, "Drive         ^A  ", 0
        .byte SP_ABOUT, "About VC65          ", 0
        .byte SP_QUIT, "Quit          STOP", 0
mn_m1:  .byte 10                    ; Edit
        .byte K_UNDO, "Undo          ^P  ", 0
        .byte K_REDO, "Redo          ^U  ", 0
        .byte K_MARK, "Mark          F5  ", 0
        .byte K_COPY, "Copy          F6  ", 0
        .byte K_CUT, "Cut           F7  ", 0
        .byte K_PASTE, "Paste         F8  ", 0
        .byte SP_FMT, "Align line        ", 0
        .byte SP_FMTA, "Align all         ", 0
        .byte SP_CALC, "Hex calculator    ", 0
        .byte SP_DATA, "Insert data       ", 0
mn_m2:  .byte 8                     ; Search
        .byte SP_FIND, "Find          F1  ", 0
        .byte SP_NEXT, "Find next     F2  ", 0
        .byte SP_PREV, "Find previous F4  ", 0
        .byte SP_GOTO, "Go to line    F3  ", 0
        .byte SP_REPL, "Replace           ", 0
        .byte SP_LAB, "Find label        ", 0
        .byte SP_MSET, "Set mark          ", 0
        .byte SP_MGO, "Go to mark        ", 0
mn_m3:  .byte 2                     ; Build
        .byte SP_ASM, "Assemble      ^E  ", 0
        .byte SP_RUN, "Run           ^R  ", 0
mn_m4:  .byte 2                     ; Debug
        .byte SP_DBG, "Debugger      ^D  ", 0
        .byte SP_BP, "Breakpoint    ^G  ", 0
