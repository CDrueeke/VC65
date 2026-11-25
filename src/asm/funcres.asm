; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; funcres.asm - Hauptprogramm-Seite des Overlays A (src/ide/aoverlay.asm, Datei VC65A): Sprungstuecke fuer die vier Einsprunge
; ex_call, argpush, arg_get und f_pass, die Zellen asp/fnargs/fi (liegen am Anfang des Overlays) und das Nachladen (oa_chk).
; Ein Sprungstueck sichert Flags und A, prueft ueber oa_chk, ob das Overlay bei $E000 steht, und springt in die Einsprungtabelle.
; Das Overlay kommt beim ersten Gebrauch von der Disk (Datei VC65A, ov_get) und wird dabei als Kopie im Attic abgelegt ($0878_1000);
; spaeter (nach einem Debugger- oder Werkzeug-Overlay) genuegt eine Kopie aus dem Attic. ov_ok und xo_ok werden geloescht: das
; geladene Overlay A ersetzt Debugger und Werkzeuge, die beim naechsten Gebrauch neu geladen werden (ov_ensure, ide_xcall setzen oa_ok = 0).
; =====================================================================================================================
OA_BASE = $e000
OA_PAGES = 19                       ; Seiten (256 Byte), die kopiert werden: bis $F2FF (das Overlay ist hoechstens so gross, siehe build_ide.py)
ERR_E204 = $04                      ; Fehlercode (steht im Overlay-Build nicht in func.asm)
asp     = $e010                     ; Zellen im Overlay (Anfang), vom Hauptprogramm benutzt
fnargs  = $e012
fi      = $e013
ex_call:
        php
        pha
        jsr oa_chk
        pla
        plp
        jmp OA_BASE
argpush:
        php
        pha
        jsr oa_chk
        pla
        plp
        jmp OA_BASE + 3
arg_get:
        php
        pha
        jsr oa_chk
        pla
        plp
        jmp OA_BASE + 6
f_pass:
        php
        pha
        jsr oa_chk
        pla
        plp
        jmp OA_BASE + 9
d_function:
        php
        pha
        jsr oa_chk
        pla
        plp
        jmp OA_BASE + 12
; oa_chk: Overlay A bei $E000 sicherstellen; X, Y, Z bleiben erhalten (A, Flags sichert das Sprungstueck). Fehler beim Laden: E900.
oa_chk: lda oa_ok
        bne oc_r
        phx
        phy
        phz
        lda oa_att
        bne oc_cp
        lda #$e0                    ; erster Gebrauch: Datei VC65A nach $E000 lesen und als Kopie im Attic merken
        sta ov_th
        ldx #<oa_name
        ldy #>oa_name
        jsr ov_get
        bcs oc_err
        lda #$00                    ; Kopie $0004_E000 -> Attic $0878_1000
        jsr oa_set
        jsr oa_cp
        lda #$01
        sta oa_att
        bne oc_ok
oc_cp:  lda #$08                    ; Kopie Attic $0878_1000 -> $0004_E000
        jsr oa_set
        jsr oa_cp
oc_ok:  lda #$01
        sta oa_ok
        lda #$00                    ; Debugger- und Werkzeug-Overlay sind ersetzt
        sta ov_ok
        sta xo_ok
        plz
        ply
        plx
oc_r:   rts
oc_err: plz
        ply
        plx
        lda #ERR_E900
        jmp ex_error
; oa_set: Quell- und Zielzeiger E2/E3 (je 32 Bit) aus der Tabelle oa_t ab Versatz A (0 oder 8) laden
oa_set: tay
        ldx #$00
os_l:   lda oa_t,y
        sta E2,x
        iny
        inx
        cpx #$08
        bne os_l
        rts
; oa_cp: OA_PAGES Seiten von [E2] nach [E3] kopieren
oa_cp:  ldx #OA_PAGES
ocp_p:  ldz #$00
ocp_l:  lda [E2],z
        sta [E3],z
        inz
        bne ocp_l
        inc E2 + 1
        inc E3 + 1
        dex
        bne ocp_p
        rts
oa_t:   .byte $00, $e0, $04, $00, $00, $10, $78, $08      ; 0: Quelle $0004_E000, Ziel $0878_1000 (Platte -> Attic)
        .byte $00, $10, $78, $08, $00, $e0, $04, $00      ; 8: Quelle $0878_1000, Ziel $0004_E000 (Attic -> Overlay)
oa_ok:  .byte 0                     ; 1 = Overlay A steht bei $E000
oa_att: .byte 0                     ; 1 = Kopie im Attic vorhanden
oa_name: .byte "VC65A"
