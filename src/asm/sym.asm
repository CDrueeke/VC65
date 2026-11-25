; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; sym.asm - Bezeichner lesen und Symboltabelle (Eintraege im Attic-RAM ab $0810_0000, Suche ueber eine Hash-Tabelle).
; Eintrag: Laenge (1), Name (Laenge Byte), Wert alt (4), Wert neu (4), Flags (1). SYME zeigt hinter den letzten Eintrag.
; read_ident: liest [A-Za-z0-9_.]* ab SRC nach NAMEBUF/NAMELEN (hoechstens 31 Zeichen).
; sym_find: sucht NAMEBUF; Carry geloescht = gefunden (SYMP zeigt auf den Eintrag), sonst Carry gesetzt.
; Werte je Eintrag: alt (vorheriger Durchlauf) und neu (dieser Durchlauf), siehe unten.
;
; Rolle im Assembler: Marken (Labels) und Konstanten (name = wert) werden hier abgelegt; Variablen (.var), Scopes und Makros
; kennt stage2.asm (sym_resolve); expr.asm ruft beim Auswerten eines Bezeichners sym_lookup_ref, asm.asm (Zeilenanalyse) ruft
; sym_define fuer Marken und Konstanten, sym_end_pass am Ende jedes Durchlaufs, sym_init vor dem ersten Durchlauf. enc.asm
; benutzt sym_find/sym_getnew/sym_known_old fuer die anonymen Marken - und +. Fehler: soft_err (weicher Fehler, siehe unten).
;
; Mehrdurchlauf-Prinzip: Der Assembler uebersetzt so oft, bis sich kein Symbolwert mehr aendert (Flag CHG, siehe sym_end_pass).
; Jedes Symbol hat deshalb zwei Werte: ALT (Wert des vorigen Durchlaufs, damit Vorwaertsreferenzen schon beim zweiten Durchlauf
; stimmen) und NEU (in diesem Durchlauf beim Definieren berechnet). Ausdruecke lesen immer ALT (sym_getval); bei Rueckwaerts-
; marken (anonym '-') liest enc.asm gezielt NEU (sym_getnew).
;
; Speicher: Symboltabelle im Attic-RAM ab $0810_0000 (SYM_B3:SYM_B2:$0000, Konstanten in zp.asm), nach oben angehaengt (SYME =
; Ende); Eintrag = Laenge(1) Name(n) Alt(4) Neu(4) Flags(1), also n + 10 Byte. Flags: Bit0 = im vorigen Durchlauf definiert,
; Bit1 = in diesem Durchlauf definiert. Hash-Tabelle fuer die Suche: HBASE in der Stufe-2-Bank (S2BANK), 8192 Plaetze (HMASK)
; zu 2 Byte; Platzinhalt = Eintragsversatz in der Symboltabelle + 1 (0 = frei). Der Versatz hat nur 16 Bit: die Tabelle darf
; hoechstens 64 KB gross werden. Kollision: lineares Sondieren (naechster Platz, ringfoermig); Symbole werden nie geloescht.
; Zeropage: SYMP (32-Bit-Zeiger auf den aktuellen Eintrag, Ergebnis von sym_find), SYME (hinter dem letzten Eintrag), NAMEBUF/NAMELEN
; (Eingabe), VAL (Wert), P6 (Hash-Platz, wird in sym_init/hash_insert zerstoert), S2T und TMP2 als Zwischenspeicher.
; =====================================================================================================================
; sym_init: Symboltabelle leeren (SYME = Anfang) und die Hash-Tabelle (64 Seiten) mit 0 fuellen. Zerstoert A, X, Z, P6.
sym_init:
        lda #$00
        sta SYME
        sta SYME + 1
        lda #SYM_B3
        sta SYME + 3
        lda #SYM_B2
        sta SYME + 2
        lda #$00                    ; Hash-Tabelle leeren
        sta P6
        sta P6 + 3
        lda #>HBASE
        sta P6 + 1
        lda #S2BANK
        sta P6 + 2
        ; Seitenzahl = HMASK + 1 = $2000 Plaetze * 2 Byte / 256 = 64 Seiten; X = ($1f + 1) * 2
        ldx #>HMASK + 1             ; Seiten (Plaetze * 2 Byte / 256)
        txa
        asl
        tax
        ; je Seite 256 Byte per [P6],z (32-Bit-Zeiger, Z = 0..255) loeschen, dann High-Byte von P6 weiter
