; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; dbgui.asm - Anzeige und Tasten des Debuggers (Etappe N8). Bildschirm (80 x 25, auf dem eigenen Debuggerbildschirm DV_S/DV_COL,
; siehe dvid.asm; der Bildschirm der IDE bleibt unberuehrt):
;   Zeile 0 Titel, 1 Register, 2 Q und Flags, 4 "Befehle", 5-14 Disassemblierung ab PC (> = PC), 16 Quelltextzeile (aus der
;   Zeilentabelle des Assemblers), 18 Stapel, 20-23 Speicher ab dbg_mem, 24 Tastenhilfe.
; Tasten: F1/s Schritt, F3/n darueber, F5/c weiter, F7/q/STOP Ende, v Programmbild, Pfeil ab/auf Speicher +/- 32 Byte.
;
; Aufrufer ist die Sitzungsschleife (dsess.asm): dui_draw baut das ganze Bild neu auf (bei jedem Halt und nach jeder
; Speicherverschiebung), dui_key uebersetzt eine Taste in eine Aktionsnummer. Alle Daten kommen aus den Zellen kt_a/x/y/z/p/b/sp/pc
; (Register des Programms beim Halt, boot.asm), dem gesicherten Stapel DBGSTK (dbg.asm) und dem Speicher des Programms (Bank 0).
;
; Zeichenausgabe: dui_row waehlt eine Zeile, loescht sie und setzt den Schreibzeiger ET + 2/3 auf ihren Anfang; dui_ch haengt
; ein ASCII-Zeichen an (Spalte du_c, Umsetzung mit asc2scr); dui_str/dui_hex2/dui_hex4/dui_lbl bauen darauf auf.
; Zeropage: ET + 2/3 = Zeiger auf die laufende Bildschirmzeile, ET + 6/7 = Zeiger auf eine Zeichenkette, E1..E3 = 32-Bit-Zeiger
; (Farb-RAM, Quelltextzeilentabelle, Speicher des Programms). Register: alle Routinen veraendern A, X, Y (und Z, wo E1 benutzt wird).
; Zellen am Dateiende: du_c Spalte, du_n Zaehler, du_a Adresse, du_t/du_u Hilfswerte, du_ln Zeilennummer, du_p Flags;
; dbg_mem (Startadresse der Speicheranzeige) und dbg_state (0 Start, 1 angehalten, 2 beendet) werden von dsess.asm gesetzt.
; =====================================================================================================================
; dui_row: A = Zeile loeschen (Zeichen bei DV_S, Farben ab $0FF8_1000), Spalte 0
; Aus: ET + 2/3 = Zeiger auf Zeichenbereich der Zeile, du_c = 0. Zeile = A * 80 (disp_row80 liefert den Versatz in disp_cur).
dui_row:
        jsr disp_row80
        clc
        lda disp_cur
        adc #<DV_S                  ; Zeichenzeile: DV_S + Versatz (CPU-Adresse im Block 6 der IDE-Abbildung)
        sta ET + 2
        lda disp_cur + 1
        adc #>DV_S
        sta ET + 3
        ldy #$4f
        lda #$20                    ; Leerzeichen (bildschirmcode $20 = ASCII $20)
dr_a:   sta (ET + 2),y
        dey
        bpl dr_a
        lda disp_cur                ; Farbzeile: $0FF8_0000 + DV_COL + disp_cur
        sta E1                      ; (32-Bit-Zeiger: das Farb-RAM liegt bei $0FF8_0000 und ist nicht in der CPU-Abbildung)
        lda disp_cur + 1
        clc
        adc #>DV_COL
        sta E1 + 1
        lda #$f8
        sta E1 + 2
        lda #$0f
        sta E1 + 3
        ldz #$4f
        lda #COL_TEXT
dr_b:   sta [E1],z
        dez
        bpl dr_b
        lda #$00
        sta du_c
        rts

; dui_ch: A = ASCII-Zeichen an die Spalte du_c
; (asc2scr setzt ASCII in Bildschirmcodes um; du_c wird um 1 erhoeht; keine Pruefung auf Zeilenende, die Texte sind kurz genug)
dui_ch: jsr asc2scr
        ldy du_c
        sta (ET + 2),y
        inc du_c
        rts

dui_str:                            ; X/Y = Zeichenkette
        stx ET + 6
        sty ET + 7
        ldy #$00
ui_s1:  lda (ET + 6),y
        beq ui_s2
        phy                         ; dui_ch benutzt Y fuer die Spalte
        jsr dui_ch
        ply
        iny
        bne ui_s1
