; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; dsess.asm - Sitzungsschleife des Debuggers (Overlay VC65D). Einsprung von ide_dbg_stub (Sprung, gleiche Stapeltiefe).
;
; Zweck: ide_debug (Strg+D) uebersetzt das Programm, startet es im Debugger (angehalten am Einsprung) und steuert danach die
; ganze Sitzung: Anzeige (dbgui.asm), Tasten, Schritt/darueber/weiter/Ende und die Umschaltung des Bildschirms (dvid.asm).
;
; Ablauf einer Sitzung:
;   Start    ide_prep (Assemblieren, Carry gesetzt = Fehler: Abbruch ohne Sitzung), Zustand loeschen, an kr_t (Einsprung des
;            Programms) einen Zwischenhaltepunkt setzen (dbg_temp), alle Haltepunkte als BRK einfuegen (dbg_ins), VIC-Zustand der
;            IDE merken (dv_start) und das Programm mit krun starten. Es laeuft los und bleibt sofort am Einsprung stehen.
;   Halt     BRK oder NMI -> ktrap/knmi (Bank 0) -> dbg_trap sichert alles und kehrt ueber kr_after hinter "jsr krun"
;            (oder hinter "jsr dsr") in diese Schleife zurueck, kr_trap <> 0. kr_trap = 0 bedeutet: Programm regulaer beendet.
;   Anzeige  dv_stop (Zustand des Programms merken, Debuggerbildschirm) + dui_draw, dann Tastenschleife (dui_key).
;   Schritt  dbg_next(0) setzt Zwischenhaltepunkte auf alle moeglichen Folgebefehle, dsr setzt das Programm fort.
;   Darueber dbg_next(1): wie Schritt, aber ein JSR wird als Ganzes uebersprungen (Haltepunkt hinter dem JSR).
;   Weiter   dsr ohne Zwischenhaltepunkte. Steht der PC auf einem Haltepunkt, wuerde dessen BRK sofort wieder anhalten: dann
;            erst ein Schritt und ds_cont = 1; der Halt nach diesem Schritt wird nicht angezeigt, sondern gleich fortgesetzt
;            (es sei denn, der Schritt landet selbst auf einem Haltepunkt).
;   Ende     Taste "Ende": Sitzung verwerfen (das Programm wird nicht fortgesetzt, sein Zustand ist verloren) -> dv_end -> IDE.
;            Programmende: ds_fin -> dv_end, dbg_state = 2, Meldung -> IDE.
;
; Stapeltiefe (wichtig): krun und dbg_resume speichern ihren SP in kr_sp; dbg_trap setzt ihn zurueck und kehrt mit RTS in die
; Ebene zurueck, die gerufen hatte. Darum rufen diese Schleife und dsr beide stets auf derselben Stapeltiefe auf (jsr krun,
; jsr dsr -> dbg_resume per Sprung); jeder Einsprung hinter dsl muss so liegen, dass kein fremder Rahmen auf dem Stapel steht.
;
; Zustandszellen: dbg_state (0 Start, 1 angehalten, 2 Programm beendet; liest dbgui), ds_cont (siehe "Weiter"),
; dbg_mem (Startadresse der Speicheranzeige, Anfang $2000, +/- $20 je Pfeiltaste), kt_pc/kt_* (Register des Programms,
; siehe boot.asm), dbg_bp (Haltepunkttabelle der IDE, siehe dbg.asm). Zeropage: nur die Editorzellen ueber die Aufrufe.
; Rueckgabe der Tastenaktion von dui_key (A): 0 keine, 1 Schritt, 2 darueber, 3 weiter, 4 Ende, 5 Speicher ab, 6 Speicher auf,
; 7 Programmbild zeigen.
; =====================================================================================================================
ide_debug:
        jsr ide_prep                ; Programm uebersetzen und zum Start vorbereiten; Carry gesetzt = Fehler (Meldung steht schon)
        bcc dg_go
        rts
dg_go:  lda #$00
        sta dbg_state
        sta ds_cont
        sta dbg_mem                 ; Speicheranzeige beginnt bei $2000
        lda #$20
        sta dbg_mem + 1
        lda #$ff                    ; kein Haltepunkt am "aktuellen" PC aussparen
        sta kt_pc                   ; ($FFFF: dbg_ins laesst nur einen Haltepunkt genau bei kt_pc aus; noch gibt es keinen PC)
        sta kt_pc + 1
        ldx kr_t                    ; Einsprung des Programms: dort ein Zwischenhaltepunkt, damit es sofort anhaelt
        lda kr_t + 1
        jsr dbg_temp                ; A = hoch, X = tief
        jsr dbg_ins                 ; alle BRK in den Programmspeicher schreiben
        jsr dv_start                ; VIC-Zustand der IDE merken, Abzug fuer den Debuggerbildschirm
        jsr dv_std                  ; das Programm im Standardzustand des VIC-IV starten (wie bei Strg+R, siehe dvid.asm)
        jsr krun                    ; kehrt erst beim Halt (BRK/NMI) oder Programmende zurueck
