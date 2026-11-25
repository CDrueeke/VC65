; SPDX-License-Identifier: GPL-3.0-or-later
; fmt.asm - Ausrichten (Formatieren) des Editortextes. Gehoert zum Editorkern (ed.asm) und wird in der IDE aus dem Werkzeug-Overlay VC65X
; aufgerufen (src/ide/xoverlay.asm), in den Testprogrammen (tools/edtest.py) direkt eingebunden.
; ---- Formatieren: Zeilen in feste Spalten ausrichten (Marke Spalte 0, Befehl Spalte 8, Operand 8 + max(4, Befehlslaenge + 1), Kommentar
; Spalte 32). Unveraendert bleiben: Kommentarzeilen, Zeilen mit . oder # in Spalte 0, Zeilen mit = (Konstanten); Leerraum am Zeilenende
; wird entfernt. ed_fmt_line formatiert die Zeile des Cursors (Cursor danach am Zeilenende), ed_fmt_all den ganzen Text (Cursor danach
; am Anfang der urspruenglichen Zeile). Zeilen ab 100 Zeichen bleiben unberuehrt.
;
; Rolle/Aufbau: Jede Zeile wird in einen Puffer fm_in (hoechstens 99 Zeichen + Endemarke 0) kopiert, von fm_conv in fm_out umgesetzt
; und nur dann im Text ersetzt (Cursor ans Zeilenende, alte Zeichen per K_BS/ed_bs loeschen, neue per ed_ins einfuegen), wenn sie
; sich unterscheiden. So bleiben Undo-Eintraege, Textstand (hp) und Zeilentabelle des Editors konsistent (alle Aenderungen laufen
; ueber die normalen Editoroperationen). Hinweis: Das Ergebnis darf laenger als die Eingabe werden (fm_out hat 170 Byte Platz).
; Speicherplan: laeuft im Overlay VC65X ab $E000 (Bank 4) mit den Zeropage-Zellen des Hauptprogramms (Basisseite $1F):
; E0..E3 (Textstelle, 32 Bit), ET (Arbeitszelle), ed_cur (Cursorposition, 32 Bit), ed_garg (Zeilennummer fuer ed_goto), ed_sel (Auswahl).
; Variablen fm_* liegen im Overlay selbst (nach dem Code, beschreibbar, weil das Overlay im RAM liegt).
; Invarianten: ed_cur steht vor und nach ed_fmt_line am Zeilenende; Zeilenlaenge < 100 (sonst unveraendert); Tabulatoren ($09)
; zaehlen wie Leerzeichen (werden als Trennraum ueberlesen).
; Zustaende von fm_conv: fm_lbl = Laenge der Marke (0: keine), fm_ms/fm_mn = Anfangsspalte/Laenge des Befehls, fm_q = Zeichen der
; offenen Zeichenkette ($22 oder $27, sonst 0; Kommentar- und Leerraum-Erkennung ignoriert dort ;), fm_st = Operand schon begonnen.

; ed_fmt_all: ganzen Text ausrichten. Ausgabe: Cursor am Anfang der Zeile, in der er vorher stand. Aendert alle Register, E0-E3.
; Verfahren: Cursor an den Textanfang, dann Zeile fuer Zeile ed_fmt_line (Cursor steht danach am Zeilenende), ein Zeichen weiter
; (hinter das LF) = naechste Zeile, bis das Textende erreicht ist. ed_recount stellt vorher die Zeilenzaehlung (ed_curline) sicher.
ed_fmt_all:
        jsr ed_recount
        lda ed_curline
        sta fm_ol
        lda ed_curline + 1
        sta fm_ol + 1
        lda #$00
        sta ed_sel                  ; Auswahl aufheben
        ldx #$03
fa_z:   sta ed_cur,x                ; Cursor = Textanfang (Position 0)
        dex
        bpl fa_z
fa_l:   jsr ed_fmt_line             ; Cursor danach am Zeilenende
        ldx #$03
fa_c:   lda ed_cur,x
        sta E0,x
        dex
        bpl fa_c
        jsr ed_eq_len               ; am Textende?
        beq fa_d
        jsr ed_inc                  ; ueber das Zeilenende (LF) hinweg = Anfang der naechsten Zeile
        ldx #$03
fa_n:   lda E0,x
        sta ed_cur,x
        dex
        bpl fa_n
        jmp fa_l