ui_s2:  rts

; dui_h1: untere Tetrade von A als Hexziffer anhaengen; dui_hex2: A als zwei Ziffern; dui_hex4: A = hoch, X = tief
dui_h1: and #$0f
        cmp #$0a
        bcc ui_h1a
        adc #$56                    ; Carry gesetzt: + $57 ergibt 'a'..'f'
        jmp dui_ch
ui_h1a: adc #$30                    ; Carry geloescht: '0'..'9'
        jmp dui_ch
dui_hex2:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr dui_h1
        pla
        jmp dui_h1
dui_hex4:                           ; A = hoch, X = tief
        phx
        jsr dui_hex2
        pla
        jmp dui_hex2

; dui_lbl: X/Y = Beschriftung, A = Wert als zwei Hexziffern
dui_lbl:
        pha
        jsr dui_str
        pla
        jmp dui_hex2

; dui_draw: das ganze Debuggerbild aufbauen (alle 25 Zeilen). Eingaben: kt_*, dbg_state, DBGSTK, dbg_stn, dbg_mem, Programmspeicher.
dui_draw:
        lda #$00                    ; ganzes Bild leeren (der Editor steht noch dahinter)
        sta du_n                    ; (jede Zeile loeschen, auch die nicht beschriebenen Zeilen 3, 15, 17, 19)
ud_cls: lda du_n
        jsr dui_row
        inc du_n
        lda du_n
        cmp #25
        bne ud_cls
        lda #$00                    ; Titel
        jsr dui_row
        ldx #<t_dbg
        ldy #>t_dbg
        jsr dui_str
        lda dbg_state
        cmp #$02
        beq ud_fin                  ; Zustand 2: Programm beendet, keine Haltestelle
        ldx #<t_halt
        ldy #>t_halt
        lda kt_nmi
        beq ud_th
        ldx #<t_nmi                 ; Notfalltaste (NMI): unterbrochen
        ldy #>t_nmi
ud_th:  jsr dui_str
        lda kt_pc + 1
        ldx kt_pc
        jsr dui_hex4
        jmp ud_reg
ud_fin: ldx #<t_end
        ldy #>t_end
        jsr dui_str
ud_reg: lda #$01                    ; Zeile 1: A X Y Z B SP PC
        jsr dui_row
        ldx #<t_a
        ldy #>t_a
        lda kt_a
        jsr dui_lbl
        ldx #<t_x
        ldy #>t_x
        lda kt_x
        jsr dui_lbl
        ldx #<t_y
        ldy #>t_y
        lda kt_y
        jsr dui_lbl
        ldx #<t_z
        ldy #>t_z
        lda kt_z
        jsr dui_lbl
        ldx #<t_b
        ldy #>t_b
        lda kt_b
        jsr dui_lbl
        ldx #<t_sp
        ldy #>t_sp
        lda kt_sp
        clc
        adc #$08                    ; SP des Testprogramms an der Haltestelle (Rahmen ist abgebaut)
        jsr dui_lbl                 ; (kt_sp zeigt unter den 8 Rahmenbytes B, Z, Y, X, A, P, PCL, PCH; ohne sie: kt_sp + 8)
        ldx #<t_pc
        ldy #>t_pc
        jsr dui_str
        lda kt_pc + 1
        ldx kt_pc
        jsr dui_hex4
        lda #$02                    ; Q und Flags
        jsr dui_row
        ldx #<t_q
        ldy #>t_q
        lda kt_z                    ; Q ist das 32-Bit-Register Z:Y:X:A (Z = hoechstes Byte)
        jsr dui_lbl
        lda kt_y
        jsr dui_hex2
        lda kt_x
        jsr dui_hex2
        lda kt_a
        jsr dui_hex2
        ldx #<t_p
        ldy #>t_p
        lda kt_p
        and #$ef                    ; B-Bit ist nur ein Merkmal des BRK-Rahmens
        sta du_p
        jsr dui_lbl
        lda #$20
        jsr dui_ch
        ldx #$00                    ; acht Flags N V - B D I Z C (Bit 7 zuerst): gesetzt = Buchstabe, sonst '.'
ud_fl:  lda du_p                    ; (Bit 5 ist beim 45GS02 das E-Bit; hier als '-' dargestellt)
        and t_fbit,x
        beq ud_f0
        lda t_flag,x
        bne ud_fs
