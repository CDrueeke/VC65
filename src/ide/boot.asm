; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; boot.asm - VC65 laeuft aus Bank 4 (Konzept Abschnitt 7: Bank 0 gehoert dem Testprogramm). BASIC laedt das PRG nach Bank 0
; ($2001..); boot kopiert das Abbild $2000..IMG_END ueber 32-Bit-Zeiger nach $0004_2000, blendet mit MAP die CPU-Adressen
; $2000-$FFFF auf Bank 4 ($42000-$4FFFF; Overlays ab $D000/$E000, IDE-Abbild selbst endet vor $D000) und laeuft dort weiter (das kopierte Abbild ist bytegleich). Danach ist Bank 0 frei.
; Die Bruecke (Bank 0, ab BR, immer sichtbar) macht die Standardabbildung fuer KERNAL-Aufrufe und das Testprogramm:
;   kcall    ruft die KERNAL-Routine in kc_t (Register A, X, Y und Flags gehen durch); die Zugriffe KSETNAM usw. sind Sprungstuecke
;   kgetin   wartet auf eine Taste (Standardabbildung, Interrupts nur waehrenddessen frei)
;   krun     ruft das Testprogramm bei kr_t auf (JSR; Rueckkehr per RTS), Basisregister B und IDE-Abbildung werden wiederhergestellt
;   kdefault stellt die Standardabbildung her (vor dem Rueckkehr nach BASIC)
; Abbildungen (MAP-Register A, X, Y, Z): Standard $00,$00,$00,$83 (KERNAL-ROM bei $E000); IDE $00,$E4,$00,$F4 (A=0,X=MAPX: CPU-Blocke 1-3 und Z=MAPZ: Blocke 4-7 -> +$40000; die Bloecke sind je 8 KByte gross; MAPZ stand frueher als $34).
; Interrupts bleiben in der IDE gesperrt (sei); der Vektor bei $FFFE waere in der IDE-Abbildung nicht das ROM.
;
; Speicherplan Bank 0 (nur die Teile, die diese Datei belegt; alles liegt in "freien" Luecken zwischen den Assemblerpuffern):
;   $1648..     Bruecke (bridge_src, BR_LEN Byte, wird von boot hierher kopiert; muss unterhalb $1800 enden)
;   $1380..     Fallenhandler ktrap/kgo/knmi/kvec_* (bridge2_src, BR2_LEN, hoechstens 128 Byte)
;   $12E0..     Variablen der Falle (bridge3_src, BR3_LEN Byte: kt_*, kg_sp, kv_sv)
; Bank-4-Abbild: Quelle $2000..IMG_END in Bank 0 -> Ziel $4_2000..; Vektoren $4_FFFA..$4_FFFF zeigen auf ide_rti.
; Das Overlay VC65D (Debugger) liegt ab $E000 (CPU), also im Bereich Bank 4 $4_E000; OV_TRAP ist sein Einsprung (Sprungtabelle).
; Zeropage bei boot: $F8/$F9 Quelle, $FA/$FB Ziel (16 Bit, Bruecke kopieren); $F8..$FB und $FC..$FF als 32-Bit-Zeiger
; ([$f8],z bzw. [$fc],z: Byte 0-1 Adresse, Byte 2 Bank, Byte 3 = 0 bzw. Megabyte) fuer das Abbild. Reihenfolge in boot:
; Bruecke -> Fallenvariablen -> Fallenhandler -> Abbild -> Vektoren -> MAP -> Sprung nach main (Bank 4).
; Invariante: Die Bruecke liegt in Bank 0 und ist in beiden Abbildungen sichtbar (MAPX blendet nur Bloecke 1-5 um), darum
; kann sie die Abbildung umschalten, ohne dass der laufende Befehlsstrom verschwindet.
; =====================================================================================================================
BR      = $1648                     ; Bruecke in Bank 0 (zwischen den Puffern $1200-$1648 und $1800)
OV_TRAP = $e003                     ; Einsprung des Debugger-Overlays: Sprungtabelle von VC65D beginnt bei $E000, Eintrag 1 (JMP) bei +3
VARR    = $12e0                     ; Variablen der Falle (Bank 0)
DBGR    = $1380                     ; Fallenhandler (128 Byte frei zwischen onelist und cynames)
MAPX    = $e4                       ; MAP-X: Bits 7-4 = Blockfreigabe 3,2,1,0 (Bit 4 = Block 0): $E = Bloecke 1-3 ($2000-$7FFF); Bits 3-0 = Offset $4 -> +$40000
MAPZ    = $f4                       ; Bloecke 4-7 ($8000-$FFFF) -> +$40000: Bank 4 liefert $C000-$FFFF (Overlay VC65D ab $D000, Vektoren)

