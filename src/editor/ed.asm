; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; ed.asm - Editorkern (Etappe N1, erste Stufe): Textpuffer als Lueckenpuffer im Attic, Cursor und Bildausschnitt, Tasten-
; ereignisse, Zeichnen in einen Bildpuffer (Zeichen- und Attributbytes). Tastatur und Bildschirm sind getrennt: der Kern
; nimmt Tastencodes (ed_key) und fuellt ed_scr/ed_attr; das Kopieren auf den VIC-IV-Bildschirm und das Lesen der Tastatur
; gehoeren zur Anzeigeschicht (spaeter). Quelltext ist ASCII, Zeilentrenner LF ($0A), das Byte 0 kommt im Text nicht vor.
; Positionen sind Zeichenpositionen im Text (0 .. Laenge), 32 Bit. Die Zeropage-Zellen E0..E3 (je 4 Byte) und ET gehoeren
; dem Editor (sie ueberlagern die des Assemblers, beide laufen nie gleichzeitig).
; Tastencodes: druckbare ASCII-Zeichen $20..$7E, K_RET $0D, K_TAB $09 (Leerzeichen bis zum naechsten Vielfachen von 4),
; K_BS $14, K_DEL $C3, Cursor K_UP $91, K_DOWN $11, K_LEFT $9D, K_RIGHT $1D, K_HOME $13, K_END $C0, K_PGUP $C1, K_PGDN $C2.
; =====================================================================================================================
; ---------------------------------------------------------------------------------------------------------------------
; UEBERBLICK UND ARCHITEKTUR
; ---------------------------------------------------------------------------------------------------------------------
; Der Kern ist reine Datenhaltung plus Zeichnen; er kennt weder Tastaturhardware noch VIC-IV-Register. Die Schichten:
;   Anzeigeschicht (disp.asm) / IDE (ide.asm)  -->  ed_key(A)  -->  Kern  -->  ed_scr / ed_attr  -->  Anzeigeschicht kopiert
;   auf den Bildschirm. Der Aufrufer ruft ed_init (einmal), ed_load oder ed_lbegin/ed_ins/ed_lend (Text laden), danach pro
;   Taste ed_key; jede Taste endet in ed_view (Bildausschnitt nachfuehren, dann komplett neu zeichnen). Gezeichnet wird immer
;   das ganze Bild (ed_rows * 80 Byte Zeichen und Farben), es gibt keine Teilaktualisierung.
;
; DATENSTRUKTUREN
; * Textpuffer (Lueckenpuffer, "gap buffer") im Attic-RAM ab $0830_0000, ECAP = 768 KB gross. Der Text steht in zwei Teilen:
;   Puffer[0 .. gs) und Puffer[ge .. ECAP); dazwischen liegt die Luecke [gs, ge). gs ("gap start") ist zugleich die Stelle,
;   an der gerade eingefuegt wird, ge ("gap end") der erste Byte hinter der Luecke. Alle Zeiger gs/ge/cur/len sind 32-Bit-
;   Zahlen (4 Byte, little endian) und Offsets relativ zum Pufferanfang, nicht absolute Adressen. Eine logische Textposition p
;   (0 .. len) liegt physisch bei p (wenn p < gs) oder bei p + (ge - gs) (sonst); das rechnet ed_phys aus. Einfuegen und
;   Loeschen am Cursor sind dadurch O(1): ed_gapto schiebt die Luecke (Byte fuer Byte) zum Cursor, dann wird gs bzw. ge
;   verschoben. Bei leerem Text ist gs = 0, ge = ECAP, len = 0. Es gilt immer: len = ECAP - (ge - gs).
; * Zeilen gibt es nur implizit: Zeilentrenner ist LF ($0A). Eine Zeile beginnt bei Position 0 oder hinter einem LF und
;   endet vor dem naechsten LF oder am Textende. Es gibt keine Zeilentabelle und keinen Zeilenindex; Zeilenanfang/-ende werden
;   durch Suchen mit ed_ls/ed_le bestimmt. Mitgefuehrt werden nur die Zeilennummern ed_curline (Cursorzeile) und ed_topline
;   (oberste sichtbare Zeile), beide 1-basiert und 16 Bit, sowie die zugehoerigen Positionen ed_cur und ed_top.
; * Cursor: ed_cur (Position, 32 Bit). ed_want = "gewuenschte Spalte" fuer Auf/Ab ($FFFF = nicht gesetzt). ed_left = erste
;   sichtbare Textspalte (waagerechtes Rollen).
; * Auswahl: Anker ed_anc und Cursor spannen den Bereich auf, solange ed_sel <> 0; sel_range ordnet ihn zu ed_ss <= ed_se
;   (Ende ausgeschlossen).
; * Zwischenablage: Attic $0870_0000, ed_cblen Byte (hoechstens CBMAX = 64 KB); CP ist der Lese-/Schreibzeiger.
; * Verlauf (Rueckgaengig/Wiederholen): Attic $083C_0000 (hinter dem Text), hoechstens 4096 Eintraege zu je 16 Byte. Ein
;   Eintrag beschreibt genau ein eingefuegtes oder geloeschtes Byte:
;       +0 Art (1 = eingefuegt, 2 = geloescht)   +1 Byte   +2/+3 Gruppennummer   +4..+7 Stelle   +8..+11 Cursor vorher
;       +12..+15 Cursor nachher.
;   hp = Verlaufsstelle (naechster freier Eintrag = Zahl der zurueckzunehmenden Eintraege), hn = Ende der Wiederholen-
;   Eintraege (hp <= hn). Ein neuer Eintrag verwirft alles hinter hp (hn := hp). Eintraege mit gleicher Gruppennummer
;   (ed_grp) werden von Rueckgaengig/Wiederholen gemeinsam behandelt; ed_kind vergibt die Gruppen (siehe dort).
;   ed_logon = 0 schaltet das Mitschreiben ab (Laden, Anwenden des Verlaufs selbst).
; * Faerbung: ein kleiner Lexer (lx_*) liefert pro Zeichen eine Farbe; sein Zustand wird je Bildzeile von vorn aufgebaut
;   (lx_reset am Zeilenanfang), er kennt also keine zeilenuebergreifenden Zustaende.
; * Fehlerzeilen: ed_elo/ed_ehi (Zeilennummern, Low/High, hoechstens 16, Anzahl ed_en) werden von der IDE (ide_emark)
;   gefuellt und in COL_ERRL gezeichnet (nur mit ed_deco). ed_ehp haelt den Textstand (hp) der Uebersetzung; ed_clear leert die
; Liste.
; * Bildpuffer: ed_scr (Bildschirmcodes) und die Attributzeilen ab ed_abase (Farben) liegen ausserhalb dieser Datei (disp.asm).
;   Bildaufbau: [Kopfzeilen vom Aufrufer] [Textzeilen ed_trows] [Fusszeilen vom Aufrufer] [Statuszeile]. ed_rows ist 25 oder 50;
;   ed_layout legt die Aufteilung fest.
;
; ZEROPAGE (gemeinsam mit dem Assembler genutzt, beide laufen nie gleichzeitig)
;   E0 ($20) Arbeitsposition: Eingabe fast aller Hilfsroutinen (ed_get, ed_inc, ed_ls, ed_le ...); wird frei veraendert
;   E1 ($24) 32-Bit-Zeiger auf ein Byte im Attic (Ausgabe von ed_phys, gp_copy_src_gs, gp_ptr_ge); Zugriff per [E1],z
;   E2 ($28) Zeiger der Ladequelle (ed_load) und Zeiger auf einen Verlaufseintrag (hist_ptr)
;   E3 ($2c) laufende Position beim Zeichnen (dw_line); bleibt ueber das Zeichnen einer Zeile hinweg erhalten
;   ET ($30..$37) Hilfszellen: ET+2/3 = 16-Bit-Zeiger auf die aktuelle Zeichenzeile in ed_scr (Zugriff (ET+2),y), ET+4/5 =
;       Zahl fuer put_num4 bzw. Byte in ed_ins_raw, ET/ET+1 = Teiler, ET+7 = Quotient (dn_dig)
;   EG ($38..$3a) Lueckengroesse in ed_phys
;   EA ($3c..$3f) 32-Bit-Zeiger auf die Attributzeile der gerade gezeichneten Zeile (Zugriff [EA],z)
;   CP ($58..$5b) 32-Bit-Zeiger in die Zwischenablage
;
; 45GS02-EIGENHEITEN, DIE HIER STAENDIG VORKOMMEN
; * [zp],z = 32-Bit-Zeiger-indirekt mit Z-Register als Index; "ldz #$00" vorher nicht vergessen. (zp),y bleibt der normale
;   16-Bit-Zeiger (Bank 0, hier fuer den Bildpuffer). inz/dez zaehlen Z, phx/plx legen X auf den Stack.
; * Mehrbyte-Arithmetik laeuft nur ueber Carry-Ketten auf den 4-Byte-Zellen (clc/adc, sec/sbc, inc mit bne-Kette). Vergleiche
;   "A < B" sind eine cmp/sbc-Kette ohne Zwischenspeichern der Teilergebnisse: nach der Kette zeigt Carry das Ergebnis an.
; * Die Routinen sind nicht wiedereintrittsfaehig: E0..E3, ET, EA und die Zellen am Dateiende sind global.
;
; INVARIANTEN
; * 0 <= gs <= ge <= ECAP; ed_cur, ed_top, ed_anc, ed_ss, ed_se liegen in [0, len].
; * ed_curline = 1 + Zahl der LF vor ed_cur (ed_recount stellt das notfalls wieder her); ed_topline gilt entsprechend zu ed_top.
; * ed_top steht auf einem Zeilenanfang; die Cursorzeile liegt zwischen topline und topline + ed_trows - 1 (ed_scroll).
; * Der Verlauf enthaelt nur Aenderungen am Text, keine Bewegungen; nach ed_load/ed_lend ist er leer (hp = hn = 0).
;
; ABLAUF EINER TASTE: ed_key -> ed_kind (Gruppe) -> ggf. Auswahl aufheben -> Verteiler ek_go -> Bewegung/Aenderung ->
; ed_view (= ed_scroll + ed_draw). Aenderungen laufen ueber ed_ins/ed_bs/ed_del (mit Mitschrift), die ihrerseits die rohen
; Fassungen ed_ins_raw/ed_bs_raw/ed_del_raw (ohne Mitschrift) aufrufen.
; ---------------------------------------------------------------------------------------------------------------------
; ---- Konstanten und Zeropage-Zuordnung
E0      = $20                       ; 32-Bit-Register (Positionen, Zeiger)
E1      = $24
E2      = $28
E3      = $2c
ET      = $30                       ; Hilfszellen ($30-$37)
EG      = $38                       ; Hilfszellen von ed_phys ($38-$3a)
EA      = $3c                       ; 32-Bit-Zeiger auf die Attributzeile der Zeichenzeile ($3c-$3f)

; ---- Tastencodes (siehe Kopf; K_MARK..K_PASTE: Steuerzeichen fuer Auswahl und Zwischenablage, K_UNDO/K_REDO fuer den Verlauf)
K_RET   = $0d
K_TAB   = $09
K_BS    = $14
K_DEL   = $c3
K_UP    = $91
K_DOWN  = $11
K_LEFT  = $9d
K_RIGHT = $1d
K_HOME  = $13
K_END   = $c0
K_PGUP  = $c1
K_PGDN  = $c2
K_MARK  = $02                       ; Auswahl beginnen/aufheben (Anker = Cursor)
K_COPY  = $03
K_CUT   = $18
K_PASTE = $16
SELF    = $20                       ; Attributbit "Auswahl" (Umkehrdarstellung im Attributmodus, in Xemu geprueft), wird zur Farbe addiert
CBMAX   = $10000                    ; groesste Zwischenablage
CP      = $58                       ; Zeiger in die Zwischenablage (Attic $0834_0000)
K_UNDO  = $1a
K_REDO  = $19
; Verlaufsspeicher: Byte 2/3 der 32-Bit-Attic-Adresse (HB2/HB3): Bank $08, Offset $3C0000 = hinter dem 768-KB-Textpuffer.
HB2     = $3c                       ; Verlauf im Attic: $083C_0000 (hinter dem Text), je Eintrag 16 Byte, hoechstens 4096
HB3     = $08

; ---- Farbcodes (C64-Palette; die tatsaechlichen RGB-Werte stammen vom Farbschema der Anzeigeschicht)
COL_TEXT = 1                        ; Farben (C64-Palette)
COL_GUTTER = 11
COL_COMMENT = 12
COL_STRING = 5
COL_NUM = 7
COL_DIR = 3
COL_LABEL = 14
COL_MNEM = 13
COL_CURNUM = 7                      ; Nummer der Cursorzeile (nur mit ed_deco)
COL_ERRL = 2                        ; Text einer Fehlerzeile (nur mit ed_deco, siehe ed_en)
COL_STAT = 12                       ; Statuszeile umgekehrt (nur mit ed_deco)

; ---- Puffergroessen und Bildschirmgeometrie
EB2     = $30                       ; Textpuffer im Attic: $0830_0000 (768 KB Text, dahinter 64 KB Verlauf)
EB3     = $08
ECAP    = $0c0000                   ; 768 KB Text (die MEGA65-Beispiele haben bis 224 KB)
; GUTTER = Randspalten vor dem Text (4 Ziffern + 1 Strich/Leerzeichen); SCRW = Zeichen je Bildzeile; Textbreite = SCRW - GUTTER.
GUTTER  = 5                         ; Zeilennummer (4 Stellen) und Leerzeichen
SCRW    = 80

; =====================================================================================================================
; INITIALISIERUNG UND LADEN
; =====================================================================================================================
; ed_init: Eingabe A = Zeilenzahl des Bildes (25 oder 50). Setzt ed_rows, die Standardaufteilung und einen leeren Text.
; Veraendert A, X (und was ed_layout/ed_clear veraendern).
; ---- ed_init: A = Zeilenzahl des Bildes (25 oder 50). Leerer Text.
ed_init:
        sta ed_rows
        lda #$00                    ; Standardaufteilung: keine Kopf- und Fussbereiche (siehe ed_layout)
        ldx #$00
        jsr ed_layout
        jmp ed_clear
; ed_layout: A = Zahl der Kopfzeilen (oben, vom Aufrufer gezeichnet), X = Zahl der Fusszeilen (ueber der Statuszeile, vom
; Aufrufer gezeichnet). Textzeilen ed_trows = ed_rows - 1 - Kopf - Fuss. Der Kern zeichnet nur die Textzeilen und die Statuszeile.
ed_layout:
        sta ed_hdr
        stx ed_ftr
        lda ed_rows
        sec
        sbc #$01
        sbc ed_hdr
        sbc ed_ftr
        sta ed_trows
        rts

