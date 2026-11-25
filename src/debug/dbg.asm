; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; dbg.asm - Debugger-Kern (Etappe N8): Haltepunkte (BRK), Einzelschritt, "darueber", Weiter. Das Testprogramm laeuft in Bank 0
; (Standardabbildung); die IDE in Bank 4. Haltepunkte: BRK ($00) wird an die Stelle geschrieben und das Original gemerkt. Beim
; Anhalten (BRK -> KERNAL -> Vektor $0316 -> ktrap -> dbg_trap) werden Register, Zeropage und der Stapel des Testprogramms
; gesichert (Zeropage ab DBGZP, Stapel ab DBGSTK; diese Puffer gehoeren dem Assembler, der waehrend des Debuggens ruht) und alle
; eingefuegten BRK entfernt. dbg_resume stellt alles wieder her und setzt das Programm fort (kgo, RTI). dbg_trap und dbg_resume
; kehren ueber krun-Schwanz (kr_after) in die Ebene zurueck, die krun beziehungsweise dbg_resume aufgerufen hat; diese Ebene
; ("Sitzungsschleife") muss beide Aufrufe auf derselben Stapeltiefe machen.
; Voraussetzung: dis.asm (dis_one, FL_*), Bruecke (boot.asm), Editorzellen E0..E3.
;
; Zwei Wege in den Debugger (beide landen ueber OV_TRAP in dbg_trap, beide mit der Abbildung der IDE und noch tiefem Stapel):
;   BRK    Haltepunkt (BRK = $00 im Programm). Die CPU legt PC + 2 ab (BRK ist ein Befehl mit Signaturbyte), darum zieht dbg_trap 2 ab.
;   NMI    Notfalltaste (RESTORE) oder NMI-Quelle: PC ist die unterbrochene Stelle (kt_nmi = 1), nichts abzuziehen.
; Stapelrahmen beim Eintritt (kt_sp = SP bei ktrap/knmi; Adresse = $0100 + kt_sp + n):
;       +1 B   +2 Z   +3 Y   +4 X   +5 A   +6 P   +7 PCL   +8 PCH     (aufsteigende Adressen; hoeher = frueher abgelegt)
;   PCH, PCL und P legt die CPU bei BRK/NMI ab, A, X, Y, Z und B legt das KERNAL (beziehungsweise knmir in boot.asm) darunter ab.
;   Der echte Wert von B kommt nicht aus dem Rahmen, sondern aus dem Register B, das ktrap/knmi in kt_b gesichert hat.
;   Der Rahmen wird mit dem Stapel gesichert (DBGSTK + 0..7 = B, Z, Y, X, A, P, PCL, PCH); dahinter folgen die Daten des
;   Programms (zum Beispiel die Rueckkehradresse eines JSR ab DBGSTK + 8).
;
; Speicher (Bank 0, Puffer des ruhenden Assemblers): DBGZP $1500-$15FF Zeropage, DBGSTK $1200-$12DF Stapel (hoechstens 224 Byte;
; dahinter beginnen bei $12E0 die Zellen kt_* der Falle). dbg_stn = Zahl der gesicherten Stapelbytes.
;
; Haltepunkttabelle dbg_bp (in ide.asm): BPALL = 20 Eintraege zu je 4 Byte; die ersten BPMAX = 16 sind Haltepunkte des
; Anwenders (Art 1), die letzten 4 Zwischenhaltepunkte (Art 2), die Schritt und "darueber" fuer das naechste Anhalten setzen.
; Zeropage: E0..E3 (32-Bit-Zeiger) liegen in der Basisseite der IDE (IDE_B); waehrend Zeropage/Stapel gesichert werden, ist B = 0.
; Invarianten: waehrend das Programm laeuft, sind alle benutzten Haltepunkte als BRK eingefuegt (Bit 7 der Art gesetzt);
; waehrend es steht, ist kein BRK im Speicher (dbg_rem hat sie alle entfernt), damit Anzeige und Speicherblick das Original zeigen.
; =====================================================================================================================
IDE_B   = $1f                       ; Basisseite der IDE
DBGZP   = $1500                     ; Sicherung der Zeropage des Testprogramms (256 Byte, Puffer inname..filebase des Assemblers)
DBGSTK  = $1200                     ; Sicherung des Stapels (hoechstens 224 Byte, Puffer curgstk)
; BPMAX, BPALL und die Tabelle dbg_bp stehen in ide.asm (der Editor schaltet Haltepunkte um)

