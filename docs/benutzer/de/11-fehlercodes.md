<!-- SPDX-License-Identifier: MIT-0 -->
# 11 Fehler- und Warnungscodes

Englische Fassung: [../en/11-error-codes.md](../en/11-error-codes.md). Zurück zur [Übersicht](README.md). Vorabversion 0.1.0-Alpha.

Der Assembler von VC65 meldet Fehler als `Ennn` und Warnungen als `Wnnn`, jeweils mit Zeile und Spalte. **Fehler** brechen den Bau ab (die Ausgabe ist dann nicht benutzbar), **Warnungen** nicht. Die Codes sind dieselben wie bei `vcc`, dem Assembler von VintageCoder; VC65 ergänzt eigene Codes für seine Grenzen (Bereich 9xx). Fehler stehen in der Probleme-Leiste rot, Warnungen gelb; die Statuszeile nennt den ersten Fehler (zum Beispiel `E205 line 9 col 13`).

> **Hinweis:** Die Texte der Meldungen im Programm sind englisch; die Beschreibung hier ist die deutsche Erklärung. Alles ist nur im Emulator Xemu getestet.

## Fehler

| Code | Bedeutung | Typische Ursache |
|---|---|---|
| **E201** | undokumentierter Opcode nicht erlaubt, oder der Befehl existiert auf dieser CPU nicht | Befehl einer anderen CPU, `illegals = deny` |
| **E202** | Fehler in einem Ausdruck | unbekanntes Symbol, fehlende Klammer, Division durch 0, falsche Argumentzahl einer Funktion, Liste statt Zahl |
| **E203** | Wert außerhalb des Bereichs | `lda #256`, `.org` außerhalb von 0 bis 65535, Sprung zu weit, negative Anzahl bei `.fill`, `.page 0`, Bereichsfehler bei `.lohifill` und `.lohitable` |
| **E204** | Name doppelt definiert | zwei gleiche Marken, Konstante mit neuem Wert, doppelte `.struct`, Marke in `.repeat` ohne Scope, Funktion mit dem Namen einer eingebauten Funktion |
| **E205** | unbekannter Befehl | Tippfehler, Marke ohne Doppelpunkt, Makro nicht definiert |
| **E206** | Operand passt nicht zum Befehl | `lda` ohne Operand, `sta #1`, Adressierungsart nicht vorhanden |
| **E207** | `.assert` fehlgeschlagen, `.error` erreicht oder anderes Ziel als `mega65` | eigene Prüfungen, `.target c64` |
| **E208** | falsche Schreibweise einer Direktive | fehlende Anführungszeichen, ungültiger Name, unbekannte Direktive, Textdirektive mit etwas anderem als Zeichenketten, `.lohifill` ohne Ausdruck, unbekanntes Sonderzeichen `{…}` |
| **E209** | Makro: falsche Argumentzahl oder Name wie ein Befehl | `m 1, 2` bei einem Parameter, Makro mit dem Namen eines Befehls |
| **E210** | Blockstruktur fehlerhaft | `.if` ohne `.endif`, `.macro` ohne `.endmacro`, `.break` außerhalb einer Schleife, Vorgabewert vor einem Pflichtparameter |
| **E211** | zu tief verschachtelt, oder Grenze überschritten | Makro ruft sich selbst auf, Include-Zyklus, Liste oder Name zu groß |
| **E212** | Datei nicht gefunden | falscher Name bei `.include`, `.incbin`, `.encoding` |
| **E213** | Scope-Fehler | `}` ohne `{`, Scope nicht geschlossen, Punkt im Scope-Namen |
| **E214** | anonyme Marke fehlt | `bne -` ohne `-` davor, `beq +` ohne `+` dahinter |
| **E215** | Adressmodus-Suffix passt nicht | `jmp.z`, `lda.z #1` |
| **E216** | `.set` auf etwas, das keine Variable ist | `.set` auf eine Konstante |
| **E217** | Schleife läuft zu lange | `.for` mit mehr als 65536 Durchläufen |
| **E218** | `.basicstub` nicht am Programmanfang | Bytes vor `.basicstub` |
| **E300** | Code oder Marke vor dem ersten `.org`; Symbole konvergieren nicht | `nop` in der ersten Zeile; eine Bedingung hängt von einer eigenen Adresse ab |
| **E301** | Segment überlappt oder verlässt seinen Bereich | zwei `.org` mit überlappendem Inhalt, `.segment` mit zu kleinem Bereich, Programmzähler läuft über `$FFFF` |
| **E900** | Grenze von VC65: Makro mit mehr als 16 Parametern | `vcc` kennt diese Grenze nicht |
| **E901** | Grenze von VC65: `.bank` mit einer anderen Bank als 0 | VC65 gibt nur den 16-Bit-Adressraum der Bank 0 aus |

## Warnungen

| Code | Bedeutung | Typische Ursache |
|---|---|---|
| **W104** | undokumentierter Opcode (bei `illegals = warn`) | `lax $d020` |
| **W105** | instabiler undokumentierter Opcode | `xaa` |
| **W200** | `.warning` erreicht | eigene Meldung |
| **W201** | Zyklenbudget überschritten | `.cycles … max=n` |
| **W202** | Kommazahl wurde abgeschnitten | `.byte 7 / 2.0` |
| **W203** | zu weiter Sprung automatisch verlängert | `.branchlong auto` |
| **W204** | `.basicstub` nicht an der BASIC-Startadresse des Zielsystems | `.org` an einer anderen Adresse als `$2001` |
| **W206** | Direktive wird gelesen, hat aber keine Wirkung | `.run` (beim MEGA65 ohne Wirkung) |

## Wie VC65 mit Fehlern umgeht

- Der Assembler arbeitet in mehreren Durchläufen. Bei einem Fehler merkt er sich die Meldung, überspringt den Rest der Zeile und übersetzt weiter. Die Fehlerliste gehört dem letzten Durchlauf.
- Die Probleme-Leiste zeigt bis zu drei Einträge, die Zeilen mit Fehlern sind rot gefärbt (höchstens 16 Zeilen).
- Fehler in einer Include-Datei zeigen `in file n` statt der Spalte; der Cursor springt dann nicht.

## Weitere Hinweise

- Schlägt etwas anders fehl, als hier beschrieben, vergleichen Sie mit dem Verhalten von `vcc`: VC65 soll für Quelltexte, die nur den MEGA65 betreffen, dasselbe Ergebnis liefern. Bekannte Abweichungen stehen in der Dokumentation für Entwickler (`docs/entwickler/de/vcasm-konformitaet-luecken.md`).
- Die BASIC-Übersetzung von VintageCoder hat eigene Fehlernummern ab E301; sie gehört nicht zu VC65.
