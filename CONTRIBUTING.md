# Mitarbeit

VC65 ist ein Projekt einer einzelnen Person im Entwurfsstadium. Hinweise und Fehlermeldungen sind willkommen; Verhalten: siehe [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Sicherheitsmeldungen: siehe [SECURITY.md](SECURITY.md).

## Regeln für Quelltext

- Jede Quelldatei beginnt mit `; SPDX-License-Identifier: GPL-3.0-or-later` (VCASM) bzw. `// …` oder `# …` in anderen Sprachen und Skripten. **Ausnahme:** Systemdateien, Vorlagen und Beispiele (eigene Ordner, sobald vorhanden) tragen `SPDX-License-Identifier: MIT-0` (Ordnervermerk in der Datei `LICENSE` des Ordners).
- Keine Abhängigkeiten ohne Not; Fremdcode, Daten oder Schriften brauchen eine mit der GPL-3.0 vereinbare Lizenz und stehen in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md), bevor sie ins Repository kommen.
- Änderungen an VCASM-Sprache, `.vcprj`-Format oder Konformitätsbeispielen werden mit VintageCoder abgestimmt (Konzept, Abschnitt 20) und im [Änderungsprotokoll](CHANGELOG.md) beider Seiten vermerkt.

## Lizenz der Beiträge

VC65 steht unter der **GNU General Public License, Version 3 oder später** (`GPL-3.0-or-later`, siehe [LICENSE](LICENSE)), mit den zusätzlichen Zusagen aus [LICENSING.md](LICENSING.md). Mit einem Beitrag erklärst du dich einverstanden, dass er unter dieser Lizenz veröffentlicht wird, und bestätigst, dass du ihn selbst geschrieben hast oder die Rechte dafür besitzt. **Beiträge zu Systemdateien, Vorlagen und Beispielen** kommen unter der **MIT-0-Lizenz** (siehe `LICENSES/MIT-0.txt`), damit sie frei in eigene Programme eingesetzt werden können.