fa_d:   lda fm_ol                   ; urspruengliche Cursorzeile wieder anspringen (ed_goto: Zeilennummer in ed_garg)
        sta ed_garg
        lda fm_ol + 1
        sta ed_garg + 1
        jmp ed_goto

; ed_fmt_line: Zeile des Cursors ausrichten. Eingabe: Cursor ed_cur in der Zeile. Ausgabe: Cursor am Zeilenende (fm_ep).
; Aendert alle Register, E0-E3, ET, fm_*. Abbruch ohne Aenderung (fg_x0), wenn die Zeile 100 oder mehr Zeichen hat oder das
; Ergebnis der Eingabe gleicht.
ed_fmt_line:
        lda #$00
        sta ed_sel
        ldx #$03
fg_c:   lda ed_cur,x
        sta E0,x
        dex
        bpl fg_c
        jsr ed_ls                   ; E0 = Zeilenanfang (ed_ls: line start)
        ldx #$03
fg_s:   lda E0,x
        sta fm_sp,x
        dex
        bpl fg_s
        jsr ed_le                   ; E0 = Zeilenende (ed_le: line end, Stelle des LF bzw. Textende)
        ldx #$03
fg_e:   lda E0,x
        sta fm_ep,x
        dex
        bpl fg_e
        sec                         ; Laenge = Ende - Anfang, hoechstens 99 (32-Bit-Subtraktion; hoehere Bytes nur zum Pruefen auf 0 per ORA)
        lda fm_ep
        sbc fm_sp
        sta fm_n
        lda fm_ep + 1
        sbc fm_sp + 1
        sta ET
        lda fm_ep + 2
        sbc fm_sp + 2
        ora ET
        sta ET
        lda fm_ep + 3
        sbc fm_sp + 3
        ora ET
        bne fg_x0
        lda fm_n
        cmp #100
        bcs fg_x0
        ldx #$03                    ; Zeile nach fm_in kopieren (ed_get liest an E0 ueber die Editorluecke hinweg)
fg_p:   lda fm_sp,x
        sta E0,x
        dex
        bpl fg_p
        lda #$00
        sta fm_k
fg_k:   lda fm_k
        cmp fm_n
        beq fg_f
        jsr ed_get
        ldx fm_k
        sta fm_in,x
        jsr ed_inc
        inc fm_k
        jmp fg_k
fg_f:   ldx fm_n
        lda #$00
        sta fm_in,x                 ; Endemarke
        jsr fm_conv
        lda fm_on                   ; gleich? dann nichts tun
        cmp fm_n
        bne fg_r
        ldx #$00
fg_q:   cpx fm_n
        beq fg_x0
        lda fm_in,x
        cmp fm_out,x
        bne fg_r
        inx
        bne fg_q
; Rueckwaertsloeschen mit der Editorfunktion ed_bs, damit Undo und Zeilentabelle stimmen; ed_kind meldet der Undo-Verwaltung
; die Art der Taste (ed_k)
fg_r:   ldx #$03                    ; Cursor ans Zeilenende, alt loeschen, neu einfuegen
fg_u:   lda fm_ep,x
        sta ed_cur,x
        dex
        bpl fg_u
        lda fm_n
        sta fm_k
fg_b:   lda fm_k
        beq fg_i
        lda #K_BS
        sta ed_k
        jsr ed_kind
        jsr ed_bs                   ; ein Zeichen links vom Cursor loeschen
        dec fm_k
        jmp fg_b
fg_i:   ldx #$00
fg_w:   cpx fm_on
        beq fg_x
        phx
        lda fm_out,x
        sta ed_k
        jsr ed_kind
        lda ed_k
        jsr ed_ins                  ; am Cursor einfuegen (Cursor wandert mit)
        plx
        inx
        jmp fg_w
fg_x:   rts
fg_x0:  ldx #$03                    ; nichts geaendert: Cursor ans Zeilenende
fg_y:   lda fm_ep,x
        sta ed_cur,x
        dex
        bpl fg_y
        rts

