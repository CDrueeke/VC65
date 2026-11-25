; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; xoverlay.asm - Werkzeug-Overlay VC65X: selten gebrauchte Editorfunktionen, die nicht im Hauptprogramm liegen (BASIC laedt das
; Hauptprogramm nur bis $CFFF). Laeuft wie das Debugger-Overlay VC65D bei CPU-Adresse $E000 (Bank 4); beide teilen sich den Platz: wer
; geladen wird, ersetzt das andere (ov_ok = Debugger geladen, xo_ok = Werkzeuge geladen, siehe ide.asm). Aufruf: ide_xcall (A = Nummer).
; Die Namen des Hauptprogramms kommen aus build/ovsyms.asm (tools/build_ide.py). Sprungtabelle: Eintrag n bei $E000 + 3 * n.
; Datei VC65X: PRG mit 2 Byte Ladeadresse ($E000); ov_get (ide.asm) verwirft diese zwei Byte und schreibt den Rest nach $0004_E000.
; Das Overlay hat keine eigene Zeropage: es laeuft mit der Basisseite $1F der IDE und beendet jede Routine per RTS zum Aufrufer von
; ide_xcall (das per jmp (xo_t) hineinspringt). Die Reihenfolge der Sprungeintraege ist eine feste Schnittstelle: die Nummern stehen
; bei den Aufrufern von ide_xcall im Hauptprogramm; neue Eintraege nur anhaengen.
; Invariante: der Code ab $E000 muss unterhalb von $F500 (VC65T) enden.
; =====================================================================================================================
.target mega65
.cpu 45gs02 { illegals = deny }
.branchlong auto
.org $e000
.include "../../build/ovsyms.asm"
xo_tab:                             ; Sprungtabelle: jeder Eintrag genau 3 Byte (JMP absolut), sonst stimmt $E000 + 3 * n nicht
        jmp ed_fmt_line             ; 0  Zeile ausrichten
        jmp ed_fmt_all              ; 1  alles ausrichten
        jmp xo_calc                 ; 2  Hex-Rechner (Eingabe in pbuf)
        jmp xo_data                 ; 3  Daten einfuegen (Eingabe in pbuf)
        jmp xo_busy                 ; 4  Hinweis "Loading file ..." (zentrierter Kasten, blinkend)
        jmp xo_thapply              ; 5  IDE-Farbschema setzen (Palette)
        jmp xo_threst               ; 6  Standardpalette (vor Testprogrammen); sichert auch die VIC-IV-Register
        jmp xo_vrest                ; 7  VIC-IV-Register wiederherstellen (nach Testprogrammen)
        jmp xo_build                ; 8  Hinweis "Building ..." (Strg+E)
        jmp xo_vstd                 ; 9  Standardzustand des VIC-IV beim Start merken
        jmp xo_logo                 ; 10 Logo und Version (Startbild, Menue File > About)
.include "../editor/fmt.asm"        ; Ausrichten (Format) des Quelltextes
.include "../editor/xtools.asm"
