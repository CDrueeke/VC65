<!-- SPDX-License-Identifier: MIT-0 -->
# Entwurf: Lücken von VC65 gegen VCASM (Ziel 100 % Konformität)

Stand 2026-11-24, **Entwurf** auf Anfrage der Hauptsession (nur Analyse; keine VCASM-Änderung, nicht eingecheckt, nicht gepusht). Gegenprobe: `vcc` 2caec744 (`tools/vcc.version`), Ziel `mega65`, Datenstand `directives.json` und `docs/diagnostik-codes.md` aus der Arbeitskopie claude/tauri-ui. Alle Läufe des nativen Assemblers in Xemu (nicht am echten MEGA65).

## 0 Kurzfassung
1. **Definition (Kommentar):** Ich stimme zu, mit zwei Schärfungen. (a) Zulässige Abweichungen sind nur *Ressourcengrenzen* des Geräts; fehlende Funktionen (`.bank`, `.segment`, `.cartridge`, `.atascii`, Medien-Include, E301/E217-Prüfungen …) sind **Lücken**, keine Grenzen, und werden geschlossen oder von dir als Ausnahme entschieden. (b) Die Ressourcengrenzen brauchen je eine Zahl und ein Fehlerverhalten: eine Überschreitung muss einen **eigenen, eindeutigen Code** liefern (VC65 verwendet ab **E900**), nie einen Code, der bei `vcc` etwas anderes bedeutet. Das ist mir selbst unterlaufen: mein erster Code für „zu viele Makroparameter“ war E301, bei `vcc` bedeutet E301 „Segment überschreitet $FFFF“. Ich habe ihn auf **E900** geändert (lokal committet).
2. **Befund Direktiven:** von 53 Direktiven sind 25 im Korpus ohne Befund, 24 teilweise (meist Fehlerfälle), **4 nicht vorhanden**: `.atascii`, `.bank`, `.cartridge`, `.segment`. Aliase, `=`, `*=`, `{`/`}`, `#include` sind vorhanden.
3. **Befund Korpus:** 494 Schnipsel aus den Tests von vc-asm (ohne 21 Testvorlagen mit `{name}`-Platzhaltern): bei 206 Schnipseln, die `vcc` übersetzt, sind **185 byte-gleich** (89 %), 20 lehnt VC65 ab (fehlende Funktionen), 1 liefert andere Bytes. Bei 288 Schnipseln, die `vcc` ablehnt, melden 155 (davon 129 genau) dieselben Codes in derselben Zeile, 42 einen allgemeinen Syntaxfehler (E201) in der richtigen Zeile, 31 nimmt VC65 an, 60 andere Codes.
4. **Antwort `.hex`:** VC65 unterstützt `.hex` (byte-gleich zu `vcc`). Gemessen in Xemu bei 40 MHz, 2048 Byte, alle Durchläufe zusammen: eine `.hex`-Zeile mit 4096 Ziffern **0,03 s**; 128 `.hex`-Zeilen zu 32 Byte 0,04 s; 128 `.byte`-Zeilen zu 16 Werten 0,11 s; 2048 `.byte`-Zeilen zu 1 Wert 0,32 s. `.hex` ist also rund viermal schneller als `.byte`-Zeilen und auch die größte Datenmenge der Beispiele (`chars` 2 KB) übersetzt in Hundertstelsekunden.
5. **Medien-Include als Assembler-Text:** machbar mit sehr kleinem Aufwand (der E219-Zweig entfällt, der Include liest Assemblertext), **wenn** der Dateiname auf die D81 passt: D81-Namen haben höchstens 16 Zeichen (`hero_over.vcsprite` hat 18). Dafür braucht der Lader eine Namensabbildung (zum Beispiel Endung weglassen, wie bei den Systemdateien); siehe 4.

