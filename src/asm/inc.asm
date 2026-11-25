; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; inc.asm - .include, #include und .incbin ueber eine Dateitabelle im Attic ($0820_0000). Die Tabelle stellt der
; Aufrufer (Testwerkzeug oder der Dateilader loader.asm der Entwicklungsumgebung) bereit: Eintrag = Namenslaenge (1), Name
; (Pfad mit /, relativ zum Hauptprogramm), Laenge (4, tief zuerst), Inhalt, 0-Byte. Ende der Tabelle: Namenslaenge 0.
; Gesucht wird erst im Ordner der einbindenden Datei, dann unveraendert; `<pfad>` sucht `sys/pfad`.
; Eine eingebundene Datei ist wie ein Makro ein Rahmen auf dem Quelltext-Stapel (FT_INC): SRC zeigt in den Dateiinhalt,
; an dessen Ende (Zeichen 0) geht es hinter der .include-Zeile weiter. `as name` oeffnet dazu einen Scope.
;
; Rolle im Assembler:
;   asm.asm (as_pass) beginnt jeden Durchlauf mit chips_enter (bindet sys/mega65/chips.asm ein) und ruft ueber die
;   Direktiventabelle d_include/d_hinclude/d_incbin auf; am Quelltextende eines eingebundenen Rahmens ruft asm.asm (eos1)
;   inc_return. Die Vorabsuche nach Makros (stage2.asm, ms_inc) benutzt fs_resolve ebenfalls. Die Datei selbst kommt aus der
;   Dateitabelle; fehlt sie, holt loader.asm (ld_load) sie vom Laufwerk und haengt sie an die Tabelle (nur wenn ldon <> 0).
;
; Namensaufloesung (fs_resolve), Reihenfolge fuer "name": 1. Ordner der einbindenden Datei + name, 2. name unveraendert
;   (jeweils erst in der Tabelle, bei aktivem Lader auch vom Laufwerk); <name> sucht stets "sys/name" (Systemdisk, inlib = 1).
;   Der Pfad wird dazu aus Teilen zusammengesetzt (path_build) und normalisiert (path_norm: "." und "x/.." fallen weg).
;
; Datenstrukturen:
;   Dateitabelle (Attic $0820_0000, FSB3:FSB2:0:0), Format siehe oben und loader.asm; 32-Bit-Zeiger P7 laeuft ueber sie.
;   Dateiverzeichnis des aktuellen Durchlaufs (hoechstens 16 Dateien, Nr. 0 = Hauptprogramm, wird in i_pass neu aufgebaut):
;     filebase[n] (4 Byte) = Attic-Adresse des Inhalts der Datei n (damit die Fehlerstelle SRC einer Datei zugeordnet wird),
;     fnames[n]   (64 Byte, siehe fn_ptr) = Name der Datei n (0-terminiert); curfile = Nummer der Datei, die gerade gelesen wird.
;   onelist: bis zu 16 Eintraege zu je 8 Byte fuer #include (nur einmal): +0..+2 Attic-Adresse (niederwertige 3 Byte),
;     +3 unbenutzt, +4 hasas (Scope ja/nein), +5 Laenge des Scope-Namens; +6/+7 unbenutzt.
;   Rahmen auf dem Quelltext-Stapel (stage2.asm, fr_push): F_TYPE = FT_INC, F_FLAGS = hasas (Bit 0: Scope wurde geoeffnet),
;     F_STARTED = Nummer der einbindenden Datei, F_A = Rueckkehrstelle (SRC hinter der .include-Zeile), F_IFSP = .if-Tiefe.
;
; Speicher/Zeropage: Arbeitspuffer inname/inpath/inpath2/filebase/onelist/fnames im freien Bereich $1200-$1EFF von Bank 0
;   (Adressen am Dateiende); Zeropage: P6/P7 (32-Bit-Zeiger), MP (16-Bit-Zeiger auf fnames[n]), TMP, SRC, FP (Rahmenzeiger),
;   VAL (Ausdruckswert, .incbin), NAMEBUF/NAMELEN, LNAME/LLEN (Scope-Name merken), IFSP/ISKIP. Das Z-Register dient als
;   Byteindex fuer [P7],z / [P6],z / [FP],z (45GS02: 32-Bit-Zeiger mit Z-Index).
; Konvention: fs_find und fs_resolve melden Erfolg mit geloeschtem Carry (gefunden), inc_media meldet mit Carry gesetzt
;   "ist Medien-Endung". Alle Pfade sind hoechstens 62 Zeichen lang (Puffer 64 Byte, Grenze $3e).
; =====================================================================================================================
; Lage der Dateitabelle im Attic: $0820_0000 = Bytes 0, 0, FSB2, FSB3 (little endian) des 32-Bit-Zeigers P7
FSB2     = $20
FSB3     = $08
FT_INC   = 7                        ; Rahmenart "eingebundene Datei" (neben FT_MAC = 1, FT_COND = 3, FT_RANGE = 4 in stage2.asm)
DID_INCLUDE = 54                    ; Direktivenkennungen (Index in der Direktiventabelle von asm.asm)
DID_INCBIN  = 55
ERR_E212 = $14                      ; Datei nicht gefunden (.include/.incbin)
ERR_E900 = $17                      ; Makro mit mehr Parametern als VC65 verarbeitet (MAXPAR; vcc kennt keine Grenze)
ERR_E301 = $18                      ; Segment verlaesst seinen Bereich (.segment, wie vcc E301)
ERR_E300 = $16                      ; Code oder Marke vor dem ersten .org (wie vcc E300)
ERR_E219 = $15                      ; Medien-Include (VintageCoder D5): in VC65 noch nicht unterstuetzt

