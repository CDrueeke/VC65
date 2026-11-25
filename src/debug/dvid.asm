; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; dvid.asm - Bildschirmumschaltung des Debuggers (Overlay VC65D). Der Debugger hat einen eigenen Bildschirm (Zeichen bei DV_S,
; Farben ab Farb-RAM-Versatz DV_COL); der VIC-IV wird mit den Zeigerregistern SCRNPTR ($D060-$D063) und COLPTR ($D064/$D065) darauf
; umgestellt, der Speicher des Testprogramms (auch Bildschirm und Farb-RAM) bleibt unberuehrt. Dazu werden die VIC-Register
; $D000-$D07F in drei Abzuegen gehalten: DV_I (Zustand der IDE beim Sitzungsbeginn), DV_T (Zustand des Testprogramms beim Anhalten)
; und DV_D (DV_I mit den Zeigern auf den Debuggerbildschirm). Zum Lesen und Schreiben der Register schaltet dv_on eine IDE-Abbildung
; ohne Block 6 ein (die Ein-/Ausgabe ist dann sichtbar); der Code liegt in Block 7 und bleibt darum sichtbar.
; Reihenfolge beim Schreiben: aufsteigend ($D011/$D016/$D018/$D031 setzen die VIC-IV-Register zurueck, diese kommen danach); $D02F
; (Freischaltung) und die Lese-/Quittierregister $D019, $D01E, $D01F werden ausgelassen.
;
; Zweck im Ablauf einer Sitzung (Aufrufer: dsess.asm):
;   dv_start  Sitzungsbeginn: DV_I und DV_D aufbauen, IDE-Zustand bleibt eingestellt.
;   dv_stop   Halt: Zustand des Programms nach DV_T, dann Debuggerbildschirm (DV_D) einschalten (nur einmal je Halt, dv_shown).
;   dv_back   vor dem Fortsetzen: Zustand des Programms (DV_T) zurueck, falls der Debuggerbildschirm gezeigt wurde.
;   dv_end    Sitzungsende: Zustand der IDE (DV_I) zurueck.
;   dv_tgt / dv_dbg   Programmbild beziehungsweise Debuggerbild einschalten (Taste V), ohne dv_shown zu aendern.
;
; Speicherplan (alles Bank 4, physisch $4xxxx; die Bereiche liegen im Block 6 und damit unter der Ein-/Ausgabe, wenn diese
; sichtbar ist; darum greift der Code ueber 32-Bit-Zeiger zu, nicht ueber die CPU-Abbildung):
;   $4D000-$4D07F DV_I   128 Byte: VIC-Register $D000-$D07F der IDE
;   $4D080-$4D0FF DV_T   128 Byte: VIC-Register des Testprogramms beim Halt
;   $4D100-$4D17F DV_D   128 Byte: VIC-Register fuer den Debuggerbildschirm
;   $4D200-$4D9CF DV_S   Debuggerbildschirm 80 x 25 = 2000 Byte (SCRNPTR = $0004_D200)
;   $0FF8_1000-$0FF8_17CF  Farbzeilen des Debuggers im Farb-RAM (COLPTR = $1000, hinter dem Farb-RAM des 50-Zeilen-Editors)
; Das ist der Bereich des 50-Zeilen-Editorbildschirms: er wird nach der Sitzung ohnehin neu gezeichnet (ed_run -> ed_view).
;
; Invarianten: dv_shown = 1 genau dann, wenn DV_T gueltig ist (Programm angehalten und Debuggerbildschirm eingeschaltet).
; Die Routinen dv_on/dv_off veraendern A, X, Y und Z (MAP) und lassen die Abbildung nach dv_off wie die der IDE (MAPX/MAPZ).
; =====================================================================================================================
DV_I    = $d000                     ; Puffer und Bild des Debuggers liegen im Bereich des 50-Zeilen-Editorbildschirms ($D000-$DF9F):
DV_T    = $d080                     ; Der Editor zeichnet nach der Sitzung alles neu (ed_run -> ed_view), waehrend der Sitzung ist sein
DV_D    = $d100                     ; Bildschirm nicht zu sehen. $F600-$FFF9 gehoeren den Tabellen (VC65T).
DV_S    = $d200                     ; Debuggerbildschirm (2000 Byte) = $0004_D200
DV_COL  = $1000                     ; COLPTR: Farben des Debuggers bei $0FF8_1000 (hinter dem Farb-RAM des 50-Zeilen-Editors $0000-$0F9F)
MAPZ_IO = $b4                       ; Bloecke 4, 5, 7 -> Bank 4; Block 6 normal (Ein-/Ausgabe)