; Eintrag je 4 Byte: Adresse (2), Original (1), Art (0 frei, 1 Haltepunkt, 2 Zwischenhaltepunkt) + Bit 7 "eingefuegt"

; dbg_trap: vom Fallenhandler gerufen, IDE-Abbildung, Stapel noch beim Testprogramm
; Ein: kt_sp, kt_nmi, kt_b (von ktrap/knmi); Stapelrahmen siehe Kopf. Aus: kt_a/x/y/z/p/pc gesetzt, Stapel und Zeropage des
; Programms gesichert, BRK entfernt, kr_trap = 1. Kehrt nicht zurueck, sondern springt nach kr_after (dort RTS in die Schleife).
dbg_trap:
        ldx kt_sp                   ; X = SP des Programms; Rahmenbytes liegen bei $0100 + X + n
        lda $0102,x                 ; (+1 ist B, siehe Kopf: der Wert kommt aus kt_b)
        sta kt_z
        lda $0103,x
        sta kt_y
        lda $0104,x
        sta kt_x
        lda $0105,x
        sta kt_a
        lda $0106,x
        sta kt_p
        lda kt_nmi                  ; Notfalltaste (NMI): PC ist die unterbrochene Stelle; BRK legt PC + 2 ab
        bne dt_pn
        lda $0107,x                 ; BRK: abgelegtes PC - 2 = Adresse des BRK-Opcodes
        sec
        sbc #$02
        sta kt_pc
        lda $0108,x
        sbc #$00
        sta kt_pc + 1
        jmp dt_pd
dt_pn:  lda $0107,x
        sta kt_pc
        lda $0108,x
        sta kt_pc + 1
dt_pd:
        lda kr_sp                   ; Stapelbereich kt_sp+1 .. kr_sp sichern
        sec                         ; (Rahmen und alles, was das Programm seit krun auf den Stapel gelegt hat)
        sbc kt_sp
        cmp #$e1                    ; hoechstens 224 Byte: DBGSTK ($1200) endet vor den Zellen kt_* bei $12E0
        bcc dt_n
        lda #$e0
dt_n:   sta dbg_stn
        ldx kt_sp
        inx                         ; X = SP + 1 = unterstes Rahmenbyte (B)
        ldy #$00
dt_c:   cpy dbg_stn
        beq dt_z
        lda $0100,x
        sta DBGSTK,y
        inx
        iny
        jmp dt_c
dt_z:   ldx #$00                    ; Zeropage (B = 0: echte Nullseite)
dt_zp:  lda $00,x                   ; (ktrap/knmi haben B auf 0 gestellt; $00,x ist damit die echte Nullseite des Programms)
        sta DBGZP,x
        inx
        bne dt_zp
        lda #IDE_B                  ; ab hier wieder die Basisseite der IDE (E0..E3, Zeiger fuer dbg_rem)
        tab
        jsr dbg_rem                 ; alle BRK entfernen: der Speicher zeigt wieder das Original
        lda #$01
        sta kr_trap                 ; 1 = angehalten (0 = Programm beendet, 2 = Overlay fehlte)
        ldx kr_sp                   ; SP auf die Stapeltiefe von krun/dbg_resume stellen ...
        txs
        jmp kr_after                ; ... und in die Sitzungsschleife zurueckkehren (kr_after: Vektoren zurueck, Abbildung IDE, RTS)

; dbg_rem: alle eingefuegten BRK entfernen (Original zurueck), Zwischenhaltepunkte loeschen
; Ein: -. Aus: Bit 7 der Arten geloescht, Zwischenhaltepunkte frei. Veraendert A, X, Z, E1..E3.
dbg_rem:
        ldx #$00
dr_l:   lda dbg_bp + 3,x
        bpl dr_n                    ; Bit 7 nicht gesetzt: nicht eingefuegt
        and #$7f
        sta dbg_bp + 3,x
        lda dbg_bp,x
        sta E1                      ; E1 = 32-Bit-Zeiger auf die Adresse in Bank 0 (E1+2, E1+3 = 0)
        lda dbg_bp + 1,x
        sta E1 + 1
        lda #$00
        sta E1 + 2
        sta E1 + 3
        ldz #$00
        lda dbg_bp + 2,x            ; gemerktes Original zurueckschreiben
        sta [E1],z
        lda dbg_bp + 3,x
        cmp #$02
        bne dr_n
        lda #$00                    ; Zwischenhaltepunkt (Art 2): Eintrag freigeben, er gilt nur fuer einen Halt
        sta dbg_bp + 3,x