; i_pass: Dateiverzeichnis zu Beginn der Vorabsuche und jedes Durchlaufs neu aufbauen: nur die Hauptdatei (Nr. 0, Name leer,
; Inhalt ab SRCBASE), keine #include-Merker. Eingabe: SRCBASE. Aendert A, X; Flags undefiniert.
i_pass: lda #$01
        sta nfiles                  ; 1 Datei bekannt (die Hauptdatei)
        lda #$00
        sta curfile
        sta onecnt                  ; keine #include-Merker
        sta fnames                  ; Name der Hauptdatei leer: kein Ordnerpraefix fuer relative Includes
        ldx #$03
ip1:    lda SRCBASE,x               ; filebase[0] = SRCBASE (32 Bit)
        sta filebase,x
        dex
        bpl ip1
        rts

; inc_getname: Dateiname hinter der Direktive: "name" oder <name> -> inname/inlen, inlib
; Eingabe: SRC hinter der Direktive. Ausgabe: inname/inlen = Name (hoechstens 62 Zeichen), inlib = 0 bei "name", 1 bei <name>;
; SRC steht hinter dem schliessenden Zeichen. Fehler: ERR_SYNTAX (kein Anfangszeichen, Zeilenende/Quelltextende vor dem
; Schlusszeichen, Name zu lang); der Abbruch laeuft ueber as_error. Aendert A, X, iclose.
inc_getname:
        jsr skipws
        jsr src_peek
        cmp #$22
        beq ig_q
        cmp #$3c
        beq ig_a
        lda #ERR_SYNTAX
        jmp as_error
ig_q:   lda #$00                    ; "name": Projektdatei, Schlusszeichen "
        sta inlib
        lda #$22
        bne ig_go
ig_a:   lda #$01                    ; <name>: Systemdatei unter sys/, Schlusszeichen >
        sta inlib
        lda #$3e
ig_go:  sta iclose                  ; Schlusszeichen merken
        jsr src_adv                 ; Anfangszeichen verbrauchen
        ldx #$00
ig_l:   jsr src_peek
        beq ig_bad                  ; Quelltextende
        cmp #$0a
        beq ig_bad                  ; Zeilenende vor dem Schlusszeichen
        cmp iclose
        beq ig_d
        cpx #$3e                    ; hoechstens 62 Zeichen
        bcs ig_bad
        sta inname,x
        inx
        jsr src_adv
        jmp ig_l
ig_bad: lda #ERR_SYNTAX
        jmp as_error
ig_d:   stx inlen
        jmp src_adv                 ; Schlusszeichen verbrauchen (kehrt zum Aufrufer zurueck)

; ip_add: A anhaengen an inpath (iplen)
; Eingabe: A = Zeichen. Ueber 62 Zeichen hinaus wird still verworfen. Aendert X, iplen (A bleibt).
ip_add: ldx iplen
        cpx #$3e
        bcs ipa1
        sta inpath,x
        inc iplen
ipa1:   rts

; path_build: Voranstellen `pre` Zeichen aus fnames[curfile] (0 = keine) bzw. `sys/` und Namen, dann normalisieren
; Eingabe: inlib, pbpre (Zahl der Zeichen des Ordnerpraefixes der einbindenden Datei, 0 = keiner), inname/inlen.
; Ausgabe: inpath2/ip2len = normalisierter Pfad (path_norm). Aendert A, X, Y, iplen, pbx, pbc, MP und was path_norm aendert.
; Bei inlib <> 0 wird immer "sys/" vorangestellt, pbpre bleibt dann unbeachtet.
path_build:
        lda #$00
        sta iplen
        lda inlib
        beq pb_f
        ldy #$00
pb_s:   lda sysname,y               ; "sys/" Zeichen fuer Zeichen anhaengen
        beq pb_n
        sty pbx                     ; Index in pbx merken (ip_add aendert X; Y bleibt dort zwar erhalten, die Sicherung ist vorsorglich)
        jsr ip_add
        ldy pbx
        iny
        jmp pb_s
pb_f:   lda pbpre                   ; Projektdatei: Ordnerpraefix der einbindenden Datei voranstellen
        beq pb_n
        sta pbc
        ldx #$00