; boot: Einsprung aus BASIC (SYS). Laeuft noch in Bank 0 mit Standardabbildung. Eingabe: keine. Kehrt nicht zurueck (jmp main).
boot:   sei                         ; waehrend Kopieren/Umschalten keine Interrupts (Vektor $FFFE waere nach MAP nicht das ROM)
        lda #<bridge_src            ; Bruecke kopieren (BR_LEN Byte)
        sta $f8
        lda #>bridge_src
        sta $f9
        lda #<BR
        sta $fa
        lda #>BR
        sta $fb
        ldy #$00
bt_c1:    lda ($f8),y               ; erste Seite (256 Byte); BR_LEN > 256 ist moeglich, daher zweite Schleife
        sta ($fa),y
        iny
        bne bt_c1
        inc $f9                     ; naechste Seite von Quelle und Ziel
        inc $fb
bt_c2:    lda ($f8),y               ; Rest: Y laeuft von 0 bis <BR_LEN (setzt BR_LEN mod 256 <> 0 voraus)
        sta ($fa),y
        iny
        cpy #<(BR_LEN)
        bne bt_c2
        ldx #BR3_LEN - 1            ; Variablen der Falle kopieren
bt_c4:  lda bridge3_src,x
        sta VARR,x
        dex
        bpl bt_c4
        ldx #BR2_LEN - 1            ; Fallenhandler kopieren
bt_c3:  lda bridge2_src,x
        sta DBGR,x
        dex
        bpl bt_c3
        lda #$00                    ; Abbild $2000.. (Bank 0) nach $0004_2000 kopieren, beides ueber 32-Bit-Zeiger
        sta $f8                     ; Quelle [$f8..$fb] = $0000_2000 (Byte 3 = $ff-Slot wird unten auf 0 gesetzt)
        sta $fc
        sta $fa
        sta $fb
        sta $ff                     ; Zielzeiger [$fc..$ff]: Byte 3 (Megabyte) = 0
        lda #$20
        sta $f9
        sta $fd
        lda #$04
        sta $fe
        ldx #(>IMG_END) - $20 + 1   ; Anzahl Seiten ($2000 bis zur Seite von IMG_END einschliesslich)
bp:     ldz #$00
bb:     lda [$f8],z                 ; 32-Bit-indirekt: Quelle Bank 0 -> Ziel Bank 4, Z als Index (Z waere sonst Bank-unabhaengig)
        sta [$fc],z
        inz
        bne bb
        inc $f9                     ; naechste Seite (Quelle und Ziel gleichzeitig)
        inc $fd
        dex
        bne bp
        lda #$fa                    ; Vektoren $FFFA-$FFFF in Bank 4 auf ide_rti (die IDE laeuft mit gesperrten Interrupts; ein NMI endet harmlos)
        sta $fc
        lda #$ff
        sta $fd
        lda #$04
        sta $fe
        lda #$00
        sta $ff
        ldz #$00
bt_v:   lda #<ide_rti
        sta [$fc],z
        inz
        lda #>ide_rti
        sta [$fc],z
        inz
        cpz #$06
        bne bt_v
        lda #$00                    ; IDE-Abbildung: ab hier ist Bank 4 sichtbar
        ldx #MAPX                   ; (A,X: Bloecke 0-3 der Abbildung; Y,Z: Bloecke 4-7; siehe MAP-Befehl des 45GS02)
        ldy #$00
        ldz #MAPZ
        map                         ; MAP wirkt erst nach dem naechsten Befehl; EOM (NOP) beendet die Abbildungs-Sperre fuer Interrupts
        eom                         ; EOM = "end of mapping": ab hier gilt die neue Abbildung; der kopierte Code ist bytegleich
        jmp main

