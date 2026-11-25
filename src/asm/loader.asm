; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; loader.asm - Dateilader (Etappe N6, erste Stufe): holt eine Datei, die in der Dateitabelle (inc.asm) fehlt, ueber die
; KERNAL-Dateiroutinen vom Laufwerk lddev (Vorgabe 8: SD-Karte oder eingelegtes D81) und haengt sie an die Tabelle an.
; Aktiv, wenn ldon <> 0 (der Aufrufer setzt es). Es gibt nur den Dateinamen ohne Ordner (letzter Teil des Pfads,
; in Grossbuchstaben): Ordner und lange Namen der SD-Karte folgen mit dem Hyppo-Direktzugriff. Der Eintrag erhaelt den
; vollen aufgeloesten Namen (inpath2). Der Lader schaltet die Basisseite B fuer die KERNAL-Aufrufe auf 0 und danach
; zurueck; der Aufrufer sperrt Interrupts (sei) oder hat sie aus.
;
; Rolle im Assembler:
;   Der Assembler kennt keine Dateien, er sucht .include/#include/.incbin-Namen nur in einer Dateitabelle im Attic-RAM
;   (siehe inc.asm). fs_resolve (inc.asm) ruft ld_load, wenn der Name dort fehlt und ldon <> 0 ist. ld_load liest die Datei
;   in einem Zug vom Laufwerk und haengt sie als neuen Eintrag ans Tabellenende; danach findet fs_find sie wie jede andere.
;   Wer die Tabelle vorab fuellt (Testwerkzeug tools/asmtest.py), laesst ldon = 0; die IDE (ide.asm) setzt lddev, ldsdev
;   und ldon = 1 vor jedem Aufruf von asm_run.
;
; Dateitabelle (Attic $0820_0000, 32-Bit-Zeiger FSB3:FSB2:hi:lo = $08:$20:$00:$00), Eintrag fuer Eintrag:
;     Byte 0          Namenslaenge n (0 = Tabellenende)
;     Byte 1..n       Name (aufgeloester Pfad, ohne Endmarke)
;     n+1..n+4        Dateilaenge, 32 Bit, niederwertiges Byte zuerst
;     danach          Inhalt (Laenge Byte), danach ein 0-Byte (Dateiende-Marke)
;   Der naechste Eintrag beginnt direkt hinter dem 0-Byte; sein Laengenbyte 0 ist zugleich das Tabellenende.
;   Invariante: Der Lader schreibt den Eintragskopf erst NACH dem vollstaendigen Lesen (ll_entry). Bei einem Fehler bleibt
;   darum das Tabellenende (Laengenbyte 0 bei fsw) unberuehrt; die bis dahin hinter fsw geschriebenen Daten sind harmlos.
;
; Speicher/Register:
;   - Zeiger P6 und P7 (Zeropage, zp.asm) sind 32-Bit-Zeiger fuer [zp],z in den Attic; Z-Register ist dabei fast immer 0.
;   - Variablen am Dateiende (ldb ... ldname); der Lesepuffer ldbuf liegt bei $1D00 (frei: $1800-$1EFF, hinter fnames).
;   - Das KERNAL rechnet mit der Zeropage $00xx, der Assembler aber mit der Basisseite B (Register B des 45GS02, "tab"/"tba").
;     Deshalb wird B vor jedem KERNAL-Aufruf auf 0 gestellt (Wert in ldb gemerkt) und danach wieder hergestellt. Zwischen
;     den KERNAL-Aufrufen (Schreiben in den Attic) gilt wieder das urspruengliche B, denn P6/P7 liegen in der Assembler-Zeropage.
;   - In der IDE sind KSETNAM usw. Sprungstuecke der Bruecke (boot.asm): sie schalten die Speicherabbildung fuer das KERNAL
;     um und kopieren den Namen nach Bank 0 (hoechstens 28 Zeichen; laengere Namen werden dort abgeschnitten).
; =====================================================================================================================
.ifndef IDE_BUILD                    ; in der IDE sind es Sprungstuecke der Bruecke (boot.asm)
KSETNAM = $ffbd                     ; sonst (Testwerkzeug) die KERNAL-Sprungtabelle direkt: Name setzen
KSETLFS = $ffba                     ; logische Datei, Geraet, Sekundaeradresse setzen
KOPEN   = $ffc0                     ; Datei oeffnen
KCLOSE  = $ffc3                     ; Datei schliessen
KCHKIN  = $ffc6                     ; Eingabekanal setzen
KCHRIN  = $ffcf                     ; ein Byte lesen
KCLRCHN = $ffcc                     ; Kanaele zuruecksetzen
KREADST = $ffb7                     ; Statusbyte (ST) lesen
.endif