dr_n:   inx
        inx
        inx
        inx
        cpx #BPALL * 4
        bne dr_l
        rts

; dbg_ins: BRK an alle Haltepunkte (nicht an kt_pc) und Zwischenhaltepunkte schreiben
; Jeder belegte, noch nicht eingefuegte Eintrag: Original nach +2, $00 (BRK) in den Speicher, Bit 7 der Art setzen.
; Ein: kt_pc. Aus: -. Veraendert A, X, Z, E1..E3.
dbg_ins:
        ldx #$00
di_l:   lda dbg_bp + 3,x
        beq di_n                    ; frei
        bmi di_n                    ; schon eingefuegt (Bit 7)
        cmp #$01
        bne dq_di_go                ; Art 2 (Zwischenhaltepunkt): immer einfuegen
        lda dbg_bp,x                ; Haltepunkt an der aktuellen Stelle bleibt draussen
        cmp kt_pc                   ; (sonst wuerde das Fortsetzen sofort wieder anhalten)
        bne di_ok
        lda dbg_bp + 1,x
        cmp kt_pc + 1
        beq di_n
di_ok:  lda dbg_bp + 3,x            ; (A wird gleich ueberschrieben)
dq_di_go:  lda dbg_bp,x
        sta E1
        lda dbg_bp + 1,x
        sta E1 + 1
        lda #$00
        sta E1 + 2
        sta E1 + 3
        ldz #$00
        lda [E1],z
        sta dbg_bp + 2,x            ; Original merken
        lda #$00                    ; BRK schreiben
        sta [E1],z
        lda dbg_bp + 3,x
        ora #$80                    ; Bit 7: eingefuegt
        sta dbg_bp + 3,x
di_n:   inx
        inx
        inx
        inx
        cpx #BPALL * 4
        bne di_l
        rts

; dbg_atbp: Carry gesetzt, wenn an kt_pc ein Haltepunkt (Art 1) steht
; Nur die Haltepunkte des Anwenders (BPMAX Eintraege), keine Zwischenhaltepunkte. Veraendert A, X.
dbg_atbp:
        ldx #$00
ab_l:   lda dbg_bp + 3,x
        and #$7f                    ; Bit "eingefuegt" ausblenden
        cmp #$01
        bne ab_n
        lda dbg_bp,x
        cmp kt_pc
        bne ab_n
        lda dbg_bp + 1,x
        cmp kt_pc + 1
        bne ab_n
        sec
        rts
ab_n:   inx
        inx
        inx
        inx
        cpx #BPMAX * 4
        bne ab_l
        clc
        rts

; dbg_rd16: E1 = Adresse (Bank 0) -> A = hoch, X = tief
; Liest ein Wort (tief zuerst) aus dem Speicher des Programms. Veraendert A, X, Z, E1+2, E1+3.
dbg_rd16:
        lda #$00
        sta E1 + 2
        sta E1 + 3
        ldz #$00
        lda [E1],z
        tax
        inz
        lda [E1],z
        rts

; dbg_temp: A = hoch, X = tief: Zwischenhaltepunkt eintragen (ab Adresse $C000 liegt ROM/E/A: nicht moeglich)
; Sucht einen freien der 4 Zwischenplaetze (ab Eintrag BPMAX); sind alle belegt, passiert nichts. Veraendert A, Y.
; Eingefuegt wird er erst von dbg_ins (kurz vor dem Fortsetzen).
dbg_temp:
        cmp #$c0                    ; ab $C000 ROM/Ein-/Ausgabe: ein BRK im RAM darunter wuerde nie ausgefuehrt
        bcs dtp_r
        sta dbg_ta + 1
        stx dbg_ta
        ldy #BPMAX * 4
dtp_l:  lda dbg_bp + 3,y
        beq dtp_f
        iny
        iny
        iny
        iny
        cpy #BPALL * 4
        bne dtp_l
dtp_r:  rts
dtp_f:  lda dbg_ta
        sta dbg_bp,y
        lda dbg_ta + 1
        sta dbg_bp + 1,y
        lda #$02
        sta dbg_bp + 3,y
        rts