; dv_on: Ein-/Ausgabe sichtbar machen und den VIC-IV freischalten. Ausgabe: A, X, Y, Z zerstoert.
; MAP: A/X = Abbildung der Bloecke 0-3 (A = Versatz tief, X = Versatz hoch + Blockmaske), Y/Z = Bloecke 4-7. MAPX ($E4) und MAPZ_IO
; ($B4) bilden die Bloecke 1-3, 4, 5 und 7 wie die IDE (Versatz $40000 = Bank 4) ab; im oberen Fenster fehlt Bit 6 der Maske, daher
; zeigt Block 6 ($C000-$DFFF) die echte Ein-/Ausgabe. EOM beendet die Abbildungsphase (bis dahin sind Interrupts gesperrt).
dv_on:  lda #$00
        ldx #MAPX
        ldy #$00
        ldz #MAPZ_IO
        map
        eom
        lda #$47                    ; VIC-IV freischalten (Schluesselpaar $47/$53 nach $D02F; sonst sind $D031/$D060... nicht schreibbar)
        sta $d02f
        lda #$53
        sta $d02f
        rts
; dv_off: Abbildung der IDE wiederherstellen (Block 6 wieder RAM der Bank 4). Ausgabe: A, X, Y, Z zerstoert.
dv_off: lda #$00
        ldx #MAPX
        ldy #$00
        ldz #MAPZ
        map
        eom
        rts

; dv_save: A = Puffer tief, X = hoch (Adresse im Block 6, physisch $4xxxx): VIC-Register -> Puffer
; Kopiert $D000-$D07F nach (Puffer), Register $2F, $19, $1E, $1F bleiben unberuehrt (siehe Kopf). Zerstoert A, X, Y, Z, E2-E3.
dv_save:
        jsr dv_ptr
        jsr dv_on
        ldx #$00                    ; X = Registernummer, Z = Pufferindex (gleichlaufend)
        ldz #$00
dvs_l:  cpx #$2f                    ; $D02F: Freischaltung, kein Zustand
        beq dvs_n
        cpx #$19                    ; $D019, $D01E, $D01F: Interrupt-/Kollisionsstatus (Lesen/Schreiben quittiert)
        beq dvs_n
        cpx #$1e
        beq dvs_n
        cpx #$1f
        beq dvs_n
        lda $d000,x
        sta [E2],z                  ; 32-Bit-Zeiger (E2 = $0004_xxxx): Puffer liegt im verdeckten Block 6
dvs_n:  inx
        inz
        cpx #$80
        bne dvs_l
        jmp dv_off

; dv_load: A = Puffer tief, X = hoch: Puffer -> VIC-Register
; Schreibt aufsteigend ($D011/$D016/$D018/$D031 setzen VIC-IV-Register zurueck; $D060ff. kommen erst danach und gelten).
dv_load:
        jsr dv_ptr
        jsr dv_on
        ldx #$00
        ldz #$00
dvl_l:  cpx #$2f
        beq dvl_n
        cpx #$19
        beq dvl_n
        cpx #$1e
        beq dvl_n
        cpx #$1f
        beq dvl_n
        lda [E2],z
        sta $d000,x
dvl_n:  inx
        inz
        cpx #$80
        bne dvl_l
        jmp dv_off

; dv_ptr: E2 = $0004_0000 + (X * 256 + A) (Block 6 und 7 liegen in Bank 4 = $4xxxx)
; Die vier Zeigerbytes E2..E3 sind ein 32-Bit-Zeiger fuer "[E2],z"; er umgeht die Abbildung und trifft den Puffer auch dann, wenn
; die Ein-/Ausgabe ueber dem Block 6 liegt.
dv_ptr: sta E2
        stx E2 + 1
        lda #$04
        sta E2 + 2
        lda #$00
        sta E2 + 3
        rts

