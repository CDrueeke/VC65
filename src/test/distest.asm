; SPDX-License-Identifier: GPL-3.0-or-later
; Testprogramm fuer den Disassembler (tools/distest.py): zerlegt die Bytes ab prog in Befehle und legt je Befehl Laenge und Text
; ab $0004_0000 ab ([Laenge][Text][0] ...), danach 0 als Ende.
.target mega65
.cpu 45gs02 { illegals = deny }
.branchlong auto
.org $2001
.basicstub start
E0      = $20
E1      = $24
E2      = $28
ET      = $30
start:  sei
        lda #$02
        tab
        lda #<prog
        sta dsp
        lda #>prog
        sta dsp + 1
        lda #$00
        sta E2
        sta E2 + 1
        sta E2 + 3
        lda #$04
        sta E2 + 2
lp:     lda dsp
        cmp #<progend
        lda dsp + 1
        sbc #>progend
        bcs fin
        jsr dis_one
        ldz #$00
        lda dis_len
        sta [E2],z
        inz
        ldx #$00
cp:     lda dis_buf,x
        sta [E2],z
        beq cpd
        inz
        inx
        bne cp
cpd:    inz
        tza
        clc
        adc E2
        sta E2
        bcc cn
        inc E2 + 1
cn:     lda dsp
        clc
        adc dis_len
        sta dsp
        bcc lp
        inc dsp + 1
        jmp lp
fin:    ldz #$00
        lda #$00
        sta [E2],z
        lda #$00
        tab
        lda #$93
        jsr $ffd2
        rts
.include "../asm/optab.asm"
.include "../debug/dtab.asm"
.include "../debug/dis.asm"
prog:   {prog}
progend:
