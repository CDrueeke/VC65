; SPDX-License-Identifier: GPL-3.0-or-later
; ERZEUGT von tools/gen_optab.py aus vendor/vintagecoder/data/cpus/45gs02.cpu.json - nicht von Hand aendern.
; Aufbau: siehe tools/gen_optab.py (Mnemonik-Tabelle, binaere Suche, Modenlisten).
; Hinweis: Diese Datei wird erzeugt; Kommentare hier gehen bei einer Neuerzeugung verloren und gehoeren dauerhaft
; in tools/gen_optab.py.
;
; Rolle im Assembler: Einzige Quelle der Befehlsdaten fuer den 45GS02 (Opcodes, Adressierungsarten, Taktzyklen). mnfind.asm (mn_find)
; sucht das Mnemonik in mn_table; enc.asm (md_has/try_mode/choose_mode) liest daraus ueber die Modenliste Adressierungsart und
; Opcode; cyc.asm liest cyc_base/cyc_worst. Die Datei enthaelt nur Daten, keinen Code, und wird deshalb auch von keinem Bank-
; oder Zeropage-Platz abhaengig.
;
; 1. Adressierungsarten M_* (Modenkennung; wird als Byte in den Modenlisten gespeichert und von enc.asm verglichen):
;    M_IMP implizit (kein Operand)   M_ACC Akkumulator (A, bei Q-Befehlen auch Q)   M_IMM #wert, 8 Bit   M_IMW #wert, 16 Bit (PHW)
;    M_ZP zp   M_ZPX zp,x   M_ZPY zp,y   M_ABS abs   M_ABX abs,x   M_ABY abs,y   M_IND (abs)   M_IAX (abs,x)
;    M_IZX (zp,x)   M_IZY (zp),y   M_IZZ (zp),z - mit Praefix $EA auch [zp],z (32-Bit-Zeiger)   M_ISY (d,sp),y
;    M_REL 8-Bit-Sprung relativ   M_RL 16-Bit-Sprung relativ (BSR, LBxx)   M_ZPR zp,ziel (BBRn/BBSn: Zeropage-Byte und Versatz)
;
; 2. mn_table: MN_COUNT (145) Eintraege zu MN_SIZE (7) Byte, aufsteigend nach den Namensbytes sortiert (Voraussetzung der binaeren
;    Suche in mn_find). Eintrag: Name (4 Byte, ASCII-Grossbuchstaben, rechts mit 0 aufgefuellt; die Ziffer von BBR0 gehoert zum Namen),
;    Flags (1 Byte: Bit0 = Q-Befehl, wird mit Praefix $42 $42 ausgegeben, alle anderen Bits 0), Zeiger auf die Modenliste (Wort).
; 3. Modenlisten md_xxx (ab md_data): [Anzahl n][Modus, Opcode] * n; Befehle mit gleichen Formen teilen die Liste nicht, sondern
;    haben je eine eigene (Q-Befehle wiederholen die Opcodes des Grundbefehls; das Praefix macht den Unterschied). Die Reihenfolge
;    in der Liste ist ohne Bedeutung (enc.asm sucht linear).
; 4. cyc_base / cyc_worst: je 256 Byte, Index = Opcode (vor Praefixen); Zyklen des Befehls ohne bzw. mit ungünstigstem Fall.

M_IMP = 0                           ; implizit
M_ACC = 1                           ; A (Akkumulator)
M_IMM = 2                           ; #wert (8 Bit)
M_IMW = 3                           ; #wert (16 Bit, PHW)
M_ZP = 4                            ; zp
M_ZPX = 5                           ; zp,x
M_ZPY = 6                           ; zp,y
M_ABS = 7                           ; abs
M_ABX = 8                           ; abs,x
M_ABY = 9                           ; abs,y
M_IND = 10                          ; (abs)
M_IAX = 11                          ; (abs,x)
M_IZX = 12                          ; (zp,x)
M_IZY = 13                          ; (zp),y
M_IZZ = 14                          ; (zp),z  (mit Praefix $EA: [zp],z)
M_ISY = 15                          ; (d,sp),y
M_REL = 16                          ; relativ 8 Bit (Bxx)
M_RL = 17                           ; relativ 16 Bit (LBxx, BSR)
M_ZPR = 18                          ; zp,ziel (BBRn/BBSn)

