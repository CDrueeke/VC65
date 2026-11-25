; SPDX-License-Identifier: GPL-3.0-or-later
; Testprogramm fuer die IDE (tools/idetest.py): wie vc65.asm, aber mit Quelltext aus dem Programm und Tasten aus einem Skript.
.target mega65
.cpu 45gs02 { illegals = deny }
.branchlong auto
.org $2001
.basicstub boot
IDE_BSS = 1
IDE_BUILD = 1
ed_scr  = $0800
ED_ATTR32 = $0ff80000               ; der Kern zeichnet direkt ins Farb-RAM
DISP_DIRECT = 1
.include "../ide/boot.asm"
main:   lda #$1f
        tab                         ; Basisseite $1F00
        jsr ide_init
        jsr ide_ldtab
        jsr oa_chk                  ; Overlay A laden (wie vc65.asm)
        lda #$09                    ; Standardzustand des VIC-IV merken (wie vc65.asm), sonst laedt ide_run einen leeren Zustand
        jsr ide_xcall
        lda #25
        jsr ed_init
        jsr ed_lbegin               ; Quelltext aus dem Attic ($0800_0000, Anfangsabbild) in den Editor laden
        lda #$00
        sta E2
        sta E2 + 1
        sta E2 + 2
        lda #$08
        sta E2 + 3
        lda #<{tlen}
        sta ed_cnt
        lda #>{tlen}
        sta ed_cnt + 1
tl:     lda ed_cnt
        ora ed_cnt + 1
        beq tld
        ldz #$00
        lda [E2],z
        jsr ed_ins
        inc E2
        bne tl1
        inc E2 + 1
tl1:    lda ed_cnt
        bne tl2
        dec ed_cnt + 1
tl2:    dec ed_cnt
        jmp tl
tld:    jsr ed_lend
        lda #<(keys)
        sta kpa
        lda #>(keys)
        sta kpa + 1
        lda #<(script_key)
        sta disp_keyv
        lda #>(script_key)
        sta disp_keyv + 1
        jsr ed_run
        lda #$00                    ; Ausgabe (Attic $0850_0000, hoechstens 4 KB) nach $0004_0000 kopieren
        sta E1
        sta E1 + 1
        sta E2
        sta E2 + 1
        sta E2 + 3
        lda #$50
        sta E1 + 2
        lda #$08
        sta E1 + 3
        lda #$04                    ; Ziel $0004_0000 (Bank 4 unterhalb des Abbilds, 8 KB frei)
        sta E2 + 2
        ldx ed_olen + 1             ; nur so viele Seiten wie noetig (hoechstens 8)
        inx
        cpx #$09
        bcc ocx
        ldx #$08
ocx:
oc:     ldz #$00
oc1:    lda [E1],z
        sta [E2],z
        inz
        bne oc1
        inc E1 + 1
        inc E2 + 1
        dex
        bne oc
        lda #$00                    ; Ergebnisse nach $0001_C400 (Bank 1): cur, olen, curline, Meldungszeile ab +$20
        sta E2
        sta E2 + 3
        lda #$c4
        sta E2 + 1
        lda #$01
        sta E2 + 2
        ldx #$03
kr:     txa
        taz
        lda ed_cur,x
        sta [E2],z
        txa
        clc
        adc #$04
        taz
        lda ed_olen,x
        sta [E2],z
        dex
        bpl kr
        ldz #$08
        lda ed_curline
        sta [E2],z
        inz
        lda ed_curline + 1
        sta [E2],z
        ldx #$00
km:     txa
        clc
        adc #$20
        taz
        lda $0800 + 24 * 80,x
        sta [E2],z
        inx
        cpx #80
        bne km
        lda #$00
        tab
        jsr kdefault
        lda #$93                    ; Bildschirm loeschen, damit BASIC wieder READY meldet (Xemu erkennt so das Ende)
        jsr $ffd2
        rts
script_key:                         ; Zeiger im Speicher (kpa), die Zeropage gehoert waehrenddessen dem Assembler/Editor
        lda kpa
        sta E2
        lda kpa + 1
        sta E2 + 1
        lda #$04                    ; das Tastenskript liegt im Abbild in Bank 4 (32-Bit-Zeiger sehen nicht durch MAP)
        sta E2 + 2
        lda #$00
        sta E2 + 3
        ldz #$00
        lda [E2],z
        beq sk_stop
        inc kpa
        bne sk_r
        inc kpa + 1
sk_r:   rts
sk_stop: lda snapd
        bne sk_s2
        lda #$01                    ; Skript zu Ende: Bild einmal nach $0004_1000 sichern (Bank 4 unterhalb des Abbilds)
        sta snapd
        lda #$00
        sta E1
        lda #$08
        sta E1 + 1
        lda #$00
        sta E1 + 2
        sta E1 + 3
        sta E2
        sta E2 + 3
        lda #$10
        sta E2 + 1
        lda #$04
        sta E2 + 2
        ldx #$08
sn_p:   ldz #$00
sn_b:   lda [E1],z
        sta [E2],z
        inz
        bne sn_b
        inc E1 + 1
        inc E2 + 1
        dex
        bne sn_p
        lda #$00                    ; Bild des Debuggers (Bank 4 bei $D200) nach $0004_1800 sichern
        sta E1
        lda #$d2
        sta E1 + 1
        lda #$04
        sta E1 + 2
        lda #$00
        sta E1 + 3
        sta E2
        lda #$18
        sta E2 + 1
        lda #$04
        sta E2 + 2
        lda #$00
        sta E2 + 3
        ldx #$08
sd_p:   ldz #$00
sd_b:   lda [E1],z
        sta [E2],z
        inz
        bne sd_b
        inc E1 + 1
        inc E2 + 1
        dex
        bne sd_p
sk_s2:  lda #$03
        rts
snapd:  .byte 0
.include "../asm/zp.asm"
.include "../asm/src.asm"
.include "optabsyms.asm"                 ; Befehlstabelle aus VC65T (build/optabsyms.asm, tools/build_ide.py: build_tables)
.include "../asm/mnfind.asm"
.include "../asm/sym.asm"
.include "../asm/expr.asm"
.include "../asm/enc.asm"
.include "../asm/numx.asm"
.include "../asm/stage2.asm"
.include "../asm/dir2.asm"
.include "../asm/text2.asm"
.include "../asm/funcres.asm"
.include "../asm/list.asm"
.include "../asm/err.asm"
.include "../asm/inc.asm"
.include "../asm/cyc.asm"
.include "../asm/loader.asm"
.include "../asm/asm.asm"
.include "../editor/ed.asm"
.include "../editor/disp.asm"
.include "../editor/file.asm"
.include "../ide/ide.asm"
kpa:    .word 0
keys:   {keys}
IMG_END:
