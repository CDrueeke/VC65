; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; file.asm - Datei laden und speichern (Editor N1) ueber die KERNAL-Dateiroutinen (Laufwerk ed_fdev, Vorgabe 8: SD-Karte
; oder eingelegtes D81). Name in ed_fname (hoechstens 16 Zeichen, Laenge ed_fnl); Kleinbuchstaben werden fuer das Laufwerk
; zu Grossbuchstaben. Es gibt nur Dateinamen ohne Ordner (Ordner folgen mit dem Hyppo-Direktzugriff, wie beim Dateilader).
; Laden: ersetzt den Text (ed_clear); Zeilenenden CR, CRLF und LF werden zu LF, Nullbytes entfallen; schlaegt das Oeffnen
; oder das erste Lesen fehl, bleibt der Text unveraendert. Speichern: schreibt den Text unveraendert (LF) als PRG-Datei (rohe Bytes) und
; ersetzt eine vorhandene Datei ("@0:", Typ PRG: "\@0:NAME,P,W"). Rueckgabe: Carry geloescht = gut; Carry gesetzt, A = 1 Oeffnen/Lesen/Schreiben
; fehlgeschlagen, 2 Text zu gross (der Anfang wurde geladen), 3 Lesefehler mitten in der Datei (Teiltext geladen).
; Die Basisseite wird fuer die KERNAL-Aufrufe auf 0 geschaltet und zurueck; Interrupts sperrt der Aufrufer.
; Eine leere Datei meldet das Laufwerk als Lesefehler (Status $42): sie laesst sich nicht laden.
;
; Rolle/Ablauf: Gemeinsame Dateischicht fuer Editor und IDE (ide.asm: ide_prg ruft ed_fsave_out). Alle KERNAL-Zugriffe laufen
; ueber die Sprungstuecke KN_* (IDE: Bruecke in Bank 0, die die Standardabbildung herstellt; sonst direkt $FFxx).
; Verfahren (Laden wie Speichern): logische Datei 2, Sekundaeradresse 2, blockweise (<= 256 Byte) ueber den Puffer fbuf. Waehrend
; der KERNAL-Aufrufe ist B = 0 (das KERNAL rechnet mit der Zeropage $00xx), zwischen den Bloecken wird B wieder auf die Basisseite
; der IDE ($1F, in fz_fl_b gesichert) gestellt, weil Editorzeiger (E0-E3) und ed_ins/ed_get dort liegen.
; Speicherplan: fbuf = $1E00 (Bank 0, 256 Byte, im freien Bereich $1800-$1EFF; fuer das KERNAL und die IDE gleichermassen sichtbar).
; Zeropage: E0..E3 (Lese-/Schreibposition im Text, 32 Bit), E1 (Zeiger auf die Assemblerausgabe), ed_len (Textlaenge).
; Rueckgabe wie oben im Kopf; Carry gesetzt = Fehler, A = Fehlerart. Die Ausgabe des Assemblers (Attic $0850_0000) wird mit zwei
; Byte Ladeadresse davor gespeichert (virtuelle Positionen 0 und 1 in fz_get).
; Reihenfolge: fl_name (Name bauen) -> SETNAM/SETLFS/OPEN -> Schleife (CHKIN/CKOUT, Bytes, CLRCHN) -> CLOSE.
; =====================================================================================================================
.ifdef IDE_BUILD                     ; Sprungstuecke der Bruecke (boot.asm); Aufruf wie das KERNAL, Register A, X, Y, Flags gehen durch
KN_SETNAM = KSETNAM
KN_SETLFS = KSETLFS
KN_OPEN = KOPEN
KN_CLOSE = KCLOSE
KN_CHKIN = KCHKIN
KN_CHRIN = KCHRIN
KN_CLRCHN = KCLRCHN
KN_READST = KREADST
KN_CKOUT = KCKOUT
KN_CHROUT = KCHROUT
.else                               ; ohne IDE (Testprogramme): direkt die KERNAL-Sprungtabelle
KN_SETNAM = $ffbd
KN_SETLFS = $ffba
KN_OPEN = $ffc0
KN_CLOSE = $ffc3
KN_CHKIN = $ffc6
KN_CHRIN = $ffcf
KN_CLRCHN = $ffcc
KN_READST = $ffb7
KN_CKOUT = $ffc9
KN_CHROUT = $ffd2
.endif