; Anzahl der Eintraege in mn_table
MN_COUNT = 145
; Eintragsgroesse in Byte (siehe mnfind.asm: Adresse = mn_table + Index * 7)
MN_SIZE = 7

; Mnemonik-Tabelle; Bytes sind die ASCII-Werte der Namen (z. B. 65, 68, 67 = "ADC"), danach Flags und Zeiger auf md_xxx.
; Beispiel: .byte 65, 68, 67, 81, 1 = "ADCQ" (4. Zeichen 'Q' = 81), Flag 1 = Q-Befehl.
mn_table:
        .byte 65, 68, 67, 0, 0
        .word md_ADC
        .byte 65, 68, 67, 81, 1
        .word md_ADCQ
        .byte 65, 78, 68, 0, 0
        .word md_AND
        .byte 65, 78, 68, 81, 1
        .word md_ANDQ
        .byte 65, 83, 76, 0, 0
        .word md_ASL
        .byte 65, 83, 76, 81, 1
        .word md_ASLQ
        .byte 65, 83, 82, 0, 0
        .word md_ASR
        .byte 65, 83, 82, 81, 1
        .word md_ASRQ
        .byte 65, 83, 87, 0, 0
        .word md_ASW
        .byte 66, 66, 82, 48, 0
        .word md_BBR0
        .byte 66, 66, 82, 49, 0
        .word md_BBR1
        .byte 66, 66, 82, 50, 0
        .word md_BBR2
        .byte 66, 66, 82, 51, 0
        .word md_BBR3
        .byte 66, 66, 82, 52, 0
        .word md_BBR4
        .byte 66, 66, 82, 53, 0
        .word md_BBR5
        .byte 66, 66, 82, 54, 0
        .word md_BBR6
        .byte 66, 66, 82, 55, 0
        .word md_BBR7
        .byte 66, 66, 83, 48, 0
        .word md_BBS0
        .byte 66, 66, 83, 49, 0
        .word md_BBS1
        .byte 66, 66, 83, 50, 0
        .word md_BBS2
        .byte 66, 66, 83, 51, 0
        .word md_BBS3
        .byte 66, 66, 83, 52, 0
        .word md_BBS4
        .byte 66, 66, 83, 53, 0
        .word md_BBS5
        .byte 66, 66, 83, 54, 0
        .word md_BBS6
        .byte 66, 66, 83, 55, 0
        .word md_BBS7
        .byte 66, 67, 67, 0, 0
        .word md_BCC
        .byte 66, 67, 83, 0, 0
        .word md_BCS
        .byte 66, 69, 81, 0, 0
        .word md_BEQ
        .byte 66, 73, 84, 0, 0
        .word md_BIT
        .byte 66, 73, 84, 81, 1
        .word md_BITQ
        .byte 66, 77, 73, 0, 0
        .word md_BMI
        .byte 66, 78, 69, 0, 0
        .word md_BNE
        .byte 66, 80, 76, 0, 0
        .word md_BPL
        .byte 66, 82, 65, 0, 0
        .word md_BRA
        .byte 66, 82, 75, 0, 0
        .word md_BRK
        .byte 66, 83, 82, 0, 0
        .word md_BSR
        .byte 66, 86, 67, 0, 0
        .word md_BVC
        .byte 66, 86, 83, 0, 0
        .word md_BVS
        .byte 67, 76, 67, 0, 0
        .word md_CLC
        .byte 67, 76, 68, 0, 0
        .word md_CLD
        .byte 67, 76, 69, 0, 0
        .word md_CLE
        .byte 67, 76, 73, 0, 0
        .word md_CLI
        .byte 67, 76, 86, 0, 0
        .word md_CLV
        .byte 67, 77, 80, 0, 0
        .word md_CMP
        .byte 67, 80, 81, 0, 1
        .word md_CPQ
        .byte 67, 80, 88, 0, 0
        .word md_CPX
        .byte 67, 80, 89, 0, 0
        .word md_CPY
        .byte 67, 80, 90, 0, 0
        .word md_CPZ
        .byte 68, 69, 67, 0, 0
        .word md_DEC
        .byte 68, 69, 81, 0, 1
        .word md_DEQ
        .byte 68, 69, 87, 0, 0
        .word md_DEW
        .byte 68, 69, 88, 0, 0
        .word md_DEX
        .byte 68, 69, 89, 0, 0
        .word md_DEY
        .byte 68, 69, 90, 0, 0
        .word md_DEZ
        .byte 69, 79, 77, 0, 0
        .word md_EOM
        .byte 69, 79, 82, 0, 0
        .word md_EOR
        .byte 69, 79, 82, 81, 1
        .word md_EORQ
        .byte 73, 78, 67, 0, 0
        .word md_INC
        .byte 73, 78, 81, 0, 1
        .word md_INQ
        .byte 73, 78, 87, 0, 0
        .word md_INW
        .byte 73, 78, 88, 0, 0
        .word md_INX
        .byte 73, 78, 89, 0, 0
        .word md_INY
        .byte 73, 78, 90, 0, 0
        .word md_INZ
        .byte 74, 77, 80, 0, 0
        .word md_JMP
        .byte 74, 83, 82, 0, 0
        .word md_JSR
        .byte 76, 66, 67, 67, 0
        .word md_LBCC
        .byte 76, 66, 67, 83, 0
        .word md_LBCS
        .byte 76, 66, 69, 81, 0
        .word md_LBEQ
        .byte 76, 66, 77, 73, 0
        .word md_LBMI
        .byte 76, 66, 78, 69, 0
        .word md_LBNE
        .byte 76, 66, 80, 76, 0
        .word md_LBPL
        .byte 76, 66, 82, 65, 0
        .word md_LBRA
        .byte 76, 66, 86, 67, 0
        .word md_LBVC
        .byte 76, 66, 86, 83, 0
        .word md_LBVS
        .byte 76, 68, 65, 0, 0
        .word md_LDA
        .byte 76, 68, 81, 0, 1
        .word md_LDQ
        .byte 76, 68, 88, 0, 0
        .word md_LDX
        .byte 76, 68, 89, 0, 0
        .word md_LDY
        .byte 76, 68, 90, 0, 0
        .word md_LDZ
        .byte 76, 83, 82, 0, 0
        .word md_LSR
        .byte 76, 83, 82, 81, 1
        .word md_LSRQ
        .byte 77, 65, 80, 0, 0
        .word md_MAP
        .byte 78, 69, 71, 0, 0
        .word md_NEG
        .byte 78, 69, 71, 81, 1
        .word md_NEGQ
        .byte 79, 82, 65, 0, 0
        .word md_ORA
        .byte 79, 82, 81, 0, 1
        .word md_ORQ
        .byte 80, 72, 65, 0, 0
        .word md_PHA
        .byte 80, 72, 80, 0, 0
        .word md_PHP
        .byte 80, 72, 87, 0, 0
        .word md_PHW
        .byte 80, 72, 88, 0, 0
        .word md_PHX
        .byte 80, 72, 89, 0, 0
        .word md_PHY
        .byte 80, 72, 90, 0, 0
        .word md_PHZ
        .byte 80, 76, 65, 0, 0
        .word md_PLA
        .byte 80, 76, 80, 0, 0
        .word md_PLP
        .byte 80, 76, 88, 0, 0
        .word md_PLX
        .byte 80, 76, 89, 0, 0
        .word md_PLY
        .byte 80, 76, 90, 0, 0
        .word md_PLZ
        .byte 82, 77, 66, 48, 0
        .word md_RMB0
        .byte 82, 77, 66, 49, 0
        .word md_RMB1
        .byte 82, 77, 66, 50, 0
        .word md_RMB2
        .byte 82, 77, 66, 51, 0
        .word md_RMB3
        .byte 82, 77, 66, 52, 0
        .word md_RMB4
        .byte 82, 77, 66, 53, 0
        .word md_RMB5
        .byte 82, 77, 66, 54, 0
        .word md_RMB6
        .byte 82, 77, 66, 55, 0
        .word md_RMB7
        .byte 82, 79, 76, 0, 0
        .word md_ROL
        .byte 82, 79, 76, 81, 1
        .word md_ROLQ
        .byte 82, 79, 82, 0, 0
        .word md_ROR
        .byte 82, 79, 82, 81, 1
        .word md_RORQ
        .byte 82, 79, 87, 0, 0
        .word md_ROW
        .byte 82, 84, 73, 0, 0
        .word md_RTI
        .byte 82, 84, 83, 0, 0
        .word md_RTS
        .byte 83, 66, 67, 0, 0
        .word md_SBC
        .byte 83, 66, 67, 81, 1
        .word md_SBCQ
        .byte 83, 69, 67, 0, 0
        .word md_SEC
        .byte 83, 69, 68, 0, 0
        .word md_SED
        .byte 83, 69, 69, 0, 0
        .word md_SEE
        .byte 83, 69, 73, 0, 0
        .word md_SEI
        .byte 83, 77, 66, 48, 0
        .word md_SMB0
        .byte 83, 77, 66, 49, 0
        .word md_SMB1
        .byte 83, 77, 66, 50, 0
        .word md_SMB2
        .byte 83, 77, 66, 51, 0
        .word md_SMB3
        .byte 83, 77, 66, 52, 0
        .word md_SMB4
        .byte 83, 77, 66, 53, 0
        .word md_SMB5
        .byte 83, 77, 66, 54, 0
        .word md_SMB6
        .byte 83, 77, 66, 55, 0
        .word md_SMB7
        .byte 83, 84, 65, 0, 0
        .word md_STA
        .byte 83, 84, 81, 0, 1
        .word md_STQ
        .byte 83, 84, 88, 0, 0
        .word md_STX
        .byte 83, 84, 89, 0, 0
        .word md_STY
        .byte 83, 84, 90, 0, 0
        .word md_STZ
        .byte 84, 65, 66, 0, 0
        .word md_TAB
        .byte 84, 65, 88, 0, 0
        .word md_TAX
        .byte 84, 65, 89, 0, 0
        .word md_TAY
        .byte 84, 65, 90, 0, 0
        .word md_TAZ
        .byte 84, 66, 65, 0, 0
        .word md_TBA
        .byte 84, 82, 66, 0, 0
        .word md_TRB
        .byte 84, 83, 66, 0, 0
        .word md_TSB
        .byte 84, 83, 88, 0, 0
        .word md_TSX
        .byte 84, 83, 89, 0, 0
        .word md_TSY
        .byte 84, 88, 65, 0, 0
        .word md_TXA
        .byte 84, 88, 83, 0, 0
        .word md_TXS
        .byte 84, 89, 65, 0, 0
        .word md_TYA
        .byte 84, 89, 83, 0, 0
        .word md_TYS
        .byte 84, 90, 65, 0, 0
        .word md_TZA