pb_p:   cpx pbc
        beq pb_n
        stx pbx
        jsr fn_char                 ; A = fnames[curfile][X]
        jsr ip_add
        ldx pbx
        inx
        jmp pb_p
pb_n:   ldx #$00                    ; dann den Namen aus der Direktive anhaengen
pb_c:   cpx inlen
        beq pb_e
        stx pbx
        lda inname,x
        jsr ip_add
        ldx pbx
        inx
        jmp pb_c
pb_e:   jmp path_norm               ; inpath -> inpath2 (kehrt zum Aufrufer zurueck)

sysname: .byte "sys/", 0
pbx:    .byte 0                     ; Schleifenindex von path_build (ueber ip_add gerettet)
pbc:    .byte 0                     ; Laenge des Ordnerpraefixes in path_build

; fn_char: A = Zeichen X des Namens der aktuellen Datei
; Eingabe: X = Index. Ausgabe: A = Zeichen (Z gesetzt am Namensende 0), Y = X; X bleibt erhalten. fn_ptr setzt MP.
fn_char:
        lda curfile
        jsr fn_ptr
        txa
        tay                         ; Y = X als Index fuer (MP),y
        lda (MP),y
        rts

; fn_ptr: A = Dateinummer -> MP = fnames + Nummer * 64
; Eingabe: A = Dateinummer 0..15. Ausgabe: MP = Zeiger auf fnames[A], A = Low-Byte von MP (Z-Flag passend); X, Y bleiben.
; Hinweis: das Carry vor "adc #>fnames" ist das zuletzt aus A herausgeschobene Bit (Bit 1 der Nummer), kein Uebertrag der
; vorangehenden Addition (fnames hat Low-Byte 0). Dateien mit gesetztem Bit 1 liegen dadurch 256 Byte weiter oben; die Plaetze
; bleiben dennoch paarweise getrennt (belegt: $1800-$1CFF). Lesen und Schreiben benutzen immer fn_ptr, daher bleibt es harmlos.
fn_ptr: pha
        asl                         ; Nummer * 64: das Low-Byte ist (Nummer und 3) * 64
        asl
        asl
        asl
        asl
        asl
        clc
        adc #<fnames                ; (<fnames = 0)
        sta MP
        pla
        lsr                         ; High-Byte = Nummer / 4 + >fnames (+ Carry, siehe oben)
        lsr
        adc #>fnames                ; Uebertrag der niederwertigen Addition geht mit ein
        sta MP + 1
        lda MP
        rts

; path_norm: inpath (iplen) -> inpath2 (ip2len): "." weglassen, "x/.." wegkuerzen
; Eingabe: inpath/iplen (hoechstens 62 Zeichen). Ausgabe: inpath2/ip2len. Der Pfad wird segmentweise (Trenner "/") gelesen:
; leere Segmente und "." fallen weg, ".." entfernt das zuletzt uebernommene Segment (steht nichts davor, bleibt ".." stehen).
; Arbeitszellen: pnr = Leseposition, pns/pne = Anfang/Ende (exklusiv) des aktuellen Segments. Aendert A, X, Y.
path_norm:
        lda #$00
        sta ip2len
        sta pnr
pn_seg: lda pnr                     ; naechstes Segment; fertig, wenn alles gelesen ist
        cmp iplen
        bcs pn_end
        sta pns                     ; Segmentanfang
        tax
pn_f:   cpx iplen                   ; Segmentende suchen: naechstes "/" oder Pfadende
        beq pn_e
        lda inpath,x
        cmp #$2f
        beq pn_e
        inx
        jmp pn_f
pn_e:   stx pne                     ; Segmentende (Index von / oder Ende)
        inx                         ; naechster Anfang
        stx pnr
        lda pne
        sec
        sbc pns                     ; A = Segmentlaenge
        beq pn_seg                  ; leeres Segment
        cmp #$01
        bne pn_dd
        ldx pns
        lda inpath,x
        cmp #$2e
        beq pn_seg                  ; "."
pn_dd:  cmp #$02                    ; (nach dem Ein-Zeichen-Fall steht in A ein Zeichen statt der Laenge; es ist nie 2)
        bne pn_cp
        ldx pns
        lda inpath,x
        cmp #$2e
        bne pn_cp
        lda inpath + 1,x
        cmp #$2e
        bne pn_cp
        ldx ip2len                  ; "..": letztes Segment entfernen
        beq pn_cp                   ; nichts da, was man entfernen koennte: ".." wird wie ein Name uebernommen
        dex
pn_b:   cpx #$00                    ; rueckwaerts bis zum "/" vor dem letzten Segment (oder bis zum Anfang)
        beq pn_bz
        dex
        lda inpath2,x
        cmp #$2f
        bne pn_b
        inx
pn_bz:  stx ip2len
        jmp pn_seg
pn_cp:  lda ip2len                  ; Segment anhaengen (mit / davor, wenn schon etwas da ist)
        beq pn_c1
        tax
        lda #$2f
        sta inpath2,x
        inc ip2len
pn_c1:  ldx pns
pn_c2:  cpx pne                     ; Zeichen des Segments von inpath nach inpath2 kopieren
        beq pn_seg
        lda inpath,x
        ldy ip2len
        sta inpath2,y
        inc ip2len
        inx
        jmp pn_c2
pn_end: rts

; fs_find: inpath2 (ip2len) in der Dateitabelle suchen. Carry geloescht = gefunden: ifp = Inhalt, ifl = Laenge
; Die Tabelle wird linear durchsucht (P7 = aktueller Eintrag, 32-Bit-Zeiger, Z = Byteindex im Eintrag); verglichen wird
; exakt (gleiche Laenge, gleiche Zeichen, Gross-/Kleinschreibung zaehlt). Carry gesetzt = nicht gefunden.
; Aendert A, X, Z, P7, TMP, ftn und ifl (auch bei Misserfolg). ifp zeigt auf das erste Inhaltsbyte (hinter den 4 Laengenbytes).
fs_find:
        lda #$00                    ; P7 = Tabellenanfang $0820_0000
        sta P7
        sta P7 + 1
        lda #FSB2
        sta P7 + 2
        lda #FSB3
        sta P7 + 3
in_ff_l:   ldz #$00
        lda [P7],z                  ; Namenslaenge des Eintrags
        beq ff_no                   ; 0 = Tabellenende: nicht gefunden
        sta ftn
        cmp ip2len
        bne in_ff_n                 ; andere Laenge: naechster Eintrag
        inz
        ldx #$00
in_ff_c:   lda [P7],z               ; Name Zeichen fuer Zeichen vergleichen
        cmp inpath2,x
        bne in_ff_n
        inz
        inx
        cpx ip2len
        bne in_ff_c
        ldx #$00                    ; Laenge lesen
ff_r:   lda [P7],z
        sta ifl,x
        inz
        inx
        cpx #$04
        bne ff_r
        tza                         ; Inhalt = P7 + Z (Z steht jetzt hinter den 4 Laengenbytes)
        clc
        adc P7
        sta ifp
        lda P7 + 1
        adc #$00
        sta ifp + 1
        lda P7 + 2
        adc #$00
        sta ifp + 2
        lda P7 + 3
        adc #$00
        sta ifp + 3
        clc
        rts
in_ff_n:   ldz ftn                     ; naechster Eintrag: ftn + 1 + 4 + Laenge + 1
        inz
        ldx #$00
ff_a:   lda [P7],z                  ; Dateilaenge des uebersprungenen Eintrags (steht hinter dem Namen)
        sta ifl,x
        inz
        inx
        cpx #$04
        bne ff_a
        lda ftn                     ; P7 += ftn + 6 (Laengenbyte, Name, 4 Laengenbytes, Endmarke) ...
        clc
        adc #$06
        sta TMP
        lda #$00
        sta TMP + 1
        clc
        lda P7
        adc TMP
        sta P7
        lda P7 + 1
        adc TMP + 1
        sta P7 + 1
        lda P7 + 2
        adc #$00
        sta P7 + 2
        lda P7 + 3
        adc #$00
        sta P7 + 3
        clc                         ; ... und danach P7 += Dateilaenge (32 Bit)
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
        jmp in_ff_l
ff_no:  sec
        rts

; fs_resolve: inname -> ifp/ifl, inpath2 = aufgeloester Name. Carry gesetzt = nicht gefunden
; Eingabe: inname/inlen/inlib (von inc_getname), curfile (die einbindende Datei). Ausgabe: Carry geloescht = gefunden
; (ifp/ifl, inpath2 = Name in der Tabelle); Carry gesetzt = nicht gefunden (inpath2 = blanker Name bzw. sys/Name).
; Reihenfolge fuer "name" mit Ordnerpraefix: Tabelle relativ -> Laufwerk relativ -> Tabelle blank -> (nur ohne Praefix:
; Laufwerk blank). fr_pre merkt, ob es einen Ordnerpraefix gab. Aendert alle Register, pbpre, fr_pre, MP, P7, TMP und die
; Pfadpuffer. Bei inlib <> 0 darf pbpre veraltet sein: path_build ignoriert ihn dann (hoechstens ein doppelter Versuch).
fs_resolve:
        lda inlib
        bne fr_plain                ; <name>: kein Ordnerpraefix, direkt zu sys/name
        lda #$00                    ; Ordner der einbindenden Datei = Name bis zum letzten /
        sta pbpre
        ldx #$00
fr_d:   jsr fn_char
        beq fr_dn                   ; Namensende
        cmp #$2f
        bne fr_dx
        inx
        stx pbpre                   ; Praefixlaenge = Index des / + 1 (einschliesslich des /)
        dex
