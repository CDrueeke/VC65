; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; dis.asm - Disassembler und Befehlsdekodierung fuer den Debugger (Etappe N8). Liest den Speicher von Bank 0 (das Testprogramm)
; ueber 32-Bit-Zeiger. Voraussetzung: optab.asm (M_*), dtab.asm (Dekodiertabellen) und die Zeropage-Zellen E0..E3 des Editors.
; dis_one: dsp (16 Bit) = Adresse -> dis_buf (ASCII, klein, mit 0 beendet), dis_len = Laenge in Byte, dis_flow = Art des Befehls
; (FL_*), dis_tgt = Sprungziel (bei Verzweigung, JMP/JSR absolut). Textformat wie "vcc dis": "lda ($20),y", "bne $2016",
; "bbr3 $12,$201c", "lda [$20],z", Quad-Befehle mit Praefix $42 $42 als "ldq $30".
;
; Zwei Verbraucher: dbgui.asm (Anzeige der Disassemblierung ab PC) und dbg.asm (dbg_next: aus dis_flow/dis_tgt/dis_len die
; moeglichen Folgebefehle fuer Schritt und "darueber" bestimmen).
;
; Dekodierung (Tabellen aus dtab.asm, je 256 Byte, Index = Opcode; Format siehe dort):
;   dt_len[op]   Befehlslaenge ohne Praefixe (1..3)        dt_mode[op]  Adressierungsart M_* (Zahlen wie in optab.asm)
;   dt_name[op]  Index in dt_names (4 Zeichen je Eintrag)   dt_qname[op] Name der Quad-Form ($FF = es gibt keine)
; Praefixe des 45GS02, die vor dem eigentlichen Opcode stehen und hier erkannt werden:
;   $42 $42      Quad-Praefix: der Befehl arbeitet auf Q (= Z:Y:X:A, 32 Bit); Name aus dt_qname ("ldq", "adcq" ...).
;                Das zweite $42 gehoert nicht zum Befehlsnamen; gibt es keine Quad-Form -> "???" (Laenge 1).
;   $EA          vor einem (zp),z-Befehl (M_IZZ) macht er daraus den 32-Bit-Zeiger "[zp],z" (sonst ist $EA = EOM/NOP).
;   Beide Praefixe zusammen: $42 $42 $EA op ... (zuerst Quad, dann der Zeigerprefix).
; Befehlslaenge: dis_len = dt_len[op] + Anzahl Praefixbytes (dso).
;
; Arbeitszellen: dsp = Adresse des Befehls (Eingabe), dsq = Quad-Flag, dse = $EA-Flag, dso = Anzahl Praefixbytes (= Versatz des
; Opcodes), dsi = Schreibindex in dis_buf, dsop = Opcode, dsm = Adressierungsart, dsn = Namensindex, dst0 = vorzeichenbehafteter
; Abstand einer Verzweigung. ET + 6/7 dient als Zeiger auf Namen/Zeichenketten. dis_buf fasst 40 Zeichen (die
; laengsten Texte, etwa "bbr7 $12,$ffff", brauchen weniger als 20).
; Register: alle Routinen veraendern A, X, Y und Z; E1..E3 und ET + 6/7 werden belegt.
; =====================================================================================================================
FL_NONE  = 0                        ; Folgebefehl = Adresse + Laenge
FL_BR    = 1                        ; Verzweigung (rel, rl, zpr): Ziel in dis_tgt, oder Folgebefehl
FL_JMP   = 2                        ; JMP abs: Ziel in dis_tgt
FL_JSR   = 3                        ; JSR/BSR abs/rl: Ziel in dis_tgt, "darueber" = Folgebefehl
FL_IND   = 4                        ; JMP (abs), JMP (abs,x), JSR (abs), JSR (abs,x): Ziel nur zur Laufzeit
FL_RET   = 5                        ; RTS, RTI, RTN: Ruecksprung aus dem Stapel
FL_BRK   = 6                        ; BRK

; dis_rd: A = Versatz (0..7) von dsp -> A = Byte des Testprogramms
; Liest ueber den 32-Bit-Zeiger E1 = $0000_xxxx (Bank 0, echter Speicher des Testprogramms; die IDE selbst liegt in Bank 4).
dis_rd: clc
        adc dsp
        sta E1
        lda dsp + 1
        adc #$00
        sta E1 + 1
        lda #$00
        sta E1 + 2
        sta E1 + 3
        ldz #$00
        lda [E1],z
        rts

; dis_ch: A an dis_buf anhaengen
dis_ch: ldx dsi
        sta dis_buf,x
        inc dsi
        rts

; dis_hex1: untere Tetrade von A als Hexziffer (Kleinbuchstaben) anhaengen
dis_hex1:
        and #$0f
        cmp #$0a
        bcc dh1
        adc #$56                    ; Carry ist gesetzt: + $57 ergibt 'a'..'f'
        jmp dis_ch