; fm_conv: fm_in (fm_n Zeichen, danach 0) -> fm_out (fm_on Zeichen). Aendert A, X, Y, fm_*.
; Ablauf: Leerraum am Anfang ueberspringen -> (leere Zeile: fertig) -> Kommentarzeile (; oder /) und Zeilen mit . # in Spalte 0 sowie
; Zeilen mit = als Zeile unveraendert (fc_raw, nur rechter Leerraum entfaellt) -> Marke (nur Spalte 0, bis einschliesslich Doppelpunkt)
; -> Befehl auf Spalte 8 (oder nach einem Leerzeichen, wenn die Marke breiter ist) -> Operand auf 8 + max(4, Befehlslaenge + 1) ->
; Kommentar auf Spalte 32 (mindestens ein Leerzeichen Abstand). Zeichenketten in " oder ' werden bis zum Endezeichen kopiert,
; ein ; darin beginnt keinen Kommentar.
fm_conv:
        lda #$00
        sta fm_on
        sta fm_lbl
        ldy #$00
fc_s0:  cpy fm_n
        beq fc_x                    ; leere Zeile
        lda fm_in,y
        cmp #$20
        beq fc_s1
        cmp #$09
        bne fc_f
fc_s1:  iny
        jmp fc_s0
fc_x:   rts
fc_f:   sty fm_ls
        cmp #$3b                    ; ; und / am Anfang: Kommentarzeile (Einrueckung des Kommentars bleibt dann erhalten, siehe fc_raw: Zeile ab fm_in)
        beq fc_raw
        cmp #$2f
        beq fc_raw
        cpy #$00                    ; (Y = Spalte des ersten Zeichens; ungleich 0 = eingerueckt)
        bne fc_m                    ; eingerueckt: keine Marke
        cmp #$2e                    ; . und # in Spalte 0: Direktive, unveraendert
        beq fc_raw
        cmp #$23
        beq fc_raw
        lda #$01                    ; Marke (endet nach einem Doppelpunkt): fm_lt = 1 laesst fc_tok am ':' enden
        sta fm_lt
        jsr fc_tok
        lda #$00
        sta fm_lt
        lda fm_on
        sta fm_lbl
        jsr fc_ws
        cpy fm_n
        bne fc_m
        rts
