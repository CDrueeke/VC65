; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; cyc.asm - .cycles [name] [max=budget] ... .endcycles: Zyklen der dazwischen uebersetzten Befehle zaehlen (wie vcc:
; die Befehle zaehlen so oft, wie sie uebersetzt werden; kein Programmablauf). min = Summe der Grundzyklen, max =
; unguenstigster Fall (bedingter Sprung genommen +2). Tabellen cyc_base/cyc_worst je Opcode (aus optab.asm).
; Bloecke duerfen verschachtelt sein (bis 8). Je abgeschlossenem Block entsteht ein Bericht (bis 16): min, max, Budget.
; Ueberschreitet max das Budget: Warnung W201 (Warnungsliste), der Bau gelingt trotzdem.
;
; Rolle: asm.asm ruft cy_pass zu Beginn jedes Durchlaufs, enc.asm ruft cyc_add nach jedem uebersetzten Befehl,
; die Direktiven-Tabelle verweist auf d_cycles/d_endcycles, und stage2.asm ruft cy_close am Ende des
; Quelltexts. Fehler gehen ueber as_error (asm.asm) bzw. err_add (err.asm); die Budgetwarnung ueber warn_add.
;
; Datenstrukturen (Felder zu je CY_MAXD = 8 Byte, Index = Verschachtelungstiefe 0..7; cydepth = Anzahl offener Bloecke):
;   cyminl/cyminh, cymaxl/cymaxh  16-Bit-Zaehler min und max je offenem Block (Ueberlauf bei 65535 wird nicht abgefangen)
;   cybl/cybh, cybf               Budget (16 Bit, auf $FFFF begrenzt) und Merker "max= angegeben" (1)
;   cynl, cynames                 Namenslaenge (0..15) und Name (je Block 16 Byte ab cynames + Tiefe * 16)
;   cypos                         Quelltextstelle des .cycles (32 Bit je Block) fuer die Meldung "nicht geschlossen"
;   cyrep, cyrepn                 Berichte abgeschlossener Bloecke: bis 16 Eintraege zu 8 Byte: min(2), max(2), Budget(2),
;                                 Budgetmerker(1), Namenslaenge(1); cyrepn = Anzahl. (Der Name selbst wird nicht mitgespeichert.)
; Speicher: cynames ($1400-$147F) und cyrep ($1480-$14FF) liegen im freien Bereich $1200-$17FF; die uebrigen Felder sind kleine
; Variablen im Programm. Zeropage wird nur ueber SRC und VAL mitbenutzt.
; Zaehlweise: nicht Programmablauf, sondern jeder uebersetzte Befehl zaehlt einmal pro Uebersetzung (Wiederholungen mit
; .repeat zaehlen also so oft, wie der Rumpf expandiert wird). Alle offenen Bloecke erhalten jeden Befehl.
; Invariante: 0 <= cydepth <= CY_MAXD. Ein neuer Durchlauf (cy_pass) vergisst offene Bloecke und alte Berichte.
; =====================================================================================================================
CY_MAXD = 8                         ; Maximale Verschachtelungstiefe offener .cycles-Bloecke

; cy_pass: Zaehlerzustand zu Beginn jedes Durchlaufs ruecksetzen (keine offenen Bloecke, keine Berichte). Zerstoert A.
cy_pass:
        lda #$00
        sta cydepth
        sta cyrepn
        rts

; cyc_add: Zyklen eines uebersetzten Befehls auf alle offenen Bloecke addieren.
;   Eingabe : A = Opcode (Index in cyc_base / cyc_worst aus optab.asm: Grundzyklen bzw. unguenstigster Fall)
;   Ausgabe : keine; ohne offenen Block (cydepth = 0) sofort Rueckkehr. Zerstoert A, X, Flags.
cyc_add:
        ldx cydepth
        beq ca_ret
        ; Opcode als Index; cyt = Grundzyklen (min), cyw = unguenstigster Fall (max, z. B. Sprung genommen +2)
        tax
        lda cyc_base,x
        sta cyt
        lda cyc_worst,x
        sta cyw
        ldx cydepth
        ; alle offenen Bloecke tiefer-1 ... 0 durchlaufen (dex zuerst, Abbruch nach Index 0): 16-Bit-Addition je Feld
