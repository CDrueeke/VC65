; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; ide.asm - Verbindung von Editor und Assembler (Etappe N1/N2): uebersetzt den Text des Editors und zeigt das Ergebnis.
; Haken fuer die Anzeigeschicht: Strg+E (SP_ASM) -> ide_asm, Strg+F (SP_PRG, nach Eingabe des Namens) -> ide_prg.
; Ablauf ide_asm: Editortext (ohne Luecke) nach $0800_0000 kopieren, Endemarke 0, Dateitabelle fuer Includes leeren
; ($0820_0000), Dateilader einschalten (Laufwerk 8), asm_run. Fehler: Cursor in die Zeile des ersten Fehlers (nur im
; Hauptprogramm), Meldung "E204 Zeile 12 Spalte 5". Erfolg: Meldung "OK 123 Byte", Ausgabe liegt im Attic ab $0850_0000.
; ide_prg schreibt die Ausgabe (ed_olen Byte) unter dem Namen ed_oname.
;
; Rolle: Klebeschicht zwischen Anzeige/Editor (disp.asm, ed.asm, file.asm) und Assembler (src/asm). Die Anzeigeschicht kennt
; diese Datei nicht direkt, sondern ruft ueber Haken (Vektoren disp_*v, von ide_init gesetzt) auf.
; Speicherplan (alles CPU-Sicht der IDE-Abbildung bzw. flache 32-Bit-Adressen, [E2],z / [E1],z):
;   $0800_0000..      Quelltext-Abbild fuer den Assembler (Kopie des Editortexts ohne Luecke, Endemarke 0) = SRCBASE
;   $0820_0000        Dateitabelle fuer .include (Ende-Marke 0 an erster Stelle; Includes kommen von der Platte)
;   $0850_0000..      Ausgabe des Assemblers (OUTBASE), Laenge in ed_olen (32 Bit), Ladeadresse in ed_ldadr
;   $0870_F000..      Probleme-Leiste: 3 Zeilen zu 64 Byte (PQ_BASE)
;   $0004_E000        Overlays VC65D/VC65X (ov_th = $E0); $0004_F500 Tabellen VC65T (ov_th = $F5), siehe ov_get
;   Bank 0 $1000..    KERNAL-Tabelle der Funktionstastenbelegung (fk_ptr, 32 Byte)
; Zeropage: E0..E3/E1/E2 (4-Byte-Zeiger des Editors, hier als Arbeitszeiger geborgt), ET+6/ET+7 (Textzeiger), P6 (Fehlerliste).
; Meldungen entstehen in dz_mbuf (mi = Laenge, hoechstens 59 Zeichen) und werden per ide_show angezeigt (dz_msg = MSG_DYN).
; Reihenfolge: ide_init (Haken) -> beim Start ide_ldtab (VC65T laden) -> Editorschleife -> ide_auto/ide_asm/ide_run/ide_prg ...
; Overlay-Regel: VC65D und VC65X teilen sich $E000; ov_ok / xo_ok zeigen, welches gerade geladen ist (nie beide 1).
; =====================================================================================================================

; ide_init: Haken der Anzeigeschicht auf die Routinen dieser Datei setzen und die Ausgabelaenge loeschen. Aendert A. Keine Eingabe.
ide_init:
        lda #<ide_xcall
        sta disp_xv
        lda #>ide_xcall
        sta disp_xv + 1
        lda #<ide_auto
        sta disp_autov
        lda #>ide_auto
        sta disp_autov + 1
        lda #$01
        sta ide_alln                ; "letzte geprueft"-Zeile ungleich 0: erste Taste loest sofort eine Pruefung aus
        lda #<ide_asm
        sta disp_asmv
        lda #>ide_asm
        sta disp_asmv + 1
        lda #<ide_prg
        sta disp_prgv
        lda #>ide_prg
        sta disp_prgv + 1
        lda #<ide_run
        sta disp_runv
        lda #>ide_run
        sta disp_runv + 1
        lda #<ide_dbg_stub          ; Strg+D: laedt bei Bedarf das Debugger-Overlay
        sta disp_dbgv
        lda #>ide_dbg_stub
        sta disp_dbgv + 1
        lda #<ide_dev
        sta disp_devv
        lda #>ide_dev
        sta disp_devv + 1
        lda #<ide_bp
        sta disp_bpv
        lda #>ide_bp
        sta disp_bpv + 1
        lda #$00                    ; noch keine Ausgabe: Strg+F / Strg+R melden "Assemble first"
        sta ed_olen
        sta ed_olen + 1
        sta ed_olen + 2
        sta ed_olen + 3
        rts

; ide_auto: nach jeder Taste aufgerufen. Wechselt die Cursorzeile und hat sich der Text seit dem letzten Uebersetzen geaendert, wird still
; uebersetzt (wie Strg+E, aber ohne Meldung und ohne Cursorsprung; Probleme-Leiste und rote Zeilen werden aktualisiert). Nur bei
; Texten unter 16 KB (das Uebersetzen dauert sonst zu lange). Carry gesetzt = es wurde uebersetzt.
ide_auto:
        lda ed_curline
        cmp ide_alln
        bne iau_c
        lda ed_curline + 1
        cmp ide_alln + 1
        beq iau_n
iau_c:  lda ed_curline              ; Zeile hat gewechselt: neuen Stand merken, dann pruefen, ob sich der Text geaendert hat
        sta ide_alln
        lda ed_curline + 1
        sta ide_alln + 1
        lda hp                      ; hp = Textstand (16-Bit-Zaehler, bei jeder Aenderung erhoeht), ide_ahp = Stand beim letzten Uebersetzen
        cmp ide_ahp
        bne iau_g
        lda hp + 1
        cmp ide_ahp + 1
        beq iau_n
iau_g:  lda ed_len + 3              ; Textlaenge (32 Bit) >= $4000 (16 KB)? Dann nicht automatisch uebersetzen
        ora ed_len + 2
        bne iau_n
        lda ed_len + 1
        cmp #$40
        bcs iau_n
        lda #$01
        sta ia_qt                   ; stiller Modus: ide_show/ia_msg unterdruecken Meldung und Cursorsprung
        jsr ide_asm
        lda #$00
        sta ia_qt
        sec
        rts