; Modenlisten: [Anzahl][Modus, Opcode]... je Befehl. Beispiel ADC: 9 Formen, (zp,x)=$61, zp=$65, #imm=$69, abs=$6d, (zp),y=$71,
; (zp),z=$72, zp,x=$75, abs,y=$79, abs,x=$7d.
md_data:
md_ADC:  .byte 9, 12, $61, 4, $65, 2, $69, 7, $6d, 13, $71, 14, $72, 5, $75, 9, $79, 8, $7d
md_ADCQ:  .byte 5, 4, $65, 7, $6d, 14, $72, 5, $75, 8, $7d
md_AND:  .byte 9, 12, $21, 4, $25, 2, $29, 7, $2d, 13, $31, 14, $32, 5, $35, 9, $39, 8, $3d
md_ANDQ:  .byte 5, 4, $25, 7, $2d, 14, $32, 5, $35, 8, $3d
md_ASL:  .byte 5, 4, $06, 1, $0a, 7, $0e, 5, $16, 8, $1e
md_ASLQ:  .byte 5, 4, $06, 1, $0a, 7, $0e, 5, $16, 8, $1e
md_ASR:  .byte 3, 0, $43, 4, $44, 5, $54
md_ASRQ:  .byte 3, 0, $43, 4, $44, 5, $54
md_ASW:  .byte 1, 7, $cb
md_BBR0:  .byte 1, 18, $0f
md_BBR1:  .byte 1, 18, $1f
md_BBR2:  .byte 1, 18, $2f
md_BBR3:  .byte 1, 18, $3f
md_BBR4:  .byte 1, 18, $4f
md_BBR5:  .byte 1, 18, $5f
md_BBR6:  .byte 1, 18, $6f
md_BBR7:  .byte 1, 18, $7f
md_BBS0:  .byte 1, 18, $8f
md_BBS1:  .byte 1, 18, $9f
md_BBS2:  .byte 1, 18, $af
md_BBS3:  .byte 1, 18, $bf
md_BBS4:  .byte 1, 18, $cf
md_BBS5:  .byte 1, 18, $df
md_BBS6:  .byte 1, 18, $ef
md_BBS7:  .byte 1, 18, $ff
md_BCC:  .byte 1, 16, $90
md_BCS:  .byte 1, 16, $b0
md_BEQ:  .byte 1, 16, $f0
md_BIT:  .byte 5, 4, $24, 7, $2c, 5, $34, 8, $3c, 2, $89
md_BITQ:  .byte 4, 4, $24, 7, $2c, 5, $34, 8, $3c
md_BMI:  .byte 1, 16, $30
md_BNE:  .byte 1, 16, $d0
md_BPL:  .byte 1, 16, $10
md_BRA:  .byte 1, 16, $80
md_BRK:  .byte 1, 0, $00
md_BSR:  .byte 1, 17, $63
md_BVC:  .byte 1, 16, $50
md_BVS:  .byte 1, 16, $70
md_CLC:  .byte 1, 0, $18
md_CLD:  .byte 1, 0, $d8
md_CLE:  .byte 1, 0, $02
md_CLI:  .byte 1, 0, $58
md_CLV:  .byte 1, 0, $b8
md_CMP:  .byte 9, 12, $c1, 4, $c5, 2, $c9, 7, $cd, 13, $d1, 14, $d2, 5, $d5, 9, $d9, 8, $dd
md_CPQ:  .byte 5, 4, $c5, 7, $cd, 14, $d2, 5, $d5, 8, $dd
md_CPX:  .byte 3, 2, $e0, 4, $e4, 7, $ec
md_CPY:  .byte 3, 2, $c0, 4, $c4, 7, $cc
md_CPZ:  .byte 3, 2, $c2, 4, $d4, 7, $dc
md_DEC:  .byte 5, 0, $3a, 4, $c6, 7, $ce, 5, $d6, 8, $de
md_DEQ:  .byte 5, 0, $3a, 4, $c6, 7, $ce, 5, $d6, 8, $de
md_DEW:  .byte 1, 4, $c3
md_DEX:  .byte 1, 0, $ca
md_DEY:  .byte 1, 0, $88
md_DEZ:  .byte 1, 0, $3b
md_EOM:  .byte 1, 0, $ea
md_EOR:  .byte 9, 12, $41, 4, $45, 2, $49, 7, $4d, 13, $51, 14, $52, 5, $55, 9, $59, 8, $5d
md_EORQ:  .byte 5, 4, $45, 7, $4d, 14, $52, 5, $55, 8, $5d
md_INC:  .byte 5, 0, $1a, 4, $e6, 7, $ee, 5, $f6, 8, $fe
md_INQ:  .byte 5, 0, $1a, 4, $e6, 7, $ee, 5, $f6, 8, $fe
md_INW:  .byte 1, 4, $e3
md_INX:  .byte 1, 0, $e8
md_INY:  .byte 1, 0, $c8
md_INZ:  .byte 1, 0, $1b
md_JMP:  .byte 3, 7, $4c, 10, $6c, 11, $7c
md_JSR:  .byte 3, 7, $20, 10, $22, 11, $23
md_LBCC:  .byte 1, 17, $93
md_LBCS:  .byte 1, 17, $b3
md_LBEQ:  .byte 1, 17, $f3
md_LBMI:  .byte 1, 17, $33
md_LBNE:  .byte 1, 17, $d3
md_LBPL:  .byte 1, 17, $13
md_LBRA:  .byte 1, 17, $83
md_LBVC:  .byte 1, 17, $53
md_LBVS:  .byte 1, 17, $73
md_LDA:  .byte 10, 12, $a1, 4, $a5, 2, $a9, 7, $ad, 13, $b1, 14, $b2, 5, $b5, 9, $b9, 8, $bd, 15, $e2
md_LDQ:  .byte 5, 4, $a5, 7, $ad, 14, $b2, 5, $b5, 8, $bd
md_LDX:  .byte 5, 2, $a2, 4, $a6, 7, $ae, 6, $b6, 9, $be
md_LDY:  .byte 5, 2, $a0, 4, $a4, 7, $ac, 5, $b4, 8, $bc
md_LDZ:  .byte 3, 2, $a3, 7, $ab, 8, $bb
md_LSR:  .byte 5, 4, $46, 1, $4a, 7, $4e, 5, $56, 8, $5e
md_LSRQ:  .byte 5, 4, $46, 1, $4a, 7, $4e, 5, $56, 8, $5e
md_MAP:  .byte 1, 0, $5c
md_NEG:  .byte 1, 0, $42
md_NEGQ:  .byte 1, 0, $42
md_ORA:  .byte 9, 12, $01, 4, $05, 2, $09, 7, $0d, 13, $11, 14, $12, 5, $15, 9, $19, 8, $1d
md_ORQ:  .byte 5, 4, $05, 7, $0d, 14, $12, 5, $15, 8, $1d
md_PHA:  .byte 1, 0, $48
md_PHP:  .byte 1, 0, $08
md_PHW:  .byte 2, 3, $f4, 7, $fc
md_PHX:  .byte 1, 0, $da
md_PHY:  .byte 1, 0, $5a
md_PHZ:  .byte 1, 0, $db
md_PLA:  .byte 1, 0, $68
md_PLP:  .byte 1, 0, $28
md_PLX:  .byte 1, 0, $fa
md_PLY:  .byte 1, 0, $7a
md_PLZ:  .byte 1, 0, $fb
md_RMB0:  .byte 1, 4, $07
md_RMB1:  .byte 1, 4, $17
md_RMB2:  .byte 1, 4, $27
md_RMB3:  .byte 1, 4, $37
md_RMB4:  .byte 1, 4, $47
md_RMB5:  .byte 1, 4, $57
md_RMB6:  .byte 1, 4, $67
md_RMB7:  .byte 1, 4, $77
md_ROL:  .byte 5, 4, $26, 1, $2a, 7, $2e, 5, $36, 8, $3e
md_ROLQ:  .byte 5, 4, $26, 1, $2a, 7, $2e, 5, $36, 8, $3e
md_ROR:  .byte 5, 4, $66, 1, $6a, 7, $6e, 5, $76, 8, $7e
md_RORQ:  .byte 5, 4, $66, 1, $6a, 7, $6e, 5, $76, 8, $7e
md_ROW:  .byte 1, 7, $eb
md_RTI:  .byte 1, 0, $40
md_RTS:  .byte 2, 0, $60, 2, $62
md_SBC:  .byte 9, 12, $e1, 4, $e5, 2, $e9, 7, $ed, 13, $f1, 14, $f2, 5, $f5, 9, $f9, 8, $fd
md_SBCQ:  .byte 5, 4, $e5, 7, $ed, 14, $f2, 5, $f5, 8, $fd
md_SEC:  .byte 1, 0, $38
md_SED:  .byte 1, 0, $f8
md_SEE:  .byte 1, 0, $03
md_SEI:  .byte 1, 0, $78
md_SMB0:  .byte 1, 4, $87
md_SMB1:  .byte 1, 4, $97
md_SMB2:  .byte 1, 4, $a7
md_SMB3:  .byte 1, 4, $b7
md_SMB4:  .byte 1, 4, $c7
md_SMB5:  .byte 1, 4, $d7
md_SMB6:  .byte 1, 4, $e7
md_SMB7:  .byte 1, 4, $f7
md_STA:  .byte 9, 12, $81, 15, $82, 4, $85, 7, $8d, 13, $91, 14, $92, 5, $95, 9, $99, 8, $9d
md_STQ:  .byte 5, 4, $85, 7, $8d, 14, $92, 5, $95, 8, $9d
md_STX:  .byte 4, 4, $86, 7, $8e, 6, $96, 9, $9b
md_STY:  .byte 4, 4, $84, 8, $8b, 7, $8c, 5, $94
md_STZ:  .byte 4, 4, $64, 5, $74, 7, $9c, 8, $9e
md_TAB:  .byte 1, 0, $5b
md_TAX:  .byte 1, 0, $aa
md_TAY:  .byte 1, 0, $a8
md_TAZ:  .byte 1, 0, $4b
md_TBA:  .byte 1, 0, $7b
md_TRB:  .byte 2, 4, $14, 7, $1c
md_TSB:  .byte 2, 4, $04, 7, $0c
md_TSX:  .byte 1, 0, $ba
md_TSY:  .byte 1, 0, $0b
md_TXA:  .byte 1, 0, $8a
md_TXS:  .byte 1, 0, $9a
md_TYA:  .byte 1, 0, $98
md_TYS:  .byte 1, 0, $2b
md_TZA:  .byte 1, 0, $6b