dh1:    adc #$30                    ; Carry ist hier geloescht: '0'..'9'
        jmp dis_ch
; dis_hex2: A als zwei Hexziffern
dis_hex2:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr dis_hex1
        pla
        jmp dis_hex1
; dis_hex4: A = hoch, X = tief
dis_hex4:
        phx
        jsr dis_hex2
        pla
        jmp dis_hex2

dis_str:                            ; X/Y = Adresse einer mit 0 beendeten Zeichenkette anhaengen
        stx ET + 6
        sty ET + 7
        ldy #$00
ds1:    lda (ET + 6),y
        beq ds2
        phy
        jsr dis_ch
        ply
        iny
        bne ds1
ds2:    rts

; dis_one: Befehl bei dsp dekodieren (Eingabe dsp; Ausgabe dis_buf, dis_len, dis_flow, dis_tgt, siehe Kopf)
; Schritte: Praefixe erkennen (dsq, dse, dso), Opcode und Tabellenwerte holen, Name ausgeben, Operand je nach Adressierungsart.
dis_one:
        lda #$00
        sta dsq
        sta dse
        sta dso
        sta dsi
        sta dis_flow
        lda #$00
        jsr dis_rd
        cmp #$42                    ; Quad-Praefix = zwei Bytes $42 $42 (ein einzelnes $42 ist NEG und kein Praefix)
        bne dq_do1
        lda #$01
        jsr dis_rd
        cmp #$42
        bne dq_do1
        lda #$01
        sta dsq
        lda #$02
        sta dso
dq_do1:    lda dso                  ; $EA-Praefix? Nur gueltig, wenn danach ein (zp),z-Befehl (M_IZZ) steht
        jsr dis_rd
        cmp #$ea
        bne dq_do2
        lda dso
        clc
        adc #$01
        jsr dis_rd
        tax
        lda dt_mode,x
        cmp #M_IZZ
        bne dq_do2
        lda #$01
        sta dse
        inc dso
dq_do2:    lda dso                  ; Opcode (hinter den Praefixen)
        jsr dis_rd
        sta dsop
        tax
        lda dt_len,x
        clc
        adc dso                     ; Gesamtlaenge = Tabellenlaenge + Praefixbytes
        sta dis_len
        lda dt_mode,x
        sta dsm
        lda dsq
        beq dq_do3
        lda dt_qname,x              ; Quad: Name der Quad-Form ($FF = der Befehl hat keine)
        cmp #$ff
        bne dq_do4
        ldx #<s_unk                 ; Quad-Praefix ohne Quad-Befehl
        ldy #>s_unk
        jsr dis_str
        lda #$00
        ldx dsi
        sta dis_buf,x
        lda #$01
        sta dis_len                 ; nur ein Byte verbrauchen: das naechste $42 wird dann einzeln gelesen
        rts
dq_do3:    lda dt_name,x
dq_do4:    sta dsn
        lda #$00                    ; Namen suchen: dt_names + Index * 4
        sta ET + 7                  ; (16-Bit-Rechnung: Index * 4 kann ueber 255 laufen, 145 Namen * 4 = 580)
        lda dsn
        asl
        rol ET + 7
        asl
        rol ET + 7
        clc
        adc #<dt_names
        sta ET + 6
        lda ET + 7
        adc #>dt_names
        sta ET + 7
        ldy #$00
dq_do5:    lda (ET + 6),y           ; bis zu 4 Zeichen, die 0 beendet kuerzere Namen
        beq dq_do6
        phy
        jsr dis_ch
        ply
        iny
        cpy #$04
        bne dq_do5
dq_do6:    lda dsm                     ; Operand je nach Art
        cmp #M_IMP
        beq dofin
        cmp #M_ACC
        bne dacc
        lda #$20                    ; Akkumulator: "asl a"
        jsr dis_ch
        lda #$61
        ldx dsq
        beq dacc2
        lda #$71                    ; Quad: "lsrq q"
dacc2:  jsr dis_ch
        jmp dofin
dacc:
        lda #$20
        jsr dis_ch
        lda dsm
        cmp #M_IMM
        bne dq_dm1
        lda #$23                    ; "#$nn" (auch RTN #n)
        jsr dis_ch
        jsr dis_dollar
        jsr dis_op1
        jmp dis_fin
dq_dm1:    cmp #M_IMW
        bne dq_dm2
        lda #$23                    ; "#$nnnn": 16-Bit-Direktwert (PHW #$nnnn)
        jsr dis_ch
        jmp dis_abs
dq_dm2:    cmp #M_ZP
        bne dq_dm3
        jsr dis_dollar              ; "$zz"
        jsr dis_op1
        jmp dis_fin