iau_n:  clc
        rts

; ide_asm (Strg+E): Editortext uebersetzen. Eingabe: Editortext (ed_*), Laufwerke ed_fdev/ed_sdev. Ausgabe: Meldung in dz_mbuf,
; ed_olen/ed_ldadr, Probleme-Leiste und Fehlerzeilen (ide_plist). Aendert alle Register und E0-E2.
ide_asm:
        lda hp                      ; Stand des Editortexts merken (Haltepunkte nur bei gleichem Stand)
        sta ide_ahp
        lda hp + 1
        sta ide_ahp + 1
        lda #$00                    ; Ziel $0800_0000 (E2 = Schreibzeiger, E0 = Lesezeiger im Editortext ab Position 0)
        sta E2
        sta E2 + 1
        sta E2 + 2
        sta E0
        sta E0 + 1
        sta E0 + 2
        sta E0 + 3
        lda #$08
        sta E2 + 3
ia_c:   jsr ed_eq_len               ; Ende des Editortextes erreicht? (Z=1)
        beq ia_d
        jsr ed_get                  ; Zeichen an Position E0 (ueberspringt die Editorluecke)
        ldz #$00
        sta [E2],z                  ; in das Attic-Abbild schreiben (32-Bit-Zeiger, Z = 0)
        jsr ed_inc                  ; E0 weiter (springt ueber die Luecke)
        inc E2                      ; 32-Bit-Zeiger hochzaehlen
        bne ia_c
        inc E2 + 1
        bne ia_c
        inc E2 + 2
        bne ia_c
        inc E2 + 3
        jmp ia_c
ia_d:   lda #$00                    ; Endemarke
        ldz #$00
        sta [E2],z
        jsr ide_ftab                ; Dateitabelle ($0820_0000) leeren
        lda #$00                    ; Basiszeiger des Assemblers: Quelle $0800_0000, Ausgabe $0850_0000
        sta SRCBASE
        sta SRCBASE + 1
        sta SRCBASE + 2
        sta OUTBASE
        sta OUTBASE + 1
        lda #$08
        sta SRCBASE + 3
        sta OUTBASE + 3
        lda #$50
        sta OUTBASE + 2
        lda ed_fdev                 ; Projektlaufwerk fuer Includes
        sta lddev
        lda ed_sdev                 ; Systemlaufwerk (Bibliotheken)
        sta ldsdev
        lda #$01
        sta ldon                    ; Dateilader des Assemblers einschalten
        jsr asm_run                 ; beide Durchlaeufe; Fehler in ercnt (Zaehler) / ERR (fataler Fehler ohne Listeneintrag)
        jsr ide_plist               ; Probleme-Leiste fuellen (vor der Meldung: benutzt dz_mbuf)
        lda ercnt                   ; Fehler vorhanden: erster Eintrag der Fehlerliste
        bne ia_err
        lda ERR                     ; fataler Fehler ohne Listeneintrag
        bne ia_err0
        sec                         ; Laenge = OUTP - OUTBASE
        lda OUTP
        sbc OUTBASE
        sta ed_olen
        lda OUTP + 1
        sbc OUTBASE + 1
        sta ed_olen + 1
        lda OUTP + 2
        sbc OUTBASE + 2
        sta ed_olen + 2
        lda OUTP + 3
        sbc OUTBASE + 3
        sta ed_olen + 3
        lda ldadr
        sta ed_ldadr
        lda ldadr + 1
        sta ed_ldadr + 1
        lda #$00
        sta mi
        ldx #<s_ok
        ldy #>s_ok
        jsr ide_cat
        lda ed_olen
        sta ide_n
        lda ed_olen + 1
        sta ide_n + 1
        jsr ide_dec
        ldx #<s_byte
        ldy #>s_byte
        jsr ide_cat
        jmp ide_show
ia_err0: sta ide_code               ; Fehler ohne Listeneintrag
        lda #$00
        sta ide_line
        sta ide_line + 1
        sta ide_file
        jmp ia_msg
ia_err: lda #$00                    ; erster Fehler der Liste
        sta pl_k
        sta pl_i
        jsr ide_ent
; ia_msg: Meldungstext "E204 Zeile 12 Spalte 5" bzw. "W2xx ..." fuer den Eintrag (ide_code, ide_line, ecol, ide_file) bauen.
; Wird auch von ide_plist benutzt (pl_q = 1 -> kein Cursorsprung, keine Anzeige).
ia_msg: lda #$00
        sta mi
        lda pl_k                    ; 0 = Fehlerliste, 1 = Warnungsliste
        bne ia_w
        lda #$45                    ; E
        jsr ide_ch
        lda ide_code
        cmp #$18                    ; Codes >= $18 unbekannt -> "???"
        bcs ia_q
        asl
        tax
        lda enum_t,x
        sta ide_n
        lda enum_t + 1,x
        sta ide_n + 1
        ora ide_n                   ; Tabelleneintrag 0 = keine Nummer vergeben -> "???"
        bne ia_nn
ia_q:   ldx #<s_q
        ldy #>s_q
        jsr ide_cat
        jmp ia_p
ia_w:   lda #$57                    ; W: Nummer = 200 + Code (unten 4 Bit)
        jsr ide_ch
        lda ide_code
        and #$0f
        clc
        adc #200
        sta ide_n
        lda #$00
        sta ide_n + 1
ia_nn:  jsr ide_dec
ia_p:   lda ide_line
        ora ide_line + 1
        beq ia_end
        ldx #<s_line
        ldy #>s_line
        jsr ide_cat
        lda ide_line
        sta ide_n
        lda ide_line + 1
        sta ide_n + 1
        jsr ide_dec
        lda ide_file                ; Datei <> 0: Fehler liegt in einer Include-Datei, Spalte nicht anzeigen
        beq ia_col
        ldx #<s_file
        ldy #>s_file
        jsr ide_cat
        lda ide_file
        sta ide_n
        lda #$00
        sta ide_n + 1
        jsr ide_dec
        jmp ia_end
