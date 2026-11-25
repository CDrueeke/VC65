; SPDX-License-Identifier: MIT-0
; =====================================================================================================================
; paldemo.asm - MEGA65: eine 256-Farben-Palette in den VIC-IV laden
; =====================================================================================================================
; Was das Programm zeigt
;   Der VIC-IV des MEGA65 hat vier Paletten (Bänke) zu je 256 Farben mit je 8 Bit Rot, Grün und Blau (der C64 kennt nur 16 feste Farben).
;   Das Programm lädt die Palette pal65 (256 Einträge: 0-15 die C64-Farben,
;   danach Verläufe) in Palettenbank 1 und wählt sie für Text/Bitmap (vic4_use_palette).  Die Tabellen pal65_red, pal65_green und pal65_blue stehen
;   fertig als .byte in pal65.asm; das Programm bindet sie ein und kopiert sie mit vic4_load_palette in die Register.
;   Auf dem Bildschirm ist kaum etwas zu sehen (Einträge 0-15 sind die C64-Farben); das Ergebnis prüft man im Monitor/Emulator,
;   indem man die Registerfenster $D100-$D3FF liest (die Bank 1 bleibt dazu am Ende eingeblendet und wird für Text/Bitmap benutzt).
;
; Bedienung / Ablauf
;   * In VC65: Strg+O und den Namen paldemo.asm laden (Projektlaufwerk mit Strg+A wählen), Strg+E übersetzt.  Das Programm hat keinen BASIC-Starter
;     (Ladeadresse $2000): Strg+R startet es aus der IDE; als Datei gespeichert (Strg+F) lädt man es mit BLOAD und startet es mit SYS 8192.
;     Das Programm bleibt danach in einer Endlosschleife (zurück in die IDE: RESTORE-Taste, die Notfalltaste).
;   * pal65.asm enthält die drei Tabellen (je 256 Byte; Rot/Grün/Blau stehen mit vertauschten Halbbytes, wie die Register es verlangen).
;
; Hardware / Bibliothek
;   vic4.inc: vic4_unlock ($47, $53 nach $D02F), vic4_load_palette, vic4_use_palette, vic4_palette_runtime.
;   $D070 (Palettenwahl, laut MEGA65-Registerbeschreibung; nicht in den Chip-Symbolen von VC65 enthalten): Bit 7-6 = Bank, die bei $D100-$D3FF eingeblendet
;   ist, Bit 5-4 = Bank für Text/Bitmap, Bit 3-2 = Bank für Sprites, Bit 1-0 = alternative Palette.
;   $D100/$D200/$D300 = Rot/Grün/Blau-Register der eingeblendeten Bank (je 256 Byte).
;
; Speicher
;   Programm ab $2000 (ca. 870 Byte mit den drei Tabellen zu je 256 Byte); Zeropage $F7-$FA (Quell- und Zielzeiger beim Kopieren).
; =====================================================================================================================
.cpu 45gs02 { illegals = deny }

.org $2000
.include "vic4.inc"                 ; definiert nur Makros, erzeugt hier noch keine Bytes

start:  sei                         ; keine Unterbrechung während $D070 umgeschaltet ist
        vic4_unlock                 ; VIC-IV-Register freischalten (sonst wirkt $D070 nicht)
        vic4_load_palette pal65_red, pal65_green, pal65_blue, 1   ; 3 x 256 Byte in die Fenster $D100/$D200/$D300 der Bank 1 kopieren
        vic4_use_palette 1          ; Bank 1 für Text/Bitmap wählen
        lda #$50
        sta $d070                   ; Bit 7-6 = 1: Bank 1 bei $D100-$D3FF eingeblendet lassen (zum Zurücklesen); Bit 5-4 = 1: Text/Bitmap
                                    ; zeigen Bank 1 (ganzes Register setzen; vic4_load_palette hat es am Ende auf 0 gestellt)
done:   bra done                    ; Endlosschleife

vic4_palette_runtime                ; Kopierunterprogramm einmal hinter dem Hauptprogramm ablegen
.include "pal65.asm"                 ; die Tabellen pal65_red, pal65_green, pal65_blue