fr_dx:  inx
        cpx #$3e
        bcc fr_d
fr_dn:  lda pbpre
        beq fr_plain                ; kein Ordner: nur der blanke Name
        jsr path_build              ; Ordner + Name zuerst in der Tabelle suchen
        jsr fs_find
        bcc fr_ok
fr_plain:
        lda ldon                    ; nicht in der Tabelle: vom Laufwerk holen (nur wenn der Lader aktiv ist)
        beq fr_p2
        lda pbpre
        sta fr_pre
        beq fr_p1
        jsr path_build              ; zuerst unter dem relativen Namen anlegen
        jsr ld_load                 ; (loader.asm) Carry gesetzt = Laufwerk kennt die Datei nicht
        bcs fr_p2
        jsr fs_find
        bcc fr_ok
fr_p1:  lda #$00                    ; blanker Name (ohne Ordnerpraefix)
        sta pbpre
        jsr path_build
        jsr fs_find
        bcc fr_ok
        lda fr_pre
        bne fr_p2                   ; es gab einen Praefix: kein weiterer Plattenzugriff
        jsr ld_load
        bcs fr_p2
        jmp fs_find                 ; frisch geladen: Eintrag suchen, Carry meldet das Ergebnis
fr_p2:  lda #$00                    ; letzter Versuch: blanker Name nur in der Tabelle (Ergebnis = Carry von fs_find)
        sta pbpre
        jsr path_build
        jmp fs_find
fr_ok:  rts
fr_pre: .byte 0                     ; 1.. = beim Aufloesen gab es einen Ordnerpraefix (Laenge)

; ---- .include / #include
; Eingabe: SRC hinter der Direktive. Syntax: .include "name" [as scopename] bzw. <name>; #include dito, aber jede Datei
; (im selben Namensraum) nur einmal. Die Datei wird als Rahmen FT_INC auf den Quelltext-Stapel gelegt; die Zeilenschleife
; (al_line) liest danach aus dem Dateiinhalt. Fehler: ERR_SYNTAX, ERR_E219 (Medien-Endung), ERR_E212 (nicht gefunden).
d_hinclude:                         ; #include (nur einmal)
        lda #$01
        bne di_go
d_include:
        lda #$00
di_go:  sta incone                  ; 1 = nur einmal einbinden
        jsr inc_getname
        jsr inc_media
        bcc di_nm
        lda #ERR_E219               ; Medien-Endung: klare Meldung statt Datei-nicht-gefunden
        jmp as_error
di_nm:
        lda #$00
        sta hasas
        jsr skipws
        jsr at_eol
        beq di_nas                  ; Zeilenende: kein "as"
        jsr read_ident              ; as name
        lda NAMELEN
        cmp #$02
        bne di_syn
        lda NAMEBUF                 ; "as" ohne Beachtung der Grossschreibung
        ora #$20
        cmp #$61
        bne di_syn
        lda NAMEBUF + 1
        ora #$20
        cmp #$73
        bne di_syn
        jsr skipws
        jsr read_ident
        lda NAMELEN
        bne di_n1
di_syn: lda #ERR_SYNTAX
        jmp as_error
di_n1:  ldx #$1f                    ; Scope-Name nach LNAME/LLEN retten: NAMEBUF wird weiter unten wieder benutzt
di_n2:  lda NAMEBUF,x
        sta LNAME,x
        dex
        bpl di_n2
        lda NAMELEN
        sta LLEN
        lda #$01
        sta hasas
di_nas: jsr at_eol_chk              ; nichts mehr hinter der Direktive erlaubt
        jsr fs_resolve
        bcc di_found
        lda #ERR_E212
        jmp as_error
di_found:
        lda incone                  ; #include: dieselbe Datei im selben Namensraum nur einmal
        beq di_push
        ldx #$00                    ; onelist (onecnt Eintraege zu 8 Byte) nach derselben Datei durchsuchen
di_o:   cpx onecnt
        beq di_new
        txa
        asl
        asl
        asl
        tay                         ; Y = Eintragsindex * 8
        lda onelist,y               ; Attic-Adresse des Inhalts (niederwertige 3 Byte genuegen: Tabelle liegt in einem Bereich)
        cmp ifp
        bne di_on
        lda onelist + 1,y
        cmp ifp + 1
        bne di_on
        lda onelist + 2,y
        cmp ifp + 2
        bne di_on
        lda onelist + 4,y           ; gleicher Namensraum: beide ohne Scope oder beide mit Scope gleicher Namenslaenge
        cmp hasas
        bne di_on
        lda hasas
        beq di_skip
        lda onelist + 5,y
        cmp LLEN
        beq di_skip
di_on:  inx
        jmp di_o
di_skip:
        jmp al_line                 ; schon eingebunden