; ld_end: fsw = Stelle des Tabellenendes (Namenslaenge 0)
; Eingabe: keine (Tabelle bei FSB3:FSB2:0:0). Ausgabe: fsw (32 Bit) = Adresse des Laengenbytes 0 hinter dem letzten Eintrag.
; Aendert A, X, Z, ftn, ifl, P7; Flags undefiniert.
ld_end: lda #$00                    ; P7 = Tabellenanfang $0820_0000 (little endian in P7..P7+3)
        sta P7
        sta P7 + 1
        lda #FSB2
        sta P7 + 2
        lda #FSB3
        sta P7 + 3
le_l:   ldz #$00
        lda [P7],z                  ; Namenslaenge des Eintrags bei P7
        beq le_d                    ; 0 = Tabellenende erreicht
        sta ftn
        ldz ftn                     ; naechster Eintrag: ftn + 1 + Name ... (Laenge steht hinter dem Namen)
        inz                         ; Z = 1 + Namenslaenge = Versatz der 4 Laengenbytes
        ldx #$00
le_b:   lda [P7],z                  ; Dateilaenge (4 Byte) nach ifl holen
        sta ifl,x
        inz
        inx
        cpx #$04
        bne le_b
        lda ftn                     ; P7 += ftn + 6 (Laengenbyte 1 + Name + 4 Laengenbytes + Endmarke 1) ...
        clc
        adc #$06
        clc
        adc P7
        sta P7
        bcc le_c
        inc P7 + 1                  ; Uebertrag in die oberen Bytes des 32-Bit-Zeigers
        bne le_c
        inc P7 + 2
        bne le_c
        inc P7 + 3
le_c:   clc                         ; ... und P7 += Dateilaenge (32 Bit) -> Anfang des naechsten Eintrags
        lda P7
        adc ifl
        sta P7
        lda P7 + 1
        adc ifl + 1
        sta P7 + 1
        lda P7 + 2
        adc ifl + 2
        sta P7 + 2
        lda P7 + 3
        adc ifl + 3
        sta P7 + 3
        jmp le_l
le_d:   ldx #$03                    ; Ergebnis P7 -> fsw (4 Byte)
le_e:   lda P7,x
        sta fsw,x
        dex
        bpl le_e
        rts

; ld_load: inpath2 (ip2len) vom Laufwerk laden und in die Tabelle haengen. Carry geloescht = geladen
; Eingabe: inpath2/ip2len = aufgeloester Name; inlib = 0 Projektdatei, <> 0 Systemdatei (Name "sys/ordner/name.ext").
; Ausgabe: Carry geloescht = Eintrag angelegt (danach findet fs_find ihn); Carry gesetzt = Fehler (Datei fehlt, Geraet fehlt,
;          Lesefehler), Tabelle unveraendert. Aendert alle Register; B wird am Ende wieder auf den Ausgangswert gesetzt.
; Ablauf: 1. Tabellenende suchen  2. KERNAL-Dateinamen (ldname/ldnl) bilden  3. Zielzeiger ldp = hinter den spaeteren Kopf
;         4. Datei in 256-Byte-Stuecken lesen (ldbuf) und jeweils in den Attic kopieren  5. Eintragskopf schreiben (ll_entry).
ld_load:
        jsr ld_end
        ldx ip2len                  ; Dateiname = letzter Teil, Grossbuchstaben
        stx ldi
