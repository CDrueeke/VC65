; SPDX-License-Identifier: GPL-3.0-or-later
; flatio.asm - Messung: VIC-IV-Register ueber die flache Adresse $0FFD30xx (32-Bit-Zeiger) lesen und schreiben, ohne die
; E/A-Abbildung bei $D000. Ergebnis ab $4000: [0]=$D031 vor, [1]=$D07B vor, [2]=$D031 nach V400 ein, [3]=$D07B danach,
; [4..6]=SCRNPTR nach dem Setzen auf $0004D000, [7]=$D031 nach V400 aus, [8]=$D07B danach, [9..11]=SCRNPTR danach
.target mega65
.cpu 45gs02 { illegals = deny }

.org $2001
.basicstub start

start:  sei
        lda #$30                    ; Zeiger $0FFD30xx, tiefes Byte je Zugriff in $FB
        sta $fc
        lda #$fd
        sta $fd
        lda #$0f
        sta $fe
        ldz #$00
        lda #$2f
        sta $fb
        lda #$47                    ; VIC-IV freischalten ($D02F)
        sta [$fb],z
        lda #$53
        sta [$fb],z
        lda #$31
        sta $fb
        lda [$fb],z
        sta $4000
        lda #$7b
        sta $fb
        lda [$fb],z
        sta $4001
        lda #$31
        sta $fb
        lda [$fb],z
        ora #$08
        sta [$fb],z                 ; V400 ein
        lda [$fb],z
        sta $4002
        lda #$7b
        sta $fb
        lda [$fb],z
        sta $4003
        lda #$60                    ; SCRNPTR = $0004D000
        sta $fb
        lda #$00
        sta [$fb],z
        inz
        lda #$d0
        sta [$fb],z
        inz
        lda #$04
        sta [$fb],z
        ldz #$00
        lda [$fb],z
        sta $4004
        inz
        lda [$fb],z
        sta $4005
        inz
        lda [$fb],z
        sta $4006
        ldz #$00
        lda #$31
        sta $fb
        lda [$fb],z
        and #$f7
        sta [$fb],z                 ; V400 aus
        lda [$fb],z
        sta $4007
        lda #$7b
        sta $fb
        lda [$fb],z
        sta $4008
        lda #$60
        sta $fb
        lda [$fb],z
        sta $4009
        inz
        lda [$fb],z
        sta $400a
        inz
        lda [$fb],z
        sta $400b
        cli
        rts