dq_dm3:    cmp #M_ZPX
        bne dq_dm4
        jsr dis_dollar              ; "$zz,x"
        jsr dis_op1
        ldx #<s_x
        ldy #>s_x
        jmp dis_str_fin
dq_dm4:    cmp #M_ZPY
        bne dq_dm5
        jsr dis_dollar              ; "$zz,y"
        jsr dis_op1
        ldx #<s_y
        ldy #>s_y
        jmp dis_str_fin
dq_dm5:    cmp #M_ABS
        bne dm6
        lda dsop                    ; JMP/JSR absolut: Art und Ziel merken (nur diese beiden Opcodes, andere abs-Befehle nicht)
        cmp #$4c
        beq dm5j
        cmp #$20
        bne dm5n
        lda #FL_JSR
        bne dm5s
dm5j:   lda #FL_JMP
dm5s:   sta dis_flow
        jsr dis_getabs
        sta dis_tgt + 1
        stx dis_tgt
dm5n:   jmp dis_abs
dm6:    cmp #M_ABX
        bne dm7
        jsr dis_abs_nf              ; "$nnnn,x"
        ldx #<s_x
        ldy #>s_x
        jmp dis_str_fin
dm7:    cmp #M_ABY
        bne dm8
        jsr dis_abs_nf              ; "$nnnn,y"
        ldx #<s_y
        ldy #>s_y
        jmp dis_str_fin
dm8:    cmp #M_IND
        bne dm9
        lda #FL_IND                 ; JMP ($nnnn), JSR ($nnnn): Ziel erst zur Laufzeit bekannt
        sta dis_flow
        lda #$28
        jsr dis_ch
        jsr dis_abs_nf
        lda #$29
        jsr dis_ch
        jmp dofin
dm9:    cmp #M_IAX
        bne dm10
        lda #FL_IND                 ; JMP ($nnnn,x), JSR ($nnnn,x)
        sta dis_flow
        lda #$28
        jsr dis_ch
        jsr dis_abs_nf
        ldx #<s_xp
        ldy #>s_xp
        jmp dis_str_fin
dm10:   cmp #M_IZX
        bne dm11
        lda #$28                    ; "($zz,x)"
        jsr dis_ch
        jsr dis_dollar
        jsr dis_op1
        ldx #<s_xp
        ldy #>s_xp
        jmp dis_str_fin
dm11:   cmp #M_IZY
        bne dm12
        lda #$28                    ; "($zz),y"
        jsr dis_ch
        jsr dis_dollar
        jsr dis_op1
        ldx #<s_py
        ldy #>s_py
        jmp dis_str_fin
dm12:   cmp #M_IZZ
        bne dm13
        lda dse                     ; mit $EA-Praefix: 32-Bit-Zeiger "[$zz],z", sonst 16-Bit "($zz),z"
        bne dm12e
        lda #$28
        jsr dis_ch
        jsr dis_dollar
        jsr dis_op1
        ldx #<s_pz
        ldy #>s_pz
        jmp dis_str_fin
dm12e:  lda #$5b
        jsr dis_ch
        jsr dis_dollar
        jsr dis_op1
        ldx #<s_bz
        ldy #>s_bz
        jmp dis_str_fin
dm13:   cmp #M_ISY
        bne dm14
        lda #$28                    ; Stapelrelativ: "($zz,sp),y"
        jsr dis_ch
        jsr dis_dollar
        jsr dis_op1
        ldx #<s_sp
        ldy #>s_sp
        jmp dis_str_fin
dm14:   cmp #M_REL
        bne dm15
        lda #FL_BR
        sta dis_flow
        lda #$01                    ; Ziel = Adresse + 2 + vorzeichenbehaftet(op1)
        jsr dis_rd
        sta dst0
        lda #$00
        sta dst0 + 1
        lda dst0
        bpl dm14a
        lda #$ff                    ; Vorzeichenerweiterung auf 16 Bit
        sta dst0 + 1
dm14a:  lda #$02
        jmp dis_target
dm15:   cmp #M_RL
        bne dm16
        lda #FL_BR                  ; lange Verzweigung (LBxx, LBRA, BSR): 16-Bit-Abstand, ebenfalls ab Adresse + 2
        sta dis_flow
        lda dsop                    ; BSR ist ein Sprung in ein Unterprogramm
        cmp #$63
        bne dm15a
        lda #FL_JSR
        sta dis_flow
dm15a:  lda #$01
        jsr dis_rd
        sta dst0
        lda #$02
        jsr dis_rd
        sta dst0 + 1
        lda #$02
        jmp dis_target
dm16:                               ; M_ZPR: $zp,$ziel mit Ziel = Adresse + 3 + vorzeichenbehaftet(op2)
        lda #FL_BR                  ; (BBR0..7, BBS0..7: Bit im Zeropage-Byte testen; zuerst die Zeropage-Adresse, dann das Ziel)
        sta dis_flow
        jsr dis_dollar
        jsr dis_op1
        lda #$2c
        jsr dis_ch
        lda #$02
        jsr dis_rd
        sta dst0
        lda #$00
        sta dst0 + 1
        lda dst0
        bpl dm16a
        lda #$ff
        sta dst0 + 1
dm16a:  lda #$03
        jmp dis_target
dofin:  jmp dis_fin

; dis_fin: Text mit 0 beenden; Ruecksprung-/BRK-Befehle erkennen
; Diese Befehle haben die Art M_IMP (oder RTN: M_IMM) und kommen sonst nicht mit einem Fluss vor; dis_flow ist hier nur dann 0.
dis_fin:
        lda #$00
        ldx dsi
        sta dis_buf,x
        lda dis_flow
        bne dfx
        lda dsop
        cmp #$60                    ; RTS
        beq dfr
        cmp #$40                    ; RTI
        beq dfr
        cmp #$62                    ; RTN #n
        beq dfr
        cmp #$00                    ; BRK (dt_len = 1: die Tabelle zaehlt nur das Opcodebyte; dbg_next addiert das Signaturbyte)
        bne dfx
        lda #FL_BRK
        sta dis_flow
dfx:    rts
dfr:    lda #FL_RET
        sta dis_flow
        rts

; dis_str_fin: X/Y = Zeichenkette anhaengen, dann Text beenden
dis_str_fin:
        jsr dis_str
        jmp dis_fin

dis_dollar:
        lda #$24
        jmp dis_ch
; dis_op1: Operandbyte 1 als zwei Hexziffern
; (Versatz dso + 1: hinter dem Opcode, also hinter eventuellen Praefixbytes)
dis_op1:
        lda dso
        clc
        adc #$01
        jsr dis_rd
        jmp dis_hex2
; dis_getabs: A = hoch, X = tief des 16-Bit-Operands
dis_getabs:
        lda dso
        clc
        adc #$01
        jsr dis_rd
        tax
        lda dso
        clc
        adc #$02
        jsr dis_rd
        rts
; dis_abs_nf: "$nnnn" ohne Textabschluss (der Aufrufer haengt noch ")" oder ",x" an); dis_abs: mit Abschluss
dis_abs_nf:
        jsr dis_dollar
        jsr dis_getabs
        jmp dis_hex4
dis_abs:
        jsr dis_abs_nf
        jmp dis_fin
; dis_target: A = Versatz des naechsten Befehls (2 oder 3); dst0 = vorzeichenbehafteter Abstand -> Ziel ausgeben, in dis_tgt
; Ziel = dsp + A + dst0 (16 Bit, Ueberlauf wird verworfen); Verzweigungen kommen nie mit Praefix vor, daher genuegt dsp statt dso.
dis_target:
        clc
        adc dsp
        sta dis_tgt
        lda dsp + 1
        adc #$00
        sta dis_tgt + 1
        clc
        lda dis_tgt
        adc dst0
        sta dis_tgt
        lda dis_tgt + 1
        adc dst0 + 1
        sta dis_tgt + 1
        jsr dis_dollar
        ldx dis_tgt
        lda dis_tgt + 1
        jsr dis_hex4
        jmp dis_fin

; Textstuecke fuer die Operanden und Arbeitszellen (Ein-/Ausgabe siehe Kopf)
s_x:    .byte ",x", 0
s_y:    .byte ",y", 0
s_xp:   .byte ",x)", 0
s_py:   .byte "),y", 0
s_pz:   .byte "),z", 0
s_bz:   .byte "],z", 0
s_sp:   .byte ",sp),y", 0
s_unk:  .byte "???", 0
dsp:    .word 0                     ; Eingabe: Adresse des Befehls
dis_len: .byte 0                    ; Ausgabe: Befehlslaenge in Byte (mit Praefixen)
dis_flow: .byte 0                   ; Ausgabe: FL_*
dis_tgt: .word 0                    ; Ausgabe: Sprungziel (bei FL_BR, FL_JMP, FL_JSR)
dst0:   .word 0                     ; vorzeichenbehafteter Abstand einer Verzweigung
dsq:    .byte 0                     ; 1 = Quad-Praefix $42 $42
dse:    .byte 0                     ; 1 = Praefix $EA (32-Bit-Zeiger)
dso:    .byte 0                     ; Anzahl Praefixbytes = Versatz des Opcodes
dsi:    .byte 0                     ; Schreibindex in dis_buf
dsop:   .byte 0                     ; Opcode
dsm:    .byte 0                     ; Adressierungsart (M_*)
dsn:    .byte 0                     ; Namensindex in dt_names
dis_buf: .fill 40, 0                ; Ausgabetext