; ed_clear: Text, Verlauf, Auswahl und Ansicht zuruecksetzen (Zeilenzahl, Zwischenablage und Suchmuster bleiben)
; Setzt alle Zellen auf "leerer Text": gs = 0, ge = ECAP (die Luecke ist der ganze Puffer), len = 0, Zeilen 1, kein Verlauf,
; Mitschrift an, ed_want = $FFFF (keine gewuenschte Spalte). Keine Eingabe; veraendert A.
ed_clear:
        lda #$00
        sta ed_en                   ; Fehlerzeilen des alten Textes vergessen
        sta hp
        sta hp + 1
        sta hn
        sta hn + 1
        sta ed_grp
        sta ed_grp + 1
        sta ed_lastkind
        sta ed_sel
        lda #$01
        sta ed_logon
        lda #$00
        sta ed_gs
        sta ed_gs + 1
        sta ed_gs + 2
        sta ed_gs + 3
        sta ed_cur
        sta ed_cur + 1
        sta ed_cur + 2
        sta ed_cur + 3
        sta ed_top
        sta ed_top + 1
        sta ed_top + 2
        sta ed_top + 3
        sta ed_left
        sta ed_left + 1
        sta ed_len
        sta ed_len + 1
        sta ed_len + 2
        sta ed_len + 3
        lda #<ECAP
        sta ed_ge
        lda #>ECAP
        sta ed_ge + 1
        lda #<(ECAP >> 16)
        sta ed_ge + 2
        lda #$00
        sta ed_ge + 3
        lda #$01
        sta ed_curline
        sta ed_topline
        lda #$00
        sta ed_curline + 1
        sta ed_topline + 1
        lda #$ff
        sta ed_want
        sta ed_want + 1
        rts

; ed_load: Eingabe ed_src (16-Bit-Adresse in Bank 0) und ed_cnt (Byte). Ausgabe: Text geladen, Cursor am Anfang, Bild gezeichnet.
; Die Bytes werden einzeln ueber ed_ins geladen (Mitschrift vorher abgeschaltet), daher entsteht kein Verlauf. Der Quelltext
; muss ASCII mit LF sein; das Byte 0 darf nicht vorkommen (siehe Kopf). Der Text wird an die Cursorposition angefuegt; ed_clear
; sollte vorher gelaufen sein.
; ed_load: ed_src (Adresse im Hauptspeicher) und ed_cnt Byte als Text laden; Cursor an den Anfang
; ed_lbegin / ed_lend: Text byteweise laden (jedes Byte mit A=Byte, jsr ed_ins, dazwischen nichts mitschreiben)
; ed_lbegin: schaltet die Mitschrift ab (fuer byteweises Laden durch den Aufrufer); ed_lend (= el_fin) schliesst das Laden ab.
ed_lbegin:
        lda #$00
        sta ed_logon
        rts
ed_lend = el_fin
        ; Schleife je Byte: [E2],z lesen -> ed_ins. E2 ist ein 32-Bit-Zeiger in Bank 0 (Byte 2/3 = 0), daher [E2],z statt (E2),y.
ed_load:
        lda ed_src
        sta E2
        lda ed_src + 1
        sta E2 + 1
        lda #$00
        sta E2 + 2
        sta E2 + 3
        lda #$00
        sta ed_logon
el_lp:  lda ed_cnt
        ora ed_cnt + 1
        beq el_fin
        ldz #$00
        lda [E2],z
        jsr ed_ins
        inc E2
        bne el_n1
        inc E2 + 1
el_n1:  lda ed_cnt
        bne el_n2
        dec ed_cnt + 1
el_n2:  dec ed_cnt
        jmp el_lp
; el_fin / ed_lend: Abschluss des Ladens. Auswahl und Verlauf leeren, Mitschrift wieder an, Cursor und Ansicht an den Anfang
; (Zeile 1), ed_want zuruecksetzen und neu zeichnen. Der Textpuffer selbst bleibt unveraendert.
el_fin: lda #$00
        sta ed_sel
        lda #$01
        sta ed_logon
        lda #$00
        sta hp
        sta hp + 1
        sta hn
        sta hn + 1
        sta ed_cur
        sta ed_cur + 1
        sta ed_cur + 2
        sta ed_cur + 3
        sta ed_top
        sta ed_top + 1
        sta ed_top + 2
        sta ed_top + 3
        sta ed_left
        sta ed_left + 1
        lda #$01
        sta ed_curline
        sta ed_topline
        lda #$00
        sta ed_curline + 1
        sta ed_topline + 1
        lda #$ff
        sta ed_want
        sta ed_want + 1
        jmp ed_view

; =====================================================================================================================
; ZUGRIFF AUF DEN PUFFER (Lueckenpuffer)
; =====================================================================================================================
; ---- Zugriff auf den Puffer
; ed_phys: E0 = Textposition -> E1 = Zeiger auf das Byte im Lueckenpuffer
; Eingabe E0 = logische Position. Ausgabe E1 = 32-Bit-Attic-Adresse des Bytes: Position (+ Luecke, falls Position >= gs) +
; Pufferanfang. E0 bleibt unveraendert. Veraendert A und EG. Positionen hinter dem Textende werden nicht geprueft (ed_get tut
; das).
ed_phys:
        lda E0
        sta E1
        lda E0 + 1
        sta E1 + 1
        lda E0 + 2
        sta E1 + 2
        lda E0 + 3
        sta E1 + 3
        ; Vergleich E0 < gs (hoechstes Byte zuerst); ist E0 nicht kleiner, muss die Lueckengroesse addiert werden.
        ; Position < gs ? sonst + (ge - gs)
        lda E0 + 3
        cmp ed_gs + 3
        bcc ep_ok
        bne ep_add
        lda E0 + 2
        cmp ed_gs + 2
        bcc ep_ok
        bne ep_add
        lda E0 + 1
        cmp ed_gs + 1
        bcc ep_ok
        bne ep_add
        lda E0
        cmp ed_gs
        bcc ep_ok
        ; Die Lueckengroesse ge - gs passt in 3 Byte (Puffer < 16 MB); das vierte Byte von E1 erhaelt nur den Uebertrag.
ep_add: sec                         ; + Lueckengroesse (ge - gs)
        lda ed_ge
        sbc ed_gs
        sta EG
        lda ed_ge + 1
        sbc ed_gs + 1
        sta EG + 1
        lda ed_ge + 2
        sbc ed_gs + 2
        sta EG + 2
        clc
        lda E1
        adc EG
        sta E1
        lda E1 + 1
        adc EG + 1
        sta E1 + 1
        lda E1 + 2
        adc EG + 2
        sta E1 + 2
        lda E1 + 3
        adc #$00
        sta E1 + 3
        ; Pufferanfang (Attic-Bank, ed_bb2/ed_bb3) auf Byte 2/3 addieren; Byte 0/1 sind schon der Offset.
ep_ok:  clc                         ; + Pufferanfang $0830_0000
        lda E1 + 2
        adc ed_bb2
        sta E1 + 2
        lda E1 + 3
        adc ed_bb3
        sta E1 + 3
        rts

; ed_get: Eingabe E0 = Position. Ausgabe A = Byte; ab dem Textende (E0 >= len) wird 0 geliefert (das Byte 0 kommt im Text sonst
; nie vor und dient daher als Endemarke). E0 bleibt erhalten; veraendert A, Z und E1. Die Flags sind nicht definiert.
; ed_get: E0 = Position -> A = Byte (0 ab dem Textende), E0 unveraendert
        ; E0 - len mit durchlaufender cmp/sbc-Kette: Carry gesetzt = E0 >= len.
ed_get: lda E0
        cmp ed_len
        lda E0 + 1
        sbc ed_len + 1
        lda E0 + 2
        sbc ed_len + 2
        lda E0 + 3
        sbc ed_len + 3
        bcs eg_end
        jsr ed_phys
        ldz #$00
        lda [E1],z
        rts
eg_end: lda #$00
        rts

; ed_inc / ed_dec: E0 um 1 erhoehen bzw. verringern (32 Bit). ed_dec prueft nicht auf 0 (der Aufrufer muss E0 > 0 sichern).
; Veraendert nur A (ed_dec) und die Flags.
; ed_inc / ed_dec: E0 um 1
ed_inc: inc E0
        bne ez_ei1
        inc E0 + 1
        bne ez_ei1
        inc E0 + 2
        bne ez_ei1
        inc E0 + 3
ez_ei1:    rts
ed_dec: lda E0
        bne ed1
        lda E0 + 1
        bne ed2
        lda E0 + 2
        bne ed3
        dec E0 + 3
ed3:    dec E0 + 2
ed2:    dec E0 + 1
ed1:    dec E0
        rts

; ed_eq_len: Ausgabe Z gesetzt, wenn E0 = len (Position steht am Textende). Veraendert A.
; ed_eq_len: Z gesetzt, wenn E0 = Textlaenge
ed_eq_len:
        lda E0
        cmp ed_len
        bne ee1
        lda E0 + 1
        cmp ed_len + 1
        bne ee1
        lda E0 + 2
        cmp ed_len + 2
        bne ee1
        lda E0 + 3
        cmp ed_len + 3
ee1:    rts

; ed_ls: Eingabe E0 = Position. Ausgabe E0 = Anfang der Zeile (Position hinter dem letzten LF davor, oder 0). Geht Byte fuer
; Byte rueckwaerts, also O(Zeilenlaenge). Veraendert A (und E1, Z ueber ed_get).
; ed_ls: E0 = Position -> E0 = Anfang der Zeile
ed_ls:  lda E0
        ora E0 + 1
        ora E0 + 2
        ora E0 + 3
        beq el_d
        jsr ed_dec
        jsr ed_get
        cmp #$0a
        beq ez_el_nl
        jmp ed_ls
ez_el_nl:  jsr ed_inc
el_d:   rts

; ed_le: Eingabe E0 = Position. Ausgabe E0 = Zeilenende: die Stelle des LF oder len. Geht vorwaerts; O(Zeilenlaenge).
; ed_le: E0 = Position -> E0 = Ende der Zeile (Stelle des LF oder Textende)
ed_le:  jsr ed_eq_len
        beq ez_le_d
        jsr ed_get
        cmp #$0a
        beq ez_le_d
        jsr ed_inc
        jmp ed_le
ez_le_d:   rts

; =====================================================================================================================
; LUECKE VERSCHIEBEN
; =====================================================================================================================
; ed_gapto: Eingabe E0 = Zielposition (0 .. len). Ausgabe: gs = E0, die Luecke steht an der Zielposition (ge - gs bleibt gleich).
; Das Verschieben geschieht Byte fuer Byte ueber das Attic und ist bei weiten Spruengen langsam; der Cursor sollte also moeglichst
; lokal bleiben. Veraendert A, E1, Z.
; Zwei Schleifen: gp_dn schiebt die Luecke nach links (Byte vor der Luecke hinter sie kopieren), gp_up nach rechts (Byte hinter
; der
; Luecke vor sie kopieren). Hoechstens eine der beiden tut etwas; bei gs = E0 geschieht nichts.
; ---- Luecke an die Position E0 verschieben
ed_gapto:
        ; solange gs > pos: gs--, ge--, buf[ge] = buf[gs]   (die Bytes werden von hinten nach vorn ueber die Luecke gereicht)
        ; solange gs > pos: gs--, ge--, buf[ge] = buf[gs]
gp_dn:  lda ed_gs + 3
        cmp E0 + 3
        bcc gp_up
        bne gp_mv1
        lda ed_gs + 2
        cmp E0 + 2
        bcc gp_up
        bne gp_mv1
        lda ed_gs + 1
        cmp E0 + 1
        bcc gp_up
        bne gp_mv1
        lda ed_gs
        cmp E0
        bcc gp_up
        beq gp_up
        ; Erst gs und ge verringern, dann das Byte kopieren: nach dem Dekrement ist Puffer[gs] das zu verschiebende Byte und
        ; Puffer[ge] sein neuer Platz (die Quelle liegt vor dem Ziel und wird erst spaeter von der Luecke ueberdeckt).
gp_mv1: lda ed_gs                   ; gs--
        bne gd1
        lda ed_gs + 1
        bne gd2
        lda ed_gs + 2
        bne gd3
        dec ed_gs + 3
gd3:    dec ed_gs + 2
gd2:    dec ed_gs + 1
gd1:    dec ed_gs
        lda ed_ge                   ; ge--
        bne gd4
        lda ed_ge + 1
        bne gd5
        lda ed_ge + 2
        bne gd6
        dec ed_ge + 3
gd6:    dec ed_ge + 2
gd5:    dec ed_ge + 1
gd4:    dec ed_ge
        ; Das Byte wird mit pha zwischengespeichert, weil E1 nacheinander fuer Quelle und Ziel dient.
        jsr gp_copy_src_gs          ; Quelle: Puffer[gs]
        ldz #$00
        lda [E1],z
        pha
        jsr gp_ptr_ge               ; Ziel: Puffer[ge]
        pla
        ldz #$00
        sta [E1],z
        jmp gp_dn
        ; (Gegenstueck zu gp_dn)
gp_up:  ; solange gs < pos: buf[gs] = buf[ge]; gs++, ge++
        lda E0 + 3
        cmp ed_gs + 3
        bcc gp_done
        bne gp_mv2
        lda E0 + 2
        cmp ed_gs + 2
        bcc gp_done
        bne gp_mv2
        lda E0 + 1
        cmp ed_gs + 1
        bcc gp_done
        bne gp_mv2
        lda E0
        cmp ed_gs
        bcc gp_done
        beq gp_done
        ; Byte Puffer[ge] nach Puffer[gs] kopieren, danach gs++ und ge++ (die Luecke wandert nach rechts).
gp_mv2: jsr gp_ptr_ge
        ldz #$00
        lda [E1],z
        pha
        jsr gp_copy_src_gs
        pla
        ldz #$00
        sta [E1],z
        inc ed_gs
        bne gu1
        inc ed_gs + 1
        bne gu1
        inc ed_gs + 2
        bne gu1
        inc ed_gs + 3
gu1:    inc ed_ge
        bne gu2
        inc ed_ge + 1
        bne gu2
        inc ed_ge + 2
        bne gu2
        inc ed_ge + 3
gu2:    jmp gp_up
gp_done:
        rts

