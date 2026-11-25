<!-- SPDX-License-Identifier: MIT-0 -->
# Bildschirmfotos

Stand 2026-11-25. Echte Aufnahmen der IDE, laufend **in Xemu** (nicht am echten MEGA65), 800 × 625 Pixel, 50-Zeilen-Bild (80 × 50, VIC-IV V400, so startet die IDE auf dem Gerät), englische Texte des Programms, Farbschema der IDE. Erzeugt mit `tools/screens.py --50 [Ordner]` (Xemu speichert mit `-screenshot` beim Beenden ein PNG; die Szenen laufen aus Tastenskripten, `SCENES=about,fehler` wählt einzelne Szenen). Die Beispielquelle ist ein kleines Programm, das die Rahmenfarbe durchläuft.

> **Ist-Stand, nicht Zielbild.** Diese Aufnahmen zeigen die IDE, wie sie heute läuft (Befehlsleiste, Dateizeile, Probleme-Leiste, Menüs mit Aufklappfeldern). Das geplante Aussehen zeigen die Entwürfe in `../mockups/` (Entwurf, noch nicht gebaut). Beides muss in der Außendarstellung getrennt beschriftet werden: „heutiger Stand (Xemu)“ und „Entwurf“.

| Datei | Szene |
|---|---|
| `vc65-editor-50.png` | Editor mit Färbung (Kommentar, Direktiven, Mnemonik, Zahlen, Marken), Zeilennummern, Dateizeile, Probleme-Leiste, Statuszeile |
| `vc65-uebersetzen-50.png` | Strg+E: „OK 21 bytes“ in der Statuszeile |
| `vc65-fehler-50.png` | Fehler: „E205 line 9 col 13“ in Probleme-Leiste und Statuszeile, der Cursor springt in die Zeile |
| `vc65-menue-50.png` | geöffnetes Menü (Edit) |
| `vc65-about-50.png` | Startbild und File > About VC65: Logo als Blockbild, Version |
| `vc65-projekt-50.png` | die ersten 46 Zeilen des Beispiels `jumprun`, volle Bildhöhe (falls vorhanden) |
| `vc65-debugger.png` | Debugger: Register, Flags, Disassemblierung, Quelltextzeile, Stapel, Speicher (PC `$2013`) |
