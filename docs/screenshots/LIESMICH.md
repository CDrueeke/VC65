<!-- SPDX-License-Identifier: MIT-0 -->
# Bildschirmfotos

Stand 2026-11-26 (0.1.1-alpha). Echte Aufnahmen der IDE aus dem Emulator **Xemu** (nicht vom echten MEGA65), 640 × 400 Pixel (der Bildschirm ohne PAL-Rand), 50-Zeilen-Bild (80 × 50), englische Texte des Programms, Farbschema der IDE. Sie wurden mit der veröffentlichten Boot-Diskette aufgenommen (Quelle `hello.asm` und `prallball.asm` von der Beispiel-Diskette); nur das About-Bild entstand mit `tools/screens.py --50` (Szene `about`, Ausschnitt 640 × 400 ab Pixel 80/104), weil der Fehler im Startbild mit geladener Datei erst in 0.1.1-alpha behoben ist.

> **Ist-Stand, nicht Zielbild.** Die Aufnahmen zeigen die IDE, wie sie heute läuft. Das geplante Aussehen zeigen die Entwürfe in `../mockups/` (privat, nicht Teil der öffentlichen Fassung). In der Außendarstellung beides getrennt beschriften: „heutiger Stand (Xemu)“ und „Entwurf“.

| Datei | Szene |
|---|---|
| `vc65-editor-50.png` | Editor mit Färbung, Zeilennummern, Dateizeile, Probleme-Leiste, Statuszeile |
| `vc65-uebersetzen-50.png` | Strg+E: Erfolgsmeldung in der Statuszeile |
| `vc65-fehler-50.png` | Fehler (E205, Zeile 34): Probleme-Leiste und Statuszeile, der Cursor springt in die Zeile |
| `vc65-menue-50.png` | geöffnetes Menü |
| `vc65-about-50.png` | File > About VC65: Logo als Blockbild, Version (Text dahinter abgedunkelt) |
| `vc65-projekt-50.png` | Beispiel `prallball`, volle Bildhöhe |
| `vc65-debugger.png` | Debugger: Register, Flags, Disassemblierung, Quelltextzeile, Stapel, Speicher |