; gp_copy_src_gs: Ausgabe E1 = Attic-Adresse von Puffer[gs] (gs + Pufferanfang). Veraendert A. gs ist ein Puffer-Offset, noch kein
; Textindex. Wird auch zum Einfuegen genutzt: das neue Byte kommt genau auf Puffer[gs].
gp_copy_src_gs:                     ; E1 = Zeiger auf Puffer[gs]
        clc
        lda ed_gs
        sta E1
        lda ed_gs + 1
        sta E1 + 1
        lda ed_gs + 2
        adc ed_bb2
        sta E1 + 2
        lda ed_gs + 3
        adc ed_bb3
        sta E1 + 3
        rts
; gp_ptr_ge: Ausgabe E1 = Attic-Adresse von Puffer[ge]. Veraendert A.
gp_ptr_ge:                          ; E1 = Zeiger auf Puffer[ge]
        clc
        lda ed_ge
        sta E1
        lda ed_ge + 1
        sta E1 + 1
        lda ed_ge + 2
        adc ed_bb2
        sta E1 + 2
        lda ed_ge + 3
        adc ed_bb3
        sta E1 + 3
        rts

; =====================================================================================================================
; EINFUEGEN UND LOESCHEN (ROH, OHNE VERLAUF)
; =====================================================================================================================
; ---- Einfuegen und Loeschen an der Cursorposition (rohe Operationen; die mitschreibenden Fassungen stehen im Verlauf)
; ed_ins_raw: Eingabe A = einzufuegendes Byte. Fuegt es am Cursor ein (Luecke zum Cursor, Byte auf Puffer[gs], gs++, len++, cur++;
; bei LF auch ed_curline++). Der Cursor steht danach hinter dem neuen Byte. Es wird kein Verlauf geschrieben und nicht auf
; Pufferueberlauf geprueft (nur ed_paste prueft die Kapazitaet). Veraendert A, X, E0, E1, Z.
ed_ins_raw:
        ; Das Byte sichern: ed_gapto/gp_copy_src_gs zerstoeren A.
        sta ET + 4
        ldx #$03
        ; Cursor nach E0 kopieren (4 Byte), dann die Luecke dorthin schieben.
ei_c:   lda ed_cur,x
        sta E0,x
        dex
        bpl ei_c
        jsr ed_gapto
        jsr gp_copy_src_gs
        lda ET + 4
        ldz #$00
        sta [E1],z
        inc ed_gs
        bne ei_1
        inc ed_gs + 1
        bne ei_1
        inc ed_gs + 2
        bne ei_1
        inc ed_gs + 3
ei_1:   inc ed_len
        bne ei_2
        inc ed_len + 1
        bne ei_2
        inc ed_len + 2
        bne ei_2
        inc ed_len + 3
ei_2:   inc ed_cur
        bne ei_3
        inc ed_cur + 1
        bne ei_3
        inc ed_cur + 2
        bne ei_3
        inc ed_cur + 3
ei_3:   lda ET + 4
        cmp #$0a
        bne ei_4
        inc ed_curline
        bne ei_4
        inc ed_curline + 1
ei_4:   rts

; ed_bs_raw: Zeichen vor dem Cursor loeschen (Rueckschritt). Am Textanfang geschieht nichts. Die Luecke wird an den Cursor gelegt,
; dann gs--, len--, cur--; war das geloeschte Byte ein LF, wird ed_curline verringert (die Zeilen verschmelzen).
; Veraendert A, X, E0, E1, Z.
ed_bs_raw:
        lda ed_cur
        ora ed_cur + 1
        ora ed_cur + 2
        ora ed_cur + 3
        beq eb_ret
        ldx #$03
eb_c:   lda ed_cur,x
        sta E0,x
        dex
        bpl eb_c
        jsr ed_gapto                ; Luecke an den Cursor; dann gs--
        jsr ed_dec
        jsr ed_get                  ; geloeschtes Byte (LF: Zeilennummer)
        pha
        lda ed_gs
        bne ez_eb1
        lda ed_gs + 1
        bne ez_eb2
        lda ed_gs + 2
        bne eb3
        dec ed_gs + 3
eb3:    dec ed_gs + 2
ez_eb2:    dec ed_gs + 1
ez_eb1:    dec ed_gs
        jsr ed_dec_len
        lda ed_cur                  ; cur--
        bne ez_ec1
        lda ed_cur + 1
        bne ec2
        lda ed_cur + 2
        bne ec3
        dec ed_cur + 3
ec3:    dec ed_cur + 2
ec2:    dec ed_cur + 1
ez_ec1:    dec ed_cur
        pla
        cmp #$0a
        bne eb_ret
        lda ed_curline
        bne ez_el1
        dec ed_curline + 1
ez_el1:    dec ed_curline
eb_ret: rts

; ed_del_raw: Zeichen am Cursor loeschen (Entf). Am Textende geschieht nichts. Nach ed_gapto beginnt hinter der Luecke das Byte am
; Cursor; es wird "verschluckt", indem ge++ die Luecke nach rechts verlaengert; cur und curline bleiben. Veraendert A, X, E0,
; E1, Z.
ed_del_raw:
        ldx #$03
edl_c:  lda ed_cur,x
        sta E0,x
        dex
        bpl edl_c
        jsr ed_eq_len
        beq edl_r
        jsr ed_gapto
        jsr ed_get                  ; (nach der Verschiebung steht das Byte hinter der Luecke)
        inc ed_ge
        bne edl_1
        inc ed_ge + 1
        bne edl_1
        inc ed_ge + 2
        bne edl_1
        inc ed_ge + 3
edl_1:  jsr ed_dec_len
edl_r:  rts

; ed_dec_len: len um 1 verringern (32 Bit). Veraendert A.
ed_dec_len:
        lda ed_len
        bne dl1
        lda ed_len + 1
        bne dl2
        lda ed_len + 2
        bne dl3
        dec ed_len + 3
dl3:    dec ed_len + 2
dl2:    dec ed_len + 1
dl1:    dec ed_len
        rts

; =====================================================================================================================
; VERLAUF (RUECKGAENGIG / WIEDERHOLEN)
; =====================================================================================================================
; ---- Verlauf (Rueckgaengig/Wiederholen): Eintraege Einfuegen/Loeschen eines Bytes, zu Gruppen zusammengefasst
; Eintrag: Art (1 einfuegen, 2 loeschen), Byte, Gruppe (2), Stelle (4), Cursor vorher (4), Cursor nachher (4)
; ed_ins (mit Verlauf): Eingabe A = Byte. Merkt den Cursor vorher (h_cb), fuegt roh ein und schreibt (bei ed_logon <> 0) einen
; Eintrag Art 1 mit Cursor vorher/nachher. Die Gruppennummer ed_grp muss vorher durch ed_kind gesetzt sein. Veraendert A, X,
; E0, E1,
; Z und h_*. Die Hilfsroutinen setzen die Eintragsfelder h_type/h_byte/h_pos/h_cb/h_ca und rufen hist_add.
ed_ins: sta h_byte
        ldx #$03
hi_c:   lda ed_cur,x
        sta h_cb,x
        dex
        bpl hi_c
        lda h_byte
        jsr ed_ins_raw
        lda ed_logon
        beq hi_r
        lda #$01
        sta h_type
        ldx #$03
hi_p:   lda h_cb,x
        sta h_pos,x
        lda ed_cur,x
        sta h_ca,x
        dex
        bpl hi_p
        jsr hist_add
hi_r:   rts

; ed_bs (mit Verlauf): wie ed_bs_raw, schreibt aber Art 2 (geloescht) mit dem geloeschten Byte (h_byte). Die Stelle des
; Eintrags ist
; die Position des geloeschten Bytes (= Cursor nach dem Loeschen); Cursor vorher = Position dahinter.
ed_bs:  lda ed_cur
        ora ed_cur + 1
        ora ed_cur + 2
        ora ed_cur + 3
        beq hb_r
        ldx #$03
hb_c:   lda ed_cur,x
        sta h_cb,x
        sta E0,x
        dex
        bpl hb_c
        jsr ed_dec
        jsr ed_get
        sta h_byte
        jsr ed_bs_raw
        lda ed_logon
        beq hb_r
        lda #$02
        sta h_type
        ldx #$03
hb_p:   lda ed_cur,x
        sta h_pos,x
        sta h_ca,x
        dex
        bpl hb_p
        jsr hist_add
hb_r:   rts

; ed_del (mit Verlauf): wie ed_del_raw, Art 2. Stelle = Cursor, Cursor vorher = nachher = Stelle (Entf bewegt den Cursor nicht).
ed_del: ldx #$03
hd_c:   lda ed_cur,x
        sta E0,x
        dex
        bpl hd_c
        jsr ed_eq_len
        beq hd_r
        jsr ed_get
        sta h_byte
        ldx #$03
hd_q:   lda ed_cur,x
        sta h_cb,x
        sta h_pos,x
        sta h_ca,x
        dex
        bpl hd_q
        jsr ed_del_raw
        lda ed_logon
        beq hd_r
        lda #$02
        sta h_type
        jsr hist_add
hd_r:   rts

; hist_ptr: Eingabe h_idx (16 Bit, Eintragsnummer 0..4095). Ausgabe E2 = 32-Bit-Attic-Adresse des Eintrags = Verlaufsbasis +
; h_idx * 16.
; Die Shift-Folgen rechnen das Produkt (h_idx << 4) aus; die oberen vier Bit gehen in das Bankbyte (E2+2). Veraendert A.
; hist_ptr: h_idx (16 Bit) -> E2 = Zeiger auf den Eintrag
hist_ptr:
        lda h_idx
        asl
        asl
        asl
        asl
        sta E2
        lda h_idx
        lsr
        lsr
        lsr
        lsr
        sta E2 + 1
        lda h_idx + 1
        asl
        asl
        asl
        asl
        ora E2 + 1
        sta E2 + 1
        lda h_idx + 1
        lsr
        lsr
        lsr
        lsr
        clc
        adc ed_hb2
        sta E2 + 2
        lda ed_hb3
        sta E2 + 3
        rts

; hist_add: legt einen Eintrag aus h_type/h_byte/h_pos/h_cb/h_ca und ed_grp an der Stelle hp ab, hp++, hn := hp (alle
; Wiederholen-Eintraege verfallen). Bei vollem Verlauf (hp >= 4096 = $1000) wird von vorn begonnen: der aeltere Verlauf wird
; verworfen (hp = hn = 0). Veraendert A, X, Z, E2.
; hist_add: neuer Eintrag an der Verlaufsstelle hp (spaetere Eintraege entfallen)
hist_add:
        lda hp + 1                  ; Verlauf voll (4096 Eintraege): von vorn beginnen (Rueckgaengig reicht dann nicht weiter zurueck)
        cmp #$10
        bcc ha_ok
        lda #$00
        sta hp
        sta hp + 1
        sta hn
        sta hn + 1
ha_ok:  lda hp
        sta h_idx
        lda hp + 1
        sta h_idx + 1
        jsr hist_ptr
        ; Eintrag schreiben: Art, Byte, Gruppe (2 Byte), dann Stelle, Cursor vorher, Cursor nachher (je 4 Byte, Z laeuft mit).
        ldz #$00
        lda h_type
        sta [E2],z
        inz
        lda h_byte
        sta [E2],z
        inz
        lda ed_grp
        sta [E2],z
        inz
        lda ed_grp + 1
        sta [E2],z
        inz
        ldx #$00
ha_p:   lda h_pos,x
        sta [E2],z
        inz
        inx
        cpx #$04
        bne ha_p
        ldx #$00
ha_b:   lda h_cb,x
        sta [E2],z
        inz
        inx
        cpx #$04
        bne ha_b
        ldx #$00
ha_a:   lda h_ca,x
        sta [E2],z
        inz
        inx
        cpx #$04
        bne ha_a
        inc hp
        bne ha_n
        inc hp + 1
ha_n:   lda hp
        sta hn
        lda hp + 1
        sta hn + 1
        rts

; hist_load: Gegenstueck zu hist_add. Eingabe h_idx. Ausgabe h_type, h_byte, h_g (Gruppe), h_pos, h_cb, h_ca. Veraendert A, X,
; Z, E2.
; hist_load: Eintrag h_idx -> h_type, h_byte, h_g, h_pos, h_cb, h_ca
hist_load:
        jsr hist_ptr
        ldz #$00
        lda [E2],z
        sta h_type
        inz
        lda [E2],z
        sta h_byte
        inz
        lda [E2],z
        sta h_g
        inz
        lda [E2],z
        sta h_g + 1
        inz
        ldx #$00
hl_p:   lda [E2],z
        sta h_pos,x
        inz
        inx
        cpx #$04
        bne hl_p
        ldx #$00
hl_b:   lda [E2],z
        sta h_cb,x
        inz
        inx
        cpx #$04
        bne hl_b
        ldx #$00
hl_a:   lda [E2],z
        sta h_ca,x
        inz
        inx
        cpx #$04
        bne hl_a
        rts

; hist_apply: wendet den soeben geladenen Eintrag an. Eingabe h_rev = 0 vorwaerts, <> 0 rueckwaerts (aus ed_undo/ed_redo).
; Der Cursor wird auf die Stelle (h_pos) gesetzt, die Mitschrift abgeschaltet; dann gilt
;   Art 1 (Einfuegen): vorwaerts = einfuegen, rueckwaerts = loeschen (an h_pos, per Entf)
;   Art 2 (Loeschen):  vorwaerts = loeschen, rueckwaerts = wieder einfuegen
; ed_curline wird dabei nicht richtig mitgefuehrt (ed_recount am Ende von Undo/Redo). Veraendert A, X, E0, E1, Z.
; Eintrag anwenden: umgekehrt (rev <> 0) oder vorwaerts. Cursor auf die Stelle, Aenderung ohne Mitschrift.
hist_apply:
        ldx #$03
hp_c:   lda h_pos,x
        sta ed_cur,x
        dex
        bpl hp_c
        lda #$00
        sta ed_logon
        lda h_type                  ; Einfuegen rueckwaerts = Loeschen, Loeschen rueckwaerts = Einfuegen
        cmp #$01
        bne hp_t2
        lda h_rev
        bne hp_del
        beq hp_ins
hp_t2:  lda h_rev
        bne hp_ins
hp_del: jsr ed_del_raw
        jmp hp_x
hp_ins: lda h_byte
        jsr ed_ins_raw
hp_x:   lda #$01
        sta ed_logon
        rts