si1:    ldz #$00
        lda #$00
si2:    sta [P6],z
        inz
        bne si2
        inc P6 + 1
        dex
        bne si1
        rts

; read_ident: Bezeichner [A-Za-z0-9_.]* ab SRC lesen und nach NAMEBUF/NAMELEN uebernehmen (hoechstens 31 Zeichen, Rest wird
; ueberlesen; SRC steht danach hinter dem Bezeichner). Zerstoert A, X und Flags. (Das erste Zeichen wird nicht geprueft.)
read_ident:
        ldx #$00
ri1:    jsr src_peek
        jsr is_identchar
        bcs ri2
        cpx #31
        bcs ri3                     ; zu lang: Rest ueberlesen
        sta NAMEBUF,x
        inx
ri3:    jsr src_adv
        jmp ri1
ri2:    stx NAMELEN
        rts

; is_identchar: Carry geloescht (C=0), wenn A Buchstabe, Ziffer, _ oder . ist, sonst C=1. A bleibt unveraendert. Zerstoert nur Flags.
is_identchar:
        cmp #$30
        bcc ic_no
        cmp #$3a
        bcc ic_yes
        cmp #$41
        bcc ic_no
        cmp #$5b
        bcc ic_yes
        cmp #$5f
        beq ic_yes
        cmp #$61
        bcc ic_no
        cmp #$7b
        bcc ic_yes
ic_no:  cmp #$2e                    ; '.' (liegt unter '0')
        beq ic_yes
        sec
        rts
ic_yes: clc
        rts

; sym_find: Symbol NAMEBUF/NAMELEN in der Hash-Tabelle suchen.
;   Ausgabe : C=0 gefunden, SYMP = Eintrag in der Symboltabelle; C=1 nicht gefunden, hh = freier Hash-Platz zum Einfuegen
;   (SYMP zeigt dann auf den Hash-Platz, nicht auf einen Eintrag; sym_define haengt den Eintrag an SYME). Zerstoert A, X, Z, hv.
sym_find:
        ; Hashwert hh bilden; er bestimmt den ersten Platz
        jsr hash_name
        ; Platzadresse = HBASE + hh * 2 (16 Bit; Carry aus asl wird per rol ins High-Byte geschoben)
sf_pr:  lda hh                      ; Platz im Hash: HBASE + hh * 2 (Bank 4)
        asl
        sta SYMP
        lda hh + 1
        rol
        clc
        adc #>HBASE
        sta SYMP + 1
        lda #S2BANK
        sta SYMP + 2
        lda #$00
        sta SYMP + 3
        ldz #$00
        lda [SYMP],z
        sta hv
        inz
        lda [SYMP],z
        sta hv + 1
        ora hv
        ; Platzinhalt 0: leer (hier endet die Sondierkette)
        beq sf_empty                ; leerer Platz: nicht vorhanden (hh = Platz fuer das Einfuegen)
        ; Eintrag liegt bei Versatz Wert - 1 (der Platzinhalt ist Versatz + 1, damit 0 "leer" heisst)
        lda hv                      ; Eintrag = $0810_0000 + (Wert - 1)
        sec
        sbc #$01
        sta SYMP
        lda hv + 1
        sbc #$00
        sta SYMP + 1
        lda #SYM_B2
        sta SYMP + 2
        lda #SYM_B3
        sta SYMP + 3
        ; Name vergleichen: erst Laenge (Z = 0), dann Zeichen fuer Zeichen (Z hinter dem Laengenbyte)
        ldz #$00
        lda [SYMP],z
        cmp NAMELEN
        bne sf_nx
        inz
        ldx #$00
sf_c:   cpx NAMELEN
        beq sf_found
        lda [SYMP],z
        cmp NAMEBUF,x
        bne sf_nx
        inz
        inx
        bne sf_c
