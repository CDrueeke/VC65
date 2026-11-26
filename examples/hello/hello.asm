; SPDX-License-Identifier: MIT-0
; =====================================================================================================================
; hello.asm - MEGA65: kleinstes Beispiel für die Besonderheiten des 45GS02 und des VIC-IV
; =====================================================================================================================
; Was das Programm zeigt
;   1. Der Rahmen (Border) wird rot: Schreiben nach $D020 (vic2.border), dem VIC-II-Register der Rahmenfarbe (Farbe 2 = rot).
;   2. Der VIC-IV wird freigeschaltet (mega65_enable_vic4: erst $47, dann $53 nach $D02F).  Für den Rahmen ist das nicht nötig - $D020 ist
;      ein VIC-II-Register und immer verfügbar -; das Beispiel zeigt aber den Handgriff, den man vor jedem Zugriff auf die erweiterten
;      VIC-IV-Register ($D030 ff., siehe die Systemdatei <mega65/vic4.asm>) braucht.
;   3. Ein 32-Bit-Zeiger [$40],z in der Zeropage schreibt ein Byte in das Chip-RAM Bank 1 (Adresse $0001_0000), das die CPU mit
;      16-Bit-Adressen nicht erreicht.  Danach wird der Zeiger als ganzes 32-Bit-Wort mit den Q-Befehlen LDQ/INQ/STQ um 1 erhöht.
;
; Bedienung / Ablauf
;   In VC65: Strg+A (Projektlaufwerk 9, wenn die Beispieldisk dort liegt), Strg+O und den Namen hello.asm, Strg+E übersetzt, Strg+R startet.
;   Der BASIC-Starter (.basicstub, "10 SYS <start>") ruft `start` auf; mit Strg+F lässt sich das Programm auch als Datei speichern und in BASIC
;   mit RUN starten.  Zu sehen ist nur der rote Rahmen; das Programm kehrt nicht zu BASIC zurück, sondern bleibt in einer Endlosschleife
;   (zurück in die IDE: RESTORE-Taste, die Notfalltaste von VC65).
;
; Speicher / Register
;   Programm ab $2001 (Anfang des BASIC-65-Speichers; BASIC-Starter + Code, wenige Dutzend Byte).
;   Zeropage: $40-$43 = 32-Bit-Zeiger (niederwertiges Byte zuerst).  Z-Register = Index des 32-Bit-Zeigers.  Das Basisseitenregister B
;   muss 0 sein (normalerweise der Fall; dieses Programm ändert B nicht).
;   Beschrieben wird $0001_0000 = $FF.  Vorsicht: Der Bereich ab $10000 wird laut sound.asm des Beispiels PRALLBALL vom DOS des KERNALs benutzt
;   ($10000-$107FF); nach dem Beispiel nicht in BASIC weiterarbeiten, ohne den Rechner zurückzusetzen.
;   Bibliothek: <mega65/gs4502.asm> (Makro mega65_enable_vic4; bindet <mega65/hardware.asm> mit den Registernamen ein).
; =====================================================================================================================
#include <mega65/gs4502.asm>   // Makro mega65_enable_vic4

.org $2001                          ; BASIC-65 lädt Programme ab $2001
.basicstub start                    ; erzeugt die BASIC-Zeile "10 SYS <start>", damit RUN das Programm startet

start:  mega65_enable_vic4          ; VIC-IV-Register freischalten ($47, dann $53 nach $D02F)
        lda #$02
        sta vic2.border             ; Rahmen rot
        ldz #$00                    ; Z = 0: Index für den 32-Bit-Zeiger
        lda #$00
        sta $40                     ; Zeropage-Zeiger $40-$43 = $0001_0000 (32-Bit-Adresse; Byte 0 = $00, 1 = $00, 2 = $01, 3 = $00)
        sta $41
        lda #$01
        sta $42
        lda #$00
        sta $43
        lda #$ff
        sta [$40],z               ; Byte nach $1_0000 schreiben (Chip-RAM Bank 1, nur über den 32-Bit-Zeiger erreichbar)
        ldq $40                     ; den Zeiger als 32-Bit-Wert (Q-Register) laden
        inq                         ; … um eins erhöhen
        stq $40                     ; … und zurückschreiben: der Zeiger zeigt jetzt auf $0001_0001
done:   bra done                    ; Endlosschleife (kein Rücksprung nach BASIC)