ia_col: ldx #<s_col
        ldy #>s_col
        jsr ide_cat
        lda ecol
        sta ide_n
        lda ecol + 1
        sta ide_n + 1
        jsr ide_dec
        lda pl_q                    ; Probleme-Leiste oder stille Pruefung: kein Cursorsprung
        ora ia_qt
        bne ia_end
        lda ide_line                ; Cursor in die Fehlerzeile
        sta ed_garg
        lda ide_line + 1
        sta ed_garg + 1
        jsr ed_goto
ia_end: lda pl_q                    ; Probleme-Leiste: nicht anzeigen, nur Text liegt in dz_mbuf
        beq ia_sh
        rts
ia_sh:  jmp ide_show

; ide_ftab: Dateitabelle fuer .include leeren (Ende 0 bei $0820_0000); Includes kommen von der Platte. Aendert A, Z, E2.
ide_ftab:
        lda #$00
        sta E2
        sta E2 + 1
        lda #$20
        sta E2 + 2
        lda #$08
        sta E2 + 3
        ldz #$00
        lda #$00
        sta [E2],z
        rts


; ide_prg (Strg+F): Ausgabe unter ed_oname speichern (Meldung "Program saved" / "Error saving"). Das Speichern laeuft ueber
; ed_fsave_out, das den Dateinamen ed_fname/ed_fnl benutzt; darum wird der Quellname hier zeitweilig vertauscht und danach
; wiederhergestellt. Aendert alle Register.
ide_prg:
        lda ed_olen
        ora ed_olen + 1
        ora ed_olen + 2
        ora ed_olen + 3
        bne ip_go
        lda #$00
        sta mi
        ldx #<s_first
        ldy #>s_first
        jsr ide_cat
        jmp ide_show
ip_go:  ldx #$0f                    ; Namen vertauschen: Quellname merken, Ausgabename einsetzen
ip_s:   lda ed_fname,x
        sta ide_sv,x
        lda ed_oname,x
        sta ed_fname,x
        dex
        bpl ip_s
        lda ed_fnl
        sta ide_svn
        lda ed_onl
        sta ed_fnl
        jsr ed_fsave_out            ; Carry gesetzt = Fehler
        php                         ; Carry merken, waehrend der Quellname zurueckkopiert wird
        ldx #$0f
ip_r:   lda ide_sv,x
        sta ed_fname,x
        dex
        bpl ip_r
        lda ide_svn
        sta ed_fnl
        lda #$00
        sta mi
        plp
        bcs ip_e
        ldx #<s_saved
        ldy #>s_saved
        jsr ide_cat
        jmp ide_show
ip_e:   ldx #<s_serr
        ldy #>s_serr
        jsr ide_cat
        jmp ide_show

; ide_run (Strg+R): Ausgabe nach Bank 0 an die Ladeadresse kopieren und aufrufen (JSR; Rueckkehr per RTS). Einsprung: SYS-Adresse
; eines .basicstub, sonst die Ladeadresse. Das Testprogramm laeuft in der Standardabbildung; die IDE (Bank 4) bleibt unberuehrt.
; ide_fkoff / ide_fkon: Das KERNAL belegt HELP und die Funktionstasten mit Zeichenfolgen (GETIN liefert dann Text wie \"help\" oder DIR statt $84,
; $85 ...). Die Laengentabelle der Belegung liegt in Bank 0 bei $1000 (16 Byte, Zeichenfolgen ab $1010): ide_fkoff sichert die ersten 32 Byte und
; belegt jede Taste mit genau ihrem Tastencode (fk_new; Laenge 0 liefert GETIN nichts, wie der Handtest zeigte); ide_fkon stellt sie wieder her (vor Programmen und beim Verlassen nach BASIC).
ide_fkoff:
        jsr fk_ptr                  ; E2 = $0000_1000 (Bank 0)
        ldx #$00
        ldz #$00
fk_o:   lda [E2],z                  ; alte Belegung nach fk_sv, neue (fk_new) einsetzen
        sta fk_sv,x
        lda fk_new,x
        sta [E2],z
        inx
        inz
        cpx #$20
        bne fk_o
        rts
ide_fkon:
        jsr fk_ptr
        ldx #$00
        ldz #$00
fk_i:   lda fk_sv,x
        sta [E2],z
        inx
        inz
        cpx #$20
        bne fk_i
        rts
; fk_ptr: E2 = $0000_1000, Tabelle der Funktionstastenbelegung des KERNAL in Bank 0. Aendert A.
fk_ptr: lda #$00
        sta E2
        sta E2 + 2
        sta E2 + 3
        lda #$10
        sta E2 + 1                  ; $0000_1000
        rts
fk_sv:  .fill 32, 0                 ; gesicherte KERNAL-Belegung (16 Laengen + 16 Zeichen)
; Neue Belegung: je Taste (Eintrag n = F(n+1); 12 = F13, 13 = F14, 14 = HELP, 15 = Umschalt+RUN) ein Zeichen, der Tastencode der IDE
; (siehe kmap_in in disp.asm); 0 = keine Zeichenfolge. Zuerst 16 Laengen, dann die Zeichen in Eintragsreihenfolge.
fk_new: .byte 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 0
        .byte $85, $89, $86, $8a, $87, $8b, $88, $8c, $10, $15, $16, $17, $84, 0, 0, 0

; ide_sidoff: alle vier SID-Chips stumm (Register $00-$18 auf 0; flache Adresse $0FFD_3400, 32 Byte je SID)
; (flache Adresse, weil in der IDE-Abbildung $D000 nicht die E/A-Bausteine zeigt). Aendert A, X, Z, E2.
ide_sidoff:
        lda #$00
        sta E2
        lda #$34
        sta E2 + 1
        lda #$fd
        sta E2 + 2
        lda #$0f
        sta E2 + 3
        ldx #$04
so_l:   ldz #$18                    ; 25 Register ($18..$00) je SID
        lda #$00
so_w:   sta [E2],z
        dez
        bpl so_w
        clc
        lda E2
        adc #$20                    ; naechster SID (Abstand $20)
        sta E2
        dex
        bne so_l
        rts