ud_f0:  lda #$2e
ud_fs:  jsr dui_ch
        inx
        cpx #$08
        bne ud_fl
        lda #$04
        jsr dui_row
        ldx #<t_cmd
        ldy #>t_cmd
        jsr dui_str
        lda kt_pc                   ; Disassemblierung
        sta du_a                    ; du_a = Adresse des laufenden Befehls (beginnt am PC), du_n = Zeilenzaehler 0..9
        lda kt_pc + 1
        sta du_a + 1
        lda #$00
        sta du_n
ud_ln:  lda du_n
        clc
        adc #$05                    ; Zeilen 5..14
        jsr dui_row
        lda du_a
        sta dsp
        lda du_a + 1
        sta dsp + 1
        jsr dis_one                 ; -> dis_buf (Text), dis_len (Laenge)
        lda du_n
        bne ud_nm
        lda #$3e                    ; > am PC
        bne ud_mk
ud_nm:  lda #$20
ud_mk:  jsr dui_ch
        lda du_a + 1
        ldx du_a
        jsr dui_hex4                ; Adresse
        lda #$20
        jsr dui_ch
        jsr dui_ch
        ldx #$00                    ; bis zu 4 Byte
ud_by:  cpx dis_len                 ; (dis_rd liest das Byte X der Befehlsbytes ab dsp; laengere Befehle werden abgeschnitten)
        bcs ud_bp
        phx
        txa
        jsr dis_rd
        jsr dui_hex2
        lda #$20
        jsr dui_ch
        plx
        inx
        cpx #$04
        bcc ud_by
        bcs ud_bd
ud_bp:  lda #$20                    ; auffuellen auf 12 Zeichen
        jsr dui_ch                  ; (3 Leerzeichen je fehlendem Byte, damit der Befehlstext in einer Spalte beginnt)
        jsr dui_ch
        jsr dui_ch
        inx
        cpx #$04
        bcc ud_bp
ud_bd:  lda #$20
        jsr dui_ch
        ldx #<dis_buf
        ldy #>dis_buf
        jsr dui_str
        clc
        lda du_a
        adc dis_len
        sta du_a
        bcc ud_n1
        inc du_a + 1
ud_n1:  inc du_n
        lda du_n
        cmp #$0a
        bne ud_ln
        lda #16                     ; Quelltextzeile
        jsr dui_row
        jsr dui_source
        lda #18                     ; Stapel
        jsr dui_row
        ldx #<t_stk
        ldy #>t_stk
        jsr dui_str
        ldx #$08                    ; ab Index 8 des gesicherten Stapels: hinter dem Rahmen (B..PCH) liegen die Daten des
ud_st:  cpx dbg_stn                 ; Programms (zum Beispiel Rueckkehradressen); hoechstens 8 Byte, soweit gesichert
        bcs ud_sd
        phx
        lda DBGSTK,x
        jsr dui_hex2
        lda #$20
        jsr dui_ch
        plx
        inx
        cpx #$10
        bne ud_st
ud_sd:  lda #$00                    ; Speicher: 4 Zeilen zu 8 Byte
        sta du_n
        lda dbg_mem
        sta du_a
        lda dbg_mem + 1
        sta du_a + 1
ud_mm:  lda du_n
        clc
        adc #20                     ; Zeilen 20..23
        jsr dui_row
        lda du_a + 1
        ldx du_a
        jsr dui_hex4
        lda #$3a
        jsr dui_ch
        lda #$00
        sta E1 + 2                  ; 32-Bit-Zeiger auf den Speicher des Programms (Bank 0)
        sta E1 + 3
        lda du_a
        sta E1
        lda du_a + 1
        sta E1 + 1
        ldz #$00
ud_mb:  lda #$20
        phz                         ; Z = Byteindex im Block: zur Sicherheit ueber die Ausgabe retten (asc2scr ist hier nicht
        jsr dui_ch                  ; als Z-erhaltend zugesichert)
        plz
        lda [E1],z
        phz
        jsr dui_hex2
        plz
        inz
        cpz #$08
        bne ud_mb
        clc
        lda du_a
        adc #$08
        sta du_a
        bcc ud_m1
        inc du_a + 1
ud_m1:  inc du_n
        lda du_n
        cmp #$04
        bne ud_mm
        lda #24
        jsr dui_row
        ldx #<t_help
        ldy #>t_help
        jmp dui_str

