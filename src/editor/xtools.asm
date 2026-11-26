; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; xtools.asm - Werkzeuge im Overlay VC65X (src/ide/xoverlay.asm): Hex-Rechner und "Daten einfuegen" (Anregungen vom Turbo Macro Pro).
; Eingabe kommt aus der Eingabezeile des Editors: pbuf / pcnt (disp.asm). Meldungen ueber die Routinen der IDE (ide_ch, ide_cat,
; ide_hex2, ide_dec, ide_show).
;   xo_calc  "2000+3f", "$d020-$d000": Summe oder Differenz zweier 16-Bit-Hexwerte, Meldung "$xxxx = nnnnn"
;   xo_data  "2000 20ff": liest den Speicher des Testprogramms (Bank 0) von bis (hoechstens 256 Byte) und fuegt ihn als .byte-Zeilen
;            (8 Werte je Zeile, 8 Leerzeichen Einrueckung) vor der Cursorzeile ein
;   xo_busy  Hinweiskasten "Loading file ..." (Werkzeug 4);  xo_thapply / xo_threst  Farbschema der IDE / Standardpalette (Werkzeug 5/6)
;
; Rolle: wird in xoverlay.asm hinter fmt.asm eingebunden und liegt damit im Overlay VC65X bei CPU-Adresse $E000.. (Bank 4). Die Routinen
; werden ueber die Sprungtabelle xo_tab (3 Byte je Eintrag) von ide_xcall aufgerufen und beenden sich per RTS zum Aufrufer.
; Gemeinsamer Zustand: pbuf/pcnt (Eingabezeile des Editors, disp.asm), Meldungspuffer dz_mbuf/mi (ide.asm), Editorzeiger ed_cur,
; E0..E3 (Textstelle, 32 Bit), E2 (Arbeitszeiger, 32 Bit); alle Zugriffe auf den VIC-IV gehen ueber E2 = $0FFD_3xxx.
; Hinweis zu den Variablen: sie liegen im Overlay (RAM, beschreibbar) und sind nach dem Laden mit 0 vorbelegt.
; Invariante: beim Einsprung ist die Basisseite die der IDE ($1F); nach jedem Werkzeug erwartet der Aufrufer ein RTS (Meldung per ide_show).
; =====================================================================================================================

; xp_hex: Hexzahl ab pbuf[xp_i] (fuehrende Leerzeichen und ein $ werden uebersprungen) -> xp_v; Carry gesetzt, wenn mindestens eine Ziffer
xp_hex:
        ldy xp_i                    ; Y = Leseposition in pbuf (xp_i bleibt zwischen den Aufrufen erhalten)
xh_s:   cpy pcnt
        bcs xh_b
        lda pbuf,y
        cmp #$20
        bne xh_d
        iny
        jmp xh_s
xh_d:   cmp #$24
        bne xh_z
        iny
xh_z:   lda #$00                    ; Wert und Ziffernzaehler (xp_n) zuruecksetzen; mehr als 4 Ziffern schieben die oberen heraus (16 Bit)
        sta xp_v
        sta xp_v + 1
        sta xp_n
xh_l:   cpy pcnt
        bcs xh_e
        lda pbuf,y
        jsr xp_dig
        bcc xh_e
        ldx #$04                    ; Wert um eine Hexziffer (4 Bit) nach links schieben und die neue Ziffer (A, Bits 0-3) unten einsetzen
xh_m:   asl xp_v
        rol xp_v + 1
        dex
        bne xh_m
        ora xp_v
        sta xp_v
        inc xp_n
        iny
        jmp xh_l
xh_e:   sty xp_i                    ; Leseposition fuer den naechsten Wert merken
        lda xp_n
        beq xh_b                    ; keine Ziffer gelesen: Fehler (Carry geloescht)
        sec
        rts
xh_b:   clc
        rts