; dv_start: Zustand der IDE merken, Abzug fuer den Debuggerbildschirm herstellen
; Ablauf: (1) IDE-Zustand nach DV_I, (2) V400 aus, (3) diesen Zustand nach DV_D, (4) DV_I zurueck, (5) in DV_D die Zeiger setzen.
dv_start:
        jsr disp_vic                ; SCRNPTR der IDE (50 Zeilen) neu setzen: das Laden des Overlays von der Diskette hat es verstellt
        lda #<DV_I
        ldx #>DV_I
        jsr dv_save
        jsr dv_v400off              ; der Debuggerbildschirm hat 25 Zeilen: V400 aus, die Hardware rechnet DISPROWS, Zeichenhoehe usw. selbst
        lda #<DV_D
        ldx #>DV_D
        jsr dv_save                 ; ... dieser Zustand (V400 aus) ist die Grundlage von DV_D
        lda #<DV_I
        ldx #>DV_I
        jsr dv_load                 ; die IDE bleibt vorerst im Zustand des Sitzungsbeginns (50 oder 25 Zeilen)
        lda #<DV_S                  ; SCRNPTR = $0004_D200, COLPTR = DV_COL
        sta DV_D + $60              ; $D060-$D063: SCRNPTR (32 Bit), tief zuerst
        lda #>DV_S
        sta DV_D + $61
        lda #$04
        sta DV_D + $62
        lda #$00
        sta DV_D + $63
        lda #<DV_COL                ; $D064/$D065: COLPTR (16 Bit, Versatz im Farb-RAM $0FF8_0000)
        sta DV_D + $64
        lda #>DV_COL
        sta DV_D + $65
        lda #$00
        sta dv_shown
        rts

; dv_v400off: $D031 Bit 3 (V400) loeschen (heisses Register: setzt DISPROWS, SCRNPTR, COLPTR usw. fuer 25 Zeilen)
; Zerstoert A, X, Y, Z. Hinweis: das Zuruecksetzen betrifft die Hardware; DV_I behaelt den vorher gesicherten 50-Zeilen-Zustand.
dv_v400off:
        jsr dv_on
        lda $d031
        and #$f7
        sta $d031
        jmp dv_off

; dv_stop: das Testprogramm ist angehalten: dessen Zustand merken und den Debuggerbildschirm einschalten (einmal je Halt)
; Beim zweiten Aufruf ohne Fortsetzen dazwischen (zum Beispiel nach Pfeiltasten) tut sie nichts: DV_T bleibt der Zustand des Programms.
dv_stop:
        lda dv_shown
        bne dvp_r
        lda #<DV_T
        ldx #>DV_T
        jsr dv_save
        jsr dv_dbg
        lda #$01
        sta dv_shown
dvp_r:  rts

; dv_back: vor dem Fortsetzen den Zustand des Testprogramms herstellen
; (nur wenn dv_stop ihn gesichert hat; sonst war die Anzeige des Programms nie verstellt)
dv_back:
        lda dv_shown
        beq dvb_r
        jsr dv_tgt
        lda #$00
        sta dv_shown
dvb_r:  rts

; dv_tgt: Programmbild einschalten (DV_T -> VIC); dv_dbg: Debuggerbild einschalten (DV_D -> VIC). Beide Sprung nach dv_load.
dv_tgt: lda #<DV_T
        ldx #>DV_T
        jmp dv_load
dv_dbg: lda #<DV_D
        ldx #>DV_D
        jmp dv_load
; dv_std: Standardzustand des VIC-IV (beim IDE-Start im Attic bei $0878_0100 gemerkt, Werkzeug 9 von VC65X) in den Puffer DV_T kopieren
; und in die Register laden: das Programm startet damit wie aus BASIC (25 Zeilen, SCRNPTR $0800) statt im 50-Zeilen-Zustand der IDE,
; denn das "heisse" Register $D031 stellt Zeiger und Zeilenzahl in aelteren Emulatoren nicht zuverlaessig zurueck. DV_T wird beim Halt
; ohnehin neu geschrieben (dv_stop). Aendert E3.
dv_std: lda #$00
        sta E3
        sta E3 + 3
        lda #$01
        sta E3 + 1
        lda #$78
        sta E3 + 2
        lda #$08
        sta E3 + 3
        ldx #$00
dvs_c:  txa
        taz
        lda [E3],z
        sta DV_T,x
        inx
        bpl dvs_c
        lda #<DV_T
        ldx #>DV_T
        jmp dv_load
; dv_end: Zustand der IDE wiederherstellen (Sitzungsende)
dv_end: lda #<DV_I
        ldx #>DV_I
        jsr dv_load
        lda #$00
        sta dv_shown
        rts

dv_shown: .byte 0                   ; 1 = DV_T gueltig (Debuggerbildschirm ist eingeschaltet), 0 = nicht