## 1 Methode
- `tools/vcasm_corpus.py extract` zieht die Quelltext-Schnipsel aus `crates/vc-asm/tests/*.rs` und `src/lib.rs` (515, dedupliziert); `run` übersetzt jedes mit `vcc` und mit dem nativen Assembler (Xemu) und vergleicht Bytes, Fehlercodes mit Zeile und Warncodes; `bericht` klassifiziert. Ergebnis: `build/corpus/ergebnis.jsonl`. Dauer rund 8 Minuten.
- Bestehende Prüfungen bleiben: `tools/conform.py` (67 Beispiele der VCASM-Hilfe: 61 identisch, 2 nativ fehlend, 4 von `vcc` nicht übersetzbar), `tools/examples.py` (7 Beispielprojekte byte-gleich), `tools/errtest.py`, `tools/selfhost.py`.
- Grenzen der Methode: Schnipsel ohne `.org` liefern bei beiden E300 (gleich), verdecken aber Folgefehler; Rust-Tests mit Zielsystemen anderer Art (Atari, Cartridge) laufen hier auf Ziel `mega65`.

## 2 Direktiven (53 aus `directives.json`)
Status: ok = im Korpus ohne Befund; teilweise = Gutfälle identisch, Fehlerfälle oder Sonderformen weichen ab; nicht = fehlt. „Korpus“ zählt Schnipsel, in denen die Direktive vorkommt (oft mit anderen zusammen), und davon abweichende.