sf_found:
        clc
        rts
        ; nicht der gesuchte Eintrag: naechster Platz; Ueberlauf von 8191 nach 0 durch Maskieren des High-Bytes
sf_nx:  inc hh                      ; naechster Platz (linear sondieren, ringfoermig)
        bne sf_pr
        inc hh + 1
        lda hh + 1
        and #>HMASK
        sta hh + 1
        jmp sf_pr
sf_empty:
        sec
        rts

; hash_name: Hashwert des Namens bilden.
;   Eingabe : NAMEBUF/NAMELEN. Ausgabe: hh = Platznummer 0..HMASK. Zerstoert A, X, Y.
;   Verfahren: hh = Laenge; je Zeichen: hh = rotl3(hh) + Zeichen (16-Bit-Rotation, das herausgeschobene Bit kommt unten wieder rein),
;   zuletzt mit HMASK maskieren.
hash_name:
        lda NAMELEN
        sta hh
        lda #$00
        sta hh + 1
        ldx #$00
hn1:    cpx NAMELEN
        beq hn2
        ; 16-Bit-Linksrotation um 3 Bit: asl/rol, ein ausgeschobenes Bit wird unten per inc zurueckgegeben (Bit 0 ist nach asl 0)
        ldy #$03                    ; um 3 Bit nach links drehen, dann das Zeichen addieren
hn3:    asl hh
        rol hh + 1
        bcc hn4
        inc hh
hn4:    dey
        bne hn3
        lda hh
        clc
        adc NAMEBUF,x
        sta hh
        bcc hn5
        inc hh + 1
hn5:    inx
        bne hn1
hn2:    lda hh + 1
        and #>HMASK
        sta hh + 1
        rts

; hash_insert: Eintrag in den Hash-Platz eintragen.
;   Eingabe : SYMP = neuer Eintrag (32 Bit), hh = freier Platz (aus dem vorangehenden sym_find). Zerstoert A, P6; Z bleibt (phz/plz).
;   Platzinhalt = Versatz (SYMP, 16 Bit) + 1.
hash_insert:
        phz
        lda hh
        asl
        sta P6
        lda hh + 1
        rol
        clc
        adc #>HBASE
        sta P6 + 1
        lda #S2BANK
        sta P6 + 2
        lda #$00
        sta P6 + 3
        ldz #$00
        ; Versatz + 1 in den Platz schreiben (Low, dann High-Byte; Carry laeuft hinein)
        lda SYMP                    ; Wert = Versatz + 1
        clc
        adc #$01
        sta [P6],z
        inz
        lda SYMP + 1
        adc #$00
        sta [P6],z
        plz
        rts

; Arbeitszellen: hh = Hashwert/Platz, hv = Platzinhalt
hh:     .word 0
hv:     .word 0

; sym_next: SYMP auf den naechsten Eintrag stellen (Groesse = Laenge + 10). Zerstoert A, Z. Zeiger 24 Bit, Bank bleibt gleich.
sym_next:
        ldz #$00
        lda [SYMP],z
        clc
        adc #$0a
        clc
        adc SYMP
        sta SYMP
        bcc sn1
        inc SYMP + 1
        bne sn1
        inc SYMP + 2
sn1:    rts

; sym_flagpos: Z = Versatz des Flagbytes im Eintrag bei SYMP (Laenge + 9). Zerstoert A, Z.
sym_flagpos:
        ldz #$00
        lda [SYMP],z
        clc
        adc #$09
        taz
        rts

; sym_getval: VAL = ALTER Wert (Offset Laenge + 1); sym_getnew: VAL = NEUER Wert (Offset Laenge + 5). Eingabe SYMP. Zerstoert A, Z.
sym_getval:
        ldz #$00
        lda [SYMP],z
        clc
        ; Laenge + 1 ist nie 0 (Laenge <= 31), daher bne immer genommen (Sprung statt bra)
        adc #$01
        bne sg_rd
sym_getnew:
        ldz #$00
        lda [SYMP],z
        clc
        adc #$05
sg_rd:  taz
        lda [SYMP],z
        sta VAL
        inz
        lda [SYMP],z
        sta VAL + 1
        inz
        lda [SYMP],z
        sta VAL + 2
        inz
        lda [SYMP],z
        sta VAL + 3
        rts

