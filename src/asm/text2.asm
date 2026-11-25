; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; text2.asm - Sonderzeichen in Zeichenketten ({name}, {$hh}, {nnn}, {name*n}, {{) und .encoding "name" { ... }.
; Die Namen stehen in charnames.asm (erzeugt von tools/gen_charnames.py).
;
; Rolle im Assembler:
;   Die Zeichenkettenausgabe selbst (emit_str / es_body / es_go / conv_char) steht in asm.asm. Sie liest die Kette Zeichen
;   fuer Zeichen ueber src_peek/src_adv und uebergibt jedes gewoehnliche Zeichen an conv_char (Kodierung nach TM). Trifft sie
;   ein '{', springt sie nach es_brace (hier). es_brace liest den Inhalt der geschweiften Klammer in escbuf, deutet ihn als
;   Zahl ($hh oder dezimal) oder als PETSCII-Name (Tabelle charnames), gibt das Zeichen n-mal ueber es_out aus und kehrt
;   mit "jmp es_go" in die Zeichenschleife von asm.asm zurueck (kein RTS: es_brace wird ersetzend angesprungen).
;   Der zweite Teil (de_fin, encblk_push, enc_check) ergaenzt d_encoding (asm.asm): er prueft den Kodierungsnamen und
;   behandelt den optionalen Block `{ ... }`, der die Kodierung nach seinem Ende wieder zuruecknimmt.
;
; Eingaben/Zustand (Zeropage und Variablen anderer Module):
;   TM      = Kodierung der laufenden Datenliste (0 ASCII unveraendert, 1 PETSCII, 2 Bildschirmcode)
;   ENC     = mit .encoding gewaehlte Kodierung fuer .text; encold = ENC vor dem letzten .encoding
;   SRC     = 32-Bit-Quelltextzeiger (nur ueber src_peek/src_adv benutzt)
;   S2T     = 16-Bit-Hilfszelle ($0c/$0d), hier Zahlenakkumulator (S2T) und aktuelle Ziffer (S2T + 1)
;   MP      = 16-Bit-Zeiger auf die Namenstabelle (charnames bzw. enc_names), TMP = Hilfswert in enc_check
; Eigener Speicher (am Dateiende): escbuf (24 Byte Klammerinhalt, klein geschrieben, '_' und '-' als Leerzeichen),
;   escs/esce = Anfang/Ende (exklusiv) des auszuwertenden Teils von escbuf, escne = Namensende vor einem '*',
;   escn = Wiederholungszahl, escv = auszugebender Code (zugleich Hilfszelle in esc_num), cntmode/cntb = Zaehlmodus fuer
;   .ptext (nur zaehlen statt ausgeben), tmpenc/sflag/encsave = Kodierungsblock-Zustand (teilt sich den Scope-Stapel).
; Fehler: alle Formfehler in {...} und unbekannte Namen/Kodierungen melden ERR_E208 (wie vcc), Stapel zu tief ERR_E211.
; =====================================================================================================================

; es_out: ein Zeichen der Kette ausgeben (oder nur zaehlen: .ptext, Trockenlauf)
; Eingabe: A = auszugebendes Zeichen (bereits kodiert). Im Zaehlmodus (cntmode <> 0) wird nur cntb erhoeht.
; Aendert X (und was emit_byte aendert); der Zaehlmodus liefert die Laenge fuer das Praefixbyte von .ptext.
es_out: ldx cntmode
        bne t2_eo1
        jmp emit_byte               ; normal: Byte an die Ausgabe (emit_byte kehrt zum Aufrufer zurueck)
t2_eo1:    inc cntb                 ; Trockenlauf: nur mitzaehlen
        rts

; es_brace: SRC steht auf '{' innerhalb einer Zeichenkette; danach geht es mit es_go weiter
; Syntax: {{ = ein '{'; {name} / {name*n}; {$hh} / {nnn} / {$hh*n} / {nnn*n} (n = Wiederholung 1..255, 0 ist verboten).
; Kehrt nicht zurueck, sondern springt nach es_go (Zeichenschleife in asm.asm); Fehler laufen ueber as_error (kein Rueckkehr).
es_brace:
        jsr src_adv                 ; die oeffnende { verbrauchen
        jsr src_peek
        cmp #$7b
        bne eb_go
        jsr conv_char               ; {{ ist ein einzelnes {
        jsr es_out
        jsr src_adv
        jmp es_go
eb_go:  ldx #$00                    ; Inhalt bis zur schliessenden } in escbuf sammeln (X = Laenge)
eb_l:   jsr src_peek
        beq eb_bad                  ; Quelltextende
        cmp #$0a
        beq eb_bad                  ; Zeilenende
        cmp #$22
        beq eb_bad                  ; Kettenende ohne }
        cmp #$7d
        beq eb_end
        cmp #$41                    ; Grossbuchstaben A-Z zu Kleinbuchstaben: Namen sind klein gespeichert
        bcc eb_n1
        cmp #$5b
        bcs eb_n1
        ora #$20                    ; klein
eb_n1:  cmp #$5f                    ; _ und - gelten wie Leerzeichen
        beq eb_sp
        cmp #$2d
        bne eb_n2
eb_sp:  lda #$20
eb_n2:  cpx #$18                    ; hoechstens 24 Zeichen (Puffergroesse)
        bcs eb_bad
        sta escbuf,x
        inx
        jsr src_adv
        jmp eb_l
eb_bad: lda #ERR_E208
        jmp as_error
eb_end: stx esce                    ; Ende des Inhalts
        jsr src_adv                 ; } verbrauchen
        lda #$01
        sta escn                    ; Anzahl 1
        ldx #$00                    ; '*' suchen
eb_s:   cpx esce
        beq eb_nostar
        lda escbuf,x
        cmp #$2a
        beq eb_star
        inx
        bne eb_s
eb_star:
        stx escne                   ; Ende des Namens
        inx
        stx escs                    ; Zahl hinter dem Stern auswerten (esc_num liest escbuf[escs..esce))
        jsr esc_num                 ; Anzahl hinter dem Stern
        bcs eb_bad
        beq eb_bad                  ; 0 ist keine gueltige Anzahl
        sta escn
        lda escne                   ; ab hier gilt nur noch der Teil vor dem Stern als Zeichen
        sta esce
eb_nostar:
        lda #$00
        sta escs
        lda esce
        beq eb_bad                  ; leerer Inhalt {}
        lda escbuf
        cmp #$24                    ; $hh
        beq eb_num
        cmp #$30                    ; Ziffer 0-9: dezimaler Code
        bcc eb_name
        cmp #$3a
        bcs eb_name
eb_num: jsr esc_num                 ; Zahl -> A (Wert 0..255)
        bcs eb_bad
        jmp eb_emit
eb_name:
        lda TM                      ; Namen gibt es nur mit PETSCII
        cmp #$01
        bne eb_bad
        jsr esc_lookup              ; Name -> PETSCII-Code in A
        bcs eb_bad
eb_emit:                            ; Zahlen werden unveraendert ausgegeben (keine conv_char-Umsetzung: es ist schon der Zielcode)
        sta escv
eb_rep: lda escv                    ; escn-mal ausgeben (escn >= 1)
        jsr es_out
        dec escn
        bne eb_rep
        jmp es_go

; esc_num: escbuf[escs..esce): $hh oder dezimal -> A (Z gesetzt bei 0), Carry gesetzt bei Fehler oder > 255
; Eingabe: escs/esce. Ausgabe: Carry geloescht, A = Wert (Flag Z passend zu A); Carry gesetzt = Fehler (leer, falsche Ziffer,
; hex mehr als 2 Ziffern, dezimal > 255). Aendert X, S2T, S2T + 1, escv (Hilfszelle fuer den Faktor 10).
esc_num:
        ldx escs
        cpx esce
        beq en_bad                  ; leer
        lda escbuf,x
        cmp #$24
        beq en_hex
        lda #$00                    ; Dezimal: S2T = S2T * 10 + Ziffer, jede Stufe auf Uebertrag (> 255) geprueft
        sta S2T
en_d:   cpx esce
        beq en_ok
        lda escbuf,x
        sec
        sbc #$30
        cmp #$0a                    ; keine Ziffer (auch fuer Zeichen unter '0': Wert laeuft ueber)
        bcs en_bad
        sta S2T + 1
        lda S2T
        asl                         ; * 2
        bcs en_bad
        sta escv
        asl                         ; * 4
        bcs en_bad
        asl                         ; * 8
        bcs en_bad
        clc
        adc escv                    ; * 8 + * 2 = * 10
        bcs en_bad
        adc S2T + 1                 ; + Ziffer
        bcs en_bad
        sta S2T
        inx
        bne en_d
en_hex: inx                         ; '$' ueberspringen; es muss mindestens eine Ziffer folgen
        cpx esce
        beq en_bad
        lda #$00
        sta S2T
en_h:   cpx esce
        beq en_ok
        lda S2T
        and #$f0
        bne en_bad                  ; mehr als zwei Ziffern
        lda escbuf,x
        sec
        sbc #$30
        cmp #$0a
        bcc en_h1                   ; 0-9
        sbc #$27                    ; a-f (Carry ist hier gesetzt: 'a' - $30 - $27 = 10); Grossbuchstaben sind schon klein
        cmp #$0a
        bcc en_bad                  ; Zeichen zwischen '9' und 'a'
        cmp #$10
        bcs en_bad
en_h1:  sta S2T + 1
        lda S2T                     ; Akkumulator um 4 Bit nach links, neue Ziffer unten einschieben
        asl
        asl
        asl
        asl
        ora S2T + 1
        sta S2T
        inx
        bne en_h
en_ok:  lda S2T                     ; (lda setzt Z fuer den Aufrufer; clc aendert Z nicht)
        clc
        rts
en_bad: sec
        rts

; esc_lookup: escbuf[0..esce) in der Namenstabelle suchen -> A = Code, Carry gesetzt wenn unbekannt
; Tabelle charnames (charnames.asm): Eintrag = Namenslaenge, Name (klein), Code; Ende = Laenge 0. Mehrere Namen duerfen
; denselben Code haben (z. B. "ret" und "return"). Aendert A, X, Y, MP.
esc_lookup:
        lda #<charnames
        sta MP
        lda #>charnames
        sta MP + 1
el_l:   ldy #$00
        lda (MP),y                  ; Namenslaenge des Eintrags
        beq el_no                   ; Tabellenende
        cmp esce
        bne el_n                    ; andere Laenge: kann nicht passen
        iny
        ldx #$00
el_c:   cpx esce
        beq el_hit
        lda (MP),y
        cmp escbuf,x
        bne el_n
        iny
        inx
        bne el_c
el_hit: lda (MP),y                  ; Y steht hinter dem Namen: dort liegt der Code
        clc
        rts
el_n:   ldy #$00                    ; MP += Namenslaenge + 2 (Laengenbyte + Codebyte) -> naechster Eintrag
        lda (MP),y
        clc
        adc #$02
        clc
        adc MP
        sta MP
        bcc el_l
        inc MP + 1
        jmp el_l
el_no:  sec
        rts

; ---- .encoding "name" { ... }: hinter dem Namen folgt optional ein Block, danach gilt wieder die alte Kodierung
; de_fin: Fortsetzung von d_encoding (asm.asm), ENC ist schon gesetzt, encold = Kodierung davor.
; Ohne '{' ist die Direktive hier zu Ende (die Kodierung gilt dann bis zur naechsten .encoding-Zeile bzw. dem Ende
; des umgebenden Blocks). Mit '{' wird der Block geoeffnet; sein Ende ('}') ruft scope_pop (stage2.asm), das ENC
; aus encsave wiederherstellt.
de_fin: jsr skipws
        jsr src_peek
        cmp #$7b
        beq de_blk
        jmp d_end
de_blk: jsr src_adv
        lda encold
        jsr encblk_push
        jmp al_line

; encblk_push: einen Kodierungsblock auf den Scope-Stapel legen (er teilt sich Stapel und Zaehler sdep mit .scope).
; Der Stapel hat 8 Ebenen (sdep 0..7); die Kennung sflag = 1 unterscheidet den Kodierungsblock von einem Scope.
; Eingabe: A = Kodierung vor dem Block (kommt am Ende des Blocks zurueck). Fehler: ERR_E211 bei voller Stapel.
; Aendert A, X, Y, tmpenc. Der Pfad (plen) bleibt gleich, die aktuelle globale Marke CURG wird wie bei einem Scope gesichert.
encblk_push:                        ; A = Kodierung vor dem Block
        sta tmpenc
        ldx sdep
        cpx #$07
        bcc ep0
        lda #ERR_E211
        jmp as_error
ep0:    txa                         ; Y = sdep * 32: Platz fuer CURG in curgstk
        asl
        asl
        asl
        asl
        asl
        tay
        ldx #$00
ep1:    lda CURG,x                  ; CURG (31 Byte) sichern
        sta curgstk,y
        iny
        inx
        cpx #$1f
        bne ep1
        ldx sdep
        lda plen,x                  ; neue Ebene uebernimmt die Pfadlaenge der alten
        inc sdep
        inx
        sta plen,x
        lda #$01                    ; sflag = 1: Kodierungsblock (kein Scope)
        sta sflag,x
        lda tmpenc
        sta encsave,x               ; alte Kodierung fuer scope_pop
        rts

cntmode: .byte 0                    ; <> 0: es_out zaehlt nur (Trockenlauf fuer .ptext)
cntb:    .byte 0                    ; im Zaehlmodus gezaehlte Zeichen
escbuf:  .fill 24, 0                ; Inhalt der geschweiften Klammer (klein, '_' und '-' als Leerzeichen)
escs:    .byte 0                    ; Anfang des auszuwertenden Teils von escbuf
esce:    .byte 0                    ; Ende (exklusiv)
escn:    .byte 0                    ; Wiederholungszahl
escne:   .byte 0                    ; Ende des Namens vor '*'
escv:    .byte 0                    ; auszugebender Code; in esc_num Hilfszelle
encold:  .byte 0                    ; ENC vor der letzten .encoding-Direktive
tmpenc:  .byte 0                    ; Zwischenspeicher fuer die Kodierung in encblk_push
sflag:   .fill 9, 0                 ; je Scope-Ebene: 1 = Kodierungsblock (Index = sdep, also 9 Ebenen 0..8)
encsave: .fill 9, 0                 ; je Ebene: Kodierung vor dem Block

; enc_check: NAMEBUF/NAMELEN muss ascii, petscii oder screen sein (sonst E208)
; Vergleich ohne Beachtung der Gross-/Kleinschreibung (ora #$20 auf das Quellzeichen). Aendert A, X, Y, MP, TMP.
; Kehrt bei Erfolg mit RTS zurueck, sonst Abbruch ueber as_error.
enc_check:
        lda #<enc_names
        sta MP
        lda #>enc_names
        sta MP + 1
ek_l:   ldy #$00                    ; Y = Index im aktuellen Tabellennamen
        lda (MP),y
        beq ek_bad                  ; leerer Name = Tabellenende (doppelte 0): kein Treffer
        ldx #$00                    ; X = Index in NAMEBUF
ek_c:   lda (MP),y
        beq ek_e                    ; Tabellenname zu Ende
        sta TMP
        cpx NAMELEN
        beq ek_n                    ; Eingabe kuerzer als der Tabellenname
        lda NAMEBUF,x
        ora #$20
        cmp TMP
        bne ek_n
        inx
        iny
        bne ek_c
ek_e:   cpx NAMELEN                 ; beide gleichzeitig zu Ende = Treffer
        beq ek_ok
ek_n:   lda (MP),y                  ; zum Ende dieses Namens, dann zum naechsten
        beq ek_n2
        iny
        bne ek_n
ek_n2:  iny                         ; hinter die 0 des Namens
        tya
        clc
        adc MP                      ; MP += Y: naechster Tabellenname
        sta MP
        bcc ek_l
        inc MP + 1
        jmp ek_l
ek_ok:  rts
ek_bad: lda #ERR_E208
        jmp as_error
enc_names: .byte "ascii", 0, "petscii", 0, "screen", 0, 0