; fl_name: Laufwerksname nach fkn/fkl (Grossbuchstaben); A = 0 Lesen, 1 Schreiben ("@0:" davor, ",P,W" dahinter: PRG, schreiben;
; "@0:" ersetzt eine vorhandene Datei). Eingabe ed_fname/ed_fnl. Ausgabe fkn (Name, hoechstens 32 Zeichen), fkl (Laenge).
; Aendert A, X, Y, fwr. Kleinbuchstaben ($61-$7A, ASCII) werden mit "and #$df" zu Grossbuchstaben (PETSCII-Namen des Laufwerks).
fl_name:
        sta fwr
        ldy #$00
        lda fwr
        beq fn_b
        lda #$40                    ; @
        sta fkn
        lda #$30
        sta fkn + 1
        lda #$3a
        sta fkn + 2
        ldy #$03
fn_b:   ldx #$00                    ; Y = Schreibposition in fkn (3 nach dem Praefix "@0:" beim Schreiben), X = Leseposition im Namen
fz_fn_l:   cpx ed_fnl
        beq fn_d
        lda ed_fname,x
        cmp #$61
        bcc fn_s
        cmp #$7b
        bcs fn_s
        and #$df
fn_s:   sta fkn,y
        iny
        inx
        jmp fz_fn_l
fn_d:   lda fwr
        beq fn_e
        ldx #$00
fn_t:   lda ftail,x
        sta fkn,y
        iny
        inx
        cpx #$04
        bne fn_t
fn_e:   sty fkl
        rts
ftail:  .byte $2c, $50, $2c, $57    ; ,P,W

; ed_fload: Datei ed_fname laden und den Editortext ersetzen. Ausgabe: Carry geloescht = gut; sonst Carry gesetzt, A = 1 Oeffnen/
; Lesen fehlgeschlagen (Text unveraendert), 2 Text zu gross (Anfang geladen), 3 Lesefehler mitten in der Datei (Teiltext geladen).
; Aendert alle Register und E0-E3. Der alte Text wird erst nach dem ersten erfolgreich gelesenen Block geloescht (fstarted).
; Zeilenenden: CR und CRLF werden zu LF (fcr merkt, dass das vorige Zeichen CR war, damit das LF nach CR nicht doppelt zaehlt),
; Nullbytes entfallen.
ed_fload:
        lda #$00
        jsr fl_name
        lda #$00
        sta fstarted
        sta fcr
        sta ffull
        tba                         ; Basisseite der IDE retten (fz_fl_b), fuer das KERNAL B = 0
        sta fz_fl_b
        lda #$00
        tab
        lda fkl
        ldx #<fkn
        ldy #>fkn
        jsr KN_SETNAM
        lda #$02
        ldx ed_fdev
        ldy #$02
        jsr KN_SETLFS
        jsr KN_OPEN
        bcs lf_e1
lf_chunk:                           ; naechster Block: Eingabekanal setzen, bis zu 256 Byte nach fbuf lesen
        lda #$00
        tab
        ldx #$02
        jsr KN_CHKIN
        ldx #$00
        stx feof
lf_r1:  jsr KN_CHRIN
        sta fbuf,x
        inx
        jsr KN_READST
        sta fst                     ; READST nach jedem Byte (Bit 6 = EOF, Bits 0-5 = Fehler)
        and #$3f
        bne lf_bad
        lda fst
        and #$40
        beq lf_r2
        lda #$01
        sta feof
        jmp lf_r3
lf_r2:  cpx #$00
        bne lf_r1
lf_r3:  stx fcnt16                  ; 0 = 256 (fcnt16+1 = 1 bei vollem Block)
        lda #$00
        sta fcnt16 + 1
        cpx #$00
        bne lf_c
        lda #$01
        sta fcnt16 + 1
lf_c:   jsr KN_CLRCHN               ; Kanal frei, bevor der Editor (ed_ins) arbeitet
        lda fz_fl_b
        tab                         ; zurueck auf die Basisseite der IDE
        lda fstarted
        bne lf_p
        inc fstarted
        jsr ed_clear                ; erst jetzt (erster Block gelesen) den alten Text verwerfen
        jsr ed_lbegin               ; Einfuegesammlung beginnen (Undo/Zeilentabelle als ein Vorgang)
lf_p:   lda #$00
        sta ez_fidx
lf_pl:  lda fcnt16
        ora fcnt16 + 1
        beq lf_pd
        ldx ez_fidx
        lda fbuf,x
        beq lf_skip                 ; Nullbyte entfaellt
        cmp #$0d
        bne lf_a
        lda #$01
        sta fcr
        lda #$0a
        bne lf_emit
lf_a:   cmp #$0a
        bne lf_b
        lda fcr
        beq lf_lf
        lda #$00
        sta fcr
        beq lf_skip
