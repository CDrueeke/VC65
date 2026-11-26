<!-- SPDX-License-Identifier: MIT-0 -->
# 10 Fehlersuche und häufige Fragen

Englische Fassung: [../en/10-troubleshooting.md](../en/10-troubleshooting.md). Zurück zur [Übersicht](README.md). Vorabversion 0.1.1-Alpha.

Dieses Kapitel sammelt Probleme, die beim Arbeiten mit VC65 auftreten können, mit Ursache und Abhilfe. Die Meldungen des Programms sind englisch und stehen hier in Code-Schreibweise. Alles ist nur im Emulator Xemu getestet.

## Start und Disketten

**VC65 startet nicht, BASIC meldet einen Fehler bei `DLOAD"VC65"`.**
Die Boot-D81 ist nicht in Laufwerk 8 eingehängt, oder das Abbild ist beschädigt. Prüfen Sie die Prüfsumme mit `SHA256SUMS` (Linux: `sha256sum -c`, macOS: `shasum -a 256 -c`).

**Die Meldung `File VC65D missing` oder `File VC65X missing` erscheint.**
Die Overlay-Dateien `VC65D` (Debugger) und `VC65X` (Ausrichten, Hex-Rechner, Daten einfügen, Meldungsfenster) müssen auf der Systemdisk in Laufwerk 8 stehen. Sie werden bei Bedarf nachgeladen; ohne sie gibt es diese Werkzeuge nicht. Prüfen Sie, dass die Boot-D81 in Laufwerk 8 liegt und nicht gegen eine andere getauscht wurde.

**Das Laden einer Datei meldet `Error loading`.**
Der Name stimmt nicht, die Datei liegt nicht auf dem Projektlaufwerk, oder die Datei ist leer. Eine **leere Datei** lässt sich nicht laden (das Laufwerk meldet sie als Lesefehler). Prüfen Sie mit **Strg+A**, welches Laufwerk gerade das Projektlaufwerk ist (rechts in der Dateizeile).

**`Error saving` beim Speichern.**
Prüfen Sie, ob die Diskette voll oder schreibgeschützt ist und ob der Name höchstens 16 Zeichen hat. Namen dürfen keine Ordner enthalten.

## Tastatur

**Der Unterstrich `_` lässt sich nicht tippen.**
Auf manchen Tastaturen (zum Beispiel einer Mac-Tastatur im Emulator) wird `_` nicht an den MEGA65 übergeben. Verwenden Sie in eigenen Namen Buchstaben und Ziffern (so heißen auch die Beispiele `paldemo.asm` und `musicdemo.asm`).

**Strg+Buchstabe tut nichts.**
Der Emulator oder das Betriebssystem Ihres Rechners kann eine Tastenkombination abfangen, bevor sie den MEGA65 erreicht. Benutzen Sie dann das Menü (**ESC** oder **HELP**), das dieselben Befehle anbietet.

## Übersetzen

**`E205` (unbekannter Befehl).**
Meist ein Tippfehler im Mnemonik, eine Marke ohne Doppelpunkt, die am Zeilenanfang steht, oder ein nicht definiertes Makro. Der Cursor springt in die Fehlerzeile.

**`E202` (Fehler in einem Ausdruck).**
Ein unbekanntes Symbol (Marke falsch geschrieben oder noch nicht definiert, Include fehlt), fehlende Klammer, Division durch 0 oder falsche Argumentzahl einer Funktion.

**`E300` (Code oder Marke vor dem ersten `.org`).**
Vor dem ersten `.org` oder `*=` wurde ein Byte ausgegeben oder eine Marke definiert. Schreiben Sie `.org` an den Anfang, vor die erste Marke und den ersten Befehl. Konstanten, Makrodefinitionen und `#include` davor sind erlaubt.

**`E207` mit `.target`.**
VC65 übersetzt nur für den MEGA65. Entfernen Sie die Zeile oder schreiben Sie `.target mega65`.

**Fehler stehen in einer Include-Datei: `in file n` statt der Spalte, und der Cursor springt nicht.**
Der Fehler liegt in der Datei, die mit `.include` oder `#include` eingebunden ist. Laden Sie diese Datei und übersetzen Sie sie dort, um die Zeile zu sehen.

**Die Meldung `Assemble first` erscheint bei Strg+F, Strg+R oder Strg+G.**
Es gibt keine aktuelle Ausgabe: Sie haben den Text seit dem letzten Übersetzen geändert oder noch nie übersetzt. Drücken Sie zuerst Strg+E.

**Ein Programm für einen anderen Computer (C64, Atari, …) lässt sich nicht übersetzen.**
VC65 ist ein reiner MEGA65-Assembler. Systemdateien anderer Ziele (zum Beispiel `<c64/kernal.asm>`) liegen nicht auf der Systemdisk, und die Direktiven `.atascii` und `.cartridge` gibt es nicht.

## Starten

**`Load address below $2000`.**
Das Programm liegt unter `$2000` und würde die IDE überschreiben; VC65 startet es nicht. Setzen Sie das Programm mit `.org $2001` (mit `.basicstub`) oder `.org $2000` an eine Adresse ab `$2000`.

**Das Programm startet, der Bildschirm bleibt hängen.**
Ein Programm, das nie zurückkehrt, bleibt stehen. Mit der **RESTORE-Taste** kehren Sie in die IDE zurück (`Program interrupted (emergency key)`). Das gilt nicht für Programme, die Stapel oder Zeropage zerstören oder einen eigenen IRQ/NMI-Betrieb haben.

**Der Text meines Programms ist nach dem Ende sofort weg.**
Kehrt ein Programm mit `RTS` zurück, schaltet VC65 gleich wieder auf das 50-Zeilen-Bild um. Lassen Sie das Programm auf eine Taste warten (siehe [Kapitel 8](08-erstes-programm.md)).

**Der Ton fehlt.**
Der Emulator braucht ein Audio-Ausgabegerät. In einer Fernsitzung ohne Audio (zum Beispiel RDP ohne Tonweiterleitung) ist nichts zu hören.

## Debugger

**`Assemble first` bei Strg+G (Haltepunkt).**
Haltepunkte brauchen die Zeilentabelle des letzten Übersetzens. Übersetzen Sie erst mit Strg+E.

**`No output here`.**
Die Zeile erzeugt keine Ausgabe (Kommentar, Leerzeile, Direktive ohne Bytes). Setzen Sie den Haltepunkt auf eine Befehlszeile.

**`Too many breakpoints`.**
Die Zahl der Haltepunkte ist begrenzt; entfernen Sie nicht benötigte mit Strg+G.

**Der Debugger zeigt `(no line info)`.**
Der Programmzähler steht in einem Bereich ohne Zeilenangabe (zum Beispiel ROM, Makro oder Include-Datei). Haltepunkte in Makrorümpfen und Include-Dateien sind nicht möglich.

## Grenzen und Alpha-Stadium

- VC65 ist ein **Alpha-Programm**. Es enthält mit Sicherheit noch Fehler und ist nur im Emulator Xemu getestet, **nicht am echten MEGA65**.
- Das Programm ist **englisch**; das Handbuch gibt es auf Deutsch und Englisch.
- Die Tastenbelegung ist vorläufig und kann sich ändern.
- Fehler und Wünsche: siehe `README.md` und `SECURITY.md` im Paket.