dsl:    lda kr_trap                 ; Schleifenkopf, auch Ruecksprungziel hinter "jsr dsr": 0 = Programm beendet
        bne ds_s
        jmp ds_fin
ds_s:   lda #$01                    ; angehalten
        sta dbg_state
        lda ds_cont                 ; stand der letzte Befehl "Weiter" auf einem Haltepunkt (Schritt davor)?
        beq ds_ui
        lda #$00
        sta ds_cont
        jsr dbg_atbp                ; Carry = jetzt auf einem Haltepunkt: dann anzeigen
        bcs ds_ui
        jsr dsr                     ; sonst ohne Anzeige weiterlaufen
        jmp dsl
ds_ui:  jsr dv_stop                 ; erster Halt: Zustand des Programms merken, Debuggerbildschirm zeigen
        jsr dui_draw
ds_k:   jsr disp_getkey             ; auf Taste warten
        jsr dui_key                 ; -> Aktion 0..7
        beq ds_k
        cmp #$01
        bne ds_n2
        lda #$00                    ; Schritt
        jsr dbg_next
        jsr dsr
        jmp dsl
ds_n2:  cmp #$02
        bne ds_n3
        lda #$01                    ; darueber
        jsr dbg_next
        jsr dsr
        jmp dsl
ds_n3:  cmp #$03
        bne ds_n4
        jsr dbg_atbp                ; weiter: steht hier ein Haltepunkt, erst einen Schritt, dann ohne Zwischenhalt weiter
        bcc ds_pl
        lda #$01
        sta ds_cont
        lda #$00
        jsr dbg_next
ds_pl:  jsr dsr
        jmp dsl
ds_n4:  cmp #$04
        bne ds_n5
        lda #$00                    ; Ende: die Sitzung wird verworfen
        sta mi                      ; mi = Fuellstand des Meldungspuffers der IDE (neu beginnen)
        ldx #<s_dend
        ldy #>s_dend
        jsr ide_cat
        jsr dv_end                  ; VIC-Zustand der IDE zurueck
        jmp ide_show                ; Meldung anzeigen, Rueckkehr in die IDE (kein RTS: der Stapel dieser Ebene wird verlassen)
ds_n5:  cmp #$05
        bne ds_n6
        clc                         ; Speicher ab: Anzeigeadresse + 32 (16 Bit, Uebertrag in den hohen Teil)
        lda dbg_mem
        adc #$20
        sta dbg_mem
        bcc ds_ui
        inc dbg_mem + 1
        jmp ds_ui
ds_n6:  cmp #$07
        bne ds_n7
        jsr dv_tgt                  ; Programmbild bis zur naechsten Taste
        jsr disp_getkey
        jsr dv_dbg                  ; danach wieder der Debuggerbildschirm
        jmp ds_ui
ds_n7:  sec                         ; Aktion 6 (Speicher auf): Anzeigeadresse - 32
        lda dbg_mem
        sbc #$20
        sta dbg_mem
        lda dbg_mem + 1
        sbc #$00
        sta dbg_mem + 1
        jmp ds_ui
ds_fin: jsr dv_end                  ; Programm regulaer beendet: VIC-Zustand der IDE zurueck
        lda #$02
        sta dbg_state
        lda #$00
        sta mi
        ldx #<s_done
        ldy #>s_done
        jsr ide_cat                 ; s_done steht im Hauptprogramm (ide.asm)
        jmp ide_show

; dsr: vor dem Fortsetzen den VIC-Zustand des Programms herstellen und dann fortsetzen (Sprung, damit die Stapeltiefe stimmt)
; Aufruf per JSR aus der Schleife: die Rueckkehradresse ist dann das, was dbg_trap spaeter ueber kr_sp/kr_after anspringt.
dsr:    jsr dv_back
        jmp dbg_resume

s_dend:  .byte "Debugger ended", 0
ds_cont:  .byte 0                   ; 1 = nach dem naechsten Halt ohne Anzeige fortsetzen (Weiter ueber einen Haltepunkt)