ca_l:   dex
        lda cyminl,x
        clc
        adc cyt
        sta cyminl,x
        bcc ca1
        inc cyminh,x
ca1:    lda cymaxl,x
        clc
        adc cyw
        sta cymaxl,x
        bcc ca2
        inc cymaxh,x
ca2:    cpx #$00
        bne ca_l
ca_ret: rts

; d_cycles: Direktive .cycles [name] [max=ausdruck]. Neuen Block eroeffnen (Tiefe < CY_MAXD, sonst E211).
;   Syntax: Optionen in beliebiger Reihenfolge bis Zeilenende; "max=" (kleingeschrieben, exakt dieses Praefix) setzt das Budget,
;   jedes andere Wort wird als Name genommen (letztes gewinnt). Bei "max=" Wert negativ -> 0; > 65535 -> 65535.
;   Endet ueber d_end (Zeilenende pruefen). Zerstoert A, X, Y, Z und mehrere Zellen (tmpsrc, tmpc).
d_cycles:
        lda cydepth
        cmp #CY_MAXD
        bcc dc_ok
        lda #ERR_E211
        jmp as_error
        ; Zaehler und Merker des neuen Blocks loeschen (X = Tiefe)
dc_ok:  ldx cydepth
        lda #$00
        sta cyminl,x
        sta cyminh,x
        sta cymaxl,x
        sta cymaxh,x
        sta cybf,x
        sta cybl,x
        sta cybh,x
        sta cynl,x
        txa                         ; Platz fuer den Namen: x * 16
        asl
        asl
        asl
        asl
        sta cyni
        txa
        pha
        ldx #$03                    ; Stelle des Blocks (fuer "nicht geschlossen")
cy_sp:  lda SRC,x
        sta tmpsrc,x
        dex
        bpl cy_sp
        ; ... und nach cypos + Tiefe * 4 uebertragen (X = Tiefe * 4)
        pla
        tax
        txa
        asl
        asl
        tax
        ldy #$00
dc_q:   lda tmpsrc,y
        sta cypos,x
        inx
        iny
        cpy #$04
        bne dc_q
        ; Optionsschleife: Leerraum ueberlesen; Zeilenende (oder Kommentar) beendet
dc_w:   jsr skipws
        jsr at_eol
        beq dc_done
        jsr src_peek                ; max=?
        ; Prueft die Zeichen 'm','a','x','=' ($6d,$61,$78,$3d): 1. per src_peek, 2. per src_peek1, 3./4. per [SRC],z
        cmp #$6d
        bne dc_name
        jsr src_peek1
        cmp #$61
        bne dc_name
        ldz #$02
        lda [SRC],z
        cmp #$78
        bne dc_name
        inz
        lda [SRC],z
        cmp #$3d
        bne dc_name
        ; "max=" ueberspringen und den Ausdruck auswerten (eval_val -> VAL, 32 Bit)
        jsr src_adv
        jsr src_adv
        jsr src_adv
        jsr src_adv
        jsr eval_val
        lda VAL + 3                 ; negativ: 0
        bpl dc_b
        lda #$00
        sta VAL
        sta VAL + 1
        sta VAL + 2
        sta VAL + 3
        ; Budget = VAL, aber auf 65535 begrenzen (obere 16 Bit <> 0)
dc_b:   ldx cydepth
        lda VAL
        sta cybl,x
        lda VAL + 1
        sta cybh,x
        lda VAL + 2
        ora VAL + 3
        beq dc_b1
        lda #$ff
        sta cybl,x
        sta cybh,x
dc_b1:  lda #$01                    ; Merker: Budget vorhanden
        sta cybf,x
        jmp dc_w
        ; Name: Zeichen bis Leerraum ($20), Tab ($09), Zeilenende ($0A/$0D), Semikolon ($3B) lesen, hoechstens 15 Zeichen speichern
        ; (weitere werden ueberlesen). Ein neues Wort ersetzt den vorigen Namen (cynl = 0 am Anfang).
dc_name:
        ldx cydepth                 ; Wort bis Leerraum/Zeilenende als Name
        lda #$00
        sta cynl,x
