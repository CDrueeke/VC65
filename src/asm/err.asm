; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; err.asm - Fehlerliste: der Assembler bricht bei einem Fehler nicht mehr ab, sondern merkt ihn (Code und Stelle im
; Quelltext), ueberspringt den Rest der Zeile und uebersetzt weiter. Die Liste gehoert dem letzten Durchlauf (sie wird
; zu Beginn jedes Durchlaufs geleert). Bank 4 ELIST: je Eintrag 8 Byte: Code (1), Dateinummer (1), 2 frei, Quelltextstelle (32 Bit).
; Fehler in einem Makrorumpf werden der Aufrufzeile zugeschrieben. err_linecol liefert Zeile und Spalte (ab 1).
;
; Rolle: Fehler werden von allen Modulen (asm.asm, enc.asm, sym.asm, expr.asm, stage2.asm, cyc.asm ...) ueber err_add gemeldet
; (A = Code, SRC = Stelle). asm.asm leert die Listen zu Beginn jedes Durchlaufs (ercnt/wcnt = 0), wertet nach dem letzten
; Durchlauf ercnt aus und laesst die IDE die Eintraege mit err_linecol in Zeile/Spalte umrechnen. Es gibt zwei getrennte Listen
; mit gleichem Aufbau: Fehler (lsel = 0, ELIST, bis EMAX Eintraege) und Warnungen (lsel = 1, WLIST, bis WMAX Eintraege).
; Ueberzaehlige Meldungen werden stillschweigend verworfen (die Zaehler stoppen bei EMAX bzw. WMAX).
;
; Speicher: beide Listen liegen in der Stufe-2-Bank S2BANK (siehe stage2.asm), Eintrag n bei Liste + n * 8:
;   +0 Fehlercode (ERR_*, siehe zp.asm)   +1 Dateinummer (curfile; 0 = Hauptprogramm, sonst Index in filebase)
;   +2,+3 unbenutzt (0)                   +4..+7 Quelltextstelle als 32-Bit-Zeiger (Bank, Adresse, wie SRC)
; Zeropage: err_add/warn_add benutzen P6 ($00-$03) als Zeiger auf den Eintrag und sichern P6, P7 und FP ($00-$0B, 12 Byte) in
; esv; das Z-Register wird mit phz/plz gerettet. err_linecol dagegen ueberschreibt SRC (Zeiger auf das aktuelle Quelltextzeichen)
; und P6 und ist nur nach dem Durchlauf (bei der Anzeige) aufzurufen.
; Zeile/Spalte werden nicht gespeichert, sondern bei Bedarf durch Abzaehlen der Zeilenenden ($0A) vom Dateianfang her gewonnen.
; =====================================================================================================================
ELIST   = $6000
EMAX    = 100
WLIST   = $6400
WMAX    = 100
WARN_W200 = $20                     ; .warning (Meldung des Anwenders)
WARN_W201 = $21                     ; Zyklenbudget ueberschritten
WARN_W202 = $22                     ; Kommazahl auf Ganzzahl abgeschnitten (int(), round() oder floor() verwenden)
WARN_W203 = $23                     ; Sprung zu weit: lange Form verwendet (.branchlong auto)

; err_add: Fehler vermerken.
;   Eingabe : A = Fehlercode, SRC = Stelle des Fehlers (32 Bit); bei Meldung im Makrorumpf zaehlt statt dessen die Aufrufzeile
;   Ausgabe : A = Fehlercode (unveraendert); Carry nicht definiert
;   Zerstoert: X (und Flags); Y, Z, P6, P7, FP bleiben erhalten. Bricht nicht ab - der Aufrufer ueberspringt selbst den Rest.
;   Liste voll (ercnt >= EMAX): der Eintrag entfaellt.
err_add:
        sta etmp                    ; etmp = Code zwischenspeichern (A wird gleich gebraucht)
        lda #$00
        sta lsel                    ; lsel = 0: Fehlerliste waehlen
        beq ea_go                   ; immer erfuellt (A = 0): Sprung in den gemeinsamen Teil

; warn_add: wie err_add, aber in die Warnungsliste (WLIST, Zaehler wcnt); Warnungen aendern das Ergebnis des Assemblers nicht.
;   Ein- und Ausgabe, Register: wie err_add.
warn_add:
        sta etmp
        lda #$01                    ; lsel = 1: Warnungsliste waehlen
        sta lsel
        ; Gemeinsamer Teil: P6/P7/FP (12 Byte ab $00) sichern, weil Aufrufer (z. B. Makro-/Rahmenverwaltung) sie gerade benutzen
ea_go:  phz
        ldx #$0b                    ; P6, P7 und FP retten (die Aufrufer koennen sie gerade brauchen)