| Direktive | Aliase / Ende | Gruppe | Status | Korpus (Schnipsel / abweichend) | Befund |
|---|---|---|---|---|---|
| `.org` | *= | address | teilweise | 344 / 76 | Adresse > $FFFF (`.org 70000`) wird nicht als E203 gemeldet; Segmentüberlauf E301 fehlt (Schnipsel 447, 482) |
| `.align` | .page | address | teilweise | 19 / 5 | `.align 256, skip` hinter Code meldet nativ E203, `vcc` übersetzt (68, 115); Füllwert > 255 und Zahl 0 stimmen |
| `.relocate` | .pseudopc, .endrelocate, .realpc, .endpseudopc | address | ok | 11 / 6 | – |
| `.bank` | – | segment | nicht | 13 / 13 | Direktive fehlt (E208): 13–15, 24, 30, 31, 34, 35, 43, 480 |
| `.segment` | – | segment | nicht | 6 / 5 | Direktive fehlt (E208): 16–20, 491 |
| `.cartridge` | – | segment | nicht | 7 / 6 | Direktive fehlt (E208): 21, 29, 39, 143, 151, 152, 402 |
| `.byte` | .db | data | ok | 90 / 15 | – |
| `.word` | .dw, .addr | data | ok | 23 / 4 | – |
| `.dword` | .long | data | ok | 8 / 2 | – |
| `.be16` | .dbyt | data | ok | 8 / 2 | – |
| `.be32` | – | data | teilweise | 4 / 2 | Wert > 32 Bit: `vcc` E203, nativ ohne Meldung (123) |
| `.retaddr` | .rta | data | ok | 9 / 2 | – |
| `.hex` | – | data | ok | 3 / 2 | – |
| `.fill` | – | data | teilweise | 17 / 2 | negative Anzahl: `vcc` E203, nativ ohne Meldung (449) |
| `.incbin` | – | data | ok | 2 / 1 | im Korpus ohne Befund (kleine Schnipsel) |
| `.lohitable` | .lohifill | data | teilweise | 15 / 6 | wie `.lohifill` |
| `.text` | – | text | teilweise | 11 / 2 | `{name}`-Zeichencodes in Zeichenketten (`.text "a{down}"`) nicht unterstützt (385) |
| `.textnull` | .null | text | ok | 12 / 2 | – |
| `.textlen` | .ptext | text | ok | 9 / 4 | – |
| `.textshift` | .shift | text | teilweise | 10 / 5 | wie `.shift` (88) |
| `.screencode` | .screen | text | teilweise | 11 / 2 | UTF-8-Bytes $C0–$DF werden bei `vcc` um $80 verschoben ($C3 → $43), nativ nicht |
| `.petscii` | – | text | ok | 7 / 2 | Zeichencodes `{..}`: im Korpus identisch; Fehlerfälle nativ nur Syntaxfehler statt E208 |
| `.atascii` | – | text | nicht | 3 / 2 | Direktive fehlt (E208): 274, 275, 387 |
| `.encoding` | – | text | ok | 15 / 3 | – |
| `.const` | .equ, = | const | ok | 8 / 3 | – |
| `.var` | – | var | ok | 17 / 1 | – |
| `.set` | – | var | ok | 4 / 1 | – |
| `.function` | – | function | teilweise | 13 / 4 | Name einer eingebauten Funktion (`sin`) nativ ohne E204 (332, 456); `.function g = 1` nativ Syntaxfehler statt E208 (334) |
| `.if` | .endif | conditional | teilweise | 13 / 6 | `.if` ohne `.endif` am Dateiende: `vcc` E210, nativ keine Meldung (201, 470) |
| `.ifdef` | .endif | conditional | teilweise | 12 / 5 | ohne Argument/ohne Ende: `vcc` E210, nativ keine Meldung (155) |
| `.ifndef` | .endif | conditional | teilweise | 12 / 5 | wie `.ifdef` (156) |
| `.elseif` | – | conditional | ok | 2 / 1 | – |
| `.else` | – | conditional | ok | 4 / 2 | – |
| `.repeat` | .endrepeat | loop | ok | 10 / 1 | – |
| `.for` | .endfor, .next | loop | teilweise | 29 / 10 | unvollständige Schleife: `vcc` E210/E208/E217, nativ andere Zeile oder allgemeiner Syntaxfehler (105, 320–323, 464, 465) |
| `.break` | – | loop | ok | 8 / 1 | – |
| `.continue` | – | loop | ok | 2 / 0 | – |
| `.macro` | .endmacro | macro | teilweise | 21 / 7 | ohne `.endmacro`: Code stimmt, Zeile weicht ab (468, 469); `.macro nop` (Befehlsname) nativ ohne E209 (204); Vorgabewert vor Pflichtparameter nativ ohne E210 (286) |
| `.exitmacro` | – | macro | ok | 4 / 0 | – |
| `.struct` | .endstruct | struct | teilweise | 15 / 4 | doppelter Name E204 nativ nicht gemeldet (375); Feld ohne Typ nativ Syntaxfehler (376–378) |
| `.enum` | .endenum | struct | teilweise | 5 / 2 | unvollständig: nativ Syntaxfehler statt E210 (377) |
| `.scope` | {, .endscope, } | scope | ok | 2 / 1 | – |
| `.namespace` | .endscope, } | scope | ok | 3 / 1 | – |
| `.include` | #include | files | teilweise | 10 / 4 | `as`-Namensraum (`#include <..> as c128`, 234) und Systemdateien anderer Ziele (`<c64/…>`, `<atari8bit/…>`, `<c128/…>`: nicht auf der Systemdisk, 211, 212, 280) fehlen; Fehlercodes bei falscher Form: nativ E201/E212 statt E208 |
| `.basicstub` | – | start | teilweise | 17 / 4 | Zusatzargumente (Zeilennummer, Text, `.basicstub start, 10, "a{$41}"`) werden nativ ignoriert: andere Bytes (400); ohne `.org` meldet nativ E300+E202, `vcc` übersetzt (139) |
| `.run` | – | start | teilweise | 13 / 3 | gelesen, ohne Wirkung (W206 wie `vcc` für mega65); mit `.cartridge`/`.bank` siehe dort |
| `.assert` | – | check | ok | 0 / 0 | – |
| `.error` | – | check | ok | 3 / 0 | – |
| `.warning` | – | check | teilweise | 1 / 1 | wird nativ überlesen: kein W200 mit dem Text (513) |
| `.cycles` | .endcycles | cycles | teilweise | 5 / 1 | Argument `irq max=LIMIT` mit Konstanten: Fehlerfall (207) nativ andere Meldung |
| `.target` | – | target | teilweise | 1 / 1 | nur `mega65`; andere Ziele melden E207 (Entscheidung, kein Fehler) |
| `.cpu` | – | target | teilweise | 2 / 1 | Optionen (`{ illegals = … }`) werden gelesen und ignoriert; Fehler bei fehlendem Namen nativ ohne Meldung (510) |
| `.branchlong` | – | branch | teilweise | 7 / 2 | ungültiger Wert (`vielleicht`) und fehlender Wert: nativ ohne E208 (359, 507) |

Nicht in der Tabelle, aber geprüft: `=` (Konstante), `*=` (Alias von `.org`), `{`/`}` (Scope), `#include` – vorhanden; `.cpu`-Optionen und `.encoding`-Namen siehe oben.