; ide_nmivec: RAM-Vektor $0000_FFFA (NMI) in Bank 0 auf knmir (Bruecke, src/ide/boot.asm) setzen. Programme, die das KERNAL ausblenden
; ($01 = $35, zum Beispiel prallball), nehmen den NMI (RESTORE) sonst ueber einen nie gesetzten RAM-Vektor und laufen ins Leere.
ide_nmivec:
        lda #$fa
        sta E2
        lda #$ff
        sta E2 + 1
        lda #$00
        sta E2 + 2
        sta E2 + 3
        ldz #$00
        lda #<knmir
        sta [E2],z
        inz
        lda #>knmir
        sta [E2],z
        ldz #$00
        rts

; ide_kc: KERNAL-Routine A/X (tief/hoch) ueber die Bruecke aufrufen (setzt kc_t, dann kcall; A/X/Y des Aufrufs gehen verloren)
; IOINIT/SCINIT arbeiten mit der Zeropage des KERNAL (z. B. dem 32-Bit-Zeiger bei $E0): B muss dafuer 0 sein. kcall laesst B unveraendert, und in
; der IDE zeigt B auf Seite IDE_B ($1F): SCINIT schrieb dann ueber die Zeiger der IDE (Zeropage der IDE verdorben, Schreibzugriff ins Leere).
ide_kc: sta kc_t
        stx kc_t + 1
        tba
        pha
        lda #$00
        tab
        jsr kcall
        pla
        tab
        rts

; ide_run (Strg+R): Ausgabe laden und starten (Ablauf siehe unten); Meldung "Program ended" bzw. "Program interrupted".
ide_run:
        jsr ide_prep                ; Ausgabe nach Bank 0 kopieren, kr_t setzen; Carry = Fehler (Meldung steht schon)
        bcs ir_x
        lda #$06                    ; Standardpalette fuer das Testprogramm (die IDE setzt ihr Farbschema danach in disp_init wieder)
        jsr ide_xcall
        jsr ide_nmivec              ; RESTORE auch bei ausgeblendetem KERNAL ($01 = $35) abfangen
        jsr ide_fkon                ; Programm sieht die Funktionstastenbelegung des KERNAL
        jsr krun                    ; Testprogramm laeuft hier (Standardabbildung); Rueckkehr per RTS oder ueber Falle/NMI
        jsr ide_fkoff               ; IDE-Belegung der Funktionstasten wieder einsetzen
        jsr ide_sidoff              ; Klang aus (Programm beendet oder durch RESTORE unterbrochen)
        lda #$07                    ; ZUERST die VIC-IV-Register wie vor dem Programm herstellen (Zeichenmodi, Zeiger auf Bildschirm und Farb-RAM ...):
        jsr ide_xcall               ; das KERNAL (SCINIT) rechnet damit und schrieb sonst mit den Zeigern des Programms ins Leere
        lda #<$ff84                 ; Grundzustand: KERNAL IOINIT (CIA, SID, VIC) und SCINIT (Bildschirm, Rahmen, Hintergrund, Sprites aus),
        ldx #>$ff84                 ; danach nochmals die Register der IDE und Farben, Zeichensatz und 50-Zeilen-Bild (disp_init)
        jsr ide_kc
        lda #<$ff81
        ldx #>$ff81
        jsr ide_kc
        lda #$07
        jsr ide_xcall
        jsr disp_init
        lda #$00
        sta mi
        lda kr_trap                 ; ungleich 0: durch Notfalltaste (NMI) oder BRK unterbrochen
        beq irn_dn
        ldx #<s_brk
        ldy #>s_brk
        jmp irn_ms
irn_dn:  ldx #<s_done
        ldy #>s_done
irn_ms:  jsr ide_cat
        jmp ide_show
ir_x:   rts

; ide_prep: Ausgabe nach Bank 0 kopieren und den Einsprung nach kr_t legen; Carry gesetzt = Fehler (Meldung steht schon)
; Quelle $0850_0000 (E1), Ziel E2 = Bank 0 ab Ladeadresse; Zaehler ide_cnt (32 Bit) = ed_olen. Aendert alle Register, E1, E2.
ide_prep:
        lda ed_olen
        ora ed_olen + 1
        ora ed_olen + 2
        ora ed_olen + 3
        bne ir_go
        lda #$00
        sta mi
        ldx #<s_first
        ldy #>s_first
        jsr ide_cat
        jsr ide_show
        sec
        rts
ir_go:  lda ed_ldadr + 1
        cmp #$20                    ; Bank 0 unterhalb von $2000 gehoert der IDE-Bruecke und den Puffern
        bcs ir_ok
        lda #$00
        sta mi
        ldx #<s_low
        ldy #>s_low
        jsr ide_cat
        jsr ide_show
        sec
        rts
ir_ok:  lda #$00                    ; Quelle $0850_0000 (Attic), Ziel Bank 0 ab Ladeadresse
        sta E1
        sta E1 + 1
        sta E2 + 2
        sta E2 + 3
        lda #$50
        sta E1 + 2
        lda #$08
        sta E1 + 3
        lda ed_ldadr
        sta E2
        lda ed_ldadr + 1
        sta E2 + 1
        ldx #$03
ir_c:   lda ed_olen,x
        sta ide_cnt,x
        dex
        bpl ir_c
ir_l:   lda ide_cnt                 ; Byteweise kopieren (langsam, aber einfach); Schleife bis der 32-Bit-Zaehler 0 ist
        ora ide_cnt + 1
        ora ide_cnt + 2
        ora ide_cnt + 3
        beq ir_d
        ldz #$00
        lda [E1],z
        sta [E2],z
        inc E1
        bne ir_a
        inc E1 + 1
        bne ir_a
        inc E1 + 2
        bne ir_a
        inc E1 + 3
ir_a:   inc E2
        bne ir_b
        inc E2 + 1
ir_b:   lda ide_cnt                 ; 32-Bit-Zaehler herunterzaehlen (Borrow-Kette)
        bne ir_e
        lda ide_cnt + 1
        bne ir_f
        lda ide_cnt + 2
        bne ir_g
        dec ide_cnt + 3
ir_g:   dec ide_cnt + 2
ir_f:   dec ide_cnt + 1
ir_e:   dec ide_cnt
        jmp ir_l
