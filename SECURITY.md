# Sicherheit

## Sicherheitslücken melden

Bitte melde Sicherheitslücken **nicht öffentlich** (kein Issue, keine Pull Request), sondern privat:

- per E-Mail an **vintagecoder@drueeke.de** mit dem Betreff „Sicherheit VC65“ (gleiche Adresse wie bei VintageCoder), oder
- über die private Meldung von GitHub („Report a vulnerability“ auf der Seite *Security* des Repositorys), falls sie dort eingeschaltet ist.

Nenne bitte die Version, die Hardware (MEGA65-Modell, ROM- und Hypervisor-Version oder Emulator), eine Beschreibung und, wenn möglich, eine Schritt-für-Schritt-Anleitung zum Nachstellen. Schicke keine Zugangsdaten oder fremde urheberrechtlich geschützte Dateien (zum Beispiel ROMs) mit.

VC65 ist ein Projekt einer einzelnen Person im Entwurfsstadium. Es gibt **keine Zusage auf eine Antwortzeit** und keine Prämien für Meldungen.

## Unterstützte Versionen

Unterstützt wird nur die **jeweils neueste veröffentlichte Version**.

## Was als Sicherheitsproblem gilt

VC65 läuft lokal auf dem MEGA65, hat keinen Server und sendet keine Daten. Relevant sind zum Beispiel: Ausführung fremden Codes durch das Öffnen einer Projektdatei oder Quelldatei von der SD-Karte, Schreiben von Dateien außerhalb des Projekts oder Beschädigung der SD-Karte durch Fehler im Dateizugriff. Fehler, die nur zum Absturz oder zu falschen Ergebnissen führen, melde bitte als gewöhnlichen Fehler. Die Pakete sind nicht signiert.