; dui_source: Quelltextzeile zum PC aus der Zeilentabelle (Attic $0860_0000): "L nnnn: Text"
; Zeilentabelle (vom Assembler gebaut, lt_cnt Eintraege zu je 8 Byte, im Attic-RAM ab $LT_B3 LT_B2 0000 = $0860_0000):
;   +0..2  Anfang der Quelltextzeile als Versatz (24 Bit) im Quelltext (Attic ab $0800_0000)
;   +3     (hier nicht benutzt)
;   +4/+5  Adresse des erzeugten Codes dieser Zeile      +6/+7  Laenge des Codes in Byte
; Es wird der erste Eintrag mit  Adresse <= PC < Adresse + Laenge  gesucht (lineare Suche ueber alle Eintraege). Dann wird die
; Zeilennummer ermittelt, indem im Quelltext von Anfang an die Zeilenenden ($0A) bis zu diesem Versatz gezaehlt werden.
; Aus: eine Zeile "L nnnn: Text" (hoechstens 70 Zeichen Text) oder "(no line info)". Verwendet du_n (Eintragszaehler), du_a/du_t.
dui_source:
        lda #$00
        sta E1
        sta E1 + 1
        lda #LT_B2
        sta E1 + 2
        lda #LT_B3
        sta E1 + 3
        lda #$00
        sta du_n
        sta du_n + 1
us_l:   lda du_n                    ; alle Eintraege durch? (du_n = lt_cnt)
        cmp lt_cnt
        bne us_c
        lda du_n + 1
        cmp lt_cnt + 1
        beq us_none
us_c:   ldz #$04                    ; Adresse, Laenge
        lda [E1],z
        sta du_a
        inz
        lda [E1],z
        sta du_a + 1
        inz
        lda [E1],z
        clc
        adc du_a
        sta du_t
        inz
        lda [E1],z
        adc du_a + 1
        sta du_t + 1                ; du_t = Adresse + Laenge (ausschliesslich)
        lda kt_pc + 1               ; PC >= Adresse ?
        cmp du_a + 1
        bcc us_n
        bne us_ge
        lda kt_pc
        cmp du_a
        bcc us_n
us_ge:  lda kt_pc + 1               ; PC < Adresse + Laenge ?
        cmp du_t + 1
        bcc us_hit
        bne us_n
        lda kt_pc
        cmp du_t
        bcc us_hit
us_n:   clc                         ; naechster Eintrag
        lda E1
        adc #$08
        sta E1
        bcc us_i
        inc E1 + 1
        bne us_i
        inc E1 + 2                  ; 24-Bit-Zeiger fortschreiben (Uebertrag bis in das dritte Byte)
us_i:   inc du_n
        bne us_l
        inc du_n + 1
        jmp us_l
us_none:
        ldx #<t_nosrc
        ldy #>t_nosrc
        jmp dui_str
us_hit: ldz #$00                    ; Zeilenanfang (24 Bit) -> E2 = Ende, Zeilennummer zaehlen
        lda [E1],z                  ; du_t = Anfang der Zeile (Versatz im Quelltext)
        sta du_t
        inz
        lda [E1],z
        sta du_t + 1
        inz
        lda [E1],z
        sta du_t + 2
        lda #$00                    ; E2 = Leseposition im Quelltext = $0800_0000 + gelesene Stellen
        sta E2
        sta E2 + 1
        sta E2 + 2
        lda #$08
        sta E2 + 3
        lda #$01                    ; erste Zeile hat die Nummer 1
        sta du_ln
        lda #$00
        sta du_ln + 1
        sta du_u                    ; gelesene Stellen (24 Bit) in du_a/du_u
        sta du_a
        sta du_a + 1
us_cnt: lda du_a                    ; Versatz erreicht (du_a/du_u = du_t)? Dann steht E2 am Zeilenanfang
        cmp du_t
        bne us_rd
        lda du_a + 1
        cmp du_t + 1
        bne us_rd
        lda du_u
        cmp du_t + 2
        beq us_txt
us_rd:  ldz #$00
        lda [E2],z
        cmp #$0a                    ; jedes Zeilenende (LF) erhoeht die Zeilennummer
        bne us_nl
        inc du_ln
        bne us_nl
        inc du_ln + 1
us_nl:  inc E2
        bne us_p2
        inc E2 + 1
        bne us_p2
        inc E2 + 2
us_p2:  inc du_a
        bne us_cnt
        inc du_a + 1
        bne us_cnt
        inc du_u
        jmp us_cnt
us_txt: lda #$00                    ; "L nnnn: " + Text bis Zeilenende (hoechstens 70 Zeichen)
        sta mi                      ; Meldungspuffer der IDE (mi = Fuellstand) als Zwischenspeicher fuer die Zeile
        ldx #<t_z1
        ldy #>t_z1
        jsr ide_cat
        lda du_ln
        sta ide_n
        lda du_ln + 1
        sta ide_n + 1
        jsr ide_dec
        lda #$3a
        jsr ide_ch
        lda #$20
        jsr ide_ch
        ldy #$00