; dbg_next: A = 0 Einzelschritt (hinein), 1 darueber -> Zwischenhaltepunkte auf allen moeglichen Folgebefehlen
; Der Befehl bei kt_pc wird disassembliert (dis_one); je nach Art (dis_flow) kommen als Folgebefehle in Frage:
;   FL_NONE/FL_BRK  der naechste Befehl (BRK ist 2 Byte lang)      FL_JMP  das Sprungziel
;   FL_BR           Verzweigung: Ziel und naechster Befehl (BRA/LBRA: nur das Ziel)
;   FL_JSR          hinein: Ziel (liegt es im ROM ab $C000, dann der naechste Befehl); darueber: der naechste Befehl
;   FL_IND          JSR (..) darueber: naechster Befehl; sonst Zeigerwort lesen, bei (abs,x) mit X indizieren
;   FL_RET          RTS/RTN: Ruecksprungadresse + 1 aus dem gesicherten Stapel (DBGSTK + 8/9); RTI: PC aus DBGSTK + 9/10
; Auf diese Weise braucht der Einzelschritt keine Befehlsemulation und keinen Einzelschrittmodus der CPU.
dbg_next:
        sta dbg_into
        ldy #BPMAX * 4 + 3          ; alte Zwischenhaltepunkte frei (Art-Byte der 4 Zwischenplaetze loeschen)
        lda #$00
dn_c:   sta dbg_bp,y
        tya
        clc
        adc #$04
        tay
        lda #$00
        cpy #BPALL * 4 + 3
        bcc dn_c
        lda kt_pc
        sta dsp
        lda kt_pc + 1
        sta dsp + 1
        jsr dis_one
        clc                         ; dg_nx = Adresse des naechsten Befehls
        lda kt_pc
        adc dis_len
        sta dg_nx
        lda kt_pc + 1
        adc #$00
        sta dg_nx + 1
        lda dis_flow
        cmp #FL_BR
        bne dn_1
        lda dsop                    ; BRA, LBRA: nur das Ziel
        cmp #$80
        beq dn_tg
        cmp #$83
        beq dn_tg
        jsr dn_nx                   ; bedingte Verzweigung: auch der naechste Befehl (Verzweigung nicht genommen)
dn_tg:  ldx dis_tgt
        lda dis_tgt + 1
        jmp dbg_temp
dn_1:   cmp #FL_JMP
        beq dn_tg
        cmp #FL_JSR
        bne dn_2
        lda dbg_into
        bne dn_nx                   ; darueber: Folgebefehl
        lda dis_tgt + 1             ; hinein: Ziel; ab $C000 (ROM) ist kein Haltepunkt moeglich, dann darueber
        cmp #$c0
        bcs dn_nx
        jmp dn_tg
dn_2:   cmp #FL_IND
        bne dn_3
        lda dbg_into
        beq dn_i0
        lda dsop                    ; JSR (..) darueber: Folgebefehl
        cmp #$22
        beq dn_nx
        cmp #$23
        beq dn_nx
dn_i0:  lda kt_pc                   ; Zeiger lesen: Operand = $kt_pc+1/2, Ziel = Wort an dieser Adresse (+ X bei (abs,x))
        clc
        adc #$01
        sta E1
        lda kt_pc + 1
        adc #$00
        sta E1 + 1
        jsr dbg_rd16                ; A/X = Operand = Adresse des Zeigerworts
        sta E1 + 1
        stx E1
        lda dsop
        cmp #$7c                    ; JMP (abs,x) beziehungsweise JSR (abs,x): X zur Zeigeradresse addieren
        beq dn_ix
        cmp #$23
        bne dn_i1
dn_ix:  clc
        lda E1
        adc kt_x
        sta E1
        bcc dn_i1
        inc E1 + 1
dn_i1:  jsr dbg_rd16                ; Zeigerwort = Ziel
        jmp dbg_temp
dn_3:   cmp #FL_RET
        bne dn_4
        lda dsop
        cmp #$40
        beq dn_rti
        lda DBGSTK + 8              ; RTS/RTN: Ruecksprungadresse + 1 aus dem gesicherten Stapel
        clc                         ; (RTS springt nach "Adresse + 1": die abgelegte Adresse ist die des letzten JSR-Bytes)
        adc #$01
        sta dg_t
        lda DBGSTK + 9
        adc #$00
        sta dg_t + 1
        cmp #>kr_after              ; Rueckkehr ins IDE-Geruest: das Programm endet, kein Haltepunkt
        bne dn_r1
        lda dg_t
        cmp #<kr_after
        beq dn_r2
dn_r1:  ldx dg_t
        lda dg_t + 1
        jmp dbg_temp
dn_r2:  rts
dn_rti: ldx DBGSTK + 9              ; RTI: P, PCL, PCH ab Index 8
        lda DBGSTK + 10             ; (RTI springt auf die abgelegte Adresse selbst, ohne + 1)
        jmp dbg_temp