ll_b:   cpx #$00                    ; rueckwaerts bis hinter das letzte "/" (oder bis zum Anfang)
        beq ll_b2
        dex
        lda inpath2,x
        cmp #$2f
        bne ll_b
        inx                         ; X = Index des ersten Namenszeichens
        jmp ll_b3
ll_b2:  ldx #$00                    ; kein "/" im Pfad: der ganze Pfad ist der Name
ll_b3:  ldy #$00                    ; Y = Schreibindex in ldname
        lda inlib
        beq lr_ll_c                 ; Projektdatei: nur der Dateiname
        stx ldi                     ; Systemdatei <ordner/name.ext> -> "ORD.NAME" (3 Zeichen des Ordners, ohne Endung): flach auf der Systemdisk
        dex                         ; X zeigt auf das / vor dem Namen
ll_pd:  txa                         ; rueckwaerts zum "/" davor (Ordneranfang) oder zum Pfadanfang
        beq ll_d1
        dex
        lda inpath2,x
        cmp #$2f
        bne ll_pd
        inx                         ; X = erstes Zeichen des Ordnernamens
ll_d1:  ldy #$00
ll_d2:  cpy #$03                    ; hoechstens 3 Zeichen des Ordnernamens (Systemdisk-Namen sind kurz und flach)
        beq ll_d3
        lda inpath2,x
        cmp #$2f
        beq ll_d3                   ; Ordnername kuerzer als 3 Zeichen
        cmp #$61                    ; Kleinbuchstaben a-z ($61-$7a) in Grossbuchstaben wandeln (Bit 5 loeschen)
        bcc ll_d4
        cmp #$7b
        bcs ll_d4
        and #$df
ll_d4:  sta ldname,y
        inx
        iny
        bne ll_d2                   ; (Y wird nie 0: Sprung faktisch unbedingt)
ll_d3:  lda #$2e                    ; "." zwischen Ordnerkuerzel und Name
        sta ldname,y
        iny
        ldx ldi                     ; ab hier den eigentlichen Dateinamen (Anfang in ldi) anhaengen
ll_d5:  cpx ip2len
        beq lr_ll_cd
        lda inpath2,x
        cmp #$2e
        beq lr_ll_cd                ; Endung weglassen
        cmp #$61
        bcc ll_d6
        cmp #$7b
        bcs ll_d6
        and #$df
ll_d6:  sta ldname,y
        inx
        iny
        cpy #$20                    ; Puffer ldname hat 32 Byte
        bne ll_d5
        beq lr_ll_cd
lr_ll_c:   cpx ip2len               ; Projektdatei: Name ab X bis Pfadende kopieren (Grossbuchstaben)
        beq lr_ll_cd
        lda inpath2,x
        cmp #$61
        bcc ll_n
        cmp #$7b
        bcs ll_n
        and #$df
ll_n:   sta ldname,y
        inx
        iny
        cpy #$20
        bne lr_ll_c
lr_ll_cd:  sty ldnl                 ; Laenge des KERNAL-Dateinamens
        ldx #$03                    ; Ziel der Daten = fsw + 1 + Namenslaenge + 4
        lda ip2len                  ; (Anfang + 5 + Pfadlaenge: hier landet der Inhalt, der Kopf folgt in ll_entry)
        clc
        adc #$05
        clc
        adc fsw
        sta ldp
        lda fsw + 1
        adc #$00
        sta ldp + 1
        lda fsw + 2
        adc #$00
        sta ldp + 2
        lda fsw + 3
        adc #$00
        sta ldp + 3
        lda #$00                    ; Bytezaehler (32 Bit) = spaetere Dateilaenge
        sta ldcnt
        sta ldcnt + 1
        sta ldcnt + 2
        sta ldcnt + 3
        tba                         ; B merken, KERNAL braucht die Basisseite 0
        sta ldb
        lda #$00
        tab
        lda ldnl                    ; Datenkanal oeffnen
        ldx #<ldname
        ldy #>ldname
        jsr KSETNAM                 ; A = Namenslaenge, X/Y = Adresse des Namens
        lda #$02                    ; (wird gleich ueberschrieben)
        ldx lddev
        lda inlib
        beq ll_dv
        ldx ldsdev                  ; Systemdatei: Systemdisk