; ed_undo: nimmt die letzte Gruppe zurueck: ab Eintrag hp-1 rueckwaerts alle Eintraege gleicher Gruppennummer anwenden und hp je
; Eintrag verringern (die Eintraege bleiben als Wiederholen-Eintraege zwischen hp und hn erhalten). Der Cursor kommt auf "Cursor
; vorher" des zuletzt (also zeitlich ersten) zurueckgenommenen Eintrags (h_last). Zuletzt ed_recount, da curline nicht mitlaeuft.
; Leerer Verlauf (hp = 0): nichts. Veraendert alle Register und viele Zellen.
ed_undo:
        lda hp
        ora hp + 1
        beq hu_r
        lda #$01
        sta h_rev
        ; Gruppe des letzten Eintrags merken (h_grp); die Schleife laeuft, solange die Gruppe gleich bleibt.
        lda hp                      ; Gruppe des letzten Eintrags
        sec
        sbc #$01
        sta h_idx
        lda hp + 1
        sbc #$00
        sta h_idx + 1
        jsr hist_load
        lda h_g
        sta h_grp
        lda h_g + 1
        sta h_grp + 1
hu_l:   lda hp
        ora hp + 1
        beq hu_d
        lda hp
        sec
        sbc #$01
        sta h_idx
        lda hp + 1
        sbc #$00
        sta h_idx + 1
        jsr hist_load
        lda h_g
        cmp h_grp
        bne hu_d
        lda h_g + 1
        cmp h_grp + 1
        bne hu_d
        jsr hist_apply
        ldx #$03
hu_s:   lda h_cb,x
        sta h_last,x
        dex
        bpl hu_s
        lda hp
        bne hu_1
        dec hp + 1
hu_1:   dec hp
        jmp hu_l
        ; Cursor auf den Zustand vor der zeitlich ersten Aenderung der Gruppe setzen und die Zeilennummer neu bestimmen.
hu_d:   ldx #$03
hu_c:   lda h_last,x
        sta ed_cur,x
        dex
        bpl hu_c
        jmp ed_recount
hu_r:   rts

; ed_redo: wiederholt die naechste Gruppe: ab Eintrag hp vorwaerts alle Eintraege der Gruppe anwenden, hp++ je Eintrag. Cursor =
; "Cursor nachher" des letzten angewendeten Eintrags. Ist hp = hn, gibt es nichts zu wiederholen (Ausstieg ueber hu_r, das
; gemeinsame RTS am Ende von ed_undo).
ed_redo:
        lda hp
        cmp hn
        bne hr_go
        lda hp + 1
        cmp hn + 1
        beq hu_r
hr_go:  lda #$00
        sta h_rev
        lda hp
        sta h_idx
        lda hp + 1
        sta h_idx + 1
        jsr hist_load
        lda h_g
        sta h_grp
        lda h_g + 1
        sta h_grp + 1
hr_l:   lda hp
        cmp hn
        bne hr_c
        lda hp + 1
        cmp hn + 1
        beq hr_d
hr_c:   lda hp
        sta h_idx
        lda hp + 1
        sta h_idx + 1
        jsr hist_load
        lda h_g
        cmp h_grp
        bne hr_d
        lda h_g + 1
        cmp h_grp + 1
        bne hr_d
        jsr hist_apply
        ldx #$03
hr_s:   lda h_ca,x
        sta h_last,x
        dex
        bpl hr_s
        inc hp
        bne hr_l
        inc hp + 1
        jmp hr_l
hr_d:   jmp hu_d

; ed_recount: stellt ed_curline neu her: 1 + Zahl der LF in [0, cur). O(Textlaenge), daher nur nach Undo/Redo, Auswahl-Loeschen
; und Suchen/Springen, wo curline nicht mitgefuehrt werden kann. Veraendert A, E0, E1, Z.
; ed_recount: ed_curline = 1 + Zeilenvorschuebe vor dem Cursor
ed_recount:
        lda #$01
        sta ed_curline
        lda #$00
        sta ed_curline + 1
        sta E0
        sta E0 + 1
        sta E0 + 2
        sta E0 + 3
rc_l:   lda E0
        cmp ed_cur
        bne rc_g
        lda E0 + 1
        cmp ed_cur + 1
        bne rc_g
        lda E0 + 2
        cmp ed_cur + 2
        bne rc_g
        lda E0 + 3
        cmp ed_cur + 3
        beq rc_d
rc_g:   jsr ed_get
        cmp #$0a
        bne rc_n
        inc ed_curline
        bne rc_n
        inc ed_curline + 1
rc_n:   jsr ed_inc
        jmp rc_l
rc_d:   rts

; =====================================================================================================================
; BEWEGEN
; =====================================================================================================================
; ---- Bewegen
; ed_calc_col: Ausgabe E0 = Anfang der Cursorzeile, ed_colv = Spalte (cur - Zeilenanfang, 16 Bit, 0-basiert). Veraendert A, X, E0,
; E1, Z. (Der Vorspann "ed_col" oben ist der alte Name der Routine.)
; ed_col: -> E0 = Zeilenanfang, A/X (ed_colv) = Spalte (cur - Zeilenanfang, 16 Bit)
ed_calc_col:
        ldx #$03
cc1:    lda ed_cur,x
        sta E0,x
        dex
        bpl cc1
        jsr ed_ls
        sec
        lda ed_cur
        sbc E0
        sta ed_colv
        lda ed_cur + 1
        sbc E0 + 1
        sta ed_colv + 1
        rts

; ed_left_k: Cursor ein Zeichen zurueck; ueber ein LF hinweg wird curline verringert. Am Textanfang geschieht nichts.
ed_left_k:
        lda ed_cur
        ora ed_cur + 1
        ora ed_cur + 2
        ora ed_cur + 3
        beq lk_r
        ldx #$03
lk_c:   lda ed_cur,x
        sta E0,x
        dex
        bpl lk_c
        jsr ed_dec
        jsr ed_get
        cmp #$0a
        bne lk_n
        lda ed_curline
        bne lk_l
        dec ed_curline + 1
lk_l:   dec ed_curline
lk_n:   ldx #$03
lk_s:   lda E0,x
        sta ed_cur,x
        dex
        bpl lk_s
lk_r:   rts

; ed_right_k: Cursor ein Zeichen vor; ueber ein LF hinweg wird curline erhoeht. Am Textende geschieht nichts.
ed_right_k:
        ldx #$03
rk_c:   lda ed_cur,x
        sta E0,x
        dex
        bpl rk_c
        jsr ed_eq_len
        beq rk_r
        jsr ed_get
        pha
        jsr ed_inc
        ldx #$03
rk_s:   lda E0,x
        sta ed_cur,x
        dex
        bpl rk_s
        pla
        cmp #$0a
        bne rk_r
        inc ed_curline
        bne rk_r
        inc ed_curline + 1
rk_r:   rts

; Der Benutzer behaelt beim Hoch/Runter die Spalte, in der er begonnen hat, auch ueber kuerzere Zeilen hinweg: ed_want merkt sie.
; ed_up / ed_down: eine Zeile; gewuenschte Spalte bleibt erhalten (ed_want)
ed_want_set:                        ; ed_want = aktuelle Spalte, falls noch nicht gesetzt
        lda ed_want + 1
        cmp #$ff
        bne ws_r
        jsr ed_calc_col
        lda ed_colv
        sta ed_want
        lda ed_colv + 1
        sta ed_want + 1
ws_r:   rts

; ed_up_k: Cursor eine Zeile hoch, Spalte = ed_want (begrenzt auf die Zeilenlaenge, siehe ed_goto_want). Erste Zeile: nichts.
ed_up_k:
        jsr ed_want_set
        jsr ed_calc_col             ; E0 = Anfang der aktuellen Zeile
        lda E0
        ora E0 + 1
        ora E0 + 2
        ora E0 + 3
        beq up_r                    ; erste Zeile
        jsr ed_dec                  ; LF davor
        jsr ed_ls                   ; E0 = Anfang der Vorzeile
        lda ed_curline
        bne up_l
        dec ed_curline + 1
up_l:   dec ed_curline
        jmp ed_goto_want
up_r:   rts

; ed_down_k: Cursor eine Zeile runter (Anfang der naechsten Zeile, dann Spalte per ed_goto_want). Letzte Zeile: nichts.
ed_down_k:
        jsr ed_want_set
        ldx #$03
dk_c:   lda ed_cur,x
        sta E0,x
        dex
        bpl dk_c
        jsr ed_le                   ; E0 = Zeilenende
        jsr ed_eq_len
        beq dk_r                    ; letzte Zeile
        jsr ed_inc                  ; Anfang der naechsten Zeile
        inc ed_curline
        bne ed_goto_want
        inc ed_curline + 1
        jmp ed_goto_want
dk_r:   rts

; ed_goto_want: E0 = Zeilenanfang -> Cursor in diese Zeile, Spalte min(want, Laenge)
ed_goto_want:
        lda ed_want
        sta ed_gw
        lda ed_want + 1
        sta ed_gw + 1
gw_l:   lda ed_gw
        ora ed_gw + 1
        beq gw_d
        jsr ed_eq_len
        beq gw_d
        jsr ed_get
        cmp #$0a
        beq gw_d
        jsr ed_inc
        lda ed_gw
        bne gw_1
        dec ed_gw + 1
gw_1:   dec ed_gw
        jmp gw_l
gw_d:   ldx #$03
gw_s:   lda E0,x
        sta ed_cur,x
        dex
        bpl gw_s
        rts

; ed_home_k: Cursor an den Zeilenanfang.
ed_home_k:
        jsr ed_calc_col
        ldx #$03
hk_s:   lda E0,x
        sta ed_cur,x
        dex
        bpl hk_s
        rts

; ed_end_k: Cursor an das Zeilenende (vor das LF bzw. an das Textende).
ed_end_k:
        ldx #$03
nk_c:   lda ed_cur,x
        sta E0,x
        dex
        bpl nk_c
        jsr ed_le
        ldx #$03
nk_s:   lda E0,x
        sta ed_cur,x
        dex
        bpl nk_s
        rts

; =====================================================================================================================
; AUSWAHL UND ZWISCHENABLAGE
; =====================================================================================================================
; ---- Auswahl und Zwischenablage
; Auswahl = Bereich zwischen Anker (ed_anc) und Cursor, solange ed_sel <> 0. Die Zwischenablage liegt im Attic
; ($0870_0000, ed_cblen Byte, hoechstens CBMAX).
; sel_range: ed_ss = kleinere, ed_se = groessere der Stellen Anker/Cursor
; Ausgabe ed_ss = Anfang, ed_se = Ende (ausgeschlossen); veraendert A, X. Die Kette Anker - Cursor laesst Carry gesetzt, wenn
; Anker >= Cursor ist; dann ist der Cursor der Anfang.
sel_range:
        lda ed_anc
        cmp ed_cur
        lda ed_anc + 1
        sbc ed_cur + 1
        lda ed_anc + 2
        sbc ed_cur + 2
        lda ed_anc + 3
        sbc ed_cur + 3
        bcc sr_lt
        ldx #$03
sr_a:   lda ed_cur,x
        sta ed_ss,x
        lda ed_anc,x
        sta ed_se,x
        dex
        bpl sr_a
        rts
sr_lt:  ldx #$03
sr_b:   lda ed_anc,x
        sta ed_ss,x
        lda ed_cur,x
        sta ed_se,x
        dex
        bpl sr_b
        rts

; (ez_fcnt ist der gemeinsame 32-Bit-Zaehler der Kopier-, Loesch- und Suchschleifen.)
; sel_size: ez_fcnt = ed_se - ed_ss
sel_size:
        sec
        lda ed_se
        sbc ed_ss
        sta ez_fcnt
        lda ed_se + 1
        sbc ed_ss + 1
        sta ez_fcnt + 1
        lda ed_se + 2
        sbc ed_ss + 2
        sta ez_fcnt + 2
        lda ed_se + 3
        sbc ed_ss + 3
        sta ez_fcnt + 3
        rts

; Aufruf beim Zeichnen je Zeichen mit E0 = Position; ed_sf wird dem Farbbyte per ora zugefuegt. X bleibt erhalten, A wird
; veraendert.
; sel_test: ed_sf = SELF, wenn Stelle E0 in der Auswahl liegt (sonst 0); verandert nur A, X nicht
sel_test:
        lda #$00
        sta ed_sf
        lda ed_sel
        beq st_r
        lda E0
        cmp ed_ss
        lda E0 + 1
        sbc ed_ss + 1
        lda E0 + 2
        sbc ed_ss + 2
        lda E0 + 3
        sbc ed_ss + 3
        bcc st_r
        lda E0
        cmp ed_se
        lda E0 + 1
        sbc ed_se + 1
        lda E0 + 2
        sbc ed_se + 2
        lda E0 + 3
        sbc ed_se + 3
        bcs st_r
        lda #SELF
        sta ed_sf
st_r:   rts

; Wird als Schleifenbedingung der Kopier-/Loeschschleifen benutzt (mit fcnt_dec).
; fcnt_zero: Z gesetzt, wenn ez_fcnt = 0
fcnt_zero:
        lda ez_fcnt
        ora ez_fcnt + 1
        ora ez_fcnt + 2
        ora ez_fcnt + 3
        rts

; cp_inc: CP um 1
cp_inc: inc CP
        bne cpi_r
        inc CP + 1
        bne cpi_r
        inc CP + 2
        bne cpi_r
        inc CP + 3
cpi_r:  rts

; cp_init: CP = Anfang der Zwischenablage ($0870_0000). Veraendert A.
cp_init:
        lda #$00
        sta CP
        sta CP + 1
        lda #$70
        sta CP + 2
        lda #$08
        sta CP + 3
        rts

; sel_del: Auswahl loeschen (mitgeschrieben als eine Gruppe), Auswahl aufheben
sel_del:
        jsr sel_range
        jsr sel_size
        ldx #$03
sx_c:   lda ed_ss,x
        sta ed_cur,x
        dex
        bpl sx_c
        jsr ed_recount
        lda #$00
        sta ed_sel
        ; Je Durchgang ein Byte am Cursor loeschen (ed_del, mit Verlauf: so wird die ganze Auswahl EINE Gruppe und laesst sich
        ; mit einem Rueckgaengig zurueckholen, weil sel_del vor dem Loeschen nicht ed_kind aufruft; die Gruppe stammt von ed_key).
sx_l:   jsr fcnt_zero
        beq sx_r
        jsr ed_del
        jsr fcnt_dec
        jmp sx_l
sx_r:   rts

; ed_copy: Auswahl in die Zwischenablage; Carry gesetzt = kopiert (Auswahl aufgehoben); ohne Auswahl oder zu gross: Carry
; geloescht
ed_copy:
        lda ed_sel
        beq ec_no
        jsr sel_range
        jsr sel_size
        lda ez_fcnt + 3
        bne ec_no
        lda ez_fcnt + 2
        cmp #>(CBMAX >> 8)
        bcc ez_ec_ok
        bne ec_no
        lda ez_fcnt
        ora ez_fcnt + 1
        bne ec_no
        ; Groesse pruefen: ez_fcnt muss <= CBMAX (64 KB) sein, sonst wird nicht kopiert (Carry geloescht).