ir_d:   lda ed_ldadr                ; Einsprung = Ladeadresse, ausser bei einem BASIC-Start (Zeile mit SYS)
        sta kr_t
        lda ed_ldadr + 1
        sta kr_t + 1
        lda #$00                    ; Byte 4 der Ausgabe = SYS-Token $9E? (Ausgabe beginnt mit der Ladeadresse, dann Zeiger+Zeilennr.)
        sta E1
        sta E1 + 1
        lda #$50
        sta E1 + 2
        lda #$08
        sta E1 + 3
        ldz #$04
        lda [E1],z
        cmp #$9e
        bne ir_go2
        lda #$00
        sta kr_t
        sta kr_t + 1
        ldz #$05
ir_dg:  lda [E1],z
        sec
        sbc #$30
        cmp #$0a
        bcs ir_go2
        sta ide_d
        lda kr_t                    ; kr_t = kr_t * 10 + Ziffer (x10 = x8 + x2: zweimal <<1, + alt, nochmal <<1)
        sta ide_n
        lda kr_t + 1
        sta ide_n + 1
        asl kr_t
        rol kr_t + 1
        asl kr_t
        rol kr_t + 1
        clc
        lda kr_t
        adc ide_n
        sta kr_t
        lda kr_t + 1
        adc ide_n + 1
        sta kr_t + 1
        asl kr_t
        rol kr_t + 1
        clc
        lda kr_t
        adc ide_d
        sta kr_t
        bcc ir_dn
        inc kr_t + 1
ir_dn:  inz
        bne ir_dg
ir_go2: clc
        rts

; ---- Overlays und Haltepunkte ------------------------------------------------------------------------------------------
BPMAX   = 16                        ; Haltepunkte; danach 4 Zwischenhaltepunkte (Schritte)
BPALL   = 20
OV_ENTRY = $e000                    ; Einsprung des Overlays (Debugger), siehe src/debug/overlay.asm

; ide_dbg_stub: Debugger-Overlay (Datei VC65D) bei Bedarf nach Bank 4 ($D000) laden und dessen Sitzung starten; das Overlay laeuft auf
; derselben Stapeltiefe (Sprung, kein Aufruf), siehe dbg.asm
ide_dbg_stub:
        jsr ov_ensure
        bcs ods_err
        jmp OV_ENTRY
ods_err:
        lda #$00
        sta mi
        ldx #<s_novl
        ldy #>s_novl
        jsr ide_cat
        jmp ide_show

; ov_ensure: Overlay geladen? Sonst Datei ov_name lesen (2 Byte Kopf ueberspringen) und nach $0004_E000 schreiben. Carry gesetzt = Fehler
ov_ensure:
        lda ov_ok
        beq oe_ld
        clc
        rts
oe_ld:  lda #$e0                    ; Zielseite $E0 -> $0004_E000
        sta ov_th
        ldx #<ov_name
        ldy #>ov_name
        jsr ov_get
        bcs oe_r
        lda #$01
        sta ov_ok
        lda #$00
        sta xo_ok                   ; das Debugger-Overlay ersetzt die Werkzeuge
        sta oa_ok                   ; ... und das Overlay A (Funktionen, funcres.asm) (gleicher Speicherbereich $E000)
        clc
oe_r:   rts

; ide_xcall: Werkzeug A (0 Zeile ausrichten, 1 alles ausrichten) aus dem Werkzeug-Overlay VC65X; laedt es bei Bedarf (es ersetzt dann das
; Debugger-Overlay, das beim naechsten Strg+D neu geladen wird)
ide_xcall:
        sta xo_n
        lda xo_ok
        bne xc_go
        lda #$e0
        sta ov_th
        ldx #<xo_name
        ldy #>xo_name
        jsr ov_get
        php
        jsr disp_vic                ; das Laden von der Diskette verstellt SCRNPTR (50 Zeilen)
        plp
        bcs xc_err
        lda #$01
        sta xo_ok
        lda #$00
        sta ov_ok
        sta oa_ok                   ; das Werkzeug-Overlay ersetzt auch das Overlay A
xc_go:  lda xo_n                    ; Einsprung $E000 + 3 * A (Sprungtabelle aus JMP-Befehlen zu je 3 Byte, siehe xtools.asm/xoverlay.asm)
        asl
        clc
        adc xo_n
        sta xo_t
        lda #$e0
        sta xo_t + 1
        jmp (xo_t)
xc_err: lda #$00
        sta mi
        ldx #<s_novx
        ldy #>s_novx
        jsr ide_cat
        jmp ide_show

; ide_ldtab: Tabellendatei VC65T (Befehlstabelle, src/ide/tdata.asm) beim Start nach $0004_F500 laden. Carry gesetzt = Fehler
ide_ldtab:
        lda #$f5
        sta ov_th
        ldx #<tt_name
        ldy #>tt_name
        ; weiter mit ov_get

; ov_get: Datei (Name mit 5 Zeichen bei X/Y) von der Systemdisk lesen, ohne die zwei Byte Kopf nach $0004_xx00 schreiben (xx = ov_th)
; Ausgabe: Carry gesetzt = Fehler. Verfahren: Datei blockweise (hoechstens 256 Byte) in den Puffer fbuf lesen, dabei laeuft das KERNAL
; mit B = 0 (Zeropage $00xx); danach Basisregister B zurueck (ov_b) und den Puffer ueber den 32-Bit-Zeiger E2 nach Bank 4 kopieren.
; Der Zeiger wandert zwischen den Bloecken in ov_dl/ov_dh, weil E2 beim KERNAL-Zugriff (B = 0) nicht dieselbe Zeropage waere.
; KN_* sind Sprungstuecke zur Bruecke (KERNAL in der Standardabbildung). Logische Datei 2, Sekundaeradresse 2.
ov_get: stx ov_np
        sty ov_np + 1
        tba                         ; B retten; das KERNAL erwartet B = 0
        sta ov_b
        lda #$00
        tab
        lda #$05
        ldx ov_np
        ldy ov_np + 1
        jsr KN_SETNAM
        lda #$02
        ldx ed_sdev
        ldy #$02
        jsr KN_SETLFS
        jsr KN_OPEN
        bcs oe_bad
        lda #$00                    ; Ziel $0004_xx00 (Zeiger in ov_dl/ov_dh, E2 wird erst bei wieder eingestellter Basisseite gesetzt)
        sta ov_dl
        sta ov_h
        lda ov_th
        sta ov_dh
