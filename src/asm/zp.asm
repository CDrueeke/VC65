; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; zp.asm - Zeropage-Belegung des Assemblers (Etappe N2). Jede Zelle genau einmal vergeben.
;
; Zweck: reine Symboldefinitionen (kein Code, keine Daten, belegt keinen Speicher im Programmabbild). Alle anderen Module in
; src/asm/ (asm.asm, expr.asm, numx.asm, math.asm, func.asm, sym.asm, stage2.asm, list.asm, ...) verwenden diese Namen; die
; Adressen werden deshalb nur hier gepflegt. Eine neue Zelle muss in einem noch freien Bereich liegen - vor dem Eintragen
; die gesamte Datei auf Ueberschneidungen pruefen (Tabelle unten), denn der Assembler meldet doppelte Belegung nicht.
;
; Adressierung: "Zeropage" ist hier die Basisseite des 45GS02 (B-Register). Zugriffe wie `lda VAL,x` oder `sta $00,x`
; (negate in expr.asm) benutzen 8-Bit-Adressen; der Loader setzt B nur kurz auf 0, wenn das KERNAL aufgerufen wird.
; Mehrbytewerte liegen tief zuerst (Little Endian). 32-Bit-Zeiger werden mit `lda [ZP],z` (Z = Index) benutzt und muessen
; daher alle vier Bytes belegen (Bank im dritten, oberstes Byte im vierten Byte).
;
; Belegungsplan (Bereiche, in Klammern die Abschnitte unten):
;   $00-$0f  Stufe 2: P6, P7, FP, S2T          $10-$1f  IFSTK (Zustand je .if-Ebene)   $20-$3f  LNAME (Konstantenname)
;   $40-$5f  CURG, CURGL, LLEN                 $60-$6f  SRC, NEGN/POSN, BLONG, BIDX, BITP, TM, SF, ENC
;   $70-$8d  Ausdruecke: VAL, LHS, TMP, ...    $a0-$ef  Assembler: Namen, Zeiger, Modus, Ausgabe, Fehler
;   $f9-$fd  SUF, DPTR, MP
; Hinweis: SYM_B2/SYM_B3 sind keine Zeropage-Adressen, sondern Werte (Bytes 2 und 3 der Symboltabellenadresse).
; =====================================================================================================================

; --- Ausdruecke und Zahlen (expr.asm, numx.asm, math.asm, func.asm) ---
; SRC wird von allen Lesern des Quelltexts benutzt (src.asm: src_peek/src_adv); Zeichen 0 beendet den Text.
SRC     = $60                       ; 32-Bit-Zeiger auf das aktuelle Quelltextzeichen ($60-$63)
VAL     = $70                       ; 32-Bit-Wert (Ergebnis, rechter Operand) ($70-$73)
LHS     = $74                       ; 32-Bit-Wert, linker Operand ($74-$77)
TMP     = $78                       ; 32-Bit-Hilfswert ($78-$7B)
TMP2    = $84                       ; 32-Bit-Hilfswert ($84-$87)
; Fehlerstand und Operatorverwaltung des Ausdrucksauswerters ($7d-$83; ESP sichert den Stapelzeiger fuer ex_fail)
ERR     = $7d                       ; Fehlercode (0 = kein Fehler)
OPID    = $7e                       ; Operatorkennung
OPLEN   = $7f                       ; Laenge des Operators in Zeichen
CNT     = $80                       ; Zaehler
PREC    = $81                       ; Vorrang des gelesenen Operators
NBASE   = $82                       ; Zahlenbasis (2, 10, 16)
ESP     = $83                       ; Stapelzeiger beim Eintritt (Fehlerabbruch)
; Hilfszellen der Division/Vergleiche (math.asm/numx.asm); $88-$8b
SGNL    = $88                       ; Vorzeichen des linken Operanden bei Division
SGNQ    = $89                       ; Vorzeichen des Quotienten
CLT     = $8a                       ; Vergleich: 1 wenn LHS < VAL (vorzeichenbehaftet)
CEQ     = $8b                       ; Vergleich: 1 wenn LHS == VAL
; Programmzaehler des Assemblers (16 Bit; `*` im Ausdruck liefert diesen Wert)
PC      = $8c                       ; Programmzaehler (16 Bit, $8c/$8d)

; Assembler (Symbole, Zeilen, Befehle)
; Name, Durchlaufsteuerung, Befehlscodierung, Zeiger in Symbol- und Ausgabespeicher ($a0-$ef)
NAMEBUF = $a0                       ; Bezeichner, bis 31 Zeichen ($a0-$bf)
NAMELEN = $c0
PASS    = $c1                       ; Durchlauf (1 = erster)
CHG     = $c2                       ; 1 = in diesem Durchlauf hat sich ein Symbolwert geaendert
UNK     = $c3                       ; 1 = Ausdruck nutzt ein noch unbekanntes Symbol
MODEID  = $c4                       ; gewaehlte Adressierungsart (M_*)
OPCODE  = $c5
PFX32   = $c6                       ; 1 = Zeigerpraefix $EA (Syntax [zp],z)
PMODE   = $c7                       ; Syntaxform des Operanden (P_*)
OUTP    = $c8                       ; 32-Bit-Ausgabezeiger ($c8-$cb)
SYMP    = $cc                       ; 32-Bit-Zeiger auf den Symboleintrag ($cc-$cf)
SYME    = $d0                       ; 32-Bit-Zeiger hinter den letzten Eintrag ($d0-$d3)
SRCBASE = $d4                       ; Anfang des Quelltexts, 32 Bit ($d4-$d7)
OPVAL   = $d8                       ; Operandenwert ($d8-$db)
OPVAL2  = $dc                       ; zweiter Wert (BBR/BBS) ($dc-$df)
MDP     = $e0                       ; Zeiger auf die Modenliste (16 Bit, $e0/$e1)
QUAD    = $e2                       ; 1 = Quad-Befehl
ASP     = $e3                       ; Stapelstand bei Zeilenanalyse (Fehlerabbruch)
DIRID   = $e4                       ; Direktivenkennung
OUTBASE = $e8                       ; Anfang der Ausgabe, 32 Bit ($e8-$eb)