ide_rti: rti                        ; Ziel aller Vektoren in Bank 4 (NMI/IRQ/RESET): ein unerwarteter Interrupt endet harmlos

; ---- Bruecke (wird nach BR kopiert; .pseudopc: Labels haben die Adresse BR+Offset) -----------------------------------
bridge_src:
.pseudopc BR
; kdefault: Standardabbildung. Eingabe: -. Ausgabe: A=0, X=0, Y=0, Z=$83 (nach MAP). Aendert A, X, Y, Z. Z=$83: Bloecke 6/7 zeigen
; das KERNAL-ROM ($E000); MAP-Z-Register muss mit dem Zielwert geladen sein, bevor MAP ausgefuehrt wird.
kdefault:
        lda #$00
        ldx #$00
        ldy #$00
        ldz #$83
        map
        eom
        rts
; kide: IDE-Abbildung (Gegenstueck von kdefault). Aendert A, X, Y, Z (Z=MAPZ); Aufrufer muss Z ggf. selbst sichern (siehe kcall).
kide:   lda #$00
        ldx #MAPX
        ldy #$00
        ldz #MAPZ
        map
        eom
        rts

; kcall: KERNAL-Routine kc_t mit A, X, Y; Ergebnis A, X, Y, Flags. Z bleibt erhalten (kc_z), B unveraendert. Das KERNAL
; laeuft in der Standardabbildung (mit Interrupts, falls es sie freigibt); danach sei. Die Flags (Carry = Fehler) werden ueber
; kc_p durchgereicht, weil kide selbst die Flags verdirbt.
kcall:  sta kc_a
        stx kc_x
        sty kc_y
        tza
        sta kc_z
        jsr kdefault
        lda kc_a
        ldx kc_x
        ldy kc_y
        ldz #$00                    ; das KERNAL erwartet Z = 0
        jsr kc_go                   ; indirekter Sprung (jmp (kc_t)) mit JSR-Rueckadresse
        php                         ; Flags sichern (kide veraendert sie)
        sta kc_a
        stx kc_x
        sty kc_y
        pla
        sta kc_p
        jsr kide
        ldz kc_z
        lda kc_p
        pha
        lda kc_a
        ldx kc_x
        ldy kc_y
        plp                         ; Flags des KERNAL wiederherstellen
        sei                         ; das KERNAL kann Interrupts freigeben; in der IDE-Abbildung duerfen sie nicht ankommen
        rts
kc_go:  jmp (kc_t)                  ; "JSR indirekt": ruft per kc_go die Adresse in kc_t auf

; Sprungstuecke fuer die KERNAL-Routinen: Adresse nach kc_t, dann kcall (A, X, Y gehen unveraendert durch)
; KSETNAM: der Dateiname muss fuer das KERNAL in Bank 0 liegen; er wird (hoechstens 28 Zeichen) nach kname kopiert
; Eingabe: A = Laenge, X/Y = Adresse (lo/hi) des Namens in der IDE-Abbildung. Ausgabe wie KERNAL SETNAM. Aendert kn_ld (selbstmodifizierend).
KSETNAM: sta kn_l
        stx kn_ld + 1
        sty kn_ld + 2
        ldx #$00
kn_c:   cpx kn_l
        beq kn_d
kn_ld:  lda $0100,x                 ; absolute Adresse (wird beim Aufruf eingesetzt; selbstmodifizierend, Bruecke liegt im RAM)
        sta kname,x
        inx
        cpx #$1c
        bne kn_c
kn_d:   stx kn_l                    ; tatsaechlich kopierte Laenge (auf 28 begrenzt)
        lda #<$ffbd                 ; KERNAL SETNAM
        sta kc_t
        lda #>$ffbd
        sta kc_t + 1
        lda kn_l
        ldx #<kname
        ldy #>kname
        jmp kcall
; Die folgenden Sprungstuecke haben alle die Form: A retten, kc_t auf den KERNAL-Sprungtabelleneintrag setzen, A zurueck, kcall.
; (A muss gerettet werden, weil das Laden von kc_t A braucht; X und Y bleiben unberuehrt.)
KSETLFS: pha                        ; KERNAL SETLFS ($FFBA)
        lda #<$ffba
        sta kc_t
        lda #>$ffba
        sta kc_t + 1
        pla
        jmp kcall