oe_ch:  ldx #$02                    ; Eingabekanal = logische Datei 2 (nach jedem Block neu, weil CLRCHN ihn loest)
        jsr KN_CHKIN
        ldx #$00
        stx ov_eof
oe_rd:  jsr KN_CHRIN
        sta fbuf,x
        inx
        jsr KN_READST
        sta ov_st
        and #$3f                    ; Bits 0-5 des Status = Fehler; Bit 6 (EOF) wird unten ausgewertet
        bne oe_bad2
        lda ov_st
        and #$40
        beq oe_r2
        lda #$01
        sta ov_eof
        jmp oe_wr
oe_r2:  cpx #$00                    ; X auf 0 umgelaufen = Puffer (256 Byte) voll
        bne oe_rd
oe_wr:  stx ov_n                    ; Anzahl (0 = 256)
        lda #$00
        cpx #$00
        bne oe_f0
        lda #$01                    ; voller Block: 256 Byte
oe_f0:  sta ov_full
        jsr KN_CLRCHN
        lda ov_b                    ; Basisregister zurueck: ab hier gelten wieder die Zeropage-Zeiger der IDE (E2)
        tab
        lda ov_dl
        sta E2
        lda ov_dh
        sta E2 + 1
        lda #$04                    ; Bank 4, Megabyte 0: $0004_xxxx
        sta E2 + 2
        lda #$00
        sta E2 + 3
        ldx #$00
oe_cp:  lda ov_full
        bne oe_c2
        cpx ov_n
        beq oe_cd
oe_c2:
        lda ov_h                    ; die ersten zwei Byte der Datei (Ladeadresse) auslassen
        cmp #$02
        bcs oe_st
        inc ov_h
        jmp oe_nx
oe_st:  lda fbuf,x
        ldz #$00
        sta [E2],z
        inc E2
        bne oe_nx
        inc E2 + 1
oe_nx:  inx
        bne oe_cp
        lda ov_full                 ; X ist umgelaufen: nur bei vollem Block ist das das Ende
        beq oe_cd
oe_cd:  lda E2
        sta ov_dl
        lda E2 + 1
        sta ov_dh
        lda ov_eof
        bne oe_end
        lda #$00
        tab
        jmp oe_ch
oe_end: lda #$00
        tab
        lda #$02
        jsr KN_CLOSE
        lda ov_b
        tab
        clc
        rts
oe_bad2: jsr KN_CLRCHN
oe_bad: lda #$02
        jsr KN_CLOSE
        lda ov_b
        tab
        sec
        rts

; ide_bp (Strg+G): Haltepunkt der Cursorzeile umschalten (Adresse aus der Zeilentabelle des letzten Uebersetzens)
; Die Zeilentabelle (lt_cnt Eintraege zu 8 Byte, ab LT_B2/LT_B3) liegt im Attic: Byte 0-2 = Textposition der Zeile im Quelltext-
; Abbild, Byte 4-5 = Programmadresse. dbg_bp: BPALL Eintraege zu 4 Byte (Adresse lo/hi, Original-Opcode waehrend BRK eingefuegt ist, Status Byte 3: 0 frei, 1 aktiv, 2 Zwischenhalt, Bit 7 = BRK eingefuegt);
; die ersten BPMAX sind Haltepunkte des Benutzers, die letzten vier Zwischenhaltepunkte des Debuggers (Schritte). Aendert alle Register.
ide_bp: lda ide_ahp                 ; Quelltext seit dem Uebersetzen veraendert?
        cmp hp
        bne ib_stale
        lda ide_ahp + 1
        cmp hp + 1
        bne ib_stale
        lda lt_cnt
        ora lt_cnt + 1
        bne ib_ok
ib_stale:
        lda #$00
        sta mi
        ldx #<s_first
        ldy #>s_first
        jsr ide_cat
        jmp ide_show
ib_ok:  ldx #$03                    ; Zeilenanfang und -ende des Cursors (Stellen im Editor = Stellen im Quelltext-Abbild)
ib_c:   lda ed_cur,x
        sta E0,x
        dex
        bpl ib_c
        jsr ed_ls
        ldx #$03
ib_s:   lda E0,x
        sta ib_ls,x
        dex
        bpl ib_s
        jsr ed_le
        ldx #$03
ib_e:   lda E0,x
        sta ib_le,x
        dex
        bpl ib_e
        lda #$00                    ; Tabelle durchsuchen: erster Eintrag mit ib_ls <= Stelle < ib_le
        sta E1
        sta E1 + 1
        lda #LT_B2
        sta E1 + 2
        lda #LT_B3
        sta E1 + 3
        lda #$00
        sta ib_cnt
        sta ib_cnt + 1
dq_ib_l:   lda ib_cnt
        cmp lt_cnt
        bne ib_t
        lda ib_cnt + 1
        cmp lt_cnt + 1
        beq ib_none
ib_t:   ldz #$00
        lda [E1],z
        sta ib_p
        inz
        lda [E1],z
        sta ib_p + 1
        inz
        lda [E1],z
        sta ib_p + 2
        lda ib_p                    ; Stelle >= ib_ls ? (24-Bit-Vergleich: cmp + sbc-Kette, nur das Carry zaehlt)
        cmp ib_ls
        lda ib_p + 1
        sbc ib_ls + 1
        lda ib_p + 2
        sbc ib_ls + 2
        bcc dq_ib_n
        lda ib_p                    ; Stelle < ib_le ?
        cmp ib_le
        lda ib_p + 1
        sbc ib_le + 1
        lda ib_p + 2
        sbc ib_le + 2
        bcs dq_ib_n
        ldz #$04
        lda [E1],z
        sta ib_a
        inz
        lda [E1],z
        sta ib_a + 1
        jmp ib_tog
dq_ib_n:   clc
        lda E1
        adc #$08
        sta E1
        bcc ib_i
        inc E1 + 1
        bne ib_i
        inc E1 + 2
ib_i:   inc ib_cnt
        bne dq_ib_l
        inc ib_cnt + 1
        jmp dq_ib_l
ib_none:
        lda #$00
        sta mi
        ldx #<s_nobp
        ldy #>s_nobp
        jsr ide_cat
        jmp ide_show