; Zyklen je Opcode: Index = Opcode ($00-$FF, 16 Werte je Zeile = hohes Nibble der Zeile), Grundzahl und ungünstigster Fall
; (cyc_base: ohne Zuschlag; cyc_worst: Sprung genommen +2, Seitenüberschreitung +1)
; Zyklen je Opcode: Grundzahl und ungünstigster Fall (Sprung genommen +2, Seitenüberschreitung +1)
cyc_base:
        .byte 9, 7, 3, 1, 6, 4, 6, 6, 3, 2, 1, 1, 7, 5, 7, 5
        .byte 2, 7, 7, 4, 6, 4, 6, 6, 1, 5, 1, 1, 7, 5, 7, 5
        .byte 5, 7, 8, 8, 4, 4, 6, 6, 4, 2, 1, 1, 5, 5, 7, 5
        .byte 2, 7, 7, 4, 4, 4, 6, 6, 1, 5, 1, 1, 5, 5, 7, 5
        .byte 6, 7, 1, 1, 6, 4, 6, 6, 3, 2, 1, 1, 5, 5, 7, 5
        .byte 2, 7, 7, 4, 6, 4, 6, 6, 3, 5, 3, 1, 3, 5, 7, 5
        .byte 5, 7, 5, 5, 3, 4, 6, 6, 4, 2, 1, 1, 7, 5, 7, 5
        .byte 2, 7, 7, 4, 3, 4, 6, 6, 1, 5, 4, 1, 7, 5, 7, 5
        .byte 4, 6, 7, 5, 3, 3, 3, 6, 1, 2, 1, 4, 4, 4, 4, 5
        .byte 2, 6, 6, 4, 3, 3, 3, 6, 1, 4, 1, 4, 4, 4, 4, 5
        .byte 2, 7, 2, 2, 4, 4, 4, 6, 1, 2, 1, 5, 5, 5, 5, 5
        .byte 2, 7, 7, 4, 4, 4, 4, 6, 1, 5, 1, 5, 5, 5, 5, 5
        .byte 2, 7, 2, 8, 4, 4, 6, 6, 1, 2, 1, 9, 5, 5, 7, 5
        .byte 2, 7, 7, 4, 4, 4, 6, 6, 1, 5, 3, 3, 5, 5, 7, 5
        .byte 2, 7, 8, 8, 4, 4, 6, 6, 1, 2, 1, 9, 5, 5, 7, 5
        .byte 2, 7, 7, 4, 6, 4, 6, 6, 1, 5, 4, 4, 9, 5, 7, 5