; sym_define: Symbol NAMEBUF mit Wert VAL als NEUEN Wert anlegen (Eintrag wird bei Bedarf erzeugt).
;   Fehler: in diesem Durchlauf schon mit anderem Wert definiert: weicher Fehler E204 (der Wert wird trotzdem ueberschrieben).
;   Ausgabe: SYMP = Eintrag. Zerstoert A, X, Z, P6, S2T, hh, hv.
sym_define:
        jsr sym_find
        ; vorhanden: nur Wert ersetzen
        bcc sd_have
        ; Neuer Eintrag: [Laenge][Name][Alt = 0][Neu = 0][Flags = 0] an SYME schreiben, im Hash eintragen und SYME weiterschieben
        ldz #$00                    ; neuer Eintrag am Ende: Name, alter Wert 0, Flags 0
        lda NAMELEN
        sta [SYME],z
        inz
        ldx #$00
sd_n:   cpx NAMELEN
        beq sd_v
        lda NAMEBUF,x
        sta [SYME],z
        inz
        inx
        bne sd_n
        ; Z steht hinter dem Namen: 9 Nullbytes (Alt, Neu, Flags)
sd_v:   ldx #$09                    ; alt (4) + neu (4) + Flags (1) mit 0 fuellen
        lda #$00
sd_z:   sta [SYME],z
        inz
        dex
        bne sd_z
        ; SYMP := Anfang des neuen Eintrags (32 Bit), SYME bleibt noch dort
        lda SYME                    ; SYMP = neuer Eintrag, SYME hinter ihn
        sta SYMP
        lda SYME + 1
        sta SYMP + 1
        lda SYME + 2
        sta SYMP + 2
        lda SYME + 3
        sta SYMP + 3
        ; hash_insert benutzt hh aus dem sym_find (freier Platz); danach SYME += Eintragsgroesse (Z = Laenge + 10 nach sd_v)
        jsr hash_insert             ; Eintrag im Hash eintragen
        tza
        clc
        adc SYME
        sta SYME
        bcc sd_have
        inc SYME + 1
        bne sd_have
        inc SYME + 2
        ; Wert-Versatz = Laenge + 5 (S2T); Flagbyte = Laenge + 9 (4 Byte weiter)
sd_have:
        ldz #$00
        lda [SYMP],z
        clc
        adc #$05
        sta S2T                     ; Versatz des neuen Werts
        clc
        adc #$04
        taz
        lda [SYMP],z                ; in diesem Durchlauf schon definiert? Dann muss der Wert gleich sein (sonst E204)
        and #$02
        beq sd_ok
        lda S2T
        taz
        ldx #$00
        ; gleicher Wert wie vorher in diesem Durchlauf? (4 Byte vergleichen)
sd_cmp: lda [SYMP],z
        cmp VAL,x
        bne sd_dup
        inz
        inx
        cpx #$04
        bne sd_cmp
        jmp sd_ok
        ; mehrfach definiert mit anderem Wert (z. B. doppelte Marke); weich melden, Neuwert wird dennoch geschrieben
sd_dup: lda #ERR_E204
        jsr soft_err
sd_ok:  lda S2T
        taz                         ; Versatz des neuen Werts
        ldx #$00
sd_w:   lda VAL,x
        sta [SYMP],z
        inz
        inx
        cpx #$04
        bne sd_w
        ; Flagbyte folgt unmittelbar auf den Wert: Bit1 = in diesem Durchlauf definiert
        lda [SYMP],z                ; Flagbyte folgt unmittelbar
        ora #$02
        sta [SYMP],z
        rts

; sym_known_old: C=0, wenn NAMEBUF im vorigen Durchlauf definiert war (Flags Bit0), dann VAL = alter Wert; sonst C=1.
;   (Heisst in aelteren Kommentaren sym_lookup_old.) Zerstoert A, X, Z, hv, hh, SYMP.
sym_known_old:
        jsr sym_find
        bcs sko_no
        jsr sym_flagpos
        lda [SYMP],z
        and #$01
        beq sko_no
        jsr sym_getval
        clc
        rts