; xp_dig: A = Zeichen -> A = Wert 0-15, Carry gesetzt; sonst Carry geloescht
xp_dig: cmp #$30
        bcc xdg_n
        cmp #$3a
        bcc xdg_0
        cmp #$41
        bcc xdg_n
        cmp #$47
        bcc xdg_u
        cmp #$61
        bcc xdg_n
        cmp #$67
        bcs xdg_n
        sec                         ; a-f
        sbc #$57
        sec
        rts
xdg_u:   sec                         ; A-F
        sbc #$37
        sec
        rts
xdg_0:   sec                         ; 0-9
        sbc #$30
        sec
        rts
xdg_n:   clc
        rts

; xo_calc: Hex-Rechner (Werkzeug 2). Eingabe pbuf/pcnt: "wert", "wert+wert" oder "wert-wert" (Leerzeichen erlaubt, Werte 16 Bit,
; Ueberlauf wird abgeschnitten). Ausgabe: Meldung "$xxxx = nnnnn" (Hex und Dezimal), bei Fehler "Input?". Aendert alle Register.
xo_calc:
        lda #$00
        sta xp_i
        jsr xp_hex
        bcc xc_bad
        lda xp_v
        sta xc_a
        lda xp_v + 1
        sta xc_a + 1
        ldy xp_i
xc_w:   cpy pcnt
        bcs xc_show                 ; nur ein Wert: anzeigen
        lda pbuf,y
        cmp #$20
        bne xc_o
        iny
        jmp xc_w
xc_o:   sta xc_op
        iny
        sty xp_i
        jsr xp_hex
        bcc xc_bad
        lda xc_op
        cmp #$2b
        beq xc_add
        cmp #$2d
        bne xc_bad
        sec
        lda xc_a
        sbc xp_v
        sta xc_a
        lda xc_a + 1
        sbc xp_v + 1
        sta xc_a + 1
        jmp xc_show
xc_add: clc
        lda xc_a
        adc xp_v
        sta xc_a
        lda xc_a + 1
        adc xp_v + 1
        sta xc_a + 1
xc_show:
        lda #$00                    ; Meldung neu beginnen (mi = 0), dann "$" + vierstellig hex
        sta mi
        lda #$24
        jsr ide_ch
        lda xc_a + 1
        jsr ide_hex2
        lda xc_a
        jsr ide_hex2
        ldx #<xs_eq
        ldy #>xs_eq
        jsr ide_cat
        lda xc_a                    ; Ergebnis 0 gesondert: die Null wird hier ausdruecklich geschrieben
        ora xc_a + 1                ; (ide_dec wuerde sie auch liefern, dieser Zweig spart den Aufruf)
        bne xc_nz
        lda #$30
        jsr ide_ch
        jmp ide_show
xc_nz:  lda xc_a
        sta ide_n
        lda xc_a + 1
        sta ide_n + 1
        jsr ide_dec
        jmp ide_show
xc_bad: lda #$00
        sta mi
        ldx #<xs_bad
        ldy #>xs_bad
        jsr ide_cat
        jmp ide_show

; xo_data: Daten einfuegen (Werkzeug 3). Eingabe pbuf/pcnt: "von bis" (zwei Hexwerte, 16 Bit, Bereich 1..256 Byte). Liest den Speicher
; des Testprogramms aus Bank 0 (flacher Zeiger E2 = $0000_xxxx, nicht die IDE-Abbildung!) und fuegt ihn als Zeilen
; "        .byte $xx, $xx, ..." (8 Werte je Zeile) vor der Cursorzeile ein. Die Zeichen gehen durch ed_kind/ed_ins wie getippte Tasten,
; damit Undo funktioniert. Danach wird die Zeilenzaehlung ungueltig gemacht (ed_want = $FFFF) und ed_recount ruft sie neu ab.
; Fehler: "Input?" bzw. "Range too large (256)". Aendert alle Register, E0-E3, E2.
xo_data:
        lda #$00
        sta xp_i
        jsr xp_hex
        bcc xc_bad
        lda xp_v
        sta xd_a
        lda xp_v + 1
        sta xd_a + 1
        jsr xp_hex
        bcc xc_bad
        sec                         ; Anzahl = bis - von + 1 (1..256)
        lda xp_v
        sbc xd_a
        sta xd_n
        lda xp_v + 1
        sbc xd_a + 1
        bcc xc_bad                  ; bis < von
        bne xd_big
        inc xd_n
        bne xd_ok
        lda #$01                    ; 256 Byte: Zaehler 0 mit Uebertrag
        sta xd_n + 1
        bne xd_go
