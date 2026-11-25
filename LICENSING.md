# Lizenz und freie Nutzung

Diese Seite erklärt in einfachen Worten, **was du mit VC65, mit der Sprache VCASM und mit den Dateien tun darfst, die du damit erzeugst**. Der verbindliche Teil ist Abschnitt 3 („Erklärung des Rechteinhabers“). VC65 steht unter **derselben Lizenz und denselben Zusagen wie VintageCoder** (GPL-3.0-or-later mit zusätzlicher Erlaubnis, MIT-0 für Systemdateien, Vorlagen und Beispiele, CC0-1.0 für eigene Zeichensätze); der Wortlaut folgt dem von VintageCoder und bleibt mit ihm gleichgerichtet.

## 1. Kurzfassung

- **Was du mit VC65 baust, gehört dir.** Programme, Quelltexte, Diskettenabbilder, Grafiken, Musik und alle anderen Dateien, die du mit VC65 erzeugst, darfst du beliebig verwenden und weitergeben: auch **kommerziell**, auch **ohne deinen Quelltext offenzulegen**, auch **ohne einen Hinweis auf VC65**.
- **Die Sprache VCASM ist frei.** Ihre Syntax und Bedeutung (Befehle, Direktiven, Ausdrücke, Makros) und die Dateiformate darf jeder in eigenen Werkzeugen umsetzen, unabhängig von der Lizenz von VC65.
- **Die GPL gilt für den Quelltext von VC65 selbst.** Wer dieses Programm ändert und weitergibt, beachtet die GNU General Public License, Version 3 oder später.

## 2. Fragen und Antworten

**Darf ich ein Spiel verkaufen, das ich mit VC65 gebaut habe?**
Ja. Das Spiel unterliegt keiner Lizenz von VC65. Ausnahme sind Fremdanteile, die du selbst einbindest (zum Beispiel Musik, Bilder und ROMs Dritter).

**Muss ich meinen Quelltext veröffentlichen?**
Nein. Das gilt für deine eigenen Quelltexte und für die Programme, die VC65 daraus erzeugt.

**Darf ich die mitgelieferten Systemdateien, Vorlagen und Beispiele in meine Programme übernehmen?**
Ja. Systemdateien, Vorlagen und Beispielprojekte von VC65 (sobald vorhanden) stehen unter der **MIT-No-Attribution-Lizenz (MIT-0)**: Du darfst sie ohne Auflagen verwenden, ändern und weitergeben, auch ohne Urheberhinweis.

**Darf ich einen eigenen Assembler oder Editor bauen, der VCASM versteht?**
Ja. Die Sprache und die Dateiformate sind frei. Du darfst dazu aber keinen Quelltext aus VC65 übernehmen, außer unter den Bedingungen der jeweiligen Lizenz der Dateien (GPL für das Programm, MIT-0 für die Systemdateien, Vorlagen und Beispiele).

**Darf ich VC65 ändern und meine Fassung weitergeben?**
Ja, unter der GPL: Du gibst den Quelltext deiner Fassung ebenfalls unter der GPL weiter und lässt die Lizenzhinweise stehen.

**Darf ich die Namen und das Logo „VC65“ verwenden?**
Der Name „VC65“ nur als wahrheitsgemäße Herkunftsangabe (zum Beispiel: ein Programm wurde mit VC65 gebaut). Das Logo darf als Verweis auf VC65 (Referenz) verwendet werden, zum Beispiel neben einem Link oder in einer Quellenangabe, auch skaliert oder einfarbig. Es darf nicht anderweitig verändert, nicht als Zeichen eines anderen Produkts verwendet und nicht so eingesetzt werden, dass der Eindruck einer Zugehörigkeit oder Billigung entsteht. Die Logo-Dateien liegen unter `branding/`; der Entwurf des Logos selbst gehört nicht zu den frei veränderbaren Teilen.

**Was ist mit ROMs, Zeichensätzen, Musik und Bildern?**
Für Inhalte, die du selbst einbindest, bist du verantwortlich: Rechte Dritter bleiben bestehen. VC65 liefert **keine ROMs** mit. Mitgelieferte eigene Zeichensätze stehen unter **CC0-1.0**.

## 3. Erklärung des Rechteinhabers

**VC65** (die native Entwicklungsumgebung für den MEGA65 und alle zugehörigen Werkzeuge) steht unter der GNU General Public License, Version 3 oder später (`GPL-3.0-or-later`, siehe [LICENSE](LICENSE)). Der Rechteinhaber erklärt darüber hinaus **ausdrücklich und unwiderruflich** (zusätzliche Erlaubnis nach Abschnitt 7 der GPLv3):

**1. Ausgaben sind frei.** Alle Dateien, die mit VC65 erzeugt werden, gehören dem Anwender und sind vollkommen frei nutzbar: übersetzte Programme (zum Beispiel PRG, BIN), Diskettenabbilder, Quelltexte (Assembler), Projekt- und Assetdateien (zum Beispiel `.vcprj`), Berichte, Protokolle und alle sonst erzeugten Dateien. Sie unterliegen nicht der GPL und keiner anderen Beschränkung durch den Rechteinhaber; der Anwender darf sie beliebig, auch kommerziell und auch ohne Offenlegung des Quelltextes, verwenden, verändern und weitergeben.