dn_4:                               ; FL_NONE, FL_BRK: Folgebefehl (BRK ist 2 Byte lang)
dn_nx:  lda dis_flow
        cmp #FL_BRK
        bne dn_n2
        lda dg_nx                   ; BRK ist zwei Byte lang
        clc                         ; (dis_len zaehlt nur das Opcodebyte, siehe dis_fin)
        adc #$01
        sta dg_nx
        bcc dn_n2
        inc dg_nx + 1
dn_n2:  ldx dg_nx
        lda dg_nx + 1
        jmp dbg_temp

; dbg_chkbrk: steht an kt_pc ein echtes BRK (kein Haltepunkt von uns), den Befehl ueberspringen
; Aufruf vor dbg_ins: alle unsere BRK sind dann entfernt, ein $00 an kt_pc ist also ein BRK des Programms (Bank 0 im Speicher).
; Das zweite Byte (Signatur) wird mit uebersprungen. Ohne das wuerde das Fortsetzen endlos wieder am selben BRK anhalten.
dbg_chkbrk:
        lda kt_pc
        sta E1
        lda kt_pc + 1
        sta E1 + 1
        lda #$00
        sta E1 + 2
        sta E1 + 3
        ldz #$00
        lda [E1],z
        bne dc_r
        lda kt_pc
        clc
        adc #$02
        sta kt_pc
        bcc dc_r
        inc kt_pc + 1
dc_r:   rts

; dbg_resume: Testprogramm fortsetzen (siehe Kopf: auf der Stapeltiefe der Sitzungsschleife aufrufen)
; Ein: kt_* (Register, PC, SP), DBGZP/DBGSTK, dbg_bp. Aus: Das Programm laeuft (kgo/RTI); zurueck in die Schleife kommt erst
; der naechste Halt ueber dbg_trap -> kr_after (mit dem hier gesicherten kr_sp). Kehrt selbst nie normal zurueck.
dbg_resume:
        tsx
        stx kr_sp                   ; Stapeltiefe der Sitzungsschleife merken (Rueckkehrpunkt fuer dbg_trap/Programmende)
        tba
        sta kr_b                    ; Basisseite der IDE fuer kr_after merken
        lda #$00
        sta kr_trap
        jsr dbg_chkbrk
        jsr dbg_ins
        lda kt_pc                   ; Rahmen im gesicherten Stapel: P, PC (PCH/PCL ab Index 6)
        sta DBGSTK + 6              ; (Index 5 = P, 6 = PCL, 7 = PCH; kt_pc kann durch dbg_chkbrk verschoben sein)
        lda kt_pc + 1
        sta DBGSTK + 7
        lda kt_p
        sta DBGSTK + 5
        lda kt_sp                   ; SP unterhalb des Stapels des Testprogramms
        sec                         ; ($10 darunter: die folgenden JSR legen ihre Rueckkehradressen dort ab und duerfen den
        sbc #$10                    ;  wiederhergestellten Programmstapel nicht ueberschreiben)
        tax
        txs
        ldx kt_sp
        inx
        ldy #$00
rs_c:   cpy dbg_stn
        beq rs_z
        lda DBGSTK,y
        sta $0100,x
        inx
        iny
        jmp rs_c
rs_z:   lda #$00
        tab                         ; B = 0: ab hier schreiben die Zugriffe auf $00,x in die echte Nullseite
        ldx #$00
rs_zp:  lda DBGZP,x
        sta $00,x
        inx
        bne rs_zp
        lda kt_sp
        clc
        adc #$05                    ; SP so, dass der RTI in kgo bei P (Index 5 des Rahmens) beginnt: P, PCL, PCH
        sta kg_sp
        jsr ide_nmivec              ; RAM-Vektor fuer den NMI bei ausgeblendetem KERNAL
        jsr kvec_set                ; BRK-/NMI-Vektor (kr_after stellt sie zurueck)
        jmp kgo                     ; Abbildung des Programms, A/X/Y/Z/B zurueck, RTI

dbg_stn: .byte 0                    ; Zahl der in DBGSTK gesicherten Stapelbytes (hoechstens $e0)
dbg_into: .byte 0                   ; dbg_next: 0 = in Unterprogramme hinein, 1 = darueber
dbg_ta:  .word 0                    ; dbg_temp: Zieladresse (Zwischenablage)
dg_nx:   .word 0                    ; dbg_next: Adresse des naechsten Befehls
dg_t:    .word 0                    ; dbg_next: Ruecksprungziel (RTS)