xd_ok:  lda #$00                    ; Zaehler 1..255: Hochbyte 0
        sta xd_n + 1
        beq xd_go
xd_big: ldx #<xs_big
        ldy #>xs_big
        lda #$00
        sta mi
        jsr ide_cat
        jmp ide_show
xd_go:  ldx #$03                    ; an den Anfang der Cursorzeile (ed_ls berechnet den Zeilenanfang aus E0 = ed_cur; Cursor dorthin setzen)
xd_c:   lda ed_cur,x
        sta E0,x
        dex
        bpl xd_c
        jsr ed_ls
        ldx #$03
xd_s:   lda E0,x
        sta ed_cur,x
        dex
        bpl xd_s
        lda #$00
        sta ed_sel
xd_line:                            ; eine Ausgabezeile: Einrueckung + bis zu 8 Werte; xd_k zaehlt die Werte der Zeile
        lda xd_n                    ; fertig?
        ora xd_n + 1
        beq xd_end
        ldx #$00
xd_i:   lda xd_ind,x                ; "        .byte " einfuegen
        beq xd_v
        phx
        jsr xd_ch
        plx
        inx
        bne xd_i
xd_v:   lda #$08
        sta xd_k
xd_b:   lda xd_a                    ; Byte aus Bank 0 (Speicher des Testprogramms); E2 wird von ed_ins benutzt, darum jedes Mal neu
        sta E2
        lda xd_a + 1
        sta E2 + 1
        lda #$00
        sta E2 + 2
        sta E2 + 3
        ldz #$00
        lda [E2],z
        sta xd_x
        lda #$24
        jsr xd_ch
        lda xd_x
        lsr
        lsr
        lsr
        lsr
        jsr xd_hx
        lda xd_x
        and #$0f
        jsr xd_hx
        inc xd_a
        bne xd_f
        inc xd_a + 1
xd_f:   lda xd_n                    ; Anzahl - 1 (16-Bit-Dekrement)
        bne xd_d1
        dec xd_n + 1
xd_d1:  dec xd_n
        lda xd_n
        ora xd_n + 1
        beq xd_nl
        dec xd_k
        beq xd_nl
        lda #$2c
        jsr xd_ch
        jmp xd_b
xd_nl:  lda #K_RET                  ; Zeilenumbruch
        sta ed_k
        jsr ed_kind
        lda #$0a
        jsr ed_ins
        jmp xd_line
xd_end: lda #$ff                    ; Zeilenzaehlung/Anzeigeziel ungueltig: ed_recount rechnet alles neu
        sta ed_want
        sta ed_want + 1
        jmp ed_recount

; xd_hx: Nibble (A = 0..15) als Kleinbuchstaben-Hexziffer einfuegen; xd_ch: A wie eine Taste einfuegen (Aendert A, X, Y, E-Zeiger).
xd_hx:  cmp #$0a                    ; Nibble -> Kleinbuchstaben-Hexziffer
        bcc xd_h0
        clc
        adc #$57
        jmp xd_ch
xd_h0:  clc
        adc #$30
xd_ch:  sta ed_k                    ; Zeichen wie eine Taste einfuegen (Verlauf)
        jsr ed_kind
        lda ed_k
        jmp ed_ins