KOPEN: pha                          ; KERNAL OPEN ($FFC0)
        lda #<$ffc0
        sta kc_t
        lda #>$ffc0
        sta kc_t + 1
        pla
        jmp kcall
KCLOSE: pha                         ; KERNAL CLOSE ($FFC3)
        lda #<$ffc3
        sta kc_t
        lda #>$ffc3
        sta kc_t + 1
        pla
        jmp kcall
KCHKIN: pha                         ; KERNAL CHKIN ($FFC6)
        lda #<$ffc6
        sta kc_t
        lda #>$ffc6
        sta kc_t + 1
        pla
        jmp kcall
KCKOUT: pha                         ; KERNAL CKOUT ($FFC9)
        lda #<$ffc9
        sta kc_t
        lda #>$ffc9
        sta kc_t + 1
        pla
        jmp kcall
KCLRCHN: pha                        ; KERNAL CLRCHN ($FFCC)
        lda #<$ffcc
        sta kc_t
        lda #>$ffcc
        sta kc_t + 1
        pla
        jmp kcall
KCHRIN: pha                         ; KERNAL CHRIN ($FFCF)
        lda #<$ffcf
        sta kc_t
        lda #>$ffcf
        sta kc_t + 1
        pla
        jmp kcall
KCHROUT: pha                        ; KERNAL CHROUT ($FFD2)
        lda #<$ffd2
        sta kc_t
        lda #>$ffd2
        sta kc_t + 1
        pla
        jmp kcall
KREADST: pha                        ; KERNAL READST ($FFB7)
        lda #<$ffb7
        sta kc_t
        lda #>$ffb7
        sta kc_t + 1
        pla
        jmp kcall

; kgetin: auf eine Taste warten. Ausgabe: A = Tastencode (nie 0). Das Basisregister B wird gesichert und auf 0 gestellt (das KERNAL
; rechnet mit Zeropage $00xx), Interrupts sind nur waehrend des Wartens frei (Tastaturabfrage im IRQ).
kernal_getin:
        tba                         ; B (Basisseite) retten
        sta kb_b
        lda #$00
        tab                         ; B = 0: Zeropage des KERNAL
        jsr kdefault
        ldz #$00                    ; KERNAL erwartet Z = 0
        cli                         ; nur hier sind Interrupts frei: der IRQ liest die Tastatur in den Tastaturpuffer
kb_l:   jsr $ffe4                   ; GETIN
        beq kb_l                    ; 0 = keine Taste, weiter warten
        sei
        sta kb_k                    ; Taste zwischenspeichern (jsr kide verdirbt A)
        jsr kide
        lda kb_b
        tab
        lda kb_k
        rts

; krun: Testprogramm bei kr_t aufrufen. Eingabe: kr_t = Startadresse (Bank 0). Rueckkehr entweder durch RTS des Programms oder (Falle,
; Notaus) ueber ktr_ab/kr_after mit wiederhergestelltem Stapel (kr_sp). kr_trap: 0 = normal, 2 = abgebrochen (Debugger fehlt/Abbruch).
krun:   tba
        sta kr_b
        lda #$00
        tab
        jsr kdefault
        lda $d031                   ; V400 aus: das Testprogramm bekommt den Standardbildschirm (25 Zeilen, SCRNPTR $0800);
        and #$f7                    ; das heisse Register $D031 setzt DISPROWS, SCRNPTR und COLPTR zurueck
        sta $d031
        ldz #$00
        jsr kvec_set                ; BRK- und NMI-Vektor auf ktrap/knmi
        lda #$00
        sta kr_trap
        tsx
        stx kr_sp
        cli
        jsr kr_go
kr_after:
        sei
        jsr kvec_rst
        jsr kide
        lda kr_b
        tab
        rts
kr_go:  jmp (kr_t)

; kvic: Rahmen und Hintergrund schwarz, Attributmodus ($D031 Bit 5): die IDE-Abbildung blendet die Ein-/Ausgabe aus, darum in der Standardabbildung
kvic:   jsr kdefault
        lda #$00
        sta $d020
        sta $d021
        lda $d031
        ora #$20
        sta $d031
        jmp kide
