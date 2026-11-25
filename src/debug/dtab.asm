; SPDX-License-Identifier: GPL-3.0-or-later
; ERZEUGT von tools/gen_dtab.py aus vendor/vintagecoder/data/cpus/45gs02.cpu.json - nicht von Hand aendern.
; Dekodiertabellen fuer Disassembler und Debugger (Aufbau siehe tools/gen_dtab.py).
;
; Aufbau: vier Tabellen zu je 256 Byte, Index = Opcode (die ersten 16 Byte = Opcodes $00-$0F, je Zeile 16 Opcodes, Zeile n
; = obere Tetrade n), dazu die Namenstabelle dt_names. Verbraucher ist nur dis.asm (dis_one). Es gibt keine Praefix-Eintraege:
; $42 $42 (Quad) und $EA werden in dis_one vor dem Nachschlagen abgetrennt, Opcode $42 allein ist NEG, $EA allein EOM.
;   dt_len    Befehlslaenge in Byte (1..3) ohne Praefixe. BRK ($00) steht mit 1: das Signaturbyte hinter BRK ist nicht dabei.
;   dt_mode   Adressierungsart, Nummern wie M_* in src/asm/optab.asm:
;             0 imp (ohne Operand)  1 acc (Akku)  2 imm (#$nn)  3 imw (#$nnnn)  4 zp  5 zpx  6 zpy  7 abs  8 abx  9 aby
;             10 ind ($nnnn)  11 iax ($nnnn,x)  12 izx ($zz,x)  13 izy ($zz),y  14 izz ($zz),z / mit $EA [$zz],z
;             15 isy ($zz,sp),y  16 rel (8-Bit-Abstand)  17 rl (16-Bit-Abstand)  18 zpr ($zz,Ziel: BBR/BBS)
;   dt_name   Namensindex: Nummer des Eintrags in dt_names (nicht das Namenszeichen selbst).
;   dt_qname  Namensindex der Quad-Form nach dem Praefix $42 $42 (zum Beispiel lda -> ldq), $FF = keine Quad-Form.
;   dt_names  Namenseintraege zu 4 Byte: ASCII klein, rechts mit 0 aufgefuellt (bei kuerzeren Namen); Byteversatz = Index * 4.
;             Sortiert nach Namen. Der Klartextname hinter dem Semikolon ist nur zur Lesbarkeit (Generator).

; Befehlslaenge je Opcode
dt_len:
        .byte 1, 2, 1, 1, 2, 2, 2, 2, 1, 2, 1, 1, 3, 3, 3, 3
        .byte 2, 2, 2, 3, 2, 2, 2, 2, 1, 3, 1, 1, 3, 3, 3, 3
        .byte 3, 2, 3, 3, 2, 2, 2, 2, 1, 2, 1, 1, 3, 3, 3, 3
        .byte 2, 2, 2, 3, 2, 2, 2, 2, 1, 3, 1, 1, 3, 3, 3, 3
        .byte 1, 2, 1, 1, 2, 2, 2, 2, 1, 2, 1, 1, 3, 3, 3, 3
        .byte 2, 2, 2, 3, 2, 2, 2, 2, 1, 3, 1, 1, 1, 3, 3, 3
        .byte 1, 2, 2, 3, 2, 2, 2, 2, 1, 2, 1, 1, 3, 3, 3, 3
        .byte 2, 2, 2, 3, 2, 2, 2, 2, 1, 3, 1, 1, 3, 3, 3, 3
        .byte 2, 2, 2, 3, 2, 2, 2, 2, 1, 2, 1, 3, 3, 3, 3, 3
        .byte 2, 2, 2, 3, 2, 2, 2, 2, 1, 3, 1, 3, 3, 3, 3, 3
        .byte 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 3, 3, 3, 3, 3
        .byte 2, 2, 2, 3, 2, 2, 2, 2, 1, 3, 1, 3, 3, 3, 3, 3
        .byte 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 3, 3, 3, 3, 3
        .byte 2, 2, 2, 3, 2, 2, 2, 2, 1, 3, 1, 1, 3, 3, 3, 3
        .byte 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 3, 3, 3, 3, 3
        .byte 2, 2, 2, 3, 3, 2, 2, 2, 1, 3, 1, 1, 3, 3, 3, 3
; Adressierungsart je Opcode (M_*)
dt_mode:
        .byte 0, 12, 0, 0, 4, 4, 4, 4, 0, 2, 1, 0, 7, 7, 7, 18
        .byte 16, 13, 14, 17, 4, 5, 5, 4, 0, 9, 0, 0, 7, 8, 8, 18
        .byte 7, 12, 10, 11, 4, 4, 4, 4, 0, 2, 1, 0, 7, 7, 7, 18
        .byte 16, 13, 14, 17, 5, 5, 5, 4, 0, 9, 0, 0, 8, 8, 8, 18
        .byte 0, 12, 0, 0, 4, 4, 4, 4, 0, 2, 1, 0, 7, 7, 7, 18
        .byte 16, 13, 14, 17, 5, 5, 5, 4, 0, 9, 0, 0, 0, 8, 8, 18
        .byte 0, 12, 2, 17, 4, 4, 4, 4, 0, 2, 1, 0, 10, 7, 7, 18
        .byte 16, 13, 14, 17, 5, 5, 5, 4, 0, 9, 0, 0, 11, 8, 8, 18
        .byte 16, 12, 15, 17, 4, 4, 4, 4, 0, 2, 0, 8, 7, 7, 7, 18
        .byte 16, 13, 14, 17, 5, 5, 6, 4, 0, 9, 0, 9, 7, 8, 8, 18
        .byte 2, 12, 2, 2, 4, 4, 4, 4, 0, 2, 0, 7, 7, 7, 7, 18
        .byte 16, 13, 14, 17, 5, 5, 6, 4, 0, 9, 0, 8, 8, 8, 9, 18
        .byte 2, 12, 2, 4, 4, 4, 4, 4, 0, 2, 0, 7, 7, 7, 7, 18
        .byte 16, 13, 14, 17, 4, 5, 5, 4, 0, 9, 0, 0, 7, 8, 8, 18
        .byte 2, 12, 15, 4, 4, 4, 4, 4, 0, 2, 0, 7, 7, 7, 7, 18
        .byte 16, 13, 14, 17, 3, 5, 5, 4, 0, 9, 0, 0, 7, 8, 8, 18
; Namensindex je Opcode (in dt_names)
dt_name:
        .byte 34, 84, 40, 116, 137, 84, 4, 97, 87, 84, 4, 139, 137, 84, 4, 9
        .byte 32, 84, 84, 70, 136, 84, 4, 98, 38, 84, 57, 62, 136, 84, 4, 10
        .byte 64, 2, 64, 64, 28, 2, 105, 99, 93, 2, 105, 143, 28, 2, 105, 11
        .byte 30, 2, 2, 68, 28, 2, 105, 100, 114, 2, 48, 53, 28, 2, 105, 12
        .byte 110, 55, 82, 6, 6, 55, 79, 101, 86, 55, 79, 134, 63, 55, 79, 13
        .byte 36, 55, 55, 72, 6, 55, 79, 102, 41, 55, 90, 131, 81, 55, 79, 14
        .byte 111, 0, 111, 35, 130, 0, 107, 103, 92, 0, 107, 144, 63, 0, 107, 15
        .byte 37, 0, 0, 73, 130, 0, 107, 104, 117, 0, 95, 135, 63, 0, 107, 16
        .byte 33, 126, 126, 71, 129, 126, 128, 118, 52, 28, 140, 129, 129, 126, 128, 17
        .byte 25, 126, 126, 65, 129, 126, 128, 119, 142, 126, 141, 128, 130, 126, 130, 18
        .byte 77, 74, 76, 78, 77, 74, 76, 120, 133, 74, 132, 78, 77, 74, 76, 19
        .byte 26, 74, 74, 66, 77, 74, 76, 121, 42, 74, 138, 78, 77, 74, 76, 20
        .byte 46, 43, 47, 50, 46, 43, 48, 122, 61, 43, 51, 8, 46, 43, 48, 21
        .byte 31, 43, 43, 69, 47, 43, 48, 123, 39, 43, 89, 91, 47, 43, 48, 22
        .byte 45, 112, 74, 59, 45, 112, 57, 124, 60, 112, 54, 109, 45, 112, 57, 23
        .byte 27, 112, 112, 67, 88, 112, 57, 125, 115, 112, 94, 96, 88, 112, 57, 24
; Namensindex der Quad-Form je Opcode ($FF = keine)
dt_qname:
        .byte 255, 255, 255, 255, 255, 85, 5, 255, 255, 255, 5, 255, 255, 85, 5, 255
        .byte 255, 255, 85, 255, 255, 85, 5, 255, 255, 255, 58, 255, 255, 85, 5, 255
        .byte 255, 255, 255, 255, 29, 3, 106, 255, 255, 255, 106, 255, 29, 3, 106, 255
        .byte 255, 255, 3, 255, 29, 3, 106, 255, 255, 255, 49, 255, 29, 3, 106, 255
        .byte 255, 255, 83, 7, 7, 56, 80, 255, 255, 255, 80, 255, 255, 56, 80, 255
        .byte 255, 255, 56, 255, 7, 56, 80, 255, 255, 255, 255, 255, 255, 56, 80, 255
        .byte 255, 255, 255, 255, 255, 1, 108, 255, 255, 255, 108, 255, 255, 1, 108, 255
        .byte 255, 255, 1, 255, 255, 1, 108, 255, 255, 255, 255, 255, 255, 1, 108, 255
        .byte 255, 255, 255, 255, 255, 127, 255, 255, 255, 255, 255, 255, 255, 127, 255, 255
        .byte 255, 255, 127, 255, 255, 127, 255, 255, 255, 255, 255, 255, 255, 127, 255, 255
        .byte 255, 255, 255, 255, 255, 75, 255, 255, 255, 255, 255, 255, 255, 75, 255, 255
        .byte 255, 255, 75, 255, 255, 75, 255, 255, 255, 255, 255, 255, 255, 75, 255, 255
        .byte 255, 255, 255, 255, 255, 44, 49, 255, 255, 255, 255, 255, 255, 44, 49, 255
        .byte 255, 255, 44, 255, 255, 44, 49, 255, 255, 255, 255, 255, 255, 44, 49, 255
        .byte 255, 255, 255, 255, 255, 113, 58, 255, 255, 255, 255, 255, 255, 113, 58, 255
        .byte 255, 255, 113, 255, 255, 113, 58, 255, 255, 255, 255, 255, 255, 113, 58, 255
; Namen: 4 Byte je Eintrag (ASCII, mit 0 aufgefuellt), Reihenfolge = Index in dt_name/dt_qname
dt_names:
        .byte 97, 100, 99, 0   ; adc
        .byte 97, 100, 99, 113   ; adcq
        .byte 97, 110, 100, 0   ; and
        .byte 97, 110, 100, 113   ; andq
        .byte 97, 115, 108, 0   ; asl
        .byte 97, 115, 108, 113   ; aslq
        .byte 97, 115, 114, 0   ; asr
        .byte 97, 115, 114, 113   ; asrq
        .byte 97, 115, 119, 0   ; asw
        .byte 98, 98, 114, 48   ; bbr0
        .byte 98, 98, 114, 49   ; bbr1
        .byte 98, 98, 114, 50   ; bbr2
        .byte 98, 98, 114, 51   ; bbr3
        .byte 98, 98, 114, 52   ; bbr4
        .byte 98, 98, 114, 53   ; bbr5
        .byte 98, 98, 114, 54   ; bbr6
        .byte 98, 98, 114, 55   ; bbr7
        .byte 98, 98, 115, 48   ; bbs0
        .byte 98, 98, 115, 49   ; bbs1
        .byte 98, 98, 115, 50   ; bbs2
        .byte 98, 98, 115, 51   ; bbs3
        .byte 98, 98, 115, 52   ; bbs4
        .byte 98, 98, 115, 53   ; bbs5
        .byte 98, 98, 115, 54   ; bbs6
        .byte 98, 98, 115, 55   ; bbs7
        .byte 98, 99, 99, 0   ; bcc
        .byte 98, 99, 115, 0   ; bcs
        .byte 98, 101, 113, 0   ; beq
        .byte 98, 105, 116, 0   ; bit
        .byte 98, 105, 116, 113   ; bitq
        .byte 98, 109, 105, 0   ; bmi
        .byte 98, 110, 101, 0   ; bne
        .byte 98, 112, 108, 0   ; bpl
        .byte 98, 114, 97, 0   ; bra
        .byte 98, 114, 107, 0   ; brk
        .byte 98, 115, 114, 0   ; bsr
        .byte 98, 118, 99, 0   ; bvc
        .byte 98, 118, 115, 0   ; bvs
        .byte 99, 108, 99, 0   ; clc
        .byte 99, 108, 100, 0   ; cld
        .byte 99, 108, 101, 0   ; cle
        .byte 99, 108, 105, 0   ; cli
        .byte 99, 108, 118, 0   ; clv
        .byte 99, 109, 112, 0   ; cmp
        .byte 99, 112, 113, 0   ; cpq
        .byte 99, 112, 120, 0   ; cpx
        .byte 99, 112, 121, 0   ; cpy
        .byte 99, 112, 122, 0   ; cpz
        .byte 100, 101, 99, 0   ; dec
        .byte 100, 101, 113, 0   ; deq
        .byte 100, 101, 119, 0   ; dew
        .byte 100, 101, 120, 0   ; dex
        .byte 100, 101, 121, 0   ; dey
        .byte 100, 101, 122, 0   ; dez
        .byte 101, 111, 109, 0   ; eom
        .byte 101, 111, 114, 0   ; eor
        .byte 101, 111, 114, 113   ; eorq
        .byte 105, 110, 99, 0   ; inc
        .byte 105, 110, 113, 0   ; inq
        .byte 105, 110, 119, 0   ; inw
        .byte 105, 110, 120, 0   ; inx
        .byte 105, 110, 121, 0   ; iny
        .byte 105, 110, 122, 0   ; inz
        .byte 106, 109, 112, 0   ; jmp
        .byte 106, 115, 114, 0   ; jsr
        .byte 108, 98, 99, 99   ; lbcc
        .byte 108, 98, 99, 115   ; lbcs
        .byte 108, 98, 101, 113   ; lbeq
        .byte 108, 98, 109, 105   ; lbmi
        .byte 108, 98, 110, 101   ; lbne
        .byte 108, 98, 112, 108   ; lbpl
        .byte 108, 98, 114, 97   ; lbra
        .byte 108, 98, 118, 99   ; lbvc
        .byte 108, 98, 118, 115   ; lbvs
        .byte 108, 100, 97, 0   ; lda
        .byte 108, 100, 113, 0   ; ldq
        .byte 108, 100, 120, 0   ; ldx
        .byte 108, 100, 121, 0   ; ldy
        .byte 108, 100, 122, 0   ; ldz
        .byte 108, 115, 114, 0   ; lsr
        .byte 108, 115, 114, 113   ; lsrq
        .byte 109, 97, 112, 0   ; map
        .byte 110, 101, 103, 0   ; neg
        .byte 110, 101, 103, 113   ; negq
        .byte 111, 114, 97, 0   ; ora
        .byte 111, 114, 113, 0   ; orq
        .byte 112, 104, 97, 0   ; pha
        .byte 112, 104, 112, 0   ; php
        .byte 112, 104, 119, 0   ; phw
        .byte 112, 104, 120, 0   ; phx
        .byte 112, 104, 121, 0   ; phy
        .byte 112, 104, 122, 0   ; phz
        .byte 112, 108, 97, 0   ; pla
        .byte 112, 108, 112, 0   ; plp
        .byte 112, 108, 120, 0   ; plx
        .byte 112, 108, 121, 0   ; ply
        .byte 112, 108, 122, 0   ; plz
        .byte 114, 109, 98, 48   ; rmb0
        .byte 114, 109, 98, 49   ; rmb1
        .byte 114, 109, 98, 50   ; rmb2
        .byte 114, 109, 98, 51   ; rmb3
        .byte 114, 109, 98, 52   ; rmb4
        .byte 114, 109, 98, 53   ; rmb5
        .byte 114, 109, 98, 54   ; rmb6
        .byte 114, 109, 98, 55   ; rmb7
        .byte 114, 111, 108, 0   ; rol
        .byte 114, 111, 108, 113   ; rolq
        .byte 114, 111, 114, 0   ; ror
        .byte 114, 111, 114, 113   ; rorq
        .byte 114, 111, 119, 0   ; row
        .byte 114, 116, 105, 0   ; rti
        .byte 114, 116, 115, 0   ; rts
        .byte 115, 98, 99, 0   ; sbc
        .byte 115, 98, 99, 113   ; sbcq
        .byte 115, 101, 99, 0   ; sec
        .byte 115, 101, 100, 0   ; sed
        .byte 115, 101, 101, 0   ; see
        .byte 115, 101, 105, 0   ; sei
        .byte 115, 109, 98, 48   ; smb0
        .byte 115, 109, 98, 49   ; smb1
        .byte 115, 109, 98, 50   ; smb2
        .byte 115, 109, 98, 51   ; smb3
        .byte 115, 109, 98, 52   ; smb4
        .byte 115, 109, 98, 53   ; smb5
        .byte 115, 109, 98, 54   ; smb6
        .byte 115, 109, 98, 55   ; smb7
        .byte 115, 116, 97, 0   ; sta
        .byte 115, 116, 113, 0   ; stq
        .byte 115, 116, 120, 0   ; stx
        .byte 115, 116, 121, 0   ; sty
        .byte 115, 116, 122, 0   ; stz
        .byte 116, 97, 98, 0   ; tab
        .byte 116, 97, 120, 0   ; tax
        .byte 116, 97, 121, 0   ; tay
        .byte 116, 97, 122, 0   ; taz
        .byte 116, 98, 97, 0   ; tba
        .byte 116, 114, 98, 0   ; trb
        .byte 116, 115, 98, 0   ; tsb
        .byte 116, 115, 120, 0   ; tsx
        .byte 116, 115, 121, 0   ; tsy
        .byte 116, 120, 97, 0   ; txa
        .byte 116, 120, 115, 0   ; txs
        .byte 116, 121, 97, 0   ; tya
        .byte 116, 121, 115, 0   ; tys
        .byte 116, 122, 97, 0   ; tza