fc_m:   jsr fc_iscm                 ; beginnt hier ein Kommentar (; oder //)? Dann kein Befehl
        bcs fc_cm
        lda fm_in,y
        cmp #$3d                    ; = : Konstante, unveraendert
        beq fc_raw
        lda fm_lbl                  ; Befehlsspalte 8: ohne Marke immer; mit Marke nur, wenn sie kuerzer als 8 Zeichen ist
        beq fc_p8
        lda fm_on
        cmp #$08
        bcs fc_p1
fc_p8:  lda #$08
        jsr fc_padto
        jmp fc_tk
fc_p1:  lda #$20
        jsr fc_put
fc_tk:  lda fm_on                   ; Befehl (Mnemonic/Direktive) kopieren; fm_ms = Anfangsspalte, fm_mn = Laenge
        sta fm_ms
        jsr fc_tok
        lda fm_on
        sec
        sbc fm_ms
        sta fm_mn
        jsr fc_ws
        lda #$00
        sta fm_q
        sta fm_st
fc_ol:  cpy fm_n                    ; Operandenschleife: Zeichen fuer Zeichen bis Zeilenende oder Kommentar
        beq fc_od
        lda fm_q
        bne fc_oq                   ; innerhalb einer Zeichenkette: Kommentarpruefung ueberspringen
        jsr fc_iscm
        bcs fc_od
        lda fm_in,y
        cmp #$22
        beq fc_qs
        cmp #$27
        bne fc_oc
fc_qs:  sta fm_q                    ; Zeichenkette beginnt: Endezeichen merken
        jmp fc_oc
fc_oq:  lda fm_in,y
        cmp fm_q
        bne fc_oc
        lda #$00
        sta fm_q
fc_oc:  lda fm_st
        bne fc_ow
        lda #$01
        sta fm_st
        lda #$20                    ; mindestens ein Leerzeichen
        jsr fc_put
        lda fm_mn                   ; Operandspalte 8 + max(4, Befehlslaenge + 1): Befehlslaenge + 1, mindestens 4, plus 8
        clc
        adc #$01
        cmp #$04
        bcs fc_o4
        lda #$04
fc_o4:  clc
        adc #$08
        jsr fc_padto
fc_ow:  lda fm_in,y
        jsr fc_put
        iny
        jmp fc_ol
fc_od:  jsr fc_rtrim                ; Leerraum am Ende des Operanden entfernen
        cpy fm_n
        bcs fc_done                 ; kein Kommentar vorhanden: fertig
fc_cm:  jsr fc_rtrim                ; Kommentar ab Y
        lda fm_on
        cmp #31                     ; steht der Code schon ueber Spalte 31? Dann nur ein Leerzeichen Abstand
        bcs fc_c1
        lda #32                     ; sonst auf Spalte 32 auffuellen
        jsr fc_padto
        jmp fc_cp
fc_c1:  lda #$20
        jsr fc_put
fc_cp:  lda fm_in,y                 ; Kommentar unveraendert (bis zum Zeilenende) kopieren
        jsr fc_put
        iny
        cpy fm_n
        bne fc_cp
        jmp fc_rtrim
fc_done: rts
fc_raw: lda #$00                    ; ganze Zeile, Leerraum am Ende entfernt
        sta fm_on
        ldy #$00
fc_r1:  lda fm_in,y
        jsr fc_put
        iny
        cpy fm_n
        bne fc_r1
        jmp fc_rtrim

; fc_put: A an fm_out anhaengen (fm_on = Zaehler). Aendert X. Keine Pruefung auf fm_out-Ende (170 Byte genuegen fuer 99 Zeichen + Fuellung).
fc_put: ldx fm_on
        sta fm_out,x
        inc fm_on
        rts
; fc_padto: mit Leerzeichen auffuellen, bis fm_on = A (nichts, wenn schon erreicht). Aendert A, X, fm_t.
fc_padto:
        sta fm_t
fc_pl:  lda fm_on
        cmp fm_t
        bcs fc_pr
        lda #$20
        jsr fc_put
        jmp fc_pl
fc_pr:  rts
; fc_tok: ein Wort ab Y kopieren (bis Leerzeichen/Tab/Zeilenende; bei fm_lt = 1 zusaetzlich bis nach dem ':' der Marke). Y wandert weiter.
fc_tok: cpy fm_n
        beq fc_tr
        lda fm_in,y
        cmp #$20
        beq fc_tr
        cmp #$09
        beq fc_tr
        jsr fc_put
        lda fm_in,y
        iny
        cmp #$3a
        bne fc_tok
        lda fm_lt
        beq fc_tok
fc_tr:  rts
; fc_ws: Leerraum (Leerzeichen, Tab) ab Y ueberspringen (Y wandert). Aendert A.
fc_ws:  cpy fm_n
        beq fc_wr
        lda fm_in,y
        cmp #$20
        beq fc_w1
        cmp #$09
        bne fc_wr
fc_w1:  iny
        jmp fc_ws
fc_wr:  rts
; fc_rtrim: rechten Leerraum aus fm_out entfernen (fm_on verkleinern). Aendert A, X.
fc_rtrim:
        ldx fm_on
fc_rl:  beq fc_re
        lda fm_out - 1,x
        cmp #$20
        beq fc_rd
        cmp #$09
        bne fc_re
fc_rd:  dex
        jmp fc_rl
fc_re:  stx fm_on
        rts
; fc_iscm: Carry gesetzt, wenn an Y ein Kommentar beginnt (; oder //)
fc_iscm:
        lda fm_in,y
        cmp #$3b
        beq fc_ic
        cmp #$2f
        bne fc_in
        lda fm_in + 1,y
        cmp #$2f
        beq fc_ic
fc_in:  clc
        rts
fc_ic:  sec
        rts

; ---- Variablen (liegen im Overlay) ----
fm_n:   .byte 0                     ; Zeichenzahl der Eingabezeile
fm_on:  .byte 0                     ; Zeichenzahl der Ausgabe
fm_lbl: .byte 0
fm_ls:  .byte 0
fm_ms:  .byte 0
fm_mn:  .byte 0
fm_q:   .byte 0
fm_st:  .byte 0
fm_t:   .byte 0
fm_lt:  .byte 0
fm_k:   .byte 0
fm_ol:  .word 0                     ; urspruengliche Cursorzeile (ed_fmt_all)
fm_sp:  .fill 4, 0                  ; Zeilenanfang (32 Bit)
fm_ep:  .fill 4, 0                  ; Zeilenende (32 Bit)
fm_in:  .fill 104, 0                ; Eingabezeile (99 Zeichen + Endemarke, Reserve)
fm_out: .fill 170, 0                ; Ausgabezeile