ib_tog: ldx #$00                    ; vorhandenen Haltepunkt entfernen?
ib_f:   lda dbg_bp + 3,x
        cmp #$01
        bne ib_fn
        lda dbg_bp,x
        cmp ib_a
        bne ib_fn
        lda dbg_bp + 1,x
        cmp ib_a + 1
        bne ib_fn
        lda #$00
        sta dbg_bp + 3,x            ; Eintrag freigeben
        lda #$00
        sta mi
        ldx #<s_bpoff
        ldy #>s_bpoff
        jsr ide_cat
        jmp ib_msg
ib_fn:  inx
        inx
        inx
        inx
        cpx #BPMAX * 4
        bne ib_f
        ldx #$00                    ; freien Platz suchen
ib_g:   lda dbg_bp + 3,x
        beq ib_set
        inx
        inx
        inx
        inx
        cpx #BPMAX * 4
        bne ib_g
        lda #$00
        sta mi
        ldx #<s_bpfull
        ldy #>s_bpfull
        jsr ide_cat
        jmp ide_show
ib_set: lda ib_a
        sta dbg_bp,x
        lda ib_a + 1
        sta dbg_bp + 1,x
        lda #$01
        sta dbg_bp + 3,x
        lda #$00
        sta mi
        ldx #<s_bpon
        ldy #>s_bpon
        jsr ide_cat
ib_msg: lda #$24                    ; " $xxxx"
        jsr ide_ch
        lda ib_a + 1
        jsr ide_hex2
        lda ib_a
        jsr ide_hex2
        jmp ide_show

; ide_hex2: A als zweistellige Hexzahl (a-f klein) an die Meldung anhaengen. Aendert A, X (ide_ch). Carry-Trick: nach cmp #$0a
; ist C=1 bei A>=10, dann ergibt "adc #$56" (mit Carry +$57) fuer 10..15 die Zeichen $61..$66 (Kleinbuchstaben a-f); bei A<10 (C=0) liefert adc #$30 '0'..'9'.
ide_hex2:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr ih_1
        pla
ih_1:   and #$0f
        cmp #$0a
        bcc ih_2
        adc #$56
        jmp ide_ch
ih_2:   adc #$30
        jmp ide_ch

; ide_plist: Eintraege der Probleme-Leiste (bis zu drei: zuerst Fehler, dann Warnungen) aus der Fehler- und Warnungsliste des
; letzten Durchlaufs; die Zeilen ("E205 Zeile 10 Spalte 13") entstehen wie die Meldung (ia_msg, ohne Cursorsprung) und liegen im
; Attic ab PQ_BASE (3 Zeilen zu 64 Byte)
PQ_BASE = $0870f000
ide_plist:
        jsr ide_emark
        lda #$00
        sta pq_n
        sta pl_k
        lda #$01
        sta pl_q
pl_k0:  lda #$00                    ; pl_k = Liste (0 Fehler, 1 Warnungen), pl_i = Index darin, pq_n = bisherige Zeilen (max. 3)
        sta pl_i
pl_e:   ldx pl_k
        lda pl_i
        cmp ercnt,x
        bcs pl_nx
        lda pq_n
        cmp #$03
        bcs pl_r
        jsr ide_ent
        jsr ia_msg                  ; Text nach dz_mbuf (pl_q = 1: kein Cursorsprung, nicht anzeigen)
        lda pq_n
        jsr pq_ptr
        ldx #$00
        ldz #$00
pl_cp:  lda dz_mbuf,x
        sta [E2],z
        inx
        inz
        cpx #60
        bne pl_cp
        ldx pq_n
        lda pl_k
        sta pq_kind,x
        inc pq_n
        inc pl_i
        jmp pl_e
pl_nx:  inc pl_k
        lda pl_k
        cmp #$02
        bne pl_k0
pl_r:   lda #$00
        sta pl_q
        rts

; pq_ptr: A = Zeile -> E2 = 32-Bit-Zeiger auf die Zeile im Attic (Zeile * 64)
pq_ptr:
        lsr                         ; A * 64 = (A >> 2) mit Rest in den hohen Bits: drei Rotationen ueber das Carry schieben
        ror                         ; die zwei niedrigen Bits von A in die Bits 7-6 (A ist hoechstens 2 -> kein Ueberlauf in E2+1)
        ror
        and #$c0
        sta E2
        lda #>PQ_BASE
        sta E2 + 1
        lda #$70
        sta E2 + 2
        lda #$08
        sta E2 + 3
        rts

; ide_emark: Zeilen der Fehler im Hauptprogramm (Datei 0, hoechstens 16) fuer die Faerbung im Editor merken
; (ed_elo/ed_ehi = Zeilennummern, ed_en = Anzahl, ed_ehp = Textstand, zu dem sie gehoeren). Aendert A, X, pl_i, pl_k.
ide_emark:
        lda #$00
        sta ed_en
        sta pl_k
        sta pl_i
        lda hp
        sta ed_ehp
        lda hp + 1
        sta ed_ehp + 1
iem_l:  lda pl_i
        cmp ercnt
        bcs iem_r
        cmp #$10
        bcs iem_r
        jsr ide_ent
        lda ide_file
        bne iem_n
        ldx ed_en
        lda ide_line
        sta ed_elo,x
        lda ide_line + 1
        sta ed_ehi,x
        inc ed_en
iem_n:  inc pl_i
        jmp iem_l
iem_r:  rts

; ide_ent: Eintrag pl_i der Liste pl_k laden: ide_code, ide_file, ide_line (Zeile), ecol (Spalte)
; (err_linecol und err_ptr stammen aus err.asm des Assemblers; P6 zeigt auf den Listeneintrag: Byte 0 Code, Byte 1 Datei)
ide_ent:
        lda pl_k
        sta lsel
        lda pl_i
        jsr err_linecol
        lda pl_k
        sta lsel
        lda pl_i
        jsr err_ptr
        ldz #$00
        lda [P6],z
        sta ide_code
        ldz #$01
        lda [P6],z
        sta ide_file
        lda eline
        sta ide_line
        lda eline + 1
        sta ide_line + 1
        rts

; ide_show: Meldung mit 0 beenden und anzeigen (dz_msg = MSG_DYN: die Anzeige nimmt den Text aus dz_mbuf). Nicht in der stillen Pruefung.
ide_show:
        lda ia_qt                   ; stille Pruefung: keine Meldung
        beq is_go
        rts