ea0:    lda P6,x
        sta esv,x
        dex
        bpl ea0
        ldx lsel                    ; X = Listennummer (0/1) fuer ercnt,x und lbase,x
        lda ercnt,x
        cmp #EMAX
        bcs ea_done                 ; Liste voll: Meldung verwerfen
        ; Eintragsadresse (16 Bit) = Liste + Zaehler * 8: Low-Byte = Zaehler * 8 (Ueberlauf faellt weg),
        ; High-Byte = Zaehler / 32 + lbase
        asl
        asl
        asl
        sta P6                      ; Eintrag = Liste + Zaehler * 8
        lda ercnt,x
        ; (Zaehler < 100, also Zaehler/32 <= 3)
        lsr
        lsr
        lsr
        lsr
        lsr
        clc
        adc lbase,x
        sta P6 + 1
        lda #S2BANK
        sta P6 + 2                  ; Bank des Eintrags
        lda #$00
        sta P6 + 3                  ; 32-Bit-Zeiger vollstaendig: Bits 24..31 = 0
        ; Quelltextstelle bestimmen: in einem Makroaufruf (inmc <> 0, Argumente werden gerade eingesetzt) steht die Stelle in mret
        lda inmc                    ; Fehler beim Aufbau eines Makroaufrufs: Aufrufzeile
        beq ea_s
        ldx #$03
ea_m:   lda mret,x
        sta epos,x
        dex
        bpl ea_m
        jmp ea_w
        ; sonst SRC kopieren (4 Byte in epos); X laeuft rueckwaerts, bpl endet nach X = 0
ea_s:   ldx #$03                    ; Stelle = SRC
er_ea1:    lda SRC,x
        sta epos,x
        dex
        bpl er_ea1
        ; Liegt SRC im Expansionspuffer ($7000-$BFFF der Bank S2BANK), so waere die Stelle fuer den Benutzer wertlos: dann
        ; Zeile des ersten (aeussersten) Makroaufrufs nehmen. Rahmen von unten (aeltester) nach oben durchsuchen.
        lda SRC + 2                 ; liegt SRC im Makropuffer?
        cmp #S2BANK
        bne ea_w
        lda SRC + 3
        bne ea_w
        lda SRC + 1
        cmp #>EXPBASE
        bcc ea_w
        cmp #>HBASE
        bcs ea_w
        lda #$00                    ; ersten Makro-Rahmen suchen: dessen Rueckkehrstelle ist die Aufrufzeile
        sta eidx
ea2:    lda eidx
        cmp fcnt
        bcs ea_w
        ; fr_addr: A = Rahmennummer -> FP zeigt auf den Rahmen (stage2.asm)
        jsr fr_addr
        ldz #F_TYPE
        lda [FP],z
        cmp #FT_MAC
        beq ea3
        inc eidx
        jmp ea2
        ; F_A = Rueckkehrstelle des Makroaufrufs (32 Bit): Stelle direkt hinter dem Aufruf in der Datei
ea3:    ldz #F_A
        ldx #$00
ea4:    lda [FP],z
        sta epos,x
        inz
        inx
        cpx #$04
        bne ea4
        ; Eintrag schreiben: +0 Code, +1 Datei, +2/+3 = 0, +4..+7 Stelle. Z indiziert den 32-Bit-Zeiger [P6],z
ea_w:   ldz #$00
        lda etmp
        sta [P6],z
        inz
        lda curfile                 ; Nummer der Datei (0 = Hauptprogramm)
        sta [P6],z
        lda #$00
        inz
        sta [P6],z
        inz
        sta [P6],z
        inz
        ldx #$00
ea5:    lda epos,x
        sta [P6],z
        inz
        inx
        cpx #$04
        bne ea5
        ; Zaehler der gewaehlten Liste erhoehen
        ldx lsel
        inc ercnt,x
ea_done:
        ; Ausgang: gesicherte Zeiger zurueckschreiben, Z wiederherstellen, A = Fehlercode
        ldx #$0b
ea6:    lda esv,x
        sta P6,x
        dex
        bpl ea6
        plz
        lda etmp
        rts

; err_ptr: Adresse eines Listeneintrags berechnen.
;   Eingabe : A = Eintragsnummer (0..99), lsel = Liste (0 Fehler, 1 Warnungen)
;   Ausgabe : P6 = 32-Bit-Zeiger auf den Eintrag (Bank S2BANK)
;   Zerstoert: A, Flags; X bleibt erhalten (phx/plx)
;   Rechenweg wie in err_add (Nummer * 8, Ueberlauf ins High-Byte als Nummer / 32 plus Listenbasis).
err_ptr:
        pha
        asl
        asl
        asl
        sta P6
        pla
        lsr
        lsr
        lsr
        lsr
        lsr
        phx
        ldx lsel                    ; Liste waehlen: lsel 0 = Fehler, 1 = Warnungen
        clc
        adc lbase,x
        plx
        sta P6 + 1
        lda #S2BANK
        sta P6 + 2
        lda #$00
        sta P6 + 3
        rts