sko_no: sec
        rts

; sym_defined_new: C=0, wenn NAMEBUF in diesem Durchlauf schon definiert wurde (Flags Bit1; fuer .ifdef/.ifndef). Zerstoert wie oben.
sym_defined_new:
        jsr sym_find
        bcs sdn_no
        jsr sym_flagpos
        lda [SYMP],z
        and #$02
        beq sdn_no
        clc
        rts
sdn_no: sec
        rts

; sym_end_pass: am Ende jedes Durchlaufs ALT := NEU fuer alle Eintraege und Flags aktualisieren: Bit1 (diesen Durchlauf definiert)
;   wird in Bit0 uebernommen, Bit1 geloescht. CHG = 1, wenn sich ein Wert geaendert hat, ein Symbol neu hinzukam oder weggefallen ist
;   (dann ist ein weiterer Durchlauf noetig). Durchlaeuft die Tabelle linear von Anfang bis SYME. Zerstoert A, X, Z, TMP2, SYMP.
sym_end_pass:
        lda #$00
        sta SYMP
        sta SYMP + 1
        lda #SYM_B3
        sta SYMP + 3
        lda #SYM_B2
        sta SYMP + 2
sep_l:  lda SYMP
        cmp SYME
        bne sep_go
        lda SYMP + 1
        cmp SYME + 1
        bne sep_go
        lda SYMP + 2
        cmp SYME + 2
        bne sep_go
        rts
        ; Flagbyte: Z = Laenge + 9; neu liegt bei Z - 4, alt bei Z - 8
sep_go: jsr sym_flagpos             ; Z = Flagbyte, davor neu (4) und alt (4)
        lda [SYMP],z
        sta TMP2                    ; Flags
        and #$02
        beq sep_undef
        ; in diesem Durchlauf definiert; war es vorher auch (Bit0)? Dann alt/neu vergleichen
        lda TMP2                    ; in diesem Durchlauf definiert: war es vorher auch? gleicher Wert?
        and #$01
        bne sep_cmp
        lda #$01                    ; neu hinzugekommen
        sta CHG
        jmp sep_copy
        ; (sep_cmp) vier Bytes alt und neu vergleichen: Z auf alt, nach 4 Byte weiter auf neu; X zaehlt 4
sep_cmp:
        tza
        sec
        sbc #$08                    ; Versatz des alten Werts
        taz
        ldx #$04
sep_c1: lda [SYMP],z
        sta TMP2 + 1                ; alt
        tza
        clc
        adc #$04
        taz
        lda [SYMP],z                ; neu
        cmp TMP2 + 1
        beq sep_same
        lda #$01
        sta CHG
sep_same:
        tza
        sec
        sbc #$03
        taz
        dex
        bne sep_c1
        ; Z zurueck auf das Flagbyte
        jsr sym_flagpos
        ; neu -> alt kopieren: Z auf neu, je Byte: lesen, 4 zurueck (alt), schreiben, 5 vor (naechstes neu)
sep_copy:
        tza
        sec
        sbc #$04                    ; Versatz des neuen Werts
        taz
        ldx #$04
sep_cp: lda [SYMP],z                ; neu lesen
        pha
        tza
        sec
        sbc #$04
        taz
        pla
        sta [SYMP],z                ; nach alt schreiben
        tza
        clc
        adc #$05
        taz
        dex
        bne sep_cp
        ; Flags := 1 (vorher definiert, jetzt nicht mehr "in diesem Durchlauf")
        jsr sym_flagpos
        lda #$01                    ; definiert im vorigen Durchlauf, nicht in diesem
        sta [SYMP],z
        jmp sep_next
        ; in diesem Durchlauf nicht definiert: wenn es im vorigen definiert war, hat sich die Symbolmenge geaendert
sep_undef:
        lda TMP2                    ; in diesem Durchlauf nicht definiert: war es vorher definiert, ist die Menge anders
        and #$01
        beq sep_next
        lda #$01
        sta CHG
        lda #$00
        sta [SYMP],z
sep_next:
        jsr sym_next
        jmp sep_l