di_new: cpx #$10                    ; neue Datei in onelist merken (hoechstens 16; danach wird sie nur eingebunden)
        bcs di_push
        txa
        asl
        asl
        asl
        tay
        lda ifp
        sta onelist,y
        lda ifp + 1
        sta onelist + 1,y
        lda ifp + 2
        sta onelist + 2,y
        lda hasas
        sta onelist + 4,y
        lda LLEN
        sta onelist + 5,y
        inc onecnt
di_push:                            ; Einsprung auch von chips_enter: Rahmen anlegen und in die Datei wechseln
        jsr fr_push                 ; neuer, geloeschter Rahmen (FP), .if-Tiefe wird gemerkt
        lda #FT_INC
        ldz #F_TYPE
        sta [FP],z
        lda hasas
        ldz #F_FLAGS
        sta [FP],z                  ; Bit 0: ein Scope wurde fuer "as name" geoeffnet (inc_return schliesst ihn)
        lda curfile
        ldz #F_STARTED
        sta [FP],z                  ; Nummer der einbindenden Datei (kommt bei der Rueckkehr nach curfile zurueck)
        jsr cp_src_tmp              ; Rueckkehrstelle
        ldz #F_A
        jsr fr_stt                  ; [FP + F_A] = SRC (hinter der .include-Zeile)
        lda nfiles                  ; neue Datei anmelden (ab der 17. teilen sich alle den letzten Platz: nur die Zuordnung der Fehler leidet)
        cmp #$10
        bcc dix_a
        lda #$0f
dix_a:  sta curfile
        asl                         ; X = Dateinummer * 4: Index in filebase
        asl
        tax
        ldy #$00
di_b:   lda ifp,y                   ; filebase[curfile] = Inhaltsadresse (32 Bit)
        sta filebase,x
        inx
        iny
        cpy #$04
        bne di_b
        lda curfile
        jsr fn_ptr                  ; MP = fnames[curfile]
        ldy #$00
di_f1:  cpy ip2len                  ; aufgeloesten Namen eintragen (0-terminiert)
        beq di_f2
        lda inpath2,y
        sta (MP),y
        iny
        bne di_f1
di_f2:  lda #$00
        sta (MP),y
        lda nfiles
        cmp #$10
        bcs dix_b
        inc nfiles
dix_b:  lda hasas
        beq di_go2
        ldx #$1f                    ; "as name": Scope-Name zurueckholen und Scope oeffnen (stage2.asm)
di_s:   lda LNAME,x
        sta NAMEBUF,x
        dex
        bpl di_s
        lda LLEN
        sta NAMELEN
        jsr scope_push
di_go2: ldx #$03                    ; SRC = Dateiinhalt: die Zeilenschleife liest jetzt aus der eingebundenen Datei
di_g:   lda ifp,x
        sta SRC,x
        dex
        bpl di_g
        jmp al_line

; chips_enter: zu Beginn jedes Durchlaufs die Chipdatei sys/mega65/chips.asm (vic2.border usw.) einbinden, sofern sie in der Dateitabelle steht
; Wird von as_pass (asm.asm) statt eines direkten Sprungs nach al_line aufgerufen (springt selbst nach al_line bzw. di_push).
; Im ersten Durchlauf wird (bei aktivem Lader auch vom Laufwerk) gesucht; fehlt die Datei, merkt sich chipok das, und die
; spaeteren Durchlaeufe versuchen es nicht mehr. chipfl = 1, solange der Rahmen der Chipdatei offen ist.
chips_enter:
        lda PASS                    ; nur im ersten Durchlauf von der Platte suchen; ohne Fund spaeter nicht mehr
        cmp #$01
        beq ce_try
        lda chipok
        beq ce_no
ce_try: lda PASS
        cmp #$01
        bne ce_t2
        lda #$00
        sta chipok
ce_t2:  ldx #chipnl - chipnm - 1    ; Name "mega65/chips.asm" als <...>-Include vorbereiten (wie <mega65/chips.asm>)
ce_c:   lda chipnm,x
        sta inname,x
        dex
        bpl ce_c
        lda #chipnl - chipnm
        sta inlen
        lda #$01
        sta inlib
        lda #$00
        sta incone
        sta hasas
        sta chipfl
        jsr fs_resolve
        bcs ce_no
        lda #$01
        sta chipfl
        sta chipok
        jmp di_push                 ; Rahmen wie bei .include; die Rueckkehrstelle ist der Quelltextanfang (SRC)
ce_no:  jmp al_line
chipfl: .byte 0                     ; 1 = Rahmen der Chipdatei ist offen
chipok: .byte 0                     ; 1 = Chipdatei wurde gefunden (spaetere Durchlaeufe binden sie wieder ein)
chipnm: .byte "mega65/chips.asm"
chipnl:

; inc_return: Ende einer eingebundenen Datei (oberster Rahmen): hinter der .include-Zeile weiter
; Wird von asm.asm (eos1) aufgerufen, wenn das Quelltextende erreicht ist und der oberste Rahmen FT_INC ist; danach geht es
; dort mit al_line weiter. Stellt IFSP (offene .if-Ebenen der Datei fallen weg), curfile und SRC wieder her, schliesst einen
; "as name"-Scope und entfernt den Rahmen. Aendert alle Register, TMP.
inc_return:
        lda chipfl                  ; Ende der selbst eingebundenen Chipdatei: ihre Dateinummer wieder freigeben
        beq ir_nc
        lda #$00
        sta chipfl
        dec nfiles
ir_nc:  ldz #F_IFSP
        lda [FP],z
        sta IFSP
        ldz #F_STARTED
        lda [FP],z
        sta curfile
        ldz #F_FLAGS
        lda [FP],z
        pha                         ; Flags merken (Bit 0 = Scope offen)
        ldz #F_A
        jsr fr_ldt                  ; TMP = Rueckkehrstelle
        jsr cp_tmp_src              ; SRC = Rueckkehrstelle
        pla
        and #$01
        beq ir1
        jsr scope_pop               ; Scope von "as name" schliessen
ir1:    jsr if_skipflag             ; ISKIP aus der wiederhergestellten .if-Tiefe neu bestimmen
        jmp fr_pop

; ---- .incbin "datei" [, offset [, laenge]]
; Bindet die Rohbytes der Datei ein (emit_byte je Byte). Es entsteht kein Rahmen; die Datei wird nicht ausgewertet.
; Rechnung (32 Bit): ibp = Anfang + offset, ibn = min(laenge, Dateilaenge - offset). Fehler: ERR_E212 (nicht gefunden),
; ERR_E203 (offset hinter dem Dateiende; offset = Dateilaenge ergibt 0 Byte). Ruft zum Schluss d_end (Zeilenende pruefen).
d_incbin:
        jsr inc_getname
        jsr fs_resolve
        bcc ib1
        lda #ERR_E212
        jmp as_error
ib1:    ldx #$03                    ; ibp = Inhalt, ibn = Dateilaenge, iboff = 0
ib2:    lda ifp,x
        sta ibp,x
        lda ifl,x
        sta ibn,x
        lda #$00
        sta iboff,x
        dex
        bpl ib2
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne ib_go                   ; kein offset
        jsr src_adv
        jsr eval_val                ; offset -> VAL
        ldx #$03
ib3:    lda VAL,x
        sta iboff,x
        dex
        bpl ib3
        sec                         ; Rest = Laenge - Offset
        ldx #$00
        ldy #$04
ib4:    lda ifl,x                   ; 32-Bit-Subtraktion (Y zaehlt 4 Bytes; INX/DEY beruehren das Carry nicht)
        sbc iboff,x
        sta ibn,x
        inx
        dey
        bne ib4
        bcs ib5
        lda #ERR_E203               ; offset > Dateilaenge
        jmp as_error
ib5:    clc                         ; Anfang + Offset
        ldx #$00
        ldy #$04
ib6:    lda ibp,x
        adc iboff,x
        sta ibp,x
        inx
        dey
        bne ib6
        jsr skipws
        jsr src_peek
        cmp #$2c
        bne ib_go                   ; keine Laenge: bis zum Dateiende
        jsr src_adv
        jsr eval_val                ; Laenge -> VAL
        ldx #$03                    ; Laenge hoechstens bis zum Dateiende
        lda VAL + 3                 ; 32-Bit-Vergleich von oben nach unten: VAL < ibn -> ib7 (VAL uebernehmen), sonst behalten
        cmp ibn + 3
        bcc ib7
        bne ib_go
        lda VAL + 2
        cmp ibn + 2
        bcc ib7
        bne ib_go
        lda VAL + 1
        cmp ibn + 1
        bcc ib7
        bne ib_go
        lda VAL
        cmp ibn
        bcs ib_go
ib7:    ldx #$03                    ; ibn = VAL
ib8:    lda VAL,x
        sta ibn,x
        dex
        bpl ib8
ib_go:  ldx #$03                    ; P6 = Lesezeiger = ibp
ib9:    lda ibp,x
        sta P6,x
        dex
        bpl ib9
ib_l:   lda ibn                     ; Schleife, solange ibn <> 0 (4 Byte verodert)
        ora ibn + 1
        ora ibn + 2
        ora ibn + 3
        beq ib_d
        ldz #$00
        lda [P6],z                  ; ein Byte der Datei aus dem Attic
        jsr emit_byte               ; in die Ausgabe (PC wird dort erhoeht)
        inc P6                      ; Lesezeiger + 1 (32 Bit)
        bne ib_n
        inc P6 + 1
        bne ib_n
        inc P6 + 2
        bne ib_n
        inc P6 + 3
ib_n:   lda ibn                     ; ibn - 1 (32 Bit): geborgt wird nur, wenn das niedrigere Byte 0 ist
        bne ib_m
        lda ibn + 1
        bne ib_m1
        lda ibn + 2
        bne ib_m2
        dec ibn + 3