; err_linecol: Zeile und Spalte eines Listeneintrags bestimmen.
;   Eingabe : A = Eintragsnummer, lsel = Liste
;   Ausgabe : eline = Zeile (16 Bit, ab 1), ecol = Spalte (16 Bit, ab 1); Stelle nicht im Quelltext (z. B. Ende der Datei): eline = 0
;   Zerstoert: A, X, Y, Z, P6, SRC, epos, ebase
;   Verfahren: SRC ab Dateianfang (filebase) Zeichen fuer Zeichen vorwaerts schieben (src_peek/src_adv), bis SRC = Fehlerstelle;
;   dabei Spalte bei jedem Zeichen erhoehen und bei Zeilenende ($0A) Zeile erhoehen und Spalte auf 1 setzen. Langsam (linear),
;   aber nur fuer die wenigen angezeigten Fehler noetig.
err_linecol:
        jsr err_ptr
        ldz #$01
        lda [P6],z                  ; Dateinummer -> Anfang der Datei
        ; Dateianfang: filebase (inc.asm) ist eine Tabelle zu 4 Byte (32-Bit-Zeiger) je Datei -> Index = Dateinummer * 4
        asl
        asl
        tax
        ldy #$00
elb:    lda filebase,x
        sta ebase,y
        inx
        iny
        cpy #$04
        bne elb
        ; Fehlerstelle aus dem Eintrag (+4..+7) nach epos
        ldz #$04
        ldx #$00
el0:    lda [P6],z
        sta epos,x
        inz
        inx
        cpx #$04
        bne el0
        ; SRC := Dateianfang; Zeile = Spalte = 1
        ldx #$03
er_el1:    lda ebase,x
        sta SRC,x
        dex
        bpl er_el1
        lda #$01
        sta eline
        sta ecol
        lda #$00
        sta eline + 1
        sta ecol + 1
        ; Schleife: SRC (4 Byte) mit epos vergleichen; gleich = fertig
er_el_l:   ldx #$03
el2:    lda SRC,x
        cmp epos,x
        bne el3
        dex
        bpl el2
        rts
        ; Stelle noch nicht erreicht: src_peek liefert das Zeichen bei SRC (Z=1 bei Textende 0 -> Stelle liegt ausserhalb)
el3:    jsr src_peek
        beq el_end
        jsr src_adv
        cmp #$0a
        beq el_nl
        inc ecol
        bne er_el_l
        inc ecol + 1
        jmp er_el_l
        ; Zeilenende: naechste Zeile, Spalte wieder 1
el_nl:  inc eline
        bne el4
        inc eline + 1
el4:    lda #$01
        sta ecol
        lda #$00
        sta ecol + 1
        jmp er_el_l
        ; Textende vor Erreichen der Stelle: Zeile 0 = unbekannt
el_end: lda #$00
        sta eline
        sta eline + 1
        rts

; ---- Daten (ausserhalb der Liste, im Programm)
; ercnt/wcnt: Anzahl Eintraege der Fehler- und der Warnungsliste (zusammen als ercnt,x mit x = lsel indiziert; wcnt MUSS direkt
; hinter ercnt stehen); lsel: gewaehlte Liste; lbase: High-Bytes der Listenanfaenge (Index = lsel)
ercnt:   .byte 0
wcnt:    .byte 0
lsel:    .byte 0
lbase:   .byte >ELIST, >WLIST
; etmp: Zwischenspeicher fuer den Code; eidx: Rahmenzaehler bei der Rahmensuche; epos: Stelle (32 Bit) des Eintrags in Arbeit
etmp:   .byte 0
eidx:   .byte 0
epos:   .fill 4, 0
; esv: Sicherung P6, P7, FP; ebase: Dateianfang; eline/ecol: Ergebnis von err_linecol
esv:    .fill 12, 0
ebase:  .fill 4, 0
eline:  .word 0
ecol:   .word 0
; inpass: 1 = Zeilenanalyse laeuft (Fehler springt in die Fehlerbehandlung von asm.asm); asp2: Stapelstand dafuer.
; Sie sind hier nur angelegt; benutzt werden sie von asm.asm und stage2.asm.
inpass: .byte 0
asp2:   .byte 0