; ---- Variablen und Texte ----
xd_ind: .byte "        .byte ", 0
xs_eq:  .byte " = ", 0
xs_bad: .byte "Input?", 0
xs_big: .byte "Range too large (256)", 0
xp_i:   .byte 0
xp_n:   .byte 0
xp_v:   .word 0
xc_a:   .word 0
xc_op:  .byte 0
xd_a:   .word 0
xd_n:   .word 0
xd_k:   .byte 0
xd_x:   .byte 0

; xo_busy: Hinweiskasten "Loading file ..." in der Bildschirmmitte (3 Zeilen, 24 Spalten) waehrend ed_fload laeuft. Das Laden von der Diskette
; blockiert die CPU; darum blinkt der Text ueber das Attribut "Blinken" ($10 im Farb-RAM, Attributmodus) von der Hardware (VIC-IV), ohne
; dass die CPU etwas tun muss. Der Editor zeichnet nach dem Laden alles neu und loescht damit den Kasten.
.ifdef ch_rowp                      ; nur mit IDE-Rahmen (chrome.asm); Pruefprogramme ohne Rahmen bekommen eine leere Routine
xo_busy:
        ldx #<xb_s1                 ; Text "Loading file ..."
        ldy #>xb_s1
        bne xb_go
xo_build:
        ldx #<xb_s2                 ; Text "Building ..." (Strg+E)
        ldy #>xb_s2
xb_go:  stx xb_tl
        sty xb_th
        lda ed_rows                 ; erste Zeile des Kastens = Bildmitte - 1
        lsr
        sec
        sbc #$01
        sta xb_r
        lda #$00
        sta xb_i
xb_l:   lda xb_r
        clc
        adc xb_i
        jsr ch_rowp                 ; Zeile waehlen (Inhalt bleibt), EA = Attribute, ET+2 = Zeilenanfang im Bild (chrome.asm)
        lda #$1c                    ; Startspalte 28 ((80 - 24) / 2)
        sta ch_c
        ldx #<xb_s0
        ldy #>xb_s0
        lda xb_i
        cmp #$01
        bne xb_a
        ldx xb_tl                   ; mittlere Zeile: Text, umgekehrt und blinkend
        ldy xb_th
        lda #COL_TEXT | SELF | $10  ; $10 = Attribut Blinken im Farb-RAM-Byte (Bit 4); SELF = umgekehrt
        bne xb_p
xb_a:   lda #COL_BAR                ; obere und untere Zeile: Rahmen in der Farbe der Leiste
xb_p:   jsr ch_put
        inc xb_i
        lda xb_i
        cmp #$03
        bne xb_l
        rts
xb_r:   .byte 0
xb_i:   .byte 0
xb_tl:  .byte 0
xb_th:  .byte 0
xb_s0:  .byte "+----------------------+", 0
xb_s1:  .byte "    Loading file ...    ", 0
xb_s2:  .byte "      Building ...      ", 0
.else
xo_busy: rts
xo_build: rts
.endif

; ---------------------------------------------------------------------------------------------------------------------
; Farbschema der IDE (Anlehnung an die Entwuerfe in docs/mockups): Der Text-Bildschirm kennt nur EINEN Hintergrund; darum wird die Palette
; des VIC-IV umbelegt (Hintergrund tiefes Blau statt Schwarz, Rahmen dunkelgrau-blau, Textfarben gedaempft, Leisten lavendel).
; xo_thapply (Werkzeug 5) setzt die Farben der IDE, xo_threst (Werkzeug 6) die Standardfarben des C65 zurueck (vor jedem Testprogramm).
; Tabelle je Eintrag: Farbnummer, neu R G B, Standard R G B (4 Bit je Kanal, im unteren Halbbyte). Die Palette liegt bei $D100 (rot),
; $D200 (gruen), $D300 (blau); Zugriff ueber die flache Adresse $0FFD_3x00, damit die Ein-/Ausgabeabbildung nicht gebraucht wird.
; ---------------------------------------------------------------------------------------------------------------------
; xo_thapply / xo_threst: Palette setzen. Eingabe: keine (xt_m = 0 neues Schema, 1 Standardfarben). Aendert alle Register, E2, Z.
; Je Tabellenzeile (7 Byte) werden die drei Farbkanaele an Palettenregister Farbnummer geschrieben: E2+1 = $31/$32/$33 nacheinander
; (rot $D100.., gruen $D200.., blau $D300..), Z = Farbnummer. Danach wird die Rahmenfarbe $D020 gesetzt.
xo_thapply:
        lda #$00
        beq xt_go