**2. Eingefügte Teile sind eingeschlossen.** Das gilt auch für Teile, die VC65 beim Übersetzen oder Erzeugen aus eigenen Beständen in die Ausgabe einsetzt oder einbindet: Systemdateien, Vorlagen, Bibliotheks- und Laufzeitroutinen, Tabellen, Kopfzeilen und erzeugte Textbausteine.

**3. Die Sprache ist frei.** Die Syntax und die Bedeutung des VCASM (Befehle, Direktiven, Ausdrücke, Makros, Kennzeichnungen) sowie die Dateiformate der Projekt-, Asset- und Austauschdateien sind frei nutzbar. Jeder darf sie in eigenen Werkzeugen (Assemblern, Editoren, Konvertern, Emulatoren) umsetzen oder unterstützen, unabhängig von der Lizenz von VC65. Der Rechteinhaber macht keine Rechte an der Sprache und den Formaten geltend, auch keine Patent- und Markenrechte an der Syntax als solcher.

**4. Die Werkzeuge dürfen frei aufgerufen werden.** Die Verwendung der Werkzeuge von VC65, soweit sie von außen aufrufbar sind (über Kommandozeile, Dateien, Standardein- und -ausgabe oder Schnittstellenprotokolle), begründet kein abgeleitetes Werk. Aufrufende Programme dürfen jeder Lizenz unterliegen.

**5. Was unberührt bleibt.**
- (a) Der Quelltext von VC65 selbst bleibt unter der GPL; wer ihn ändert und weitergibt, beachtet die GPL.
- (b) Rechte Dritter an Inhalten, die der Anwender einbindet (zum Beispiel ROMs, fremde Zeichensätze, Musik, Bilder, Disketten), bleiben unberührt; dafür ist der Anwender selbst verantwortlich.
- (c) Namen und Marken (zum Beispiel „VC65“) bleiben geschützt, soweit sie es sind; die freie Nutzung der Syntax und der Ausgaben schließt die Nutzung des Namens als Herkunftsangabe nicht ein. Für das Logo gilt: Das Logo darf als Verweis auf VC65 (Referenz) verwendet werden, zum Beispiel neben einem Link oder in einer Quellenangabe, auch skaliert oder einfarbig. Es darf nicht anderweitig verändert, nicht als Zeichen eines anderen Produkts verwendet und nicht so eingesetzt werden, dass der Eindruck einer Zugehörigkeit oder Billigung entsteht.

**5a. Fremde Anteile.** Diese Erklärung erfasst nicht Quelltext, der von Dritten stammt und unter einer eigenen Lizenz steht. Wer ein Programm weitergibt, das solchen Quelltext enthält, muss die Bedingungen der jeweiligen Lizenz einhalten. Der Rechteinhaber erteilt für fremde Anteile keine zusätzlichen Erlaubnisse. Derzeit enthält VC65 keine Fremdanteile (siehe [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)).

**6. Wirkung.** Diese Erklärung gilt ab ihrer Veröffentlichung für alle früheren und künftigen Fassungen, soweit der Rechteinhaber über die Rechte verfügt; sie ergänzt die Lizenz und ersetzt sie nicht.

## 4. Welche Lizenz gilt wo?

| Teil | Lizenz | Hinweis |
|---|---|---|
| Programm (VCASM-Quelltext von VC65, Werkzeuge und Skripte) | `GPL-3.0-or-later` | Kopfzeile `SPDX-License-Identifier` in den Dateien; zusätzliche Erlaubnis nach Abschnitt 3 |
| Systemdateien, Vorlagen und Beispiele (sobald vorhanden, eigene Ordner mit Datei `LICENSE`) | `MIT-0` | frei einsetzbar, auch ohne Urheberhinweis |
| Eigene Zeichensätze (sobald vorhanden) | `CC0-1.0` | wie bei VintageCoder |
| Name | nur als Herkunftsangabe | siehe Abschnitt 3, Punkt 5(c) |
| Logo | nur als Verweis (Referenz), auch skaliert oder einfarbig; sonst unverändert | siehe Abschnitt 3, Punkt 5(c) |
| Abhängigkeiten (Bibliotheken, Fremdcode) | jeweils eigene Lizenz | siehe [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) |

Der Lizenztext der MIT-No-Attribution-Lizenz steht in [LICENSES/MIT-0.txt](LICENSES/MIT-0.txt), der der GPL in [LICENSE](LICENSE).

## 5. Bezug zu VintageCoder

VC65 ist eine eigene Entwicklung, die aus dem Repository von VintageCoder hervorgegangen ist; es gelten **dieselben Lizenzen und Zusagen**. Die Zusagen zur freien Nutzung von VCASM, der Dateiformate und der Ausgaben gelten für beide Werkzeuge gleich. Änderungen am Wortlaut dieser Seite werden mit der Seite von VintageCoder abgestimmt.

## 6. Kein Rechtsrat, keine Gewähr

Diese Seite erklärt die Absicht des Rechteinhabers in einfachen Worten und ist **keine Rechtsberatung**. Im Zweifel gilt der Wortlaut der Lizenztexte und der Erklärung in Abschnitt 3. VC65 wird ohne jede Gewährleistung bereitgestellt (siehe [LICENSE](LICENSE)). Die rechtliche Prüfung der Texte durch einen Anwalt steht noch aus.

Fragen zur Lizenz: siehe [README.md](README.md).