lf_lf:  lda #$0a
        bne lf_emit
lf_b:   pha
        lda #$00
        sta fcr
        pla
lf_emit:
        pha
        lda ed_len + 2              ; Platz? (hoechstens ECAP - 1 Byte)
        cmp #(ECAP >> 16)
        bcs lf_fl
        cmp #(ECAP >> 16) - 1
        bne lf_ok
        lda ed_len + 1
        and ed_len
        cmp #$ff
        bne lf_ok
lf_fl:
        pla
        lda #$01
        sta ffull
        jmp lf_pd
lf_ok:  pla
        jsr ed_ins                  ; Zeichen am Textende einfuegen
lf_skip: inc ez_fidx
        lda fcnt16
        bne lf_d1
        dec fcnt16 + 1
lf_d1:  dec fcnt16
        jmp lf_pl
lf_pd:  lda ffull
        bne lf_end
        lda feof
        bne lf_end
        jmp lf_chunk
lf_end: lda #$00                    ; Normalende (oder Textgrenze): Datei schliessen, Einfuegesammlung beenden
        tab
        lda #$02
        jsr KN_CLOSE
        lda fz_fl_b
        tab
        jsr ed_lend
        lda ffull
        bne lf_big
        clc
        rts
lf_big: lda #$02
        sec
        rts
lf_bad: jsr KN_CLRCHN               ; Fehler beim Lesen: A = 3, falls schon Text geladen wurde, sonst wie Oeffnungsfehler (A = 1)
        lda #$02
        jsr KN_CLOSE
        lda fz_fl_b
        tab
        lda fstarted
        beq lf_e1
        jsr ed_lend
        lda #$03
        sec
        rts
lf_e1:  lda #$00                    ; Oeffnen fehlgeschlagen (oder Fehler vor dem ersten Block): Text bleibt unveraendert
        tab
        lda #$02
        jsr KN_CLOSE
        lda fz_fl_b
        tab
        lda #$01
        sec
        rts

; ed_fsave_out: wie ed_fsave, schreibt aber die Ausgabe des Assemblers als PRG (Ladeadresse ed_ldadr, dann ed_olen Byte ab $0850_0000)
ed_fsave_out:
        clc                         ; Ende = ed_olen + 2 (zwei Byte Ladeadresse vorweg)
        lda ed_olen
        adc #$02
        sta fz_end
        lda ed_olen + 1
        adc #$00
        sta fz_end + 1
        lda ed_olen + 2
        adc #$00
        sta fz_end + 2
        lda ed_olen + 3
        adc #$00
        sta fz_end + 3
        lda #$01
        bne fs_go                   ; (immer; Quelle = Ausgabe)
; ed_fsave: Editortext unveraendert unter ed_fname speichern. Ausgabe: Carry geloescht = gut, sonst Carry gesetzt, A = 1.
; Eingang fs_go gemeinsam mit ed_fsave_out (A = fsrc: 0 Editortext, 1 Assemblerausgabe). Aendert alle Register, E0-E3.
ed_fsave:
        lda #$00
fs_go:  sta fsrc
        jmp fz_save
fz_save:
        lda #$01                    ; Schreibmodus: "@0:NAME,P,W"
        jsr fl_name
        tba
        sta fz_fl_b
        lda #$00
        tab
        lda fkl
        ldx #<fkn
        ldy #>fkn
        jsr KN_SETNAM
        lda #$02
        ldx ed_fdev
        ldy #$02
        jsr KN_SETLFS
        jsr KN_OPEN
        bcs sv_e
        lda fz_fl_b
        tab
        ldx #$03                    ; Leseposition E0 = 0 (32 Bit)
        lda #$00
sv_z:   sta E0,x
        dex
        bpl sv_z
sv_chunk:                           ; Block in fbuf sammeln (B = IDE-Basisseite, damit ed_get/ed_inc E0 benutzen), dann ausgeben
        lda #$00
        sta ez_fidx
        sta feof
sv_f:   jsr fz_atend
        bne sv_g
        lda #$01
        sta feof
        jmp sv_w
sv_g:   jsr fz_get
        ldx ez_fidx
        sta fbuf,x
        jsr ed_inc
        inc ez_fidx
        bne sv_f                    ; 256 Byte voll (ez_fidx umgelaufen)
        lda #$01
        sta fcnt16 + 1
        jmp sv_w2
sv_w:   lda #$00
        sta fcnt16 + 1