**Ausdrücke und Operatoren, Makros, Funktionen:** die Beispiele der Hilfe (`conform.py`) und die Selbstübersetzung (14 000 Zeilen, `selfhost.py`) laufen byte-gleich. Bekannte Unterschiede in der Rechnung: Kommazahlen sind **Festkomma 32.32** (nicht IEEE-Double; Abweichung nur in Grenzfällen um ein Bit, `docs/entwickler/de/n4-assembler-stufe2.md`), Ganzzahlen **32 Bit** (`vcc`: 64 Bit). Das wäre nach deiner Definition eine Ressourcengrenze (Speicher/Rechenzeit der 8-Bit-CPU) und gehört samt Zahlenbereich ins Handbuch. Größenzusätze bei Befehlen (`lda.abs`, `lda.zp`, `ldx.z`, `bne.a`) fehlen (Schnipsel 250, 252, 254, 255, 478): **Lücke**.

## 3 Fehler- und Warncodes (`diagnostik-codes.md`, Assembler: 30 Codes mit 161 Varianten)
| Code | Bedeutung bei `vcc` | VC65 |
|---|---|---|
| E201 | Befehl gibt es auf dieser CPU nicht | nativ nur als allgemeiner Syntaxfehler (wird als E201 angezeigt) |
| E202–E206, E209, E211–E216, E218, E300 | Ausdruck, Adresse, Namen, Operanden, Makro, Datei, Scope, Marke, Basicstub, Code vor `.org` | vorhanden, im Korpus überwiegend gleich |
| E207 | Assertion | vorhanden |
| E208 | Zuweisung/Argument erwartet (35 Varianten) | **teilweise**: oft allgemeiner Syntaxfehler (18 Schnipsel) |
| E210 | Block ohne Ende (`.struct`/`.enum`/`.if`/`.for`/`.macro` …, 11 Varianten) | **teilweise**: nativ fehlt die Prüfung am Dateiende bei `.if`, `.ifdef`; Zeile weicht ab (10 allgemeiner Syntaxfehler) |
| E217 | zu viele Schleifendurchläufe | **fehlt** (321) |
| E301 | Segment überschreitet $FFFF | **fehlt** (447, 482); wegen der fehlenden Segmente |
| W104, W105 | undokumentierter Opcode | nicht anwendbar auf mega65 (45GS02 hat keine) |
| W200 | `.warning` mit Text | **fehlt** (`.warning` wird überlesen) |
| W201 | Zyklenbudget überschritten | vorhanden |
| W202 | Kommazahl abgeschnitten | **fehlt** |
| W203 | Sprung zu weit, lange Form | Bytes stimmen, Warnung **fehlt** |
| W204, W206 | `.basicstub`/`.run` | vorhanden |
| W205, W207 | `.basicstub` ohne BASIC-Zeile, Programm ohne Startvektor | **fehlt** |
Eigene Codes von VC65 (bei `vcc` nicht definiert): E219 (Medien-Include, vorübergehend), **E900** (Makro mit mehr als 16 Parametern). Empfehlung: E219 ebenfalls in den VC65-Bereich verlegen oder bei VintageCoder reservieren, damit `vcc` den Code später nicht anders belegt.

## 4 Bekannte Abweichungen mit Aufwand und Platz
Platz im Hauptprogramm heute: **237 Byte** unter `$D000` (BASIC lädt nicht darüber); `VC65T` und das Overlay sind fast voll. Aufwandsangaben sind Schätzungen (Bytes Code im Assembler, soweit nicht anders vermerkt).