xo_threst:
        jsr xo_vsave                ; vor einem Testprogramm: VIC-IV-Register der IDE merken (xo_vrest stellt sie danach wieder her)
        lda #$01                    ; und das Programm im Standardzustand starten (Bildschirm 25 Zeilen bei $0800 wie von BASIC): nicht auf die
        sta xv_pg                   ; "heissen" Register verlassen, ein aelteres Xemu setzt Zeiger und Zeilenzahl dabei nicht zurueck
        jsr xo_vrest
        lda #$00
        sta xv_pg
        lda #$01
xt_go:  sta xt_m
        lda #$00
        sta E2
        lda #$fd
        sta E2 + 2
        lda #$0f
        sta E2 + 3
        lda #$30                    ; VIC-IV freischalten ($D02F = $47, $53)
        sta E2 + 1
        ldz #$2f
        lda #$47
        sta [E2],z
        lda #$53
        sta [E2],z
        ldy #$00
xt_r:   lda xt_tab,y                ; Farbnummer = Index in die Palettenregister
        taz
        iny
        lda #$31                    ; rot ab $D100
        sta E2 + 1
        ldx #$03                    ; drei Kanaele: neue Werte bei Y .. Y+2, Standardwerte bei Y+3 .. Y+5
xt_c:   lda xt_m
        bne xt_d
        lda xt_tab,y                ; neue Farbe
        jmp xt_w
xt_d:   lda xt_tab + 3,y            ; Standardfarbe
xt_w:   sta [E2],z
xt_n:   inc E2 + 1
        iny
        dex
        bne xt_c
        iny                         ; die drei Standardwerte der Zeile ueberspringen
        iny
        iny
        cpy #XT_LEN
        bne xt_r
        lda #$30                    ; Rahmenfarbe $D020: IDE = Nummer 9 (dunkelgrau-blau), Testprogramm = 0 (schwarz)
        sta E2 + 1
        ldz #$20
        ldx xt_m
        lda xt_bd,x
        sta [E2],z
        ldz #$00
        rts
xt_bd:  .byte $09, $00              ; Rahmenfarbnummer: [0] IDE, [1] Standard
xt_m:   .byte 0                     ; 0 = IDE-Schema setzen, 1 = Standard
xt_tab:                             ; je Zeile: Farbnummer, neu R G B, Standard R G B (4 Bit je Kanal)
        .byte  0,  1,  1,  2,  0,  0,  0
        .byte  1, 14, 14, 15, 15, 15, 15
        .byte  2, 15,  6,  6, 15,  0,  0
        .byte  3, 15,  8, 11,  0, 15, 15
        .byte  5,  8, 14,  8,  0, 15,  0
        .byte  7, 15, 11,  4, 15, 15,  0
        .byte  9,  3,  3,  4, 10,  4,  0
        .byte 11,  5,  6,  9,  5,  5,  5
        .byte 12,  7,  7, 11,  8,  8,  8
        .byte 13,  7, 14, 15,  9, 15,  9
        .byte 14,  9,  9, 15,  9,  9, 15
XT_LEN = * - xt_tab