is_go:  ldx mi
        lda #$00
        sta dz_mbuf,x
        lda #MSG_DYN
        sta dz_msg
        rts

; ide_ch: A an die Meldung anhaengen (hoechstens 59 Zeichen; ein Zeichen mehr fuer die Endemarke 0). Aendert X.
ide_ch: ldx mi
        cpx #59
        bcs ic_r
        sta dz_mbuf,x
        inc mi
ic_r:   rts

; ide_cat: Zeichenkette (X = lo, Y = hi, mit 0 beendet) anhaengen. Aendert A, X, Y, ET+6/ET+7 (Y wird in der Schleife gerettet).
ide_cat:
        stx ET + 6
        sty ET + 7
        ldy #$00
ct_l:   lda (ET + 6),y
        beq ct_r
        phy
        jsr ide_ch
        ply
        iny
        bne ct_l
ct_r:   rts

; ide_dec: ide_n (16 Bit) als Dezimalzahl anhaengen (fuehrende Nullen unterdrueckt; Zerstoert ide_n). Wiederholte Subtraktion der
; Zehnerpotenzen aus dec_lo/dec_hi (10000, 1000, 100, 10); der Rest sind die Einer.
ide_dec:
        lda #$00
        sta ide_z
        ldx #$00
dc_l:   lda #$00
        sta ide_d
dc_s:   lda ide_n + 1
        cmp dec_hi,x
        bcc dc_o
        bne dc_sub
        lda ide_n
        cmp dec_lo,x
        bcc dc_o
dc_sub: sec
        lda ide_n
        sbc dec_lo,x
        sta ide_n
        lda ide_n + 1
        sbc dec_hi,x
        sta ide_n + 1
        inc ide_d
        jmp dc_s
dc_o:   lda ide_d
        bne dc_p
        ldy ide_z
        beq dc_n
dc_p:   inc ide_z
        clc
        adc #$30
        phx
        jsr ide_ch
        plx
dc_n:   inx
        cpx #$04
        bne dc_l
        lda ide_n                   ; Einer immer ausgeben
        clc
        adc #$30
        jmp ide_ch

dec_lo: .byte <10000, <1000, <100, <10
dec_hi: .byte >10000, >1000, >100, >10
; Fehlercode des Assemblers (Index) -> Nummer E2xx; 0 = keine Nummer (zeigt "???"). Bei Warnungen: W = 200 + Code (siehe ia_w).
enum_t: .word 0, 201, 202, 203, 204, 205, 206, 207, 208, 0, 210, 211, 216, 213, 209, 207, 212, 214, 218, 215, 212, 219, 300, 900, 301, 901
s_ok:    .byte "OK ", 0
s_byte:  .byte " bytes", 0
s_q:     .byte "???", 0
s_line:  .byte " line ", 0
s_col:   .byte " col ", 0
s_file:  .byte " in file ", 0
s_first: .byte "Assemble first", 0
s_saved: .byte "Program saved", 0
s_done:  .byte "Program ended", 0
s_brk:   .byte "Program interrupted (emergency key)", 0
s_novl:  .byte "File VC65D missing", 0
s_nobp:  .byte "No output here", 0
s_bpon:  .byte "Breakpoint set", 0
s_bpoff: .byte "Breakpoint removed", 0
s_bpfull: .byte "Too many breakpoints", 0
s_low:   .byte "Load address below $2000", 0
s_serr:  .byte "Error saving", 0
; ---- Variablen -----------------------------------------------------------------------------------------------------
mi:       .byte 0                   ; Laenge der Meldung in dz_mbuf
ide_n:    .word 0                   ; Zahl fuer ide_dec
ide_cnt:  .fill 4, 0                ; Restzaehler beim Kopieren der Ausgabe
ide_ahp:  .word 0                   ; Textstand (hp) beim letzten Uebersetzen
ov_ok:    .byte 0                   ; 1: Debugger-Overlay VC65D geladen
ov_b:     .byte 0
ov_h:     .byte 0
ov_eof:   .byte 0
ov_st:    .byte 0
ov_n:     .byte 0
ov_full:  .byte 0
ov_dl:    .byte 0
ov_dh:    .byte 0
ov_name:  .byte "VC65D"
tt_name:  .byte "VC65T"
xo_name:  .byte "VC65X"
xo_ok:    .byte 0                   ; 1: Werkzeug-Overlay VC65X geladen
xo_n:     .byte 0
xo_t:     .word 0
s_novx:   .byte "File VC65X missing", 0
ov_th:    .byte 0                   ; Zielseite (hoch) fuer ov_get
ov_np:    .word 0                   ; Namenszeiger
dbg_bp:   .fill BPALL * 4, 0
ib_ls:    .fill 4, 0
ib_le:    .fill 4, 0
ib_p:     .fill 3, 0
ib_a:     .word 0
ib_cnt:   .word 0
ide_d:    .byte 0
ide_z:    .byte 0
ide_code: .byte 0
pq_n:     .byte 0                   ; Eintraege (hoechstens 3)
pq_kind:  .byte 0, 0, 0             ; 0 Fehler, 1 Warnung
pl_k:     .byte 0
pl_i:     .byte 0
ia_qt:    .byte 0                   ; 1: stille Pruefung (ide_auto)
ide_alln: .word 0                   ; Cursorzeile bei der letzten Pruefung
pl_q:     .byte 0                   ; 1: ia_msg fuer die Probleme-Leiste (kein Cursorsprung, keine Anzeige)
ide_file: .byte 0
ide_line: .word 0
ide_svn:  .byte 0
ide_sv:   .fill 16, 0

; ide_dev (Strg+A): Projektlaufwerk zwischen 8 und 9 umschalten, Meldung "Project drive 9". Aendert alle Register.
ide_dev:
        lda ed_fdev
        eor #$01                    ; 8 <-> 9
        sta ed_fdev
        lda #$00
        sta mi
        ldx #<s_pdev
        ldy #>s_pdev
        jsr ide_cat
        lda ed_fdev
        clc
        adc #$30
        jsr ide_ch
        jmp ide_show
s_pdev: .byte "Project drive ", 0
