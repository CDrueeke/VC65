; SPDX-License-Identifier: GPL-3.0-or-later
; ERZEUGT von tools/gen_charnames.py aus vendor/vintagecoder/data/chars/petscii.json - nicht von Hand aendern.
; Eintrag: Laenge, Name (klein, Leerzeichen), Code. Ende: Laenge 0.
;
; Zweck: Namen der PETSCII-Steuerzeichen fuer die Textschreibweise `{name}` bzw. `{name*n}` in Zeichenketten (text2.asm,
; esc_lookup). Die Tabelle ist reine Daten (Bytes), liegt im Programmspeicher und wird nur gelesen. Die Suche in esc_lookup
; ist linear, Namen gleicher Laenge werden Byte fuer Byte verglichen (Kleinschreibung; der Aufrufer wandelt vorher), der
; erste Treffer gewinnt. Mehrere Namen duerfen denselben Code haben (ret/return, rvs on/rvon, ...); ein Name mit Leerzeichen
; (z. B. "rvs on") ist zulaessig, weil die Laenge zaehlt, nicht ein Nullbyte.
; Eintragsformat in Bytes: [Namenslaenge n][n Zeichen][PETSCII-Code]; Tabellenende = Laenge 0. Codes siehe PETSCII-Tabelle des
; MEGA65 (z. B. $0d = RETURN, $93 = CLR/Bildschirm loeschen, $13 = HOME, $90..$9f = Farben/Revers). Nicht von Hand aendern,
; sondern vendor/vintagecoder/data/chars/petscii.json bzw. den Generator anpassen und neu erzeugen.
charnames:
        .byte 4, "stop", $03
        .byte 3, "wht", $05
        .byte 3, "ret", $0d
        .byte 6, "return", $0d
        .byte 5, "lower", $0e
        .byte 4, "down", $11
        .byte 6, "rvs on", $12
        .byte 4, "rvon", $12
        .byte 4, "home", $13
        .byte 3, "del", $14
        .byte 3, "red", $1c
        .byte 5, "right", $1d
        .byte 4, "rght", $1d
        .byte 3, "grn", $1e
        .byte 3, "blu", $1f
        .byte 5, "space", $20
        .byte 5, "pound", $5c
        .byte 6, "orange", $81
        .byte 4, "orng", $81
        .byte 2, "f1", $85
        .byte 2, "f3", $86
        .byte 2, "f5", $87
        .byte 2, "f7", $88
        .byte 2, "f2", $89
        .byte 2, "f4", $8a
        .byte 2, "f6", $8b
        .byte 2, "f8", $8c
        .byte 9, "shift ret", $8d
        .byte 12, "shift return", $8d
        .byte 5, "upper", $8e
        .byte 3, "blk", $90
        .byte 2, "up", $91
        .byte 7, "rvs off", $92
        .byte 4, "rvof", $92
        .byte 3, "clr", $93
        .byte 4, "inst", $94
        .byte 3, "brn", $95
        .byte 4, "lred", $96
        .byte 4, "gry1", $97
        .byte 4, "gry2", $98
        .byte 4, "lgrn", $99
        .byte 4, "lblu", $9a
        .byte 4, "gry3", $9b
        .byte 3, "pur", $9c
        .byte 4, "left", $9d
        .byte 3, "yel", $9e
        .byte 3, "cyn", $9f
        .byte 11, "shift space", $a0
        .byte 2, "pi", $ff
        .byte 0