| Nr | Abweichung | Art | Aufwand | Platz |
|---|---|---|---|---|
| 1 | Medien-Include E219 (`.include "hero.vcsprite"`) | Lücke | klein, **wenn** die Medien als Assemblertext mit Marken exportiert werden (`.hex`, so wie ihr denkt): der E219-Zweig entfällt, Namensabbildung im Lader für D81-Namen über 16 Zeichen (+ rund 30 Byte). Ohne Textexport: groß | negativ (Code entfällt) bis +30 B |
| 2 | Nicht-ASCII in Labels, Konstanten (E205) | Lücke | klein: Bytes ≥ $80 als Bezeichnerzeichen; nur exakt, wenn `vcc` dieselbe Zeichenklasse hat (Unicode-Buchstaben; für 100 % bei Symbolen wie „ – € ein Fehler wie bei `vcc`, der Code dafür fehlt) | rund 15 B (nur ≥ $80); exakt: Tabelle, nicht bezahlbar |
| 3 | Zeichenliteral `'ü'` (E201) | Lücke | klein bis mittel: UTF-8 lesen, Wert = Codepunkt bis 255 (`vcc`: `'ü'` = $FC, `'€'` E203) | rund 40 B |
| 4 | `.screencode` mit UTF-8 | Lücke | klein: Bytes $C0–$DF um $80 verschieben (`vcc`: $C3 → $43, $CE → $4E, sonst unverändert; geprüft an ä Ω ж € 😀) | rund 10 B |
| 5 | Makro-Grenze 16 / E900 | Ressource | Zahl erhöhen: je Parameter 32 B (`ptbl`) + 5 B (`argtbl`); 32 Parameter = +512 B, nur nach Auslagerung der Tabelle (zum Beispiel nach `VC65T`, das jedoch voll ist) | heute nicht frei |
| 6 | `.target` nur `mega65` (E207 bei anderen Zielen) | Entscheidung | – (kein Aufwand, Beschluss vom 2026-11-24) | – |
| 7 | `.bank`, `.segment`, `.cartridge` | Lücke | **groß**: Segmentmodell (Namen, Grenzen, E301), Ausgabe mehrerer Segmente (heute ein PRG), `.cartridge`-Typen; `vcc` übersetzt sie auch für Ziel mega65 | rund 600–1000 B + Daten; **nicht ohne neuen Platz** |
| 8 | `.atascii` und `{name}`-Zeichencodes in `.text` | Lücke | mittel (Namenstabelle für ATASCII/PETSCII-Codes erweitern; `charnames.asm` hat 297 B für PETSCII) | rund 300 B + Tabelle |
| 9 | Größenzusätze `.abs/.zp/.z/.a` | Lücke | klein bis mittel (Operandenparser) | rund 80 B |
| 10 | E210 am Dateiende, E208-Formen, E217, E301, W200, W202, W203, W205, W207 | Lücke | mittel in Summe (jeweils einzelne Prüfungen und Meldungen); Fehlerzeile `vcc` = Anfang des Blocks | rund 300–500 B |
| 11 | `.basicstub` mit Zeilennummer und Text | Lücke | klein (Argumente lesen, BASIC-Zeile bauen) | rund 100 B |
| 12 | `.align` mit `skip` hinter Code, `.org`/`.fill` mit Wertbereich E203 | Lücke | klein | rund 60 B |
| 13 | Systemdateien anderer Ziele (`<c64/…>`, `<atari8bit/…>`) | Ressource | Platz auf der Disk, kein Code: die Disk hat 800 KB, die Systemdateien aller Ziele sind klein | nur Disk |
| 14 | Festkomma 32.32 statt Double, Ganzzahlen 32 Bit | Ressource | dokumentiert; exakte Double-Arithmetik ist auf dem 45GS02 nicht bezahlbar | – |

**Gesamtbild:** die Punkte 2 bis 4, 9, 11 und 12 lassen sich mit zusammen rund 300 B schließen und kommen den Platz-Reserven nahe; 7, 8 und 10 brauchen neuen Platz. Vorschlag: zuerst Platz schaffen (Assembler-Tabellen und Hilfstexte in eine zweite Datei auslagern, zum Beispiel einen **Assembler-Overlay-Teil**), dann in der Reihenfolge 4, 2/3, 12, 11, 9, 10, 8, 7 arbeiten und nach jedem Schritt den Korpus (`tools/vcasm_corpus.py`) erneut fahren.

## 5 Fragen an dich
1. Soll der Korpus (`vcasm_corpus.py`) aus den Rust-Tests dauerhaft als Konformitätsmaß gelten? Besser wäre eine von VintageCoder bereitgestellte Liste „Quelltext, erwartete Bytes oder Codes“ ohne Rust-Auszug.
2. Die Medien-Exportdateien als Assemblertext: welche Dateinamen auf der D81 (16 Zeichen) und welche Marken, damit `.include "x.vcsprite"` bei `vcc` und VC65 dasselbe Ergebnis hat?
3. Gilt eine **Zeilenabweichung bei gleichem Fehlercode** (zum Beispiel E210 am Dateiende statt am Blockanfang) als Konformitätsfehler?
4. E219 in einen VC65-Bereich (E9xx) legen?