ib_m2:  dec ibn + 2
ib_m1:  dec ibn + 1
ib_m:   dec ibn
        jmp ib_l
ib_d:   jmp d_end

; ---- Daten
nfiles:  .byte 0                    ; Zahl der bekannten Dateien (1..16), Hauptdatei eingerechnet
curfile: .byte 0                    ; Nummer der Datei, aus der gerade gelesen wird
onecnt:  .byte 0                    ; Zahl der Eintraege in onelist
incone:  .byte 0                    ; 1 = #include (nur einmal)
hasas:   .byte 0                    ; 1 = "as name" angegeben
inlib:   .byte 0                    ; 1 = <name> (Systemdatei), 0 = "name"
iclose:  .byte 0                    ; Schlusszeichen des Dateinamens (" oder >)
inlen:   .byte 0                    ; Laenge in inname
iplen:   .byte 0                    ; Laenge in inpath
ip2len:  .byte 0                    ; Laenge in inpath2
pbpre:   .byte 0                    ; Laenge des Ordnerpraefixes der einbindenden Datei (0 = keiner)
pnr:     .byte 0                    ; path_norm: Leseposition in inpath
pns:     .byte 0                    ; path_norm: Segmentanfang
pne:     .byte 0                    ; path_norm: Segmentende
ftn:     .byte 0                    ; Namenslaenge des gerade betrachteten Tabelleneintrags (fs_find, ld_end)
ifp:     .fill 4, 0                 ; Ergebnis von fs_find: Adresse des Inhalts (32 Bit)
ifl:     .fill 4, 0                 ; Ergebnis von fs_find: Dateilaenge (32 Bit); auch Hilfszelle beim Weiterlaufen der Tabelle
ibp:     .fill 4, 0                 ; .incbin: Lesezeiger (32 Bit)
ibn:     .fill 4, 0                 ; .incbin: noch auszugebende Bytes (32 Bit)
iboff:   .fill 4, 0                 ; .incbin: Offset (32 Bit)
inname = $1500                    ; 64 Byte im freien Bereich $1200-$17FF
inpath = $1540                    ; 64 Byte im freien Bereich $1200-$17FF
inpath2 = $1580                    ; 64 Byte im freien Bereich $1200-$17FF
filebase = $15c0                    ; 64 Byte im freien Bereich $1200-$17FF
fnames  = $1800                     ; 1024 Byte im freien Bereich $1800-$1EFF (spart Programmgroesse)
onelist = $1300                    ; 128 Byte im freien Bereich $1200-$17FF

; inc_media: Carry gesetzt, wenn der Name in inname (inlen Zeichen) auf eine Medien-Endung von VintageCoder endet
; (.vcsprite .vcpmg .vcchar .vctiles .vcscreen .vcsong .vcplay .vcpal, Gross-/Kleinschreibung gleich)
; Eingabe: inname/inlen. Ausgabe: Carry gesetzt = Medien-Endung (Aufrufer meldet ERR_E219), sonst Carry geloescht.
; Aendert A, X, Y, im_s. Vergleicht die Endung (hinter dem letzten Punkt) gegen die Tabelle im_tab (Namen 0-terminiert,
; Tabellenende = zweite 0); hinter dem Namensende gilt "Zeichen 0", so dass nur ganze Endungen treffen.
inc_media:
        ldx inlen
im_f:   dex                         ; letzten Punkt im Namen suchen
        bmi im_no                   ; kein Punkt im Namen
        lda inname,x
        cmp #$2e
        bne im_f
        inx
        stx im_s                    ; Anfang der Endung
        ldy #$00                    ; Y = Position in im_tab
im_e:   lda im_tab,y
        beq im_no                   ; Tabellenende
        ldx im_s
im_c:   cpx inlen
        bcc im_ch
        lda #$00                    ; hinter dem Namen: Zeichen 0
        beq im_cm
im_ch:  lda inname,x
        ora #$20                    ; Kleinschreibung (Tabelle ist klein)
im_cm:  cmp im_tab,y
        bne im_nx
        cmp #$00                    ; beide gleichzeitig zu Ende = Endung gleich
        beq im_yes
        inx
        iny
        jmp im_c
im_nx:  lda im_tab,y                ; zum Ende dieser Endung und zur naechsten
        beq im_n2
        iny
        bne im_nx
im_n2:  iny
        jmp im_e
im_yes: sec
        rts
im_no:  clc
        rts
im_s:   .byte 0                     ; Anfang der Endung in inname
im_tab: .byte "vcsprite", 0, "vcpmg", 0, "vcchar", 0, "vctiles", 0, "vcscreen", 0, "vcsong", 0, "vcplay", 0, "vcpal", 0, 0

ERR_E901 = $19                      ; .bank ungleich 0: PRG-Ausgabe kennt nur Bank 0 (vcc: Meldung ohne Code, nur Modulformate)