dc_nl:  jsr src_peek
        beq dc_w
        cmp #$20
        beq dc_w
        cmp #$09
        beq dc_w
        cmp #$0a
        beq dc_w
        cmp #$0d
        beq dc_w
        cmp #$3b
        beq dc_w
        ; Zeichen in cynames[Tiefe * 16 + Laenge] ablegen; Y = bisherige Laenge, A = Zeichen
        ldx cydepth
        ldy cynl,x
        cpy #$0f
        bcs dc_nn
        sta tmpc
        tya
        clc
        adc cyni
        tax
        lda tmpc
        sta cynames,x
        ldx cydepth
        inc cynl,x
dc_nn:  jsr src_adv
        jmp dc_nl
        ; Block ist eroeffnet: Tiefe erhoehen, Zeilenende pruefen
dc_done:
        inc cydepth
        jmp d_end

; d_endcycles: Direktive .endcycles. Letzten Block schliessen, ggf. Warnung W201, Bericht ablegen.
;   Ohne offenen Block: E210. Endet ueber d_end. Zerstoert A, X, Y.
d_endcycles:
        lda cydepth
        bne ec_ok
        lda #ERR_E210
        jmp as_error
ec_ok:  dec cydepth
        ldx cydepth
        ; Budget ueberschritten? Warnung nur, wenn Budget gesetzt und max > Budget (16 Bit, High-Byte zuerst; gleich ist ok)
        lda cybf,x                  ; Budget ueberschritten?
        beq ec_rep
        lda cymaxh,x
        cmp cybh,x
        bcc ec_rep
        bne ec_w
        lda cymaxl,x
        cmp cybl,x
        bcc ec_rep
        beq ec_rep
ec_w:   lda #WARN_W201
        jsr warn_add
        ; Bericht ablegen (nur die ersten 16): Offset = cyrepn * 8; Reihenfolge min, max, Budget, Merker, Namenslaenge
ec_rep: lda cyrepn
        cmp #$10
        bcs cy_ec_done
        ldx cydepth
        lda cyrepn
        asl
        asl
        asl
        tay                         ; Bericht: min, max, Budget, Merker
        lda cyminl,x
        sta cyrep,y
        lda cyminh,x
        sta cyrep + 1,y
        lda cymaxl,x
        sta cyrep + 2,y
        lda cymaxh,x
        sta cyrep + 3,y
        lda cybl,x
        sta cyrep + 4,y
        lda cybh,x
        sta cyrep + 5,y
        lda cybf,x
        sta cyrep + 6,y
        lda cynl,x
        sta cyrep + 7,y
        inc cyrepn
cy_ec_done:
        jmp d_end

; cy_close: am Ende des Quelltexts: offene Bloecke melden (E210).
;   Je offenem Block (von innen nach aussen) wird SRC auf die gemerkte Stelle des .cycles gesetzt (cypos) und err_add gerufen,
;   damit die Fehlermarkierung am .cycles steht. Zerstoert A, X, Y, SRC (am Quelltextende ohnehin bedeutungslos).
cy_close:
cc_l:   lda cydepth
        beq cc_d
        dec cydepth
        lda cydepth
        asl
        asl
        tay
        ldx #$00
cc_p:   lda cypos,y
        sta SRC,x
        iny
        inx
        cpx #$04
        bne cc_p
        lda #ERR_E210
        jsr err_add
        jmp cc_l
cc_d:   rts

; ---- Daten (siehe Kopf)
cydepth: .byte 0                    ; Zahl offener Bloecke
cyrepn:  .byte 0                    ; Zahl abgelegter Berichte
cyt:     .byte 0                    ; Arbeitszelle: Grundzyklen des Befehls
cyw:     .byte 0                    ; Arbeitszelle: unguenstigster Fall
cyni:    .byte 0                    ; Namensoffset des Blocks in Arbeit
tmpc:    .byte 0
tmpsrc:  .fill 4, 0
cyminl:  .fill 8, 0
cyminh:  .fill 8, 0
cymaxl:  .fill 8, 0
cymaxh:  .fill 8, 0
cybl:    .fill 8, 0
cybh:    .fill 8, 0
cybf:    .fill 8, 0
cynl:    .fill 8, 0
cypos:   .fill 32, 0
cynames = $1400                    ; 128 Byte im freien Bereich $1200-$17FF
cyrep = $1480                    ; 128 Byte im freien Bereich $1200-$17FF