## 6 Gewollte Abweichungen der mitgelieferten Beispiele
Die Beispiele in `examples/` sind Kopien der VintageCoder-Beispiele und weichen bewusst in zwei Punkten ab (Entscheidung des Inhabers); das VintageCoder-Original bleibt unverändert:
1. **prallball:** Die Titelzeile heißt „ein demospiel von vc65“ statt „… von vintagecoder“ (Programmdaten, 32 Zeichen mittig; die Bytes weichen vom Original ab).
2. **`.target` entfernt** (alle Beispiele): Das Ziel kommt aus der Projektdatei. `tools/examples.py` prüft die Kopien ohne `.target` gegen `vcc` und findet keinen Unterschied zum nativen Assembler.

## 7 Befunde aus der Quelltext-Durchsicht (2026-11-24)
Beim ausführlichen Kommentieren sind mögliche Fehler gemeldet worden; ein Test gegen `vcc` mit je einem kleinen Quelltext hat geklärt, was echt ist:
- **`exp(x)`, behoben:** große positive Werte (zum Beispiel `exp(100)`) wurden ohne Fehler übersetzt, große negative (`exp(-100)`) lieferten fälschlich E203. Jetzt wie `vcc`: positiv ab k >= 31 E203, negativ ab |k| > 63 das Ergebnis 0. Bei `exp(20)`, `exp(10)`, `exp(0)`, `exp(-5)`, `exp(-30)` unverändert gleich.
- **`pow(0.0, 0.0)` in Kommaschreibweise, offen:** `vcc` liefert 1, VC65 0 (die Ganzzahlform `pow(0, 0)` stimmt). Korrektur kostet rund 20 Byte im Hauptprogramm, das nur noch wenig Platz hat; wird mit der Auslagerung der Assembler-Teile in Overlays nachgeholt.
- **Listen (`t[len(u)-1]`, `Liste * 256`/`* 300`):** gleich wie `vcc`, kein Fehler.
- **`path_norm` mit mehreren `..`:** betrifft nur Unterordner; die Projektdisk ist flach, darum nicht geprüft.
- **Textpuffer voll:** `ed_ins` prüft die Kapazität (768 KB) nicht; bei Quelltexten dieser Größe unrealistisch, offen.

Korpuslauf nach der `exp`-Korrektur (515 Schnipsel, einschließlich der Testvorlagen): 187 byte-gleich (vorher 185 von 494), 1 mit anderen Bytes (unverändert), 22 lehnt VC65 ab; bei den von `vcc` abgelehnten: 134 gleicher Code und gleiche Zeile, 42 Syntaxfehler in der richtigen Zeile, 31 nimmt VC65 an. Kein Rückschritt gegenüber dem Stand vorher (Zähler der Vorlagen kamen neu hinzu).

## 8 Lücke: `{name}` in `.text` (2026-11-24)
`.text "x{red}y"`: `vcc` gibt den Text unverändert aus (`7b 72 65 64 7d`, die geschweiften Klammern gelten nur für `.petscii`), VC65 meldet E208 (unbekanntes Sonderzeichen). Bestand seit der Textschreibweise; der Korpus ändert sich durch die Auslagerung von `charnames` nicht. Aufwand: klein (in `text2.asm` die `{`-Behandlung nur für PETSCII-Ausgabearten einschalten, etwa 20 Byte); wird mit der Auslagerung des Textmoduls erledigt, nicht vorher im Hauptprogramm.

## 9 Lückenschluss (ab 2026-11-25, Wort der Hauptsession)
Mit der Luft aus den Overlay-Schnitten werden Lücken einzeln geschlossen (je Lücke ein Commit, Korpus nach jeder Gruppe):
- **`.align n, skip` mit n >= 256 (behoben):** `d_align` rechnete mit einer 8-Bit-Maske und meldete E203 bei `.align 256`; jetzt 16-Bit-Maske und -Prüfung wie `vcc` (n höchstens 16 Bit, Zweierpotenz). Korpus-Schnipsel 68 und 115 jetzt byte-gleich, `t23_misc` und `t29_align` ok. Kosten 36 Byte.
- **Gruppe 1 (behoben, Einzelproben gegen `vcc` gleich):** `.shift ""`/`.textshift ""` (E203), offene `.if`-Blöcke am Quelltextende (E210 je Ebene an der Eröffnungsstelle, innerste zuerst), Größenzusatz an ungeeigneter Form (`bne.a`, `lda.z #1`: E215), `.function` mit eingebautem Namen (E204), `.branchlong` mit anderem Wort als auto/jmp/off (E208). **Offen:** E301 (Überlauf über `$FFFF`, `vcc` meldet Zeile 0, nicht darstellbar). 
- **Offen, größer:** `.bank`/`.segment`/`.cartridge`/`.atascii`, Systemdateien anderer Ziele (nur Disk), `{name}` in `.text`, Größenzusätze `.abs`/`.zp` (Operandenparser), W200/W202/W203/W205/W207.