cyc_worst:
        .byte 9, 7, 3, 1, 6, 4, 6, 6, 3, 2, 1, 1, 7, 5, 7, 5
        .byte 4, 7, 7, 4, 6, 4, 6, 6, 1, 5, 1, 1, 7, 5, 7, 5
        .byte 5, 7, 8, 8, 4, 4, 6, 6, 4, 2, 1, 1, 5, 5, 7, 5
        .byte 4, 7, 7, 4, 4, 4, 6, 6, 1, 5, 1, 1, 5, 5, 7, 5
        .byte 6, 7, 1, 1, 6, 4, 6, 6, 3, 2, 1, 1, 5, 5, 7, 5
        .byte 4, 7, 7, 4, 6, 4, 6, 6, 3, 5, 3, 1, 3, 5, 7, 5
        .byte 5, 7, 5, 5, 3, 4, 6, 6, 4, 2, 1, 1, 7, 5, 7, 5
        .byte 4, 7, 7, 4, 3, 4, 6, 6, 1, 5, 4, 1, 7, 5, 7, 5
        .byte 6, 6, 7, 5, 3, 3, 3, 6, 1, 2, 1, 4, 4, 4, 4, 5
        .byte 4, 6, 6, 4, 3, 3, 3, 6, 1, 4, 1, 4, 4, 4, 4, 5
        .byte 2, 7, 2, 2, 4, 4, 4, 6, 1, 2, 1, 5, 5, 5, 5, 5
        .byte 4, 7, 7, 4, 4, 4, 4, 6, 1, 5, 1, 5, 5, 5, 5, 5
        .byte 2, 7, 2, 8, 4, 4, 6, 6, 1, 2, 1, 9, 5, 5, 7, 5
        .byte 4, 7, 7, 4, 4, 4, 6, 6, 1, 5, 3, 3, 5, 5, 7, 5
        .byte 2, 7, 8, 8, 4, 4, 6, 6, 1, 2, 1, 9, 5, 5, 7, 5
        .byte 4, 7, 7, 4, 6, 4, 6, 6, 1, 5, 4, 4, 9, 5, 7, 5