kc_t:   .word 0
kn_l:   .byte 0
kname:  .fill 28, 0
; knmir: NMI-Einsprung ueber den RAM-Vektor $FFFA (Programme, die das KERNAL ausblenden, z. B. $01 = $35; ide_nmivec setzt den Vektor):
; legt wie das KERNAL A, X, Y, Z, B ab (gleicher Rahmen wie bei ktrap) und springt zu knmi
knmir:  pha
        phx
        phy
        phz
        tba
        pha
        jmp knmi
kc_a:   .byte 0
kc_x:   .byte 0
kc_y:   .byte 0
kc_z:   .byte 0
kc_p:   .byte 0
kb_b:   .byte 0
kb_k:   .byte 0
kr_b:   .byte 0
kr_t:   .word 0
kr_sp:  .byte 0
kr_trap: .byte 0
.endpseudopc
bridge_end:
BR_LEN = bridge_end - bridge_src

; Fallenhandler (Bank 0, $1380: freier Bereich zwischen den Assemblerpuffern); der BRK-Vektor ($0316) des KERNAL ruft ktrap, nachdem
; es B, Z, Y, X, A auf den Stapel gelegt hat (Rahmen ab SP+1: B, Z, Y, X, A, P, PCL, PCH). ktrap schaltet auf die IDE-Abbildung und
; ruft dbg_trap (Bank 4) mit dem noch tiefen Stapel des Testprogramms; kgo geht den umgekehrten Weg (dbg_resume ruft es).
bridge2_src:
.pseudopc DBGR
ktrap:  tsx
        stx kt_sp
        tba
        sta kt_b
        lda #$00
        sta kt_nmi
        tab
        jsr kide
        jmp ktr_go
kgo:    jsr kdefault
        lda $dd0d                   ; waehrend des Anhaltens aufgelaufene CIA-2-NMI quittieren (sonst kommt keine neue Flanke)
        ldx kg_sp
        txs
        ldz kt_z
        ldy kt_y
        lda kt_b
        tab
        ldx kt_x
        lda kt_a
        rti
; kvec_set / kvec_rst: BRK-Vektor ($0316) und NMI-Vektor ($0318) des KERNAL auf ktrap/knmi setzen und zurueckstellen
kvec_set:
        ldx #$03
kv_s:   lda $0316,x
        sta kv_sv,x
        lda kv_new,x
        sta $0316,x
        dex
        bpl kv_s
        rts
kvec_rst:
        ldx #$03
kv_r:   lda kv_sv,x
        sta $0316,x
        dex
        bpl kv_r
        rts
kv_new: .word ktrap, knmi
; knmi: Notfalltaste (RESTORE = NMI) oder NMI-Quelle: wie ktrap, aber PC ist die Stelle, an der das Programm unterbrochen wurde
knmi:   tsx
        stx kt_sp
        lda $dd0d                   ; CIA-2-NMI quittieren (die RESTORE-Taste braucht das nicht)
        tba
        sta kt_b
        lda #$00
        tab
        lda #$01
        sta kt_nmi
        jsr kide
ktr_go: lda ov_ok                   ; Debugger-Overlay geladen? Sonst nur abbrechen (kr_trap = 2, krun kehrt zurueck)
        beq ktr_ab
        jmp OV_TRAP                 ; Overlay VC65D: Sprungtabelle bei $E000 (siehe src/debug/overlay.asm)
ktr_ab: ldx kr_sp
        txs
        lda #$02
        sta kr_trap
        jmp kr_after
.endpseudopc
bridge2_end:

; Variablen der Falle (Bank 0, $12E0: freier Bereich hinter curgstk)
bridge3_src:
.pseudopc VARR
kt_nmi: .byte 0
kt_sp:  .byte 0
kt_b:   .byte 0
kt_a:   .byte 0
kt_x:   .byte 0
kt_y:   .byte 0
kt_z:   .byte 0
kt_p:   .byte 0
kt_pc:  .word 0
kg_sp:  .byte 0
kv_sv:  .fill 4, 0
.endpseudopc
bridge3_end:
BR3_LEN = bridge3_end - bridge3_src
BR2_LEN = bridge2_end - bridge2_src
