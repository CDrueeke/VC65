; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; vc65.asm - VC65: Editor und Assembler in einem Programm (MEGA65). Start mit RUN. Speicher (Bank 0): Basisseite $1F00,
; Bildschirm (zugleich Bildpuffer des Editors) bei 50 Zeilen $D000-$DF9F in Bank 4 (SCRNPTR), bei 25 Zeilen $0800, Farb-RAM direkt ($0FF8_0000), Puffer $1800-$1EFF, Programm ab $2001. Daten im Attic und in
; Bank 4/5 (siehe Assembler- und Editordokumentation). Tasten (vorlaeufig): Strg+E uebersetzen, Strg+F Programm speichern,
; Strg+O laden, Strg+K speichern, F1-F8 Suchen/Gehe zu/Markieren/Kopieren/Ausschneiden/Einfuegen, STOP beendet.
; (Die genaue, aktuelle Tastenbelegung steht in disp.asm, Tabelle kmap_in; weitere Tasten: Strg+R starten, Strg+D Debugger,
; Strg+G Haltepunkt, Strg+A Projektlaufwerk.)
;
; Rolle: Hauptdatei (Wurzel der Uebersetzung). Sie legt Ziel, Prozessor und Konfiguration fest, bindet alle Quellen in fester
; Reihenfolge ein und enthaelt das Hauptprogramm main. Das Ergebnis ist das PRG "vc65" (BASIC-Stub bei $2001, SYS -> boot).
; Speicherplan (CPU-Adressen der IDE-Abbildung = Bank 4, siehe boot.asm):
;   $1F00         Basisseite (B-Register = $1F), die Zeropage der IDE liegt also bei $1F00..$1FFF (Bank 0, aber ueber B erreichbar)
;   $2001..IMG_END  Programmabbild (BASIC-Stub, boot, Bruecke-Quelle, Assembler, Editor, Anzeige, ide, chrome); IMG_END < $D000
;   $D000..$DF9F  Bildschirm bei 50 Zeilen (Bank 4), 80 x 50 = 4000 Byte; SCRNPTR zeigt darauf (VIC-IV)
;   $E000         Overlay VC65D (Debugger) oder VC65X (Werkzeuge, xoverlay.asm), jeweils eines davon
;   $F500         Tabellen VC65T (Befehlstabelle + Puffer, tdata.asm/tbss.asm)
;   Bank 0: $1800-$1EFF Puffer, $0800 Bildschirm bei 25 Zeilen (Standard fuer BASIC/Testprogramme), Bruecke $1648, Falle $1380
;   Attic (flach): $0800_0000 Quelle, $0820_0000 Dateitabelle, $0850_0000 Ausgabe; Farb-RAM $0FF8_0000 (ED_ATTR32)
; Konfiguration: IDE_BSS (Puffer liegen in VC65T), IDE_BUILD (Bruecke statt direkter KERNAL-Aufrufe), IDE_ROWS (50 oder 25),
; DISP_DIRECT (Kern zeichnet direkt ins Farb-RAM/Bildschirm).
; Reihenfolge der Einbindung ist wichtig: boot (muss ganz vorn nach dem Stub stehen, wird an $2001 aufgerufen) -> main -> Assembler
; (zp, src, optabsyms, ... asm) -> Editor (ed, disp, file) -> ide -> chrome -> IMG_END (Ende des zu kopierenden Abbilds).
; =====================================================================================================================
.target mega65
.cpu 45gs02 { illegals = deny }
.branchlong auto                    ; Verzweigungen, die zu weit sind, werden automatisch als Sprung gebaut
.org $2001
.basicstub boot                     ; BASIC-Zeile "SYS <boot>"; boot kopiert das Abbild nach Bank 4
IDE_BSS = 1                         ; Puffer in VC65T (src/ide/tbss.asm)
IDE_BUILD = 1                       ; Anzeige/Dateien/Assembler: Bruecke statt direkter KERNAL-Aufrufe, Stufe-2-Daten in Bank 5
IDE_ROWS = 50                       ; Zeilen des Editorbildes: 50 (80 x 50, VIC-IV V400) oder 25 (80 x 25, Bildschirm $0800)
.if IDE_ROWS == 50
ed_scr  = $d000                     ; Bildschirm im Bank-4-Fenster (CPU $D000-$DF9F = $0004_D000, 4000 Byte); SCRNPTR zeigt darauf
ED_SCRPHYS = $0004d000
.else
ed_scr  = $0800
.endif
ED_ATTR32 = $0ff80000               ; der Kern zeichnet direkt ins Farb-RAM
DISP_DIRECT = 1
.include "boot.asm"
; main: Hauptprogramm der IDE. Wird von boot (nach MAP) in Bank 4 angesprungen; Reihenfolge der Initialisierung:
; Basisseite -> ide_init (Haken) -> VC65T laden -> Funktionstasten -> ed_init -> chrome_init -> disp_init -> Editorschleife.
; Bei fehlender Tabellendatei (bad_tab) wird gar nicht erst gestartet, sondern direkt nach BASIC zurueckgekehrt.
main:   lda #$1f
        tab                         ; Basisseite $1F00 (B-Register: Zeropage-Adressen $xx gelten als $1Fxx)
        jsr ide_init
        jsr ide_ldtab               ; Tabellen laden (Datei VC65T); Carry = Fehler
        bcs bad_tab
        jsr oa_chk                  ; Overlay A (Funktionen) einmal von der Disk laden und als Kopie im Attic merken (spaeter nur noch Kopien)
        lda #$09                    ; Standardzustand des VIC-IV (wie von BASIC) fuer Testprogramme merken, bevor die IDE den Bildschirm umstellt
        jsr ide_xcall
        jsr ide_fkoff               ; HELP und Funktionstasten ohne Zeichenfolgen des KERNAL (siehe ide.asm)
        lda #IDE_ROWS
        jsr ed_init                 ; Editor (A = Zeilenzahl)
        jsr chrome_init             ; Rahmen/Palette/Menues der IDE (chrome.asm)
        jsr disp_init               ; VIC-IV-Modus, Bildschirm, Zeichensatz (disp.asm)
        lda #$0a                    ; Startbild: Logo und Version (Werkzeug 10), eine Taste weiter
        jsr ide_xcall
        jsr ed_run                  ; Editorschleife bis zum Beenden (STOP)
        jsr ide_fkon                ; KERNAL-Belegung der Funktionstasten zurueck
bad_tab:
.if IDE_ROWS == 50
        lda #25
        jsr disp_mode               ; zurueck in den 25-Zeilen-Standard (V400 aus, SCRNPTR $0800) fuer BASIC
.endif
        lda #$00
        tab                         ; B = 0: Zeropage wieder $0000 (BASIC erwartet das)
        jsr kdefault                ; Standardabbildung, zurueck nach BASIC
        cli
        rts                         ; Rueckkehr zum BASIC-Interpreter (SYS-Aufrufer)
; ---- Assembler- und Editorquellen (Reihenfolge: zp zuerst, Daten/Tabellen vor Code, der sie benutzt) -----------------------
.include "../asm/zp.asm"
.include "../asm/src.asm"
.include "../../build/optabsyms.asm"   ; Befehlstabelle: Datei VC65T (src/ide/tdata.asm), wird beim Start nach $F500 geladen
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
.include "ide.asm"
.include "chrome.asm"
IMG_END:                            ; Ende des Abbilds; boot kopiert $2000 bis zur Seite von IMG_END nach Bank 4