sv_w2:  lda ez_fidx
        sta fcnt16
        lda fcnt16
        ora fcnt16 + 1
        beq sv_nw
        lda #$00                    ; Ausgabe: B = 0 fuer das KERNAL, Ausgabekanal = Datei 2
        tab
        ldx #$02
        jsr KN_CKOUT
        lda #$00
        sta ez_fidx
sv_o:   ldx ez_fidx
        lda fbuf,x
        jsr KN_CHROUT
        inc ez_fidx
        lda fcnt16 + 1
        bne sv_o2
        lda ez_fidx
        cmp fcnt16
        bne sv_o
        jmp sv_od
sv_o2:  lda ez_fidx
        bne sv_o                    ; 256 Byte: bis zum Umlauf
sv_od:  jsr KN_READST               ; Status der Schreibvorgaenge pruefen (ungleich 0 = Fehler)
        sta fst
        jsr KN_CLRCHN
        lda fz_fl_b
        tab
        lda fst
        bne sv_e2
sv_nw:  lda fz_fl_b
        tab
        lda feof                    ; Ende erreicht? Sonst naechster Block
        beq sv_chunk
        lda #$00
        tab
        lda #$02
        jsr KN_CLOSE
        lda fz_fl_b
        tab
        clc
        rts
sv_e2:  lda #$00                    ; Schreibfehler: Datei schliessen (bei Oeffnungsfehler sv_e: nichts zu schliessen)
        tab
        lda #$02
        jsr KN_CLOSE
sv_e:   lda fz_fl_b
        tab
        lda #$01
        sec
        rts

; Quelle des Speicherns: 0 = Editortext, 1 = Ausgabe des Assemblers
; fz_atend: Z = 1 am Ende (Quelle erschoepft). Editortext: ed_eq_len; Ausgabe: E0 (32 Bit) gleich fz_end (ed_olen + 2).
fz_atend:
        lda fsrc
        bne fz_a1
        jmp ed_eq_len
fz_a1:  lda E0
        cmp fz_end
        bne fz_a2
        lda E0 + 1
        cmp fz_end + 1
        bne fz_a2
        lda E0 + 2
        cmp fz_end + 2
        bne fz_a2
        lda E0 + 3
        cmp fz_end + 3
fz_a2:  rts
; fz_get: naechstes Byte der Quelle an Position E0 nach A (E0 wird vom Aufrufer mit ed_inc erhoeht). Aendert A, X, E1, Z.
fz_get: lda fsrc
        bne fz_g1
        jmp ed_get
fz_g1:  lda E0 + 1                  ; Byte 0/1: Ladeadresse, danach Ausgabe ab $0850_0000
        ora E0 + 2
        ora E0 + 3
        bne fz_g2
        lda E0
        cmp #$02
        bcs fz_g2
        tax
        lda ed_ldadr,x
        rts
fz_g2:  clc                         ; Zeiger = E0 + $084F_FFFE (Ausgabe im Attic ab $0850_0000, davor zwei Byte Ladeadresse)
        lda E0
        adc #$fe
        sta E1
        lda E0 + 1
        adc #$ff
        sta E1 + 1
        lda E0 + 2
        adc #$4f
        sta E1 + 2
        lda E0 + 3
        adc #$08
        sta E1 + 3
        ldz #$00
        lda [E1],z
        rts

; ---- Variablen ----
ed_fdev:   .byte 8                  ; Projektlaufwerk (Strg+A schaltet zwischen 8 und 9 um)
ed_sdev:   .byte 8                  ; Systemdisk: VC65D-Overlay und Bibliotheken <mega65/...>
fsrc:      .byte 0                  ; Quelle des Speicherns: 0 Editortext, 1 Assemblerausgabe
ed_olen:   .fill 4, 0               ; Laenge der Assemblerausgabe (ohne Ladeadresse), 32 Bit; 0 = noch nichts uebersetzt
ed_ldadr:  .word 0                   ; Ladeadresse der Ausgabe (zwei Byte vor den Daten der PRG-Datei)
fz_end:    .fill 4, 0
ed_fnl:    .byte 0
ed_fname:  .fill 16, 0
fkn:       .fill 32, 0              ; Laufwerksname (mit "@0:" und ",P,W" beim Schreiben)
fkl:       .byte 0                  ; dessen Laenge
fwr:       .byte 0
fz_fl_b:      .byte 0               ; gerettete Basisseite der IDE waehrend der KERNAL-Aufrufe
fst:       .byte 0
feof:      .byte 0
fstarted:  .byte 0
fcr:       .byte 0
ffull:     .byte 0
ez_fidx:      .byte 0
fcnt16:    .word 0
fbuf       = $1e00                 ; 256 Byte im freien Bereich $1800-$1EFF