us_tc:  cpy #$46                    ; 70 Zeichen Text (Zeile und Nummer passen so in 80 Spalten)
        beq us_te
        ldz #$00
        lda [E2],z
        beq us_te
        cmp #$0a
        beq us_te
        cmp #$0d
        beq us_te
        phy
        jsr ide_ch
        ply
        inc E2
        bne us_t2
        inc E2 + 1
us_t2:  iny
        jmp us_tc
us_te:  ldx mi
        lda #$00
        sta dz_mbuf,x               ; Text mit 0 abschliessen und ausgeben
        ldx #<dz_mbuf
        ldy #>dz_mbuf
        jmp dui_str

; dui_key: A = Taste (PETSCII) -> A = Aktion (und Z-Flag): 1 Schritt, 2 darueber, 3 weiter, 4 Ende, 5/6 Speicher ab/auf,
; 7 Programmbild zeigen, 0 nichts. Mehrere Tastencodes je Aktion: Funktionstaste, Buchstabe, Grossbuchstabe (Umschalttaste).
dui_key:
        cmp #$85                    ; F1 / s / S
        beq uk_1
        cmp #$53
        beq uk_1
        cmp #$d3
        beq uk_1
        cmp #$86                    ; F3 / n / N
        beq uk_2
        cmp #$4e
        beq uk_2
        cmp #$ce
        beq uk_2
        cmp #$87                    ; F5 / c / C
        beq uk_3
        cmp #$43
        beq uk_3
        cmp #$c3
        beq uk_3
        cmp #$88                    ; F7 / q / Q / STOP ($03)
        beq uk_4
        cmp #$8c                    ; F8 (je nach Tastaturbelegung des Emulators liefert die Taste F7 diesen Code)
        beq uk_4
        cmp #$51
        beq uk_4
        cmp #$d1
        beq uk_4
        cmp #$03
        beq uk_4
        cmp #$11                    ; Cursor ab
        beq uk_5
        cmp #$91                    ; Cursor auf
        beq uk_6
        cmp #$56                    ; v / V
        beq uk_7
        cmp #$d6
        beq uk_7
        cmp #$10                    ; zusaetzlicher Code fuer das Programmbild
        beq uk_7
        lda #$00
        rts
uk_1:   lda #$01
        rts
uk_2:   lda #$02
        rts
uk_3:   lda #$03
        rts
uk_4:   lda #$04
        rts
uk_5:   lda #$05
        rts
uk_6:   lda #$06
        rts
uk_7:   lda #$07
        rts

t_dbg:  .byte "VC65 Debugger  ", 0
t_halt: .byte "stopped at $", 0
t_end:  .byte "Program ended", 0
t_nmi:  .byte "interrupted (emergency key) at $", 0
t_a:    .byte "A=", 0
t_x:    .byte " X=", 0
t_y:    .byte " Y=", 0
t_z:    .byte " Z=", 0
t_b:    .byte " B=", 0
t_sp:   .byte " SP=", 0
t_pc:   .byte " PC=", 0
t_q:    .byte "Q=", 0
t_p:    .byte "  P=", 0
t_cmd:  .byte "Commands:", 0
t_stk:  .byte "Stack: ", 0
t_nosrc: .byte "(no line info)", 0
t_z1:   .byte "L ", 0
t_help: .byte "F1 Step  F3 Over  F5 Go  F7 End  V Program screen  Arrows: memory", 0
t_flag: .byte "NV-BDIZC"            ; Flag-Buchstaben, Bit 7 zuerst
t_fbit: .byte $80, $40, $20, $10, $08, $04, $02, $01   ; Bitmasken dazu
du_c:   .byte 0                     ; aktuelle Spalte in der Zeile
du_n:   .word 0                     ; Zaehler (Zeile, Eintrag)
du_a:   .word 0                     ; Adresse (Disassemblierung, Speicher, Tabellenadresse)
du_t:   .fill 3, 0                  ; Hilfswert: Ende der Codeadresse beziehungsweise Zeilenanfang (24 Bit)
du_u:   .byte 0                     ; hohes Byte des 24-Bit-Zaehlers der gelesenen Quelltextstellen
du_ln:  .word 0                     ; Zeilennummer im Quelltext
du_p:   .byte 0                     ; Flags der Anzeige (P ohne B)
dbg_mem: .word 0                    ; Startadresse der Speicheranzeige
dbg_state: .byte 0                  ; 0 Start, 1 angehalten, 2 Programm beendet