ll_dv:  lda #$02                    ; logische Dateinummer 2
        ldy #$02                    ; Sekundaeradresse 2: normales Lesen einer Programm-/Sequentialdatei
        jsr KSETLFS                 ; A = Dateinummer, X = Geraet, Y = Sekundaeradresse
        jsr KOPEN
        bcs ll_fail0                ; Carry gesetzt = OPEN-Fehler
        ldx #$02
        jsr KCHKIN                  ; Eingabe von Datei 2
ll_rd:  ldx #$00                    ; bis zu 256 Byte in den Puffer lesen
        stx ldeof
ll_r1:  jsr KCHRIN
        sta ldbuf,x
        inx
        jsr KREADST                 ; Status nach jedem Byte pruefen
        sta ldst
        and #$3f                    ; Fehlerbits (Datei nicht gefunden: $42, Geraet fehlt: $80)
        bne ll_fail0                ; (die Maske blendet Bit 6 = EOF und Bit 7 aus; ein fehlendes Geraet meldet schon KOPEN per Carry)
        lda ldst
        and #$40                    ; Bit 6 = EOF: das eben gelesene Byte war das letzte
        beq ll_r2
        lda #$01
        sta ldeof
        jmp ll_r3
ll_r2:  cpx #$00                    ; X ist nach 256 Bytes auf 0 umgelaufen: Puffer voll
        bne ll_r1
ll_r3:  stx ldn                     ; Anzahl im Puffer (0 = 256 bei vollem Puffer ohne Ende)
        jsr KCLRCHN                 ; Kanal freigeben, bevor in den Attic geschrieben wird
        lda ldb                     ; Basisseite zurueck, Puffer in den Attic schreiben
        tab
        lda ldp                     ; P6 = aktuelle Schreibstelle im Attic
        sta P6
        lda ldp + 1
        sta P6 + 1
        lda ldp + 2
        sta P6 + 2
        lda ldp + 3
        sta P6 + 3
        ldx #$00                    ; X = Leseindex in ldbuf
        lda ldn
        bne ll_w0
        lda #$00                    ; voller Puffer (x ist umgelaufen): 256 Byte
        sta ldm
        lda #$01
        sta ldm + 1
        jmp ll_w2
ll_w0:  sta ldm                     ; ldm = 16-Bit-Restzahl der zu kopierenden Bytes
        lda #$00
        sta ldm + 1
        jmp ll_w2
ll_w1:  lda #$00                    ; (nicht angesprungen: Rest von frueher)
        sta ldm
        sta ldm + 1
ll_w2:  lda ldm
        ora ldm + 1
        beq ll_wd                   ; nichts (mehr) zu kopieren
ll_w3:  lda ldbuf,x                 ; ein Byte: ldbuf[X] -> [P6]
        ldz #$00
        sta [P6],z
        inc P6                      ; P6 um 1 weiter (32-Bit-Zaehler)
        bne ll_w4
        inc P6 + 1
        bne ll_w4
        inc P6 + 2
        bne ll_w4
        inc P6 + 3
ll_w4:  inx
        inc ldcnt                   ; Dateilaenge mitzaehlen (32 Bit)
        bne ll_w5
        inc ldcnt + 1
        bne ll_w5
        inc ldcnt + 2
        bne ll_w5
        inc ldcnt + 3
ll_w5:  lda ldm                     ; ldm -= 1 (16 Bit)
        bne ll_w6
        dec ldm + 1
ll_w6:  dec ldm
        lda ldm
        ora ldm + 1
        bne ll_w3