## 10 Korpuslauf nach dem Lückenschluss (2026-11-25, leerer Zwischenspeicher, getrennter Worktree)
Stand efdf82c (nach `.align 256`, Gruppe 1, leere Operandenlisten, `.segment`, `.bank`, `.cartridge`; das Korpuswerkzeug wertet `vcc` „keine Ausgabe“ jetzt als leere Ausgabe und zählt diese Schnipsel zu den von `vcc` übersetzten):
- 515 Schnipsel: **223 byte-gleich** von 240, die `vcc` übersetzt (92,9 %; Referenz vorher 185 von 206 = 89 %), 1 mit anderen Bytes, 16 lehnt VC65 ab.
- Von `vcc` abgelehnt (275): 152 gleicher Code und gleiche Zeile, 39 allgemeiner Syntaxfehler in der richtigen Zeile, 15 mit zusätzlichen Meldungen, 16 gleicher Code in anderer Zeile, 25 anderer Code, 14 nur ein Teil der Fehler, 13 nimmt VC65 an.
- Vorstand (Stand ef03edf, altes Werkzeug): 189 byte-gleich von 210 (90,0 %), 17 angenommen, 50 andere Codes.

Korpuslauf nach „offene Blöcke“ (Stand `.for`/`.repeat`/`.macro`/`.struct`/`.enum` E210 an der Direktivenzeile, Scope E213 in der letzten Zeile; leerer Zwischenspeicher): 223 byte-gleich von 240 (unverändert), von `vcc` abgelehnt: 158 gleicher Code und gleiche Zeile (vorher 152), 40 Syntaxfehler in der richtigen Zeile, 24 mit zusätzlichen Meldungen (vorher 15), 12 gleicher Code in anderer Zeile (vorher 16), **13 anderer Code (vorher 25)**, 14 nur ein Teil der Fehler, 13 nimmt VC65 an, 16 lehnt VC65 ab. Kein Rückschritt.

Korpuslauf nach der Gruppe „Wertebereich, fehlende Operanden, Suffixe, `.segment`/`.bank`“ (Stand `.atascii`-Korrektur; leerer Zwischenspeicher): 515 Schnipsel: **232 byte-gleich von 240** (96,7 %; vorher 223 von 240 = 92,9 %, Referenz am Anfang 89 %), 1 mit anderen Bytes (`.basicstub` mit `{$41}` im Kommentar, bestand schon), 7 lehnt VC65 ab (Systemdateien anderer Ziele, `.atascii` mit Namen, `.text` mit Zeichen außerhalb ASCII). Von `vcc` abgelehnt: 167 gleicher Code und gleiche Zeile (vorher 152), 40 Syntaxfehler in der richtigen Zeile, 23 mit zusätzlichen Meldungen, 12 gleicher Code in anderer Zeile, 13 anderer Code (vorher 25), 10 nur ein Teil der Fehler (vorher 14), 9 nimmt VC65 an (vorher 13). Offen: ATASCII-Namen, `{$hh}` im `.basicstub`-Kommentar, E301 (Zeile 0), `.lohifill`/`.lohitable`-Bereiche, `.be32` über 32 Bit, doppeltes `.struct` E204, `.macro`-Standardwerte E210, Systemdateien anderer Ziele (nur Disk), W200–W207.

**Entscheidung des Inhabers (2026-11-25):** `.atascii` (und damit ATASCII-Namen) ist nur für Atari und wird in VC65 **nicht** umgesetzt; die Direktive meldet E208. Gewollte Abweichung von `vcc`, keine Lücke.
**Entscheidung des Inhabers (2026-11-25):** Systemdateien anderer Ziele (`<c64/...>` außer `hardware`, `<c128/...>`, `<atari8bit/...>`, …) werden in VC65 **nicht** mitgeliefert: VC65 ist ausschließlich für den MEGA65. Gewollte Abweichung von `vcc`; das Korpuswerkzeug führt solche Schnipsel als „gewollte_ausnahme“ getrennt. Die Systemdateien für den MEGA65 und `common` liegen auf der Systemdisk; im Korpus-Prüfstand fehlen sie, dort gemeldete 212-Fehler bei `<common/...>` sind eine Grenze des Prüfstands, keine der IDE.