; ---------------------------------------------------------------------------------------------------------------------
; VIC-IV-Zustand sichern und wiederherstellen (Werkzeug 7). Ein Testprogramm wie prallball schaltet Zeichenmodi des VIC-IV um (640 x 400,
; Vollfarbzeichen $D054, Zeilenschritt, Sprite-Zeiger ...), die IOINIT/SCINIT nicht zuruecksetzen. xo_vsave (aus xo_threst, vor dem Programm)
; kopiert $D000-$D07F ins Attic ($0878_0000); xo_vrest schreibt sie nach dem Programm aufsteigend zurueck ("heisse" Register wie $D031 setzen
; dabei SCRNPTR usw. zurueck, die danach folgenden Register stellen sie wieder her) und haelt den DMA-Audio-Kanal an ($D711).
; Ausgenommen sind $D019 (Interruptmeldung), $D01E/$D01F (Kollisionen, beim Lesen geloescht) und $D02F (Schluessel).
; ---------------------------------------------------------------------------------------------------------------------
xv_ptr: lda #$00                    ; E2 = $0FFD_3000 (VIC-IV, flach), E3 = $0878_0000 (Attic)
        sta E2
        sta E3
        lda xv_pg                   ; Seite im Attic: 0 = Zustand der IDE, 1 = Standardzustand beim Start (Bildschirm wie von BASIC)
        sta E3 + 1
        lda #$30
        sta E2 + 1
        lda #$fd
        sta E2 + 2
        lda #$0f
        sta E2 + 3
        lda #$78
        sta E3 + 2
        lda #$08
        sta E3 + 3
        ldz #$2f                    ; VIC-IV freischalten
        lda #$47
        sta [E2],z
        lda #$53
        sta [E2],z
        ldz #$00
        rts
xv_pg:  .byte 0
xo_vstd:                            ; Werkzeug 9: Standardzustand des VIC-IV beim Start der IDE merken (Seite 1)
        lda #$01
        sta xv_pg
        jsr xo_vsave
        lda #$00
        sta xv_pg
        rts
xo_vsave:
        jsr xv_ptr
xv_s:   lda [E2],z
        sta [E3],z
        inz
        cpz #$80
        bne xv_s
        ldz #$00
        rts
xo_vrest:
        jsr xv_ptr
xv_r:   cpz #$19
        beq xv_n
        cpz #$1e
        beq xv_n
        cpz #$1f
        beq xv_n
        cpz #$2f
        beq xv_n
        lda [E3],z
        sta [E2],z
xv_n:   inz
        cpz #$80
        bne xv_r
        lda #$37                    ; $D711 (DMA-Audio-Steuerung): Kanaele aus
        sta E2 + 1
        ldz #$11
        lda #$00
        sta [E2],z
        ldz #$00
        rts

; ---------------------------------------------------------------------------------------------------------------------
; xo_logo (Werkzeug 10): Logo "VC65." als Blockbild aus Zeichenzellen (Startbild und Menue File > About). Eine Pixelschrift 5 x 7: jedes Pixel
; sind zwei umgekehrte Leerzeichen nebeneinander; "VC" in Lavendel (wie die Leisten), "65" weiss, der Punkt gelb (Palettenfarbe 7). Darunter
; Version, Beschreibung und "Press any key"; wartet auf eine Taste (disp_getkey), der Aufrufer zeichnet danach den Editor neu. Nur mit IDE-Rahmen.
; ---------------------------------------------------------------------------------------------------------------------
.ifdef ch_rowp
xo_logo:
        jsr ed_view                 ; Editorbild und Rahmen neu zeichnen (loescht ein offenes Menue); das Logo kommt darueber
        jsr disp_show
        lda #$02                    ; Textbereich abdunkeln (Zeilen 2 bis ed_rows-2: Zeichen bleiben, Farbe = COL_GUTTER ohne Auswahl-/Blinkbit),
        sta lg_rr                   ; damit das Logo darueber lesbar bleibt; Befehlsleiste (0), Reiterleiste (1) und Statuszeile (letzte) bleiben
lg_cl:  lda lg_rr
        jsr ch_rowp                 ; ET+2 = Zeichenzeile, EA = Attribute
        ldz #$4f                    ; 80 Spalten
        lda #COL_GUTTER
