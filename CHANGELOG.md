<!-- SPDX-License-Identifier: MIT-0 -->
# Änderungsprotokoll

Die Versionsnummer hat die Form `MAJOR.MINOR.PATCH` mit Zusatz (`-alpha`). Solange sie unter 1.0 liegt, steht `0.MINOR` für ein neues Funktionspaket und `PATCH` für Fehlerkorrekturen. Die Nummer und die Tags (`vMAJOR.MINOR.PATCH-alpha`) legt der Projektinhaber fest. Änderungen für die nächste Version stehen unter „Unveröffentlicht“.

## Unveröffentlicht

## 0.1.0-alpha

Erste Vorabversion von VC65: eine native Entwicklungsumgebung für den MEGA65 (Editor, VCASM-kompatibler Assembler, Debugger), die auf dem MEGA65 selbst läuft. Bisher nur im Emulator Xemu getestet, am echten Gerät ungeprüft.

### Enthalten
- **Editor** (80 × 50): Farbhervorhebung, Zeilennummern, Auswahl, Kopieren, Rückgängig, Suchen/Ersetzen, Gehe zu, Marken, Ausrichten, Hex-Rechner, Daten einfügen, Menü (HELP oder ESC), Laden/Speichern, Lade- und Bau-Anzeige, Startbild und About.
- **Assembler**: VCASM für den 45GS02 des MEGA65, byte-gleich zu `vcc` (Konformitätskorpus rund 98,7 %, Warnungen identisch), Fehlerliste, automatische Prüfung bei Zeilenwechsel, Systembibliotheken von der Diskette.
- **Bauen und Starten**: übersetzen, Programm speichern (PRG), starten, zurück in die IDE; Notfalltaste RESTORE.
- **Debugger**: Haltepunkte, Einzelschritt, Register, Speicher, eigenes Bild.
- **Beispiele**: hello, paldemo, musicdemo, prallball (MIT-0).
- **Handbuch** (Deutsch und Englisch) als PDF und Markdown, mit Anleitung, Beispielen, Fehlersuche, Fehlercodes und Glossar.
- **Lizenz**: GPL-3.0-or-later; mit VC65 erzeugte Dateien, die Sprache VCASM und die Dateiformate sind frei nutzbar; Systemdateien und Beispiele unter MIT-0.

### Bekannte Einschränkungen
- Nur Ziel `mega65`; `.atascii`, `.cartridge` und Systemdateien anderer Ziele gibt es nicht; `.bank` kennt nur Bank 0 (E901).
- Keine Ordner und langen Dateinamen, keine Projektdateien, keine Haltepunkte in Makrorümpfen und Include-Dateien.
- Die Oberfläche ist nur englisch.
- Alpha: enthält mit Sicherheit noch Fehler.
