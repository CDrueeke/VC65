<!-- SPDX-License-Identifier: MIT-0 -->
# Änderungsprotokoll

Die Versionsnummer hat die Form `MAJOR.MINOR.PATCH` mit Zusatz (`-alpha`). Solange sie unter 1.0 liegt, steht `0.MINOR` für ein neues Funktionspaket und `PATCH` für Fehlerkorrekturen. Die Nummer und die Tags (`vMAJOR.MINOR.PATCH-alpha`) legt der Projektinhaber fest. Änderungen für die nächste Version stehen unter „Unveröffentlicht“.

## Unveröffentlicht

## 0.1.1-alpha

Fehlerkorrekturen und Feinschliff; Funktionsumfang wie 0.1.0-alpha. Weiterhin nur im Emulator Xemu getestet.

### Behoben
- **Startbild und File > About:** Mit geladener Datei schimmerte der Quelltext durch das Logo. Der Text hinter dem Logo wird jetzt abgedunkelt, das Logo liegt darüber.
- **Debugger, Haltepunkte:** Haltepunkte sind Adressen und überlebten eine Textänderung samt Neuübersetzung; dann lag ein BRK mitten in einem Befehl, der Debugger zeigte `brk` und das Programm entgleiste (oder hielt nicht am Haltepunkt). Haltepunkte werden jetzt gelöscht, wenn der Text seit dem letzten Übersetzen geändert wurde (sie gelten nur für den zuletzt übersetzten Stand). Außerdem bleiben nach einem regulären Programmende keine „eingefügt“-Markierungen in der Haltepunkttabelle zurück.

### Geändert
- `.cpu` ist in den Beispielen und im Tutorial entfernt: VC65 unterstützt nur den MEGA65, der Befehlssatz 45GS02 ist der Standard. Die Direktive wird weiterhin gelesen und ignoriert, damit Quelltexte aus anderen Assemblern übersetzbar bleiben. Die Ausgabe der Beispiele ist byte-gleich zu `vcc` geblieben.

### Dokumentation
- Handbuch und Release mit echten Aufnahmen aus Xemu (vorher Bilder aus der Testumgebung).
- Das Handbuch nennt die Version nicht mehr „nicht veröffentlicht“.

### Mitarbeit
- Vorlage für Pull Requests (`.github/pull_request_template.md`).

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