ez_ec_ok:  ldx #$03
ec_l:   lda ez_fcnt,x
        sta ed_cblen,x
        lda ed_ss,x
        sta E0,x
        dex
        bpl ec_l
        jsr cp_init
ec_cp:  jsr fcnt_zero
        beq ec_d
        jsr ed_get
        ldz #$00
        sta [CP],z
        jsr cp_inc
        jsr ed_inc
        jsr fcnt_dec
        jmp ec_cp
ec_d:   lda #$00
        sta ed_sel
        sec
        rts
ec_no:  clc
        rts

; ed_paste: Zwischenablage am Cursor einfuegen (eine ersetzte Auswahl wird vorher geloescht); Carry gesetzt = eingefuegt
ed_paste:
        lda ed_cblen
        ora ed_cblen + 1
        ora ed_cblen + 2
        ora ed_cblen + 3
        beq ep_no
        ; ed_len + ed_cblen (Byte 0..2) gegen ECAP vergleichen: passt es noch? (Byte 2 muss kleiner als das von ECAP sein.)
        clc                         ; passt der Text noch in den Puffer?
        lda ed_len
        adc ed_cblen
        lda ed_len + 1
        adc ed_cblen + 1
        lda ed_len + 2
        adc ed_cblen + 2
        cmp #>(ECAP >> 8)
        bcs ep_no
        ; Ersetzt die Einfuegung eine Auswahl, wird sie zuerst geloescht; Einfuegen laeuft ueber ed_ins und ist rueckgaengig
        ; machbar.
        lda ed_sel
        beq ep_g
        jsr sel_del
ep_g:   ldx #$03
ep_c:   lda ed_cblen,x
        sta ez_fcnt,x
        dex
        bpl ep_c
        jsr cp_init
ep_l:   jsr fcnt_zero
        beq ep_d
        ldz #$00
        lda [CP],z
        jsr ed_ins
        jsr cp_inc
        jsr fcnt_dec
        jmp ep_l
ep_d:   sec
        rts
ep_no:  clc
        rts

; =====================================================================================================================
; SUCHEN, ERSETZEN, GEHE-ZU
; =====================================================================================================================
; ---- Suchen und Gehe-zu (Aufruf von der Eingabezeile aus; Muster in ed_pat/ed_patn, Zeilennummer in ed_garg)
; Gross-/Kleinschreibung wird nicht unterschieden. Treffer: Carry gesetzt, Cursor auf dem Treffer; sonst Carry
; geloescht und Cursor unveraendert. Gesucht wird ab der Stelle hinter (vor) dem Cursor, am Ende (Anfang) umbrechend.
; ed_find_next: Eingabe Muster ed_pat (ed_patn Zeichen). Ausgabe Carry gesetzt = Treffer, Cursor auf dem Treffer (ed_want zurueck-
; gesetzt, curline neu gezaehlt); Carry geloescht = nichts gefunden oder kein Muster/leerer Text, Cursor unveraendert.
; Algorithmus: naive Suche ab cursor+1, fp (32 Bit) = Kandidatenposition, wird am Ende zu 0 umgebrochen (fp_wrap); ez_fcnt = len
; zaehlt die Kandidaten, also hoechstens ein voller Umlauf. Veraendert A, X, E0, E1, Z, fp, ez_fcnt, ed_k (ueber
; fs_start/ed_kind).
ed_find_next:
        jsr fs_start
        bcc fn_no
        ldx #$03
fn_c:   lda ed_cur,x
        sta fp,x
        dex
        bpl fn_c
        inc fp
        bne ez_fn_i
        inc fp + 1
        bne ez_fn_i
        inc fp + 2
        bne ez_fn_i
        inc fp + 3
ez_fn_i:   jsr fp_wrap
ez_fn_l:   jsr fs_match
        bcs fs_hit
        inc fp
        bne fn_w
        inc fp + 1
        bne fn_w
        inc fp + 2
        bne fn_w
        inc fp + 3
fn_w:   jsr fp_wrap
        jsr fcnt_dec
        bne ez_fn_l
fn_no:  clc
        rts

; ed_find_prev: wie ed_find_next, aber rueckwaerts ab cursor-1 (fp_back umbricht von 0 nach len-1).
ed_find_prev:
        jsr fs_start
        bcc fn_no
        ldx #$03
fv_c:   lda ed_cur,x
        sta fp,x
        dex
        bpl fv_c
        jsr fp_back
fv_l:   jsr fs_match
        bcs fs_hit
        jsr fp_back
        jsr fcnt_dec
        bne fv_l
        clc
        rts

; fs_hit: gemeinsamer Treffer-Ausgang: Cursor := fp, gewuenschte Spalte zuruecksetzen, Zeilennummer neu zaehlen, Carry setzen.
fs_hit: ldx #$03
fh_c:   lda fp,x
        sta ed_cur,x
        dex
        bpl fh_c
        lda #$ff
        sta ed_want
        sta ed_want + 1
        jsr ed_recount
        sec
        rts

; ed_repl_all: Suchmuster (ed_pat) ab dem Cursor bis zum Textende durch ed_rep ersetzen (ohne Umbruch, Gross-/Kleinschreibung
; egal).
; Jeder Treffer: Muster mit Rueckschritt loeschen, Ersatz einfuegen (Verlauf wie bei Tasten). rp_cnt = Zahl der Ersetzungen;
; der Cursor
; steht hinter der letzten Ersetzung.
; (Die Schleife rl_l laeuft bis zum Textende; hinter jeder Ersetzung wird hinter dem Ersatz weitergesucht, damit ein Ersatz, der
; das Muster enthaelt, nicht endlos neu getroffen wird.)
ed_repl_all:
        lda #$00
        sta rp_cnt
        sta rp_cnt + 1
        sta ed_sel                  ; eine Auswahl wuerde Rueckschritt verschlucken
        jsr fs_start
        bcc rl_done
        ldx #$03
rl_c:   lda ed_cur,x
        sta fp,x
        dex
        bpl rl_c
        ; Ohne Rest-Platz fuer das Muster (fp + patn > len) kann es keinen Treffer mehr geben -> fertig.
rl_l:   clc                         ; fp + Musterlaenge <= Textlaenge?
        lda fp
        adc ed_patn
        sta E0
        lda fp + 1
        adc #$00
        sta E0 + 1
        lda fp + 2
        adc #$00
        sta E0 + 2
        lda fp + 3
        adc #$00
        sta E0 + 3
        lda ed_len
        cmp E0
        lda ed_len + 1
        sbc E0 + 1
        lda ed_len + 2
        sbc E0 + 2
        lda ed_len + 3
        sbc E0 + 3
        bcc rl_done
        jsr fs_match
        bcc rl_nx
        ; Treffer: Cursor hinter den Treffer, dann patn mal Rueckschritt (ed_bs mit Verlauf), dann den Ersatz einfuegen.
        ; ed_k/ed_kind setzen die Art der Taste, damit die Gruppierung im Verlauf wie bei echten Tasten ablaeuft.
        clc                         ; Cursor hinter den Treffer
        lda fp
        adc ed_patn
        sta ed_cur
        lda fp + 1
        adc #$00
        sta ed_cur + 1
        lda fp + 2
        adc #$00
        sta ed_cur + 2
        lda fp + 3
        adc #$00
        sta ed_cur + 3
        ldx ed_patn
rl_d:   phx
        lda #K_BS
        sta ed_k
        jsr ed_kind
        jsr ed_bs
        plx
        dex
        bne rl_d
        ldx #$00
rl_i:   cpx ed_repn
        beq rl_e
        phx
        lda ed_rep,x
        sta ed_k
        jsr ed_kind
        lda ed_k
        jsr ed_ins
        plx
        inx
        jmp rl_i
rl_e:   ldx #$03                    ; weiter hinter dem Ersatz
rl_p:   lda ed_cur,x
        sta fp,x
        dex
        bpl rl_p
        inc rp_cnt
        bne rl_l
        inc rp_cnt + 1
        jmp rl_l
        ; Kein Treffer an fp: Kandidat um 1 weiter.
rl_nx:  inc fp
        bne rl_l
        inc fp + 1
        bne rl_l
        inc fp + 2
        bne rl_l
        inc fp + 3
        jmp rl_l
rl_done:
        lda #$ff
        sta ed_want
        sta ed_want + 1
        jmp ed_recount

; ed_find_label: Zeile suchen, die mit dem Namen in ed_pat (ed_patn Zeichen) beginnt und dann Doppelpunkt, Leerraum oder
; Zeilenende hat
; (Gross-/Kleinschreibung egal), vom Textanfang an. Treffer: Cursor an den Zeilenanfang, Carry gesetzt; sonst Carry geloescht.
ed_find_label:
        jsr fs_start
        bcc efl_no
        lda #$00
        ldx #$03
        ; fp = 0: ab dem Textanfang, eine Zeile nach der anderen (efl_l pruefen, efl_nx springt zur naechsten Zeilenanfang).
efl_z:   sta fp,x
        dex
        bpl efl_z
efl_l:   clc                         ; fp + Musterlaenge <= Textlaenge?
        lda fp
        adc ed_patn
        sta E0
        lda fp + 1
        adc #$00
        sta E0 + 1
        lda fp + 2
        adc #$00
        sta E0 + 2
        lda fp + 3
        adc #$00
        sta E0 + 3
        lda ed_len
        cmp E0
        lda ed_len + 1
        sbc E0 + 1
        lda ed_len + 2
        sbc E0 + 2
        lda ed_len + 3
        sbc E0 + 3
        bcc efl_no
        jsr fs_match
        bcc efl_nx
        ; Hinter dem Namen muss ein Doppelpunkt, Leerzeichen, Tab, LF oder das Textende stehen (sonst nur Namensanfang).
        clc                         ; Zeichen hinter dem Namen
        lda fp
        adc ed_patn
        sta E0
        lda fp + 1
        adc #$00
        sta E0 + 1
        lda fp + 2
        adc #$00
        sta E0 + 2
        lda fp + 3
        adc #$00
        sta E0 + 3
        jsr ed_eq_len
        beq efl_hit
        jsr ed_get
        cmp #$3a
        beq efl_hit
        cmp #$20
        beq efl_hit
        cmp #$09
        beq efl_hit
        cmp #$0a
        beq efl_hit
        ; Zur naechsten Zeile: bis hinter das naechste LF laufen (E0 am Ende = Anfang der Folgezeile) und als neues fp nehmen.
efl_nx:  ldx #$03                    ; naechste Zeile
efl_c:   lda fp,x
        sta E0,x
        dex
        bpl efl_c
efl_s:   jsr ed_eq_len
        beq efl_no
        jsr ed_get
        jsr ed_inc
        cmp #$0a
        bne efl_s
        ldx #$03
efl_p:   lda E0,x
        sta fp,x
        dex
        bpl efl_p
        jmp efl_l
efl_hit: jmp fs_hit
efl_no:  clc
        rts

; fs_start: neue Gruppe (wie eine Taste ohne Aenderung); ez_fcnt = Textlaenge; Carry gesetzt, wenn Suche moeglich
fs_start:
        lda #$00
        sta ed_k
        jsr ed_kind
        ldx #$03
fs_c:   lda ed_len,x
        sta ez_fcnt,x
        dex
        bpl fs_c
        lda ed_len
        ora ed_len + 1
        ora ed_len + 2
        ora ed_len + 3
        beq fs_no
        lda ed_patn
        beq fs_no
        sec
        rts
fs_no:  clc
        rts

; fp_wrap: fp >= Textlaenge -> 0
fp_wrap:
        lda fp
        cmp ed_len
        lda fp + 1
        sbc ed_len + 1
        lda fp + 2
        sbc ed_len + 2
        lda fp + 3
        sbc ed_len + 3
        bcc fw_r
        lda #$00
        sta fp
        sta fp + 1
        sta fp + 2
        sta fp + 3
fw_r:   rts

; fp_back: fp = fp - 1, bei 0 = Textlaenge - 1
fp_back:
        lda fp
        ora fp + 1
        ora fp + 2
        ora fp + 3
        bne fb_d
        ldx #$03
fb_c:   lda ed_len,x
        sta fp,x
        dex
        bpl fb_c
fb_d:   lda fp
        bne fb1
        lda fp + 1
        bne fb2
        lda fp + 2
        bne fb3
        dec fp + 3
fb3:    dec fp + 2
fb2:    dec fp + 1
fb1:    dec fp
        rts

; (Die Z-Flagge am Ende gilt nach der Verknuepfung aller vier Byte; Schleifenende der Suche.)
; fcnt_dec: ez_fcnt - 1; Z gesetzt, wenn danach 0
fcnt_dec:
        lda ez_fcnt
        bne ez_fd1
        lda ez_fcnt + 1
        bne ez_fd2
        lda ez_fcnt + 2
        bne ez_fd3
        dec ez_fcnt + 3
ez_fd3:    dec ez_fcnt + 2
ez_fd2:    dec ez_fcnt + 1
ez_fd1:    dec ez_fcnt
        lda ez_fcnt
        ora ez_fcnt + 1
        ora ez_fcnt + 2
        ora ez_fcnt + 3
        rts

; Vergleicht ed_pat (ed_patn Zeichen) mit dem Text ab fp, Zeichen fuer Zeichen mit fs_fold (Kleinschreibung). Ausgabe Carry
; gesetzt = Treffer. Veraendert A, X, E0, E1, Z, ez_fi, fa. Hinter dem Textende liefert ed_get 0 und das Muster passt dort nicht.
; fs_match: Carry gesetzt, wenn das Muster an Stelle fp steht
fs_match:
        lda #$00
        sta ez_fi
fm_l:   ldx #$03
fm_c:   lda fp,x
        sta E0,x
        dex
        bpl fm_c
        clc
        lda E0
        adc ez_fi
        sta E0
        bcc fm_g
        inc E0 + 1
        bne fm_g
        inc E0 + 2
        bne fm_g
        inc E0 + 3
fm_g:   jsr ed_get
        jsr fs_fold
        sta fa
        ldx ez_fi
        lda ed_pat,x
        jsr fs_fold
        cmp fa
        bne fm_no
        inc ez_fi
        lda ez_fi
        cmp ed_patn
        bne fm_l
        sec
        rts
fm_no:  clc
        rts

