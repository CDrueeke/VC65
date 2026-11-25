; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; mnfind.asm - Mnemonik in der Opcode-Tabelle (optab.asm) suchen (binaere Suche).
; Eingabe: MN_TOK ($F0-$F3) = Name, Grossbuchstaben, 4 Zeichen, rechts mit 0 aufgefuellt.
; Ausgabe: Carry geloescht = gefunden, MN_PTR ($F4/$F5) = Adresse des Eintrags (7 Byte: Name(4), Flags, Modenliste(Wort));
;          Carry gesetzt = nicht gefunden. Veraendert A, X, Y, $F6-$F9.
; Voraussetzung: optab.asm ist eingebunden (mn_table, MN_COUNT).
;
; Rolle: Der Assembler (asm.asm, Zeilenanalyse) schneidet das Mnemonik einer Zeile aus dem Quelltext, wandelt es in
; Grossbuchstaben, fuellt MN_TOK und ruft mn_find. Bei Erfolg liefert MN_PTR die Modenliste (Wort im Eintrag, Offset 5/6), aus
; der enc.asm die Adressierungsart und den Opcode waehlt. Nicht gefunden: der Aufrufer behandelt das Wort als Marke bzw.
; Fehler E205 (unbekannter Befehl).
;
; Tabellenformat (optab.asm): mn_table = MN_COUNT Eintraege zu je 7 Byte, aufsteigend nach den 4 Namensbytes sortiert
; (Byte-fuer-Byte-Vergleich, vorzeichenlos). Die Sortierung ist Voraussetzung der binaeren Suche; wer in optab.asm einen
; Eintrag einfuegt, muss die Reihenfolge einhalten.
;
; Zeropage: $F0-$F3 MN_TOK (Eingabe), $F4/$F5 MN_PTR (Ausgabe/Arbeitszeiger), $F6-$F8 Suchgrenzen. Keine dieser Zellen steht
; in zp.asm; sie werden nur waehrend mn_find benutzt. MN_COUNT darf bis 255 gehen (die Summe LO+HI wird ueber Carry und ror geteilt).
; =====================================================================================================================
; MN_TOK: Eingabename (4 Byte), MN_PTR: Zeiger auf den gefundenen Eintrag
MN_TOK = $f0
MN_PTR = $f4
; Suchgrenzen: MN_LO inklusiv, MN_HI exklusiv; MN_MID = aktuelle Mitte
MN_LO = $f6
MN_HI = $f7

MN_MID = $f8

; mn_find: binaere Suche ueber die sortierte Tabelle.
;   Eingabe : MN_TOK (4 Byte, Grossbuchstaben, mit 0 aufgefuellt)
;   Ausgabe : C=0 gefunden, MN_PTR = Eintragsadresse; C=1 nicht gefunden (MN_PTR dann unbestimmt)
;   Zerstoert: A, X, Y, MN_LO/HI/MID, MN_PTR
mn_find:
        lda #$00
        sta MN_LO
        lda #MN_COUNT
        sta MN_HI                   ; Suchbereich [LO, HI)
mf_loop:
        lda MN_LO
        cmp MN_HI                   ; leerer Bereich: nicht gefunden
        bcs mf_none                 ; leer: nicht gefunden
        clc
        adc MN_HI
        ror                         ; Mitte = (LO + HI) / 2, Uebertrag wird mit hineingeschoben
        sta MN_MID
        ; Eintragsadresse = mn_table + MID * 7 = mn_table + MID * 8 - MID  (7 ist keine Zweierpotenz: schieben, abziehen)
        sta MN_PTR
        lda #$00
        sta MN_PTR + 1
        asl MN_PTR
        rol MN_PTR + 1
        asl MN_PTR
        rol MN_PTR + 1
        asl MN_PTR
        rol MN_PTR + 1              ; MID * 8
        sec
        lda MN_PTR
        sbc MN_MID
        sta MN_PTR
        bcs mf_a                    ; kein Unterlauf des Low-Bytes: High-Byte bleibt
        dec MN_PTR + 1              ; MID * 7
mf_a:   clc
        lda MN_PTR
        adc #<(mn_table)
        sta MN_PTR
        lda MN_PTR + 1
        adc #>(mn_table)
        sta MN_PTR + 1
        ; Vier Namensbytes vergleichen: Y zaehlt im Eintrag, X im Suchnamen (beide gleichzeitig hochzaehlen)
        ldy #$00
        ldx #$00                    ; X indiziert MN_TOK (zp,x ist B-relativ; ein zp,y gibt es nicht und waere absolut)
mf_cmp: lda MN_TOK,x
        cmp (MN_PTR),y
        bne mf_diff                 ; erstes abweichendes Byte entscheidet (Carry steht von cmp: C=0 heisst Name < Eintrag)
        inx
        iny
        cpy #$04
        bne mf_cmp
        clc                         ; gefunden
        rts
mf_diff:
        bcc mf_less                 ; Name < Eintrag: obere Haelfte verwerfen
        lda MN_MID                  ; Name > Eintrag: LO = MID + 1
        clc
        adc #$01
        sta MN_LO
        jmp mf_loop
mf_less:
        lda MN_MID
        sta MN_HI
        jmp mf_loop
mf_none:
        sec
        rts