ll_wd:  ldx #$03                    ; neue Schreibstelle P6 -> ldp merken
ll_wp:  lda P6,x
        sta ldp,x
        dex
        bpl ll_wp
        lda ldeof
        bne lr_ll_done              ; Dateiende: fertig
        lda #$00                    ; naechster Puffer: wieder Basisseite 0
        tab
        ldx #$02
        jsr KCHKIN                  ; Kanal wieder setzen (wurde mit KCLRCHN freigegeben)
        jmp ll_rd
lr_ll_done:
        lda #$00                    ; Erfolg: Datei schliessen (B fuer das KERNAL wieder 0), B danach zurueck
        tab
        lda #$02
        jsr KCLOSE
        lda ldb
        tab
        jmp ll_entry                ; Carry loescht und rts erledigt ll_entry
ll_fail0:                           ; Fehlerausgang: Kanal und Datei freigeben, B zurueck, Carry gesetzt
        jsr KCLRCHN
        lda #$02
        jsr KCLOSE
        lda ldb
        tab
        sec
        rts
; Eintrag schreiben: Namenslaenge, Name, Laenge, (Daten stehen schon), 0, 0
; Eingabe: fsw (Eintragsstelle), ip2len/inpath2, ldcnt (Laenge), ldp (Stelle hinter den Daten). Ausgabe: Carry geloescht.
ll_entry:
        lda fsw                     ; P6 = Eintragsanfang
        sta P6
        lda fsw + 1
        sta P6 + 1
        lda fsw + 2
        sta P6 + 2
        lda fsw + 3
        sta P6 + 3
        ldz #$00
        lda ip2len                  ; Byte 0: Namenslaenge
        sta [P6],z
        inz
        ldx #$00
ll_e1:  cpx ip2len                  ; Name: voller aufgeloester Pfad (nicht der gekuerzte KERNAL-Name)
        beq ll_e2
        lda inpath2,x
        sta [P6],z
        inz
        inx
        jmp ll_e1
ll_e2:  ldx #$00
ll_e3:  lda ldcnt,x                 ; Dateilaenge, 4 Byte, niederwertiges zuerst
        sta [P6],z
        inz
        inx
        cpx #$04
        bne ll_e3
        lda ldp                     ; hinter den Daten: 0 (Dateiende) und 0 (Tabellenende)
        sta P6
        lda ldp + 1
        sta P6 + 1
        lda ldp + 2
        sta P6 + 2
        lda ldp + 3
        sta P6 + 3
        ldz #$00
        lda #$00
        sta [P6],z
        inz
        sta [P6],z
        clc
        rts

lddev:  .byte 8                     ; Projektlaufwerk
ldsdev: .byte 8                     ; Systemdisk (Bibliotheken <mega65/...>)
ldon:   .byte 0                     ; <> 0: Lader aktiv (fehlende Dateien werden vom Laufwerk geholt)
ldb:    .byte 0                     ; gemerkte Basisseite B des Aufrufers
ldi:    .byte 0                     ; Index des Dateinamenanfangs in inpath2
ldnl:   .byte 0                     ; Laenge des KERNAL-Namens in ldname
ldst:   .byte 0                     ; letztes KERNAL-Statusbyte
ldeof:  .byte 0                     ; 1 = Dateiende im aktuellen Puffer erreicht
ldn:    .byte 0                     ; Bytes im Puffer (0 = 256)
ldm:    .word 0                     ; Restzaehler beim Kopieren Puffer -> Attic
fsw:    .fill 4, 0                  ; Tabellenende (32-Bit-Adresse im Attic), von ld_end gesetzt
ldp:    .fill 4, 0                  ; aktuelle Schreibstelle fuer die Dateidaten (32 Bit)
ldcnt:  .fill 4, 0                  ; bisher gelesene Bytes = Dateilaenge (32 Bit)
ldname: .fill 32, 0                 ; Dateiname fuer das KERNAL (Grossbuchstaben, ggf. "ORD.NAME")
ldbuf   = $1d00                     ; 256 Byte im freien Bereich $1800-$1EFF