Korpuslauf nach „Warnungen, E301, doppeltes `.struct`, `.macro`-Vorgabewerte“ (Stand d923198; leerer Zwischenspeicher; `.atascii`, `.cartridge` und Systemdateien anderer Ziele als gewollte Ausnahmen getrennt): 515 Schnipsel: **225 byte-gleich von 229** übersetzten Schnipseln außerhalb der Ausnahmen (98,3 %), 1 mit anderen Bytes (`.basicstub`-Kommentar mit `{$41}`), 3 lehnt VC65 ab, 13 gewollte Ausnahmen. Von `vcc` abgelehnt: 169 gleicher Code und gleiche Zeile, 40 Syntaxfehler in der richtigen Zeile, 23 mit zusätzlichen Meldungen, 12 gleicher Code in anderer Zeile, 13 anderer Code, 10 nur ein Teil der Fehler, 5 nimmt VC65 an. Warnungen: bis auf 2 Schnipsel (403, 404: VC65 meldet W204 bei `.basicstub` nicht bei `$2001`, `vcc` nicht in diesen Fällen) gleiche Warncodes wie `vcc` (W200, W202, W203 neu umgesetzt).
Offen: `{$hh}` im `.basicstub`-Kommentar, `.lohifill`/`.lohitable`-Bereiche, E301 mit Zeile 0 (VC65 meldet in der Zeile der überzähligen Ausgabe), W204-Sonderfälle, rückwärts springendes `.org` (Rohabbild von der niedrigsten Adresse), `.be32` über 32 Bit (Grenze: Ganzzahlen 32 Bit).

Korpuslauf nach „`.lohifill`-Bereich, W204, `{$hh}` im `.basicstub`-Kommentar“ (Stand 7d857bf; leerer Zwischenspeicher): 515 Schnipsel: **226 byte-gleich von 229** übersetzten Schnipseln außerhalb der gewollten Ausnahmen (98,7 %), **keiner mit anderen Bytes**, 3 lehnt VC65 ab, 13 gewollte Ausnahmen (ATASCII, `.cartridge`, Systemdateien anderer Ziele). Von `vcc` abgelehnt: 172 gleicher Code und gleiche Zeile, 40 Syntaxfehler in der richtigen Zeile, 23 mit zusätzlichen Meldungen, 12 gleicher Code in anderer Zeile, 13 anderer Code, 8 nur ein Teil der Fehler, 4 nimmt VC65 an. **Warnungen: alle Codes gleich** (0 Abweichungen).
**Gewollte Abweichungen (Format, keine Lücken):** `.org` rückwärts hinter ausgegebene Bytes (die PRG-Ausgabe hat eine Ladeadresse; `vcc` erzeugt dort ein Rohabbild ab der niedrigsten Adresse), `.be32` über 32 Bit (Ganzzahlen 32 Bit), E301 in Zeile 0 (VC65 meldet in der Zeile der überzähligen Ausgabe).

Korpuslauf nach „Textanweisungen nur mit Zeichenketten, `.lohifill` ohne Ausdruck, `.page 0`“ (Stand 243e8bb; leerer Zwischenspeicher): 515 Schnipsel: 226 byte-gleich von 229 übersetzten außerhalb der gewollten Ausnahmen (98,7 %), 0 mit anderen Bytes, 3 lehnt VC65 ab (Prüfstand ohne Systemdisk), 13 gewollte Ausnahmen. Von `vcc` abgelehnt: **179 gleicher Code und gleiche Zeile** (vorher 172), 40 Syntaxfehler in der richtigen Zeile, 23 mit zusätzlichen Meldungen, **6 gleicher Code in anderer Zeile** (vorher 12), 13 anderer Code (davon 7 `.bank` mit E901 als gewollte Abweichung), 8 nur ein Teil der Fehler, 3 nimmt VC65 an. Warnungen: alle Codes gleich.
