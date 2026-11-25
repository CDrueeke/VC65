; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; overlay.asm - Debugger-Overlay VC65D: Wurzeldatei, die die Debugger-Quelltexte zu einem Abbild zusammenfuegt.
;
; Lage: das Overlay laeuft in Bank 4 bei CPU-Adresse $E000 (physisch $4E000, Block 7 des oberen Fensters $8000-$FFFF).
; Block 7 statt Block 6 ($C000-$DFFF), damit Block 6 mit der Ein-/Ausgabe ($D000-$DFFF: VIC, CIA, Farb-RAM) fuer den Debugger
; frei schaltbar bleibt (siehe dvid.asm, dv_on/dv_off); der Code bleibt dabei sichtbar.
; Laden: ide_dbg_stub (Hauptprogramm) laedt es bei Bedarf aus der Datei VC65D (ein PRG mit Kopf; der Lader ueberspringt die
; zwei Kopfbytes). Alle Namen des Hauptprogramms (ide_prep, krun, kt_pc, dbg_bp ...) kommen aus build/ovsyms.asm, das
; tools/build_ide.py aus der Labeldatei des Hauptprogramms erzeugt; dieses Overlay hat darum keine eigenen Definitionen davon.
; Aufbau (Reihenfolge der Includes = Reihenfolge im Speicher, hinter der Sprungtabelle):
;   dtab.asm   Dekodiertabellen des 45GS02 (erzeugt)      dis.asm    Disassembler (dis_one)
;   dbg.asm    Kern: Haltepunkte, Falle, Fortsetzen        dbgui.asm  Anzeige und Tasten
;   dvid.asm   Bildschirmumschaltung (VIC-IV-Zeiger)       dsess.asm  Sitzungsschleife (ide_debug)
; Einsprung: Sprungtabelle bei $E000: +0 ide_debug (Strg+D), +3 dbg_trap (OV_TRAP, vom Fallenhandler ktrap/knmi in boot.asm).
; Platz: das Overlay ist knapp bemessen: es muss vor $F600 enden (ab dort liegen die Tabellen VC65T, siehe dvid.asm, danach
; die Vektoren $FFFA-$FFFF); jede Aenderung am Code oder an den Daten verschiebt alles dahinter.
; =====================================================================================================================
.target mega65
.cpu 45gs02 { illegals = deny }
.branchlong auto
.org $e000
.include "../../build/ovsyms.asm"
ov_entry:
        jmp ide_debug               ; $E000: Sitzung starten (Strg+D), siehe dsess.asm
        jmp dbg_trap                ; $E003 (OV_TRAP): Halt nach BRK/NMI, vom Fallenhandler in Bank 0 gerufen (dbg.asm)
.include "dtab.asm"
.include "dis.asm"
.include "dbg.asm"
.include "dbgui.asm"
.include "dvid.asm"
.include "dsess.asm"