; fs_fold: A = Zeichen -> A = Kleinbuchstabe (nur A-Z wird umgesetzt, per ora #$20); alles andere unveraendert.
fs_fold:
        cmp #$41
        bcc ff_d
        cmp #$5b
        bcs ff_d
        ora #$20
ff_d:   rts

; Zaehlt vom Textanfang Zeilen (fl = laufende Zeilennummer) bis ed_garg; fp merkt den Anfang der zuletzt gesehenen Zeile, damit
; bei
; einer Zahl hinter der letzten Zeile die letzte Zeile genommen wird. Beginnt eine neue Undo-Gruppe (ed_kind mit Taste 0).
; ed_goto: Cursor an den Anfang der Zeile ed_garg (0 = 1; hinter der letzten Zeile = letzte Zeile)
ed_goto:
        lda #$00
        sta ed_k
        jsr ed_kind
        lda #$00
        sta E0
        sta E0 + 1
        sta E0 + 2
        sta E0 + 3
        lda #$01
        sta fl
        lda #$00
        sta fl + 1
gt_l:   lda fl
        cmp ed_garg
        lda fl + 1
        sbc ed_garg + 1
        bcs gt_d
        ldx #$03                    ; Zeilenanfang merken
gt_m:   lda E0,x
        sta fp,x
        dex
        bpl gt_m
        jsr ed_le
        jsr ed_eq_len
        beq gt_e
        jsr ed_inc
        inc fl
        bne gt_l
        inc fl + 1
        jmp gt_l
gt_e:   ldx #$03                    ; letzte Zeile: Anfang dieser Zeile
gt_f:   lda fp,x
        sta E0,x
        dex
        bpl gt_f
gt_d:   ldx #$03
gt_c:   lda E0,x
        sta ed_cur,x
        dex
        bpl gt_c
        lda #$ff
        sta ed_want
        sta ed_want + 1
        jmp ed_recount

; =====================================================================================================================
; TASTEN
; =====================================================================================================================
; ---- Tasten
; ed_key: Eingabe A = Tastencode. Bestimmt zuerst die Gruppe (ed_kind), behandelt dann die Auswahl und springt in den Verteiler
; ek_go. Alle Zweige enden in ed_view. Unbekannte Codes veraendern nichts, zeichnen aber neu.
; Auswahlregeln: Rueckschritt/Entf loeschen die Auswahl (ek_sd); Undo/Redo und jede Aenderung (ed_kd <> 0) heben sie auf;
; Bewegung, Kopieren, Markieren behalten sie (der Anker bleibt, der Cursor wandert mit).
; ed_key: A = Tastencode
ed_key: sta ed_k
        jsr ed_kind                 ; Gruppe fuer Rueckgaengig bestimmen
        lda ed_sel                  ; Auswahl aktiv: Rueckschritt/Entf loeschen sie, Aenderungen heben sie auf
        beq ek_go
        lda ed_k
        cmp #K_BS
        beq ek_sd
        cmp #K_DEL
        beq ek_sd
        cmp #K_UNDO
        beq ek_cs
        cmp #K_REDO
        beq ek_cs
        lda ed_kd
        beq ek_go
ek_cs:  lda #$00
        sta ed_sel
ek_go:  lda ed_k
        cmp #K_MARK
        beq ek_mark
        cmp #K_COPY
        beq ek_copy
        cmp #K_CUT
        beq ek_cut
        cmp #K_PASTE
        beq ek_paste
        cmp #K_UNDO
        beq ek_undo
        cmp #K_REDO
        beq ek_redo
        cmp #K_UP
        beq ek_up
        cmp #K_DOWN
        beq ek_down
        cmp #K_PGUP
        beq ek_pgup
        cmp #K_PGDN
        beq ek_pgdn
        pha
        ; Alles andere (links/rechts/Pos1/Ende/Zeichen) setzt die gewuenschte Spalte zurueck; nur Auf/Ab/Bild auf/ab behalten sie.
        lda #$ff                    ; alles andere setzt die gewuenschte Spalte zurueck
        sta ed_want
        sta ed_want + 1
        pla
        cmp #K_LEFT
        beq ek_left
        cmp #K_RIGHT
        beq ek_right
        cmp #K_HOME
        beq ek_home
        cmp #K_END
        beq ek_end
        cmp #K_BS
        beq ek_bs
        cmp #K_DEL
        beq ek_del
        cmp #K_RET
        beq ek_ret
        cmp #K_TAB
        beq ek_tab
        cmp #$20
        bcc ek_x
        cmp #$7f
        bcs ek_x
        jsr ed_ins
ek_x:   jmp ed_view
        ; ek_sd: Auswahl mit Rueckschritt oder Entf loeschen (eine Gruppe), sonst nichts.
ek_sd:  jsr ek_w
        jsr sel_del
        jmp ed_view
        ; ek_mark: Auswahl umschalten; beim Beginnen wird der Anker = Cursor (ed_sel toggelt mit eor #1).
ek_mark: jsr ek_w
        lda ed_sel
        eor #$01
        sta ed_sel
        beq ek_m1
        ldx #$03
ek_m0:  lda ed_cur,x
        sta ed_anc,x
        dex
        bpl ek_m0
ek_m1:  jmp ed_view
        ; ek_w: Hilfsroutine, setzt ed_want zurueck (ed_want = $FFFF).
ek_w:   lda #$ff                    ; gewuenschte Spalte zuruecksetzen
        sta ed_want
        sta ed_want + 1
        rts
        ; ek_copy/ek_cut/ek_paste: Zwischenablage. Ausschneiden = Kopieren und, falls erfolgreich (Carry), Auswahl loeschen.
ek_copy: jsr ek_w
        jsr ed_copy
        jmp ed_view
ek_cut: jsr ek_w
        jsr ed_copy
        bcc ek_cx
        jsr sel_del
ek_cx:  jmp ed_view
ek_paste: jsr ek_w
        jsr ed_paste
        jmp ed_view
ek_undo: lda #$ff
        sta ed_want
        sta ed_want + 1
        jsr ed_undo
        jmp ed_view
ek_redo: lda #$ff
        sta ed_want
        sta ed_want + 1
        jsr ed_redo
        jmp ed_view

; ed_kind: Eingabe ed_k = Tastencode. Bestimmt die Art der Taste (ed_kd): 1 Zeichen/Tab, 2 Return, 3 Rueckschritt, 4 Entf, 0
; sonst (Bewegung,
; Steuercodes). Vergibt eine NEUE Gruppennummer (ed_grp++), wenn die Art 0 ist oder sich von der letzten Art (ed_lastkind)
; unterscheidet; so wird ein zusammenhaengender Lauf gleicher Tasten (z.B. ein getipptes Wort) mit einem einzigen Rueckgaengig
; zurueckgenommen, Bewegungen trennen die Gruppen. Veraendert A, X, ed_kd, ed_lastkind, ed_grp.
; ed_kind: Art der Taste (1 Zeichen/Tab, 2 Return, 3 Rueckschritt, 4 Entf, 0 sonst); neue Gruppe, wenn sich die Art aendert
ed_kind:
        lda ed_k
        ldx #$00
        cmp #K_RET
        bne kd1
        ldx #$02
        bne kd_s
kd1:    cmp #K_BS
        bne kd2
        ldx #$03
        bne kd_s
kd2:    cmp #K_DEL
        bne kd3
        ldx #$04
        bne kd_s
kd3:    cmp #K_TAB
        beq kd_t
        cmp #$20
        bcc kd_s
        cmp #$7f
        bcs kd_s
kd_t:   ldx #$01
kd_s:   stx ed_kd
        beq kd_new
        cpx ed_lastkind
        beq kd_same
kd_new: inc ed_grp
        bne kd_same
        inc ed_grp + 1
kd_same: lda ed_kd
        sta ed_lastkind
        rts
        ; Ab hier: die Einsprungstellen der Tastenzweige (jeweils Aufruf der Bewegungs-/Aenderungsroutine, dann ed_view).
ek_left: jsr ed_left_k
        jmp ed_view
ek_right: jsr ed_right_k
        jmp ed_view
ek_home: jsr ed_home_k
        jmp ed_view
ek_end: jsr ed_end_k
        jmp ed_view
ek_bs:  jsr ed_bs
        jmp ed_view
ek_del: jsr ed_del
        jmp ed_view
ek_up:  jsr ed_up_k
        jmp ed_view
ek_down: jsr ed_down_k
        jmp ed_view
        ; Bild auf/ab: (ed_trows - 1) mal Auf bzw. Ab (ed_up_k/ed_down_k); eine Zeile bleibt als Ueberlappung stehen.
ek_pgup:
        lda ed_trows
        sec
        sbc #$01
        sta ed_pg
pu_l:   lda ed_pg
        beq ek_x
        jsr ed_up_k
        dec ed_pg
        jmp pu_l
ek_pgdn:
        lda ed_trows
        sec
        sbc #$01
        sta ed_pg
pd_l:   lda ed_pg
        beq ek_x
        jsr ed_down_k
        dec ed_pg
        jmp pd_l
ek_tab: lda #$20                    ; Leerzeichen bis zum naechsten Vielfachen von 4
        jsr ed_ins
        jsr ed_calc_col
        lda ed_colv
        and #$03
        bne ek_tab
        jmp ed_view
        ; Return: LF einfuegen, dann die Einrueckung der Vorzeile uebernehmen (Auto-Einrueckung).
ek_ret: lda #$0a
        jsr ed_ins
        ldx #$03                    ; Anfang der Vorzeile suchen (cur steht hinter dem LF)
er_p:   lda ed_cur,x
        sta E0,x
        dex
        bpl er_p
        jsr ed_dec                  ; LF
        jsr ed_ls
        lda #$00
        sta ed_ind
er_c:   jsr ed_get                  ; fuehrende Leerzeichen zaehlen (das LF beendet die Schleife)
        cmp #$20
        bne er_i
        inc ed_ind
        jsr ed_inc
        jmp er_c
er_i:   lda ed_ind
        beq er_d
        lda #$20
        jsr ed_ins
        dec ed_ind
        jmp er_i
er_d:   jmp ed_view

; =====================================================================================================================
; BILDAUSSCHNITT NACHFUEHREN UND ZEICHNEN
; =====================================================================================================================
; ---- Bildausschnitt nachfuehren und zeichnen
; ed_view: Ausschnitt nachfuehren, dann neu zeichnen. Einstieg am Ende jeder Taste.
ed_view:
        jsr ed_scroll
        jmp ed_draw

; ed_scroll: Eingabe ed_cur/ed_curline. Ausgabe ed_top/ed_topline/ed_left so, dass der Cursor im sichtbaren Bereich liegt.
; Senkrecht: ist curline < topline, wird top = Anfang der Cursorzeile; ist curline >= topline + ed_trows, wird top Zeile fuer
; Zeile vorgeschoben (ed_top_next; ed_lim = topline + Textzeilen wird mitgezogen). Waagerecht (sc_h): left <= Spalte < left +
; (SCRW - GUTTER).
; ed_scroll: sorgt dafuer, dass der Cursor sichtbar ist (top/topline/left)
ed_scroll:
        lda ed_curline + 1          ; curline < topline ?
        cmp ed_topline + 1
        bcc ez_sc_up
        bne ez_sc_dn
        lda ed_curline
        cmp ed_topline
        bcs ez_sc_dn
ez_sc_up:  jsr ed_calc_col             ; top = Anfang der Cursorzeile
        ldx #$03
su_s:   lda E0,x
        sta ed_top,x
        dex
        bpl su_s
        lda ed_curline
        sta ed_topline
        lda ed_curline + 1
        sta ed_topline + 1
        jmp sc_h
ez_sc_dn:  lda ed_trows               ; Textzeilen; curline >= topline + Textzeilen -> vorwaerts
        clc
        adc ed_topline
        sta ed_lim
        lda ed_topline + 1
        adc #$00
        sta ed_lim + 1
sd_l:   lda ed_curline + 1
        cmp ed_lim + 1
        bcc sc_h
        bne sd_do
        lda ed_curline
        cmp ed_lim
        bcc sc_h
sd_do:  jsr ed_top_next
        inc ed_lim
        bne sd_l
        inc ed_lim + 1
        jmp sd_l
sc_h:   jsr ed_calc_col            ; horizontal: left <= col < left + Textbreite
        lda ed_colv + 1
        cmp ed_left + 1
        bcc sh_l
        bne sh_r
        lda ed_colv
        cmp ed_left
        bcc sh_l
sh_r:   lda ed_left
        clc
        adc #SCRW - GUTTER
        sta ed_lim
        lda ed_left + 1
        adc #$00
        sta ed_lim + 1
        lda ed_colv + 1
        cmp ed_lim + 1
        bcc sh_d
        bne sh_m
        lda ed_colv
        cmp ed_lim
        bcc sh_d
sh_m:   sec                         ; left = col - Textbreite + 1
        lda ed_colv
        sbc #SCRW - GUTTER - 1
        sta ed_left
        lda ed_colv + 1
        sbc #$00
        sta ed_left + 1
        rts
sh_l:   lda ed_colv
        sta ed_left
        lda ed_colv + 1
        sta ed_left + 1
sh_d:   rts

; ed_top_next: top und topline um eine Zeile vor (nicht ueber die letzte Zeile hinaus)
ed_top_next:
        ldx #$03
tn_c:   lda ed_top,x
        sta E0,x
        dex
        bpl tn_c
        jsr ed_le
        jsr ed_eq_len
        beq tn_r
        jsr ed_inc
        ldx #$03
tn_s:   lda E0,x
        sta ed_top,x
        dex
        bpl tn_s
        inc ed_topline
        bne tn_r
        inc ed_topline + 1
tn_r:   rts

; =====================================================================================================================
; ZEICHNEN
; =====================================================================================================================
; ---- Zeichnen: ed_scr (Zeichencodes) und ed_attr (Farben), ed_rows * 80 Byte
; Bildzeile: 4 Stellen Zeilennummer, Leerzeichen, Text ab Spalte left. Letzte Zeile: Statuszeile "Z nnnn S nnn".
; ed_draw: Eingabe Text, ed_top/ed_topline, ed_left, Auswahl. Ausgabe ed_scr/Attribute komplett neu: Kopfzeilen werden
; uebersprungen,
; dann ed_trows Textzeilen (jeweils erst loeschen, dann dw_line), dann Fusszeilen uebersprungen, Statuszeile.
; ed_rp = 16-Bit-Zeiger auf den Anfang der aktuellen Bildzeile in ed_scr (Bank 0); die Attributzeile erreicht man ueber EA
; (dw_attrptr). E3 = Position des naechsten zu zeichnenden Zeichens; ed_dl = Nummer der Zeile; ed_exist = 0, sobald der Text
; zu Ende ist (die Restzeilen bleiben leer). Mit Auswahl wird vorher sel_range gerufen (ed_ss/ed_se fuer sel_test).
ed_draw:
        lda ed_sel
        beq dw_ns
        jsr sel_range
dw_ns:
        lda #<ed_scr
        sta ed_rp
        lda #>ed_scr
        sta ed_rp + 1
        ldx ed_hdr                  ; Kopfzeilen uebergehen
        jsr dw_skip
        ldx #$03
dw_t:   lda ed_top,x
        sta E3,x
        dex
        bpl dw_t
        lda ed_topline
        sta ed_dl
        lda ed_topline + 1
        sta ed_dl + 1
        lda #$01
        sta ed_exist
        lda #$00
        sta ed_dr
dw_row: lda ed_trows
        cmp ed_dr
        beq dw_stat
        jsr dw_clear
        lda ed_exist
        beq dw_adv
        jsr dw_line
dw_adv: lda ed_rp
        clc
        adc #SCRW
        sta ed_rp
        bcc dw_a1
        inc ed_rp + 1
dw_a1:  inc ed_dr
        jmp dw_row
        ; Statuszeile: nach den Fusszeilen, leeren; mit ed_deco als umgekehrte Leiste einfaerben (COL_STAT | SELF).
dw_stat:
        ldx ed_ftr                  ; Fusszeilen uebergehen
        jsr dw_skip
        jsr dw_clear
        lda ed_deco                 ; Schmuck: Statuszeile als umgekehrte Leiste
        beq dw_sn
        ldz #SCRW - 1
        lda #COL_STAT | SELF
dw_sf:  sta [EA],z
        dez
        bpl dw_sf
dw_sn:  jmp dw_status
; er_chk: ed_erl = 1, wenn Zeile ed_dl eine Fehlerzeile des letzten Uebersetzens ist (nur mit ed_deco; gueltig, solange sich
; der Text
; nicht geaendert hat: ed_ehp = hp beim Uebersetzen)
er_chk: lda #$00
        sta ed_erl
        lda ed_deco
        beq erc_r
        ldx ed_en
        beq erc_r
erc_l:  dex
        bmi erc_r
        lda ed_elo,x
        cmp ed_dl
        bne erc_l
        lda ed_ehi,x
        cmp ed_dl + 1
        bne erc_l
        inc ed_erl
erc_r:  rts
; dw_skip: ed_rp um X Bildzeilen vorruecken
dw_skip:
        txa
        beq dsk_r
dsk_l:   lda ed_rp
        clc
        adc #SCRW
        sta ed_rp
        bcc dsk_n
        inc ed_rp + 1
dsk_n:   dex
        bne dsk_l
dsk_r:   rts
; dw_clear: loescht die Bildzeile ed_rp: Zeichen = Leerzeichen ($20, (ET+2),y), Farbe = COL_TEXT ([EA],z mit EA aus dw_attrptr).
; Mit dem Zeiger (ET+2),y wird hier das Bildpuffer in Bank 0 adressiert, mit [EA],z der 32-Bit-Attributbereich. Veraendert A,
; Y, Z, ET+2/3, EA.
dw_clear:
        lda ed_rp
        sta ET + 2
        lda ed_rp + 1
        sta ET + 3
        ldy #SCRW - 1
        lda #$20
ez_dc1:    sta (ET + 2),y
        dey
        bpl ez_dc1
        jsr dw_attrptr
        ldz #SCRW - 1
        lda #COL_TEXT
ez_dc2: sta [EA],z
        dez
        bpl ez_dc2
        rts

; dw_attrptr: EA = Attributbasis ed_abase (32 Bit: Puffer in Bank 0 oder Farb-RAM $0FF8_0000) + (ed_rp - ed_scr)
dw_attrptr:
        sec
        lda ed_rp
        sbc #<ed_scr
        sta ed_ao
        lda ed_rp + 1
        sbc #>ed_scr
        sta ed_ao + 1
        clc
        lda ed_abase
        adc ed_ao
        sta EA
        lda ed_abase + 1
        adc ed_ao + 1
        sta EA + 1
        lda ed_abase + 2
        adc #$00
        sta EA + 2
        lda ed_abase + 3
        adc #$00
        sta EA + 3
        rts

; Ablauf: Zeilennummer (put_num4), Randfarbe, ggf. Schmuck (Strich, Cursorzeilenmarke), dann Zeichen fuer Zeichen: ed_get ->
; sel_test (Auswahlfarbe) -> ed_inc -> lx_step (Syntaxfarbe) -> Fehlerzeilenfarbe -> Ausgabe, falls das Zeichen im sichtbaren
; Fenster [left, left + SCRW - GUTTER) liegt (ed_dd = ed_cc - left; negativ oder zu gross = nicht zeichnen). ed_cc zaehlt die
; Spalte.
; Endet an LF (E3 hinter das LF) oder Textende (ed_exist = 0).
; dw_line: E3 = Zeilenanfang -> Zeile zeichnen; danach E3 = naechste Zeile, ed_exist = 0 nach der letzten
dw_line:
        lda ed_rp
        sta ET + 2
        lda ed_rp + 1
        sta ET + 3
        lda ed_dl
        sta ET + 4
        lda ed_dl + 1
        sta ET + 5
        ldy #$00
        jsr put_num4
        ldz #$04                    ; Zeilennummer in Randfarbe (EA zeigt seit dw_clear auf die Attributzeile)
        lda #COL_GUTTER
dl_g:   sta [EA],z
        dez
        bpl dl_g
        lda ed_deco                 ; Schmuck: Strich hinter der Zeilennummer, Cursorzeile mit > und heller Nummer
        beq dl_nd
        ldy #$04
        lda #$5d
        sta (ET + 2),y
        lda ed_dl
        cmp ed_curline
        bne dl_nd
        lda ed_dl + 1
        cmp ed_curline + 1
        bne dl_nd
        lda #$3e
        sta (ET + 2),y
        ldz #$04
        lda #COL_CURNUM
dl_h:   sta [EA],z
        dez
        bpl dl_h
dl_nd:
        jsr er_chk
        lda #$00
        sta ed_cc
        sta ed_cc + 1
        jsr lx_reset
        ; Zeichenschleife: E0 := E3 (aktuelle Zeichenstelle); am Textende endet der Text (dl_last), bei LF die Zeile (dl_lf).
dl_l:   ldx #$03
dl_c:   lda E3,x
        sta E0,x
        dex
        bpl dl_c
        jsr ed_eq_len
        beq dl_last
        jsr ed_get
        cmp #$0a
        beq dl_lf
        pha
        jsr sel_test
        jsr ed_inc
        ldx #$03
dl_s:   lda E0,x
        sta E3,x
        dex
        bpl dl_s
        pla
        sta ed_ch
        jsr lx_step                 ; Farbe des Zeichens (und Lexerzustand)
        ldx ed_erl
        beq dl_ne
        lda #COL_ERRL
dl_ne:  ora ed_sf
        sta ed_cl
        ; Fensterpruefung: d = cc - left muss in [0, SCRW - GUTTER) liegen; das High-Byte ungleich 0 heisst "ausserhalb".
        sec                         ; d = cc - left
        lda ed_cc
        sbc ed_left
        sta ed_dd
        lda ed_cc + 1
        sbc ed_left + 1
        bne dl_n                    ; links davor (negativ) oder weit rechts
        lda ed_dd
        cmp #SCRW - GUTTER
        bcs dl_n
        ; Ausgabe: ASCII -> Bildschirmcode, in ed_scr an Spalte GUTTER + d (y = d + 5 per iny*5), Farbe nach [EA],z (Z =
        ; Spaltenindex).
        lda ed_ch
        jsr asc2scr
        ldy ed_dd
        iny
        iny
        iny
        iny
        iny
        sta (ET + 2),y
        tya
        taz
        lda ed_cl
        sta [EA],z
dl_n:   inc ed_cc
        bne dl_l
        inc ed_cc + 1
        jmp dl_l
dl_lf:  ldx #$03                    ; LF ueberspringen: naechste Zeile
        jsr ed_inc
dl_x:   lda E0,x
        sta E3,x
        dex
        bpl dl_x
        inc ed_dl
        bne dl_r
        inc ed_dl + 1
dl_r:   rts
dl_last: lda #$00                   ; letzte Zeile (ohne LF) gezeichnet
        sta ed_exist
        rts

; put_num4: Eingabe ET+4/5 = Zahl (0..9999), Y = Startspalte in der Bildzeile ((ET+2),y). Ausgabe 4 Ziffern ab (ET+2),y;
; fuehrende Nullen werden zu Leerzeichen (die letzte Stelle bleibt immer Ziffer). Rechnet per fortgesetzter Subtraktion
; (dn_dig) die Stellen 1000/100/10 aus. Veraendert A, X, Y, ET, ET+4..7, num_d, ed_ny.
; put_num4: ET+4/5 = Zahl (0..9999) -> 4 Stellen ab (ET+2),Y; fuehrende Nullen als Leerzeichen
put_num4:
        sty ed_ny
        lda #<1000
        sta ET
        lda #>1000
        sta ET + 1
        jsr dn_dig
        sta num_d
        lda #<100
        sta ET
        lda #>100
        sta ET + 1
        jsr dn_dig
        sta num_d + 1
        lda #<10
        sta ET
        lda #>10
        sta ET + 1
        jsr dn_dig
        sta num_d + 2
        lda ET + 4
        sta num_d + 3
        ; Fuehrende Nullen (nur die ersten drei Stellen) durch Leerzeichen ersetzen: $20 - $30 wird unten mit +$30 wieder $20.
        ldx #$00
dn_z:   cpx #$03
        beq dn_out
        lda num_d,x
        bne dn_out
        lda #$20 - $30
        sta num_d,x
        inx
        jmp dn_z
dn_out: ldx #$00
        ldy ed_ny
dn_o:   lda num_d,x
        clc
        adc #$30
        sta (ET + 2),y
        iny
        inx
        cpx #$04
        bne dn_o
        rts
dn_dig: lda #$00                    ; A = (ET+4/5) / (ET/ET+1); Rest in ET+4/5
        sta ET + 7
dn_l:   lda ET + 5
        cmp ET + 1
        bcc dn_d
        bne dn_s
        lda ET + 4
        cmp ET
        bcc dn_d
dn_s:   lda ET + 4
        sec
        sbc ET
        sta ET + 4
        lda ET + 5
        sbc ET + 1
        sta ET + 5
        inc ET + 7
        jmp dn_l
dn_d:   lda ET + 7
        rts

; dw_status: Statuszeile (letzte Bildzeile, ed_rp zeigt darauf): "L nnnn" (Zeile) ab Spalte 0/2 und "C nnnn" (Spalte,
; 1-basiert) ab Spalte 9/11.
; Statuszeile (letzte Bildzeile, ed_rp zeigt darauf): "Z nnnn S nnnn"
dw_status:
        lda ed_rp
        sta ET + 2
        lda ed_rp + 1
        sta ET + 3
        ldy #$00
        lda #$4c                    ; L (line; capital letter in the upper/lower case character set)
        sta (ET + 2),y
        lda ed_curline
        sta ET + 4
        lda ed_curline + 1
        sta ET + 5
        ldy #$02
        jsr put_num4
        jsr ed_calc_col
        lda ed_colv
        clc
        adc #$01
        sta ET + 4
        lda ed_colv + 1
        adc #$00
        sta ET + 5
        ldy #$09
        lda #$43                    ; C (column)
        sta (ET + 2),y
        ldy #$0b
        jsr put_num4
        rts

; =====================================================================================================================
; LEXER (FAERBUNG)
; =====================================================================================================================
; Der Lexer arbeitet zeichenweise waehrend des Zeichnens einer Zeile. Zustand: lx_state (0 normal, 1 Kommentar bis Zeilenende,
; 2 Zeichenkette), lx_rem/lx_tok = noch zu faerbende Restzeichen eines schon erkannten Wortes und dessen Farbe, lx_first = 1,
; solange
; noch kein Wort in dieser Zeile stand (nur das erste Wort kann eine Mnemonik sein), lx_len = Laenge des Wortes.
; Das Wort wird beim ersten Zeichen per lx_peek vorausgelesen (Vorausschau ueber E0, ohne E3 zu veraendern), dann liefern die
; Folgezeichen ihre Farbe aus lx_tok, bis lx_rem abgelaufen ist.
; ---- Lexer (Faerbung): Zustand je Zeile; ein Zeichen pro Schritt
; lx_reset: Zeilenanfang
lx_reset:
        lda #$01
        sta lx_first
        lda #$00
        sta lx_state
        sta lx_rem
        rts

; lx_step: Eingabe ed_ch = Zeichen (E3 steht schon dahinter, daher "E3 - 1" fuer das Zeichen), ed_cc = Spalte. Ausgabe A = Farbe.
; Veraendert A, X, E0, E1, Z und die lx_*-Zellen. Erkennt: Kommentar (; oder //), Zeichenkette ("..."), Direktive (.name),
; Zahl (Dezimal, $hex, %bin), Marke (Spalte 0 mit ':' dahinter), Mnemonik (erstes Wort, lx_ismn), sonstiger Bezeichner/Text.
; lx_step: ed_ch = Zeichen (steht an E3 - 1), ed_cc = Spalte -> A = Farbe
lx_step:
        lda lx_state
        beq ls_norm
        cmp #$01
        bne ls_str
        lda #COL_COMMENT
        rts
ls_str: lda ed_ch                   ; Zeichenkette: endet mit dem schliessenden "
        cmp #$22
        bne ls_s1
        lda #$00
        sta lx_state
ls_s1:  lda #COL_STRING
        rts
; Normalzustand: zuerst Restzeichen eines schon erkannten Wortes liefern (lx_rem), sonst beginnt hier ein neues Token (ls_new).
ls_norm:
        lda lx_rem
        beq ls_new
        dec lx_rem
        lda lx_tok
        rts
ls_new: lda ed_ch
        cmp #$3b                    ; ;
        beq ls_cm
        cmp #$2f                    ; //
        bne ls_n1
        lda #$01
        jsr lx_peek
        cmp #$2f
        beq ls_cm
        lda #COL_TEXT
        rts
ls_n1:  cmp #$22
        bne ls_n2
        lda #$02
        sta lx_state
        lda #COL_STRING
        rts
; ls_cm: Kommentar beginnt (; oder //); lx_state = 1 haelt ihn bis zum Zeilenende (der Zustand wird je Zeile zurueckgesetzt).
ls_cm:  lda #$01
        sta lx_state
        lda #COL_COMMENT
        rts
ls_n2:  cmp #$2e                    ; .name: Direktive (oder lokale Marke)
        bne ls_n3
        lda #$01
        jsr lx_peek
        jsr lx_isid
        bcs ls_pl
        ldx #$01
        jsr lx_scan                 ; X = Laenge ab 1
        lda #COL_DIR
        jmp ls_ident
; Dezimalzahl: Laenge per lx_scan, dann lx_rem = Laenge - 1 (das erste Zeichen wird sofort geliefert), Farbe in lx_tok.
ls_n3:  jsr lx_isdigit
        bcs ls_n4
        ldx #$00
        jsr lx_scan
        lda #COL_NUM
        sta lx_tok
        dex
        stx lx_rem
        lda #$00
        sta lx_first
        lda #COL_NUM
        rts
ls_n4:  lda ed_ch
        cmp #$24                    ; $hex
        bne ls_n5
        lda #$01
        jsr lx_peek
        jsr lx_ishex
        bcs ls_pl
        ldx #$01
        jsr lx_scanhex
        jmp ls_num
; %: nur Binaerzahl, wenn eine 0 oder 1 folgt, sonst einfaches Zeichen (ls_pl).
ls_n5:  cmp #$25                    ; %bin
        bne ls_n6
        lda #$01
        jsr lx_peek
        cmp #$30
        beq ls_b1
        cmp #$31
        bne ls_pl
ls_b1:  ldx #$01
        jsr lx_scanbin
ls_num: lda #COL_NUM
        sta lx_tok
        dex
        stx lx_rem
        lda #$00
        sta lx_first
        lda #COL_NUM
        rts
ls_n6:  jsr lx_isid                 ; Bezeichner
        bcs ls_pl
        ldx #$00
        jsr lx_scan
        lda #COL_TEXT
; ls_ident: gemeinsame Auswertung eines Wortes (Eingabe A = vorlaeufige Farbe, X = Laenge). Marke vor Mnemonik vor Text.
ls_ident:
        sta lx_tok                  ; X = Laenge; ed_cc = Spalte
        stx lx_len
        lda ed_cc                   ; Marke: in Spalte 0 und direkt dahinter ':'
        ora ed_cc + 1
        bne ls_nl
        txa
        jsr lx_peek
        cmp #$3a
        bne ls_nl
        ldx lx_len                  ; Marke samt Doppelpunkt
        stx lx_rem
        lda #COL_LABEL
        sta lx_tok
        rts
ls_nl:  lda lx_tok
        cmp #COL_DIR
        beq ls_done
        lda lx_first                ; erster Bezeichner der Zeile: Mnemonik?
        beq ls_done
        jsr lx_ismn
        bcs ls_done
        lda #COL_MNEM
        sta lx_tok
ls_done: lda #$00
        sta lx_first
        ldx lx_len
        dex
        stx lx_rem
        lda lx_tok
        rts
ls_pl:  lda #COL_TEXT
        rts

; lx_peek: A = Abstand (1..) -> A = Zeichen an der Stelle (aktuelles Zeichen + A); 0 hinter dem Textende
lx_peek:
        phx
        sta lx_pk
        ldx #$03
ez_lp1:    lda E3,x
        sta E0,x
        dex
        bpl ez_lp1
        jsr ed_dec                  ; aktuelles Zeichen
ez_lp2:    lda lx_pk
        beq ez_lp3
        jsr ed_inc
        dec lx_pk
        jmp ez_lp2
ez_lp3:    jsr ed_get
        plx
        rts

; lx_isid: Eingabe A = Zeichen; Carry geloescht = Buchstabe oder Unterstrich (Bezeichnerbeginn), sonst gesetzt.
lx_isid:                            ; A: Carry geloescht bei Buchstabe oder _
        cmp #$5f
        beq li_y
        cmp #$41
        bcc li_n
        cmp #$5b
        bcc li_y
        cmp #$61
        bcc li_n
        cmp #$7b
        bcc li_y
li_n:   sec
        rts
li_y:   clc
        rts
; lx_isdigit: Carry geloescht = Ziffer 0-9.
lx_isdigit:                         ; Carry geloescht bei Ziffer
        cmp #$30
        bcc ld_n
        cmp #$3a
        bcs ld_n
        clc
        rts
ld_n:   sec
        rts
; lx_ishex: Carry geloescht = 0-9, a-f oder A-F (ora #$20 faltet auf Kleinbuchstaben; erhaelt A nicht).
lx_ishex:
        jsr lx_isdigit
        bcc lh_y
        ora #$20
        cmp #$61
        bcc lh_n
        cmp #$67
        bcs lh_n
lh_y:   clc
        rts
lh_n:   sec
        rts

; lx_scan: ab Abstand X: Zeichen der Klasse Bezeichner/Ziffer/_ zaehlen -> X = Laenge ab Zeichenbeginn
lx_scan:
        txa
        jsr lx_peek
        jsr lx_isid
        bcc lc_n
        jsr lx_isdigit
        bcs lc_e
lc_n:   inx
        bne lx_scan
lc_e:   rts
; lx_scanhex / lx_scanbin: wie lx_scan, aber nur Hex-/Binaerziffern und '_' (Trennzeichen in Zahlen).
lx_scanhex:
        txa
        jsr lx_peek
        jsr lx_ishex
        bcc lcx_n
        cmp #$5f
        bne lcx_e
lcx_n:  inx
        bne lx_scanhex
lcx_e:  rts
lx_scanbin:
        txa
        jsr lx_peek
        cmp #$30
        beq lcb_n
        cmp #$31
        beq lcb_n
        cmp #$5f
        bne lcb_e
lcb_n:  inx
        bne lx_scanbin
lcb_e:  rts

; Die Mnemonikliste steht im Assembler (mn_find, ausserhalb dieser Datei); MN_TOK ist der Suchpuffer (4 Byte, gross, mit 0
; aufgefuellt).
; Namen mit mehr als 4 Zeichen sind nie Mnemonik.
; lx_ismn: ist der Bezeichner am aktuellen Zeichen (lx_len Zeichen) eine Mnemonik? Carry geloescht = ja
lx_ismn:
        lda lx_len
        cmp #$05
        bcs lm_no
        ldx #$03                    ; 4 Zeichen, gross, mit 0 aufgefuellt
        lda #$00
lm_z:   sta MN_TOK,x
        dex
        bpl lm_z
        lda #$00
        sta ed_mi
lm_c:   lda ed_mi
        cmp lx_len
        beq lm_f
        jsr lx_peek
        cmp #$61
        bcc lm_u
        and #$df
lm_u:   ldx ed_mi
        sta MN_TOK,x
        inc ed_mi
        lda ed_mi
        jmp lm_c
lm_f:   lda MN_TOK                  ; NOP ist ein anderer Name fuer EOM
        cmp #$4e
        bne lm_g
        lda MN_TOK + 1
        cmp #$4f
        bne lm_g
        lda MN_TOK + 2
        cmp #$50
        bne lm_g
        lda MN_TOK + 3
        beq lm_yes
lm_g:   jsr mn_find
        rts
lm_yes: clc
        rts
lm_no:  sec
        rts

; =====================================================================================================================
; ASCII -> BILDSCHIRMCODE (Kleinbuchstabensatz)
; =====================================================================================================================
; asc2scr: Eingabe A = ASCII-Zeichen. Ausgabe A = Bildschirmcode im Zeichensatz mit Kleinbuchstaben; was sich nicht darstellen
; laesst
; ($00-$1F, $60 `, $7B-$7F), wird zum Punkt ($2E). Bildschirmcodes: @ = $00, a-z = $01-$1A, [ \ ] ^ _ = $1B-$1F, $20-$3F und
; A-Z gleich ASCII.
; ---- ASCII -> Bildschirmcode (Kleinbuchstabensatz); nicht darstellbar: Punkt
asc2scr:
        cmp #$20
        bcc a2_dot
        cmp #$7f
        bcs a2_dot
        cmp #$40
        bcc a2_r                    ; $20..$3f gleich
        beq a2_at
        cmp #$5b
        bcc a2_r                    ; A-Z bleibt $41-$5a
        cmp #$60
        bcc a2_sym                  ; [ \ ] ^ _ -> $1b-$1f
        beq a2_dot                  ; ` gibt es nicht
        cmp #$7b
        bcc a2_lo                   ; a-z -> $01-$1a
        bcs a2_dot                  ; { | } ~
a2_at:  lda #$00
        rts
a2_sym: sec
        sbc #$40
        rts
a2_lo:  sec
        sbc #$60
        rts
a2_dot: lda #$2e
a2_r:   rts

; =====================================================================================================================
; DATEN (alle Zellen ausserhalb der Zeropage; Mehrbytewerte little endian)
; =====================================================================================================================
; ed_rows = Zeilen des Bildes (25/50); ed_trows = Textzeilen; ed_hdr/ed_ftr = Kopf-/Fusszeilen; gs/ge/cur/top/len =
; 32-Bit-Positionen
; (siehe Kopf); ed_curline/ed_topline = Zeilennummern; ed_left = erste sichtbare Spalte; ed_colv = Spalte der Cursorzeile;
; ed_dl/ed_dr/ed_rp = Zeichen-Schleifenzellen (Zeilennummer, Textzeile, Bildzeile-Zeiger); ed_cc = Spalte beim Zeichnen; ed_dd
; = Fensterspalte;
; ed_lim = Hilfsgrenze (Scroll); ed_gw = Hilfszaehler (goto_want); ed_pg = Zaehler Bild auf/ab; ed_ind = Einrueckung (Return);
; ed_exist = 1, solange der Text noch Zeilen hat (Zeichnen); ed_ny = Startspalte put_num4; num_d = Ziffern; ed_ao = Offset in
; ed_scr (dw_attrptr);
; ed_bb2/ed_bb3 = Pufferbank (Attic); ed_hb2/ed_hb3 = Verlaufsbank; ed_abase = 32-Bit-Basis der Attribute; ed_sel/ed_sf =
; Auswahl aktiv /
; Farbbit des aktuellen Zeichens; ed_anc/ed_ss/ed_se = Anker, Auswahlanfang, -ende; ed_cblen = Laenge der Zwischenablage.
; ed_pat/ed_rep (je 32 Byte) = Suchmuster und Ersatztext; ed_patn/ed_repn = ihre Laengen; rp_cnt = Ersetzungen; ed_garg =
; Zeilenziel (Gehe-zu);
; fp = Suchposition; ez_fcnt = 32-Bit-Zaehler; ez_fi = Mustermarke; fa = Vergleichszeichen; fl = Zeilenzaehler (ed_goto);
; ed_k = Tastencode; ed_kd/ed_lastkind = Art der Taste und der Vorgaengertaste; ed_grp = Gruppennummer; ed_logon = Mitschrift an;
; hp/hn = Verlaufsstelle/-ende; h_* = Eintragsfelder (h_type, h_byte, h_g/h_grp = Gruppe des Eintrags/der Gruppe, h_pos =
; Stelle, h_cb/h_ca = Cursor
; vorher/nachher, h_last = Cursor am Ende von Undo/Redo, h_rev = Richtung); lx_* = Lexerzustand; ed_ch/ed_cl = Zeichen und
; Farbe; ed_mi = Index (lx_ismn);
; lx_pk = Vorausschau-Abstand; ed_src/ed_cnt = Quelladresse und Zahl der Bytes fuer ed_load. Mit IDE_BSS stehen ed_pat/ed_rep
; im Datenbereich der IDE.
; ---- Daten
ed_rows: .byte 25
ed_erl:  .byte 0                    ; 1: gerade gezeichnete Zeile ist eine Fehlerzeile
ed_en:   .byte 0                    ; Zahl der Fehlerzeilen (hoechstens 16), von ide_emark gefuellt
ed_ehp:  .word 0                    ; Textstand (hp), zu dem die Fehlerzeilen gehoeren
ed_elo:  .fill 16, 0
ed_ehi:  .fill 16, 0
ed_deco: .byte 0                    ; 1: Schmuck der IDE (Zeilenstrich, Cursorzeilenmarke, Statusleiste); Tests laufen mit 0
ed_hdr:  .byte 0                    ; Kopfzeilen (ed_layout)
ed_ftr:  .byte 0                    ; Fusszeilen
ed_trows: .byte 24                  ; Textzeilen
ed_gs:   .fill 4, 0
ed_ge:   .fill 4, 0
ed_cur:  .fill 4, 0
ed_top:  .fill 4, 0
ed_len:  .fill 4, 0
ed_curline: .word 1
ed_topline: .word 1
ed_left: .word 0
ed_want: .word $ffff
ed_colv: .word 0
ed_dl:   .word 0
ed_dr:   .byte 0
ed_pg:   .byte 0
ed_ind:  .byte 0
ed_exist: .byte 1
ed_ny:   .byte 0
ed_lim:  .word 0
ed_cc:   .word 0
ed_dd:   .byte 0
ed_rp:   .word 0
num_d:   .fill 4, 0
ed_gw:   .word 0
ed_bb2:  .byte EB2                    ; Pufferanfang (Byte 2 und 3 der Attic-Adresse)
ed_bb3:  .byte EB3
ed_hb2:  .byte HB2
ed_hb3:  .byte HB3
ed_ao:   .word 0
ed_abase: .byte <ED_ATTR32, >ED_ATTR32, <(ED_ATTR32 >> 16), >(ED_ATTR32 >> 16)
ed_sel:  .byte 0
ed_sf:   .byte 0
ed_anc:  .fill 4, 0
ed_ss:   .fill 4, 0
ed_se:   .fill 4, 0
ed_cblen: .fill 4, 0
.ifndef IDE_BSS
ed_pat:  .fill 32, 0
ed_rep:  .fill 32, 0                 ; Ersatztext (ed_repl_all)
.endif
ed_repn: .byte 0
rp_cnt:  .word 0                    ; Zahl der Ersetzungen
ed_patn: .byte 0
ed_garg: .word 0
fp:      .fill 4, 0
ez_fcnt:    .fill 4, 0
ez_fi:      .byte 0
fa:      .byte 0
fl:      .word 0
ed_k:    .byte 0
ed_kd:   .byte 0
ed_lastkind: .byte 0
ed_grp:  .word 0
ed_logon: .byte 1
hp:      .word 0
hn:      .word 0
h_idx:   .word 0
h_type:  .byte 0
h_byte:  .byte 0
h_rev:   .byte 0
h_g:     .word 0
h_grp:   .word 0
h_pos:   .fill 4, 0
h_cb:    .fill 4, 0
h_ca:    .fill 4, 0
h_last:  .fill 4, 0
lx_first: .byte 0
lx_state: .byte 0
lx_rem: .byte 0
lx_tok: .byte 0
lx_len: .byte 0
ed_ch:   .byte 0
ed_cl:   .byte 0
ed_mi:   .byte 0
lx_pk:   .byte 0
ed_src:  .word 0
ed_cnt:  .word 0