lg_cc:  sta [EA],z
        dez
        bpl lg_cc
        inc lg_rr
        ldx ed_rows
        dex
        cpx lg_rr
        bne lg_cl
        lda ed_rows                 ; oberste Zeile des Logos = Bildmitte - 6
        lsr
        sec
        sbc #$06
        sta lg_top
        lda #$00
        sta lg_r
lg_row: lda lg_top
        clc
        adc lg_r
        jsr ch_rowp                 ; Zeile waehlen: ET+2 = Zeichenzeile, EA = Attribute
        lda #$00
        sta lg_l
lg_let: lda lg_l                    ; Muster der Zeile: lg_tab[Buchstabe * 7 + Zeile]
        asl
        asl
        asl
        sec
        sbc lg_l
        clc
        adc lg_r
        tax
        lda lg_tab,x
        asl                         ; Bit 4 nach Bit 7 schieben
        asl
        asl
        sta lg_b
        ldx #COL_BAR                ; V und C lavendel, 6 und 5 weiss
        lda lg_l
        cmp #$02
        bcc lg_c1
        ldx #COL_TEXT | SELF
lg_c1:  stx lg_col
        lda lg_l                    ; Startspalte = 15 + Buchstabe * 12
        asl
        asl
        sta lg_x
        asl
        clc
        adc lg_x
        adc #$0f
        sta lg_x
        ldx #$05
lg_px:  asl lg_b
        bcc lg_np
        ldy lg_x
        lda #$20
        sta (ET + 2),y
        iny
        sta (ET + 2),y
        ldz lg_x
        lda lg_col
        sta [EA],z
        inz
        sta [EA],z
lg_np:  inc lg_x
        inc lg_x
        dex
        bne lg_px
        inc lg_l
        lda lg_l
        cmp #$04
        bne lg_let
        lda lg_r                    ; gelber Punkt in den beiden unteren Zeilen (Spalten 63, 64)
        cmp #$05
        bcc lg_nd
        ldy #$3f
        lda #$20
        sta (ET + 2),y
        iny
        sta (ET + 2),y
        ldz #$3f
        lda #COL_NUM | SELF
        sta [EA],z
        inz
        sta [EA],z
lg_nd:  inc lg_r
        lda lg_r
        cmp #$07
        bne lg_row
        lda lg_top                  ; Version, Beschreibung, Hinweis
        clc
        adc #$09
        jsr ch_rowp
        lda #$20
        sta ch_c
        ldx #<lg_s1
        ldy #>lg_s1
        lda #COL_TEXT
        jsr ch_put
        lda lg_top
        clc
        adc #$0a
        jsr ch_rowp
        lda #$11
        sta ch_c
        ldx #<lg_s2
        ldy #>lg_s2
        lda #COL_COMMENT
        jsr ch_put
        lda lg_top
        clc
        adc #$0c
        jsr ch_rowp
        lda #$21
        sta ch_c
        ldx #<lg_s3
        ldy #>lg_s3
        lda #COL_NUM
        jsr ch_put
        jmp disp_getkey             ; auf eine Taste warten
lg_top: .byte 0
lg_rr:  .byte 0
lg_r:   .byte 0
lg_l:   .byte 0
lg_b:   .byte 0
lg_col: .byte 0
lg_x:   .byte 0
lg_tab: .byte 17, 17, 17, 17, 17, 10, 4            ; V
        .byte 14, 17, 16, 16, 16, 17, 14            ; C
        .byte 6, 8, 16, 30, 17, 17, 14              ; 6
        .byte 31, 16, 30, 1, 1, 17, 14              ; 5
lg_s1:  .byte "VC65 0.1.1-alpha", 0
lg_s2:  .byte "Native development environment for the MEGA65", 0
lg_s3:  .byte "Press any key", 0
.else
xo_logo: rts
.endif