; mangle: lokaler Name ".x" -> "<globale Marke>.x" (in NAMEBUF/NAMELEN); CURG/CURGL = Name der aktuellen globalen Marke.
;   Ohne globale Marke (CURGL = 0) bleibt der Name unveraendert. Zu lang (zusammen > 31 Zeichen): E203 (harter Fehler).
;   Zerstoert A, X, Y, mbuf.
mangle: lda CURGL
        beq mg_done
        ; Laenge pruefen: CURGL + NAMELEN muss < 32 sein (Namenspuffer NAMEBUF hat 32 Byte)
        clc
        adc NAMELEN
        cmp #$20
        bcs mg_long
        ; erst die globale Marke nach mbuf, dann den lokalen Namen dahinter, dann alles zurueck nach NAMEBUF
        ldx #$00
mg1:    cpx CURGL
        beq mg2
        lda CURG,x
        sta mbuf,x
        inx
        bne mg1
mg2:    ldx #$00
        ldy CURGL
mg3:    cpx NAMELEN
        beq mg4
        lda NAMEBUF,x
        sta mbuf,y
        inx
        iny
        bne mg3
mg4:    sty NAMELEN
        ldx #$00
mg5:    cpx NAMELEN
        beq mg_done
        lda mbuf,x
        sta NAMEBUF,x
        inx
        bne mg5
mg_done:
        rts
mg_long:
        lda #ERR_E203
        jmp as_error
; mbuf: Zwischenpuffer fuer mangle (32 Byte)
mbuf:   .fill 32, 0

; sym_lookup_ref: Wert des Bezeichners NAMEBUF (ALTER Wert; Aufruf aus expr.asm) nach VAL/VFR/VTY. Unbekannt: UNK = 1, Wert 0.
;   Unbekannt ist ausser im Test (PASS = 0) nie sofort ein Fehler, sondern nur ein weicher Fehler E202, der erst im letzten
;   Durchlauf zaehlt (die Liste gehoert dem letzten Durchlauf). Zerstoert A, X, Y, Z u. a.; kehrt mit rts zurueck.
sym_lookup_ref:
        ; Suchreihenfolge: Variablen und Scopes (stage2.asm), dann die Konstante pi, dann Fehler (unbekannt)
        jsr sym_resolve             ; Stufe 2: Variablen und Scopes; Carry geloescht = gefunden
        bcs sl_none
        rts
sl_none:
        jsr sym_pi                  ; pi
        bcc sl_pi
        lda #$00
        ; VTY = 0: Ganzzahl; unbekannt: Wert 0 und UNK = 1 (der Aufrufer rechnet im ersten Durchlauf weiter)
        sta VTY
        lda #$01
        sta UNK
        lda #$00
        sta VAL
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        ; PASS = 0: Einzeltest des Ausdrucksrechners, kein Assembler-Durchlauf
        lda PASS
        bne sl_soft
        lda #ERR_E202               ; Einzeltest des Ausdrucksrechners: sofortiger Fehler
        jmp ex_error
sl_soft:
        lda #ERR_E202
        jmp soft_err

sl_pi:  rts

; sym_pi: Name "pi" -> VAL/VFR/VTY (Carry geloescht), sonst Carry gesetzt
sym_pi: lda NAMELEN
        cmp #$02
        bne spi_no
        lda NAMEBUF
        cmp #$70
        bne spi_no
        lda NAMEBUF + 1
        cmp #$69
        bne spi_no
        lda #$03
        sta VAL
        lda #$00
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        lda #$88                    ; 3.14159265... = 3 + $243F6A88 / 2^32
        sta VFR
        lda #$6a
        sta VFR + 1
        lda #$3f
        sta VFR + 2
        lda #$24
        sta VFR + 3
        lda #$01
        sta VTY
        clc
        rts
spi_no: sec
        rts

; soft_err: Fehler A in die Fehlerliste (weicher Fehler), weiter. Die Uebersetzung der Zeile laeuft weiter (anders als as_error,
;   das die Zeile abbricht); err_add zeichnet Code und Stelle (SRC) auf. Zerstoert wie err_add (X). Kehrt ueber err_add (jmp) zurueck.
soft_err:
        jmp err_add