; Lokale/anonyme Marken, lange Spruenge, Textdirektiven ($40-$6f) und .if-Zustand ($0e-$1f), Direktiventabelle ($f9-$fb)
; (CURG/CURGL: aktueller globaler Marken-Name als Praefix fuer lokale Marken)
CURG    = $40                       ; Name der aktuellen globalen Marke, bis 30 Zeichen ($40-$5d)
CURGL   = $5e
NEGN    = $64                       ; Zaehler der anonymen Marken '-' in diesem Durchlauf
POSN    = $65                       ; Zaehler der anonymen Marken '+'
BLONG   = $66                       ; 1 = .branchlong auto
BIDX    = $67                       ; Sprungzaehler (16 Bit, $67/$68)
BITP    = $69                       ; 32-Bit-Zeiger in die Tabelle der langen Spruenge ($69-$6c)
TM      = $6d                       ; Textkodierung der laufenden Datenliste (0 ASCII, 1 PETSCII, 2 Bildschirmcode)
SF      = $6e                       ; Textform: Bit0 .null, Bit1 .ptext, Bit2 .shift
ENC     = $6f                       ; mit .encoding gewaehlte Kodierung fuer .text
DPTR    = $fa                       ; Zeiger in die Direktiventabelle ($fa/$fb)
SUF     = $f9                       ; Befehlssuffix: 0 keins, 1 .z, 2 .a
IFSP    = $0e                       ; Tiefe der .if-Verschachtelung (0 = keine)
ISKIP   = $0f                       ; 1 = Zeilen werden gerade uebersprungen
IFSTK   = $10                       ; Zustand je .if-Ebene ($10-$1f): Bit0 aktiv, Bit1 Zweig schon genommen, Bit2 Eltern aktiv
; Weiche Fehler: werden gemerkt und erst am Ende des Durchlaufs gemeldet (z. B. Symbol noch unbekannt im ersten Durchlauf)
SOFT    = $e5                       ; erster weicher Fehler dieses Durchlaufs (0 = keiner)
SOFTP   = $ec                       ; Quelltextstelle dieses Fehlers (32 Bit, $ec-$ef)
; Stufe 2 (stage2.asm, list.asm, func.asm): Zeiger in Bank 4 (der Name P6 ist historisch); FP = Rahmenzeiger
P6      = $00                       ; Stufe 2: 32-Bit-Zeiger (Bank 6) fuer Variablen und Makrotabelle ($00-$03)
P7      = $04                       ; zweiter Zeiger ($04-$07)
FP      = $08                       ; Zeiger auf den obersten Rahmen ($08-$0b)
S2T     = $0c                       ; 16-Bit-Hilfszelle ($0c/$0d)
; Symboltabelle: Adresse $0810_0000, d. h. Byte 2 = $10 und Byte 3 = $08 (Wert, keine Zeropage-Adresse)
SYM_B2   = $10                       ; Symboltabelle im Attic: $0810_0000 (Bank 2 und 3 der Adresse)
SYM_B3   = $08
; Parametertabelle (Makro-/Funktionsparameter) und gesicherter Konstantenname
MP      = $fc                       ; 16-Bit-Zeiger in die Parametertabelle ($fc/$fd)
LNAME   = $20                       ; gesicherter Name einer Konstante ($20-$3f)
LLEN    = $5f

; Fehlercodes (Auszug, an vcc angelehnt): Die Nummer E2xx entspricht der Meldung des Referenzassemblers vcc; der Code ist
; der Wert in ERR (0 = kein Fehler). Die Codes sind nicht nach E-Nummer geordnet, sondern nach Vergabe; nicht umnummerieren.
ERR_SYNTAX = $01                    ; Syntaxfehler im Ausdruck
ERR_E202   = $02                    ; unbekanntes Symbol / Division durch 0
ERR_E203   = $03                    ; Wert ausserhalb des erlaubten Bereichs
ERR_E205   = $05                    ; unbekannter Befehl
ERR_E208   = $08                    ; unbekannte Direktive
ERR_TARGET = $07                    ; .target ist nicht mega65
ERR_E206   = $06                    ; Adressierungsart nicht unterstuetzt
ERR_E209   = $0e                    ; falsche Argumentzahl / Makro
ERR_E210   = $0a                    ; Block nicht abgeschlossen / .break ausserhalb einer Schleife
ERR_E211   = $0b                    ; zu tief verschachtelt / Puffer voll
ERR_E216   = $0c                    ; Variable nicht mit .var angelegt
ERR_E213   = $0d                    ; Scope nicht geschlossen oder } ohne {
ERR_E207   = $0f                    ; .assert/.error
ERR_NOFILE = $10                    ; Dateizugriff (.include/.incbin) folgt mit N6
ERR_E214   = $11                    ; kein passendes -/+-Label
ERR_E218   = $12                    ; .basicstub nicht am Anfang
ERR_E215   = $13                    ; .z/.a nicht moeglich
