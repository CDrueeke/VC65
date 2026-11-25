<!-- SPDX-License-Identifier: MIT-0 -->
# Etappe N4: Assembler Stufe 2 (Stand und Aufbau)

Englische Fassung: [../en/n4-assembler-stage2.md](../en/n4-assembler-stage2.md). Aufbauend auf [n2-assembler.md](n2-assembler.md): Variablen, Wiederholungen, Makros, Scopes, Strukturen und weitere Direktiven, gleiche Ergebnisse wie `vcc`. Alles läuft in Xemu (Mac) und besteht die Differenztests; am echten MEGA65 ungeprüft.

## Was Stufe 2 kann

| Bereich | Umfang | Datei |
|---|---|---|
| Variablen | `.var`, `.set`, `name = …`, `name op= …` (`+ - * / % & \| ^ << >>`); Wert gilt ab der Zeile, in der er gesetzt wird | `stage2.asm` |
| Wiederholen | `.repeat n [, var]`, `.for i = a, bedingung, schritt`, `.for i in range(…)`, `.for c in [liste]`, `.next`, `.break`, `.continue`; die Laufvariable gilt nur im Block und verdeckt eine gleichnamige | `stage2.asm` |
| Makros | `.macro`/`.endmacro`, Parameter durch Textersetzung (Klammern und Vorgabewerte `p=wert`), Aufruf mit und ohne Klammern, Aufruf vor der Definition, `@label` je Aufruf eindeutig, `.exitmacro`, Schachtelung bis 64 Rahmen | `stage2.asm` |
| Scopes | `{ }` (benannt durch die Marke in der Zeile, sonst anonym), `.namespace name {`; innerster Scope gewinnt, `scope.name` von außen, lokale Labels je Scope, Variablen verdecken | `stage2.asm` |
| Weitere Direktiven | `.page [n]`, `.pseudopc`/`.endpseudopc`/`.realpc`, `.fill` und `.lohifill` mit Ausdruck und Laufvariable, `.struct`, `.enum`, `.rta` mit Liste, `.basicstub ziel, zeile, "text"`, `.assert`, `.error`, `.warning`, Aliase `.db .dw .dbyt .long`, `//`-Kommentare | `dir2.asm`, `asm.asm` |
| Funktionen | eingebaut: `abs sign min max int floor ceil round next align pow sqrt sin cos tan asin acos atan atan2 exp log log2 log10 len range`; eigene: `.function name(a, b) = ausdruck` (ein Ausdruck, bis 16 Ebenen tief, keine Rekursion), Aufruf nur mit direkt folgender Klammer | `func.asm`, `math.asm`, `list.asm` |
| Kommazahlen | Literale `2.5`, `1e3`, `1.5e-2`, `pi`; Rechnen `+ - * /`, Vergleiche, `&& \|\| !`; `int`/`floor`/`ceil`/`round`; als `.var` haltbar; an Stellen, die eine Ganzzahl brauchen, wird zur Null hin gekürzt (vcc warnt dort mit W202) | `numx.asm`, `math.asm` |
| Listen | `[a, b, c]`, `t[i]`, `t[-1]`, `t[a:b]`, `t[:n]`, `t[n:]`, `Liste + Liste`, `Liste * n`, `len`, `range`, Listen in Listen; `.byte`/`.word`/`.dword` geben Listen flach aus; `.for x in liste`; `.var t = []` mit `t += [..]` | `list.asm` |
| Text | `{name}`, `{$hh}`, `{nnn}`, `{name*n}`, `{{` in Zeichenketten; `.encoding "name" { … }` | `text2.asm`, `charnames.asm` |

`charnames.asm` wird von `tools/gen_charnames.py` aus `vendor/vintagecoder/data/chars/petscii.json` erzeugt (49 Namen samt BASIC-Namen und Aliasen).

- **`.target` ist optional**: VC65 übersetzt nur für den MEGA65. Ohne `.target` gilt `mega65`; `.target mega65` wird akzeptiert, jedes andere Ziel meldet einen Fehler (E207). Quelltexte aus VintageCoder mit `.target mega65` laufen unverändert (Tests `t00_*` ohne, `t17_var` mit der Zeile).

## Wie es funktioniert

**Quelltext-Stapel.** Der Assembler liest weiter über den 32-Bit-Zeiger `SRC`. Schleifen setzen `SRC` am Blockende auf den Anfang ihres Rumpfs zurück; ein Makroaufruf schreibt den Rumpf mit eingesetzten Parametern in einen Textpuffer und liest von dort weiter. Das Ende des Puffers (Zeichen 0) führt zur Aufrufzeile zurück. Jede laufende Schleife und jeder Makroaufruf ist ein **Rahmen** (32 Byte) auf einem Stapel; `.break`, `.continue` und `.exitmacro` bauen Rahmen ab und stellen die `.if`-Tiefe wieder her.

**Makros.** Vor dem ersten Durchlauf sucht `mac_scan` alle `.macro`-Zeilen (ein Makro darf vor seiner Definition aufgerufen werden); die Tabelle merkt Name (klein) und den Textzeiger hinter dem Namen. Beim Aufruf werden die Argumente nach `vcc` zerlegt (führende `(` und abschließende `)` des Argumenttexts entfallen, Kommas auf Klammertiefe 0 trennen), mit dem Kopf des Makros gepaart (Vorgabewerte füllen fehlende Argumente, sonst **E209**) und der Rumpf Zeichen für Zeichen kopiert: ein Name, der genau einem Parameter entspricht, wird durch das Argument ersetzt (nicht in Zeichenketten und Kommentaren); `@name` wird zu `.zqNNNNname` mit einer je Aufruf neuen Nummer (lokales Label, dadurch je Aufruf eindeutig). Die Aufrufnummer wird in jedem Durchlauf neu gezählt, damit alle Durchläufe dieselben Namen erzeugen.

**Variablen** liegen in einer eigenen Tabelle (immer aktueller Wert, kein „alt/neu“ wie bei Marken) und werden zu Beginn jedes Durchlaufs geleert; beim Nachschlagen haben sie Vorrang vor Marken desselben Namens im selben Scope.

**Scopes.** Der Pfad der offenen Scopes steht als Text (`a.b.`); Namen werden beim Anlegen mit dem Pfad versehen und beim Nachschlagen vom innersten Scope nach außen probiert. Anonyme Scopes heißen `#hhhh` (Zähler je Durchlauf). `{`/`}` nach `.encoding` bilden einen Kodierungsblock auf demselben Stapel (stellt die Kodierung wieder her, Marken bleiben sichtbar).

**Soft-Fehler.** `.assert` und `.error` zählen wie Wertfehler erst im letzten, stabilen Durchlauf (`E207`).

## Speicher (Stufe 2)

Bank 4 (`$0004_0000`): Variablen `$0000–$1FFF`, Listenspeicher `$2000–$3FFF`, Rahmen `$4000–$47FF`, Funktionstabelle `$4800–$4BFF`, Argumentstapel `$4C00–$5FFF` (9 Byte je Wert), Makrotabelle `$6000–$6FFF`, Expansionspuffer `$7000–$BFFF`, Hash-Tabelle der Symbole `$C000–$FFFF` (8192 Plätze zu 2 Byte, lineares Sondieren; Hash = dreimal links drehen und Zeichen addieren). **Bank 6 und höher gibt es im Chip-RAM nicht** (nur Bank 0, 1, 4, 5; Bank 2 und 3 sind ROM-Bereich); ein erster Entwurf mit Bank 6 scheiterte genau daran. Im Bankplan des Konzepts sind Bank 4 und 5 Arbeits- und Tabellenbänke; die Stufe-2-Daten gehören zur Rolle „Assembler-Arbeitsdaten“.

Zeropage: `$00–$0d` (`P6`, `P7`, `FP`, `S2T`) und `$fc/$fd` (`MP`); der Rest unverändert aus `zp.asm`. Ergebnisse der Testprogramme liegen jetzt bei `$C200`. Das Programm ist inzwischen so groß (bis etwa `$7E00`), dass die Basisseite der Tests von `$6F00` nach `$9F00` wandern musste; sie muss im RAM unter `$A000` liegen (BASIC-ROM) und darf den Code nicht überdecken. Im fertigen VC65 liegt der Code in Bank 4, dort ist das kein Thema.

## Grenzen (noch offen)

- **Nicht-ASCII-Zeichen (UTF-8, Umlaute):** In Kommentaren und in Zeichenketten für `.text`, `.petscii` und `.byte` übersetzt VC65 wie `vcc` (byte-gleich). **Abweichungen von `vcc`:** Labels, Konstanten und Zeichenliterale (`'ü'`) mit Nicht-ASCII-Zeichen meldet der native Assembler als Fehler (E205 beziehungsweise E201), `vcc` nimmt sie an; `.screencode` mit Nicht-ASCII-Zeichen ergibt anderen Code (zum Beispiel `$C3` statt `$43` für das erste Byte von ü). Empfehlung: Umlaute nur in Kommentaren und in Zeichenketten für `.text`, `.petscii` und `.byte`; Bezeichner und `.screencode` nur mit ASCII. Der Editor zeigt jedes Byte über 127 als Punkt (ein ü als zwei Punkte); gespeichert werden die Bytes unverändert.
- **Makroparameter:** höchstens 16 (`MAXPAR` in `stage2.asm`; Tabelle `ptbl` im Abbild, 32 Byte je Parameter). `vcc` kennt keine Grenze (belegt in vc-asm, E209 prüft nur die Zahl der Aufrufargumente). Mehr Parameter in der Makrodeklaration melden E900 (`ERR_E900`, nur VC65), mehr Argumente als Parameter E209 wie bei `vcc`. Test: `tools/errtest.py` (`par16`, `par17`).
- **Kommazahlen sind Festkomma 32.32**, nicht IEEE-Double wie in `vcc`: Auflösung 2,3·10⁻¹⁰, Ganzzahlteil 32 Bit. Winkel-, Logarithmus- und Wurzelfunktionen (CORDIC, Newton, Reihen) liefern bis auf Rundungsfehler um 10⁻⁸ dasselbe; Ergebnisse, die bis auf etwa 2⁻²² ganzzahlig sind, werden auf die ganze Zahl gesetzt (`sin(pi/2)` = 1, `log10(1000)` = 3, wie bei `vcc`). Grenzfälle, in denen ein exakter Halbwert nur in Doppelgenauigkeit auf der einen oder anderen Seite liegt, können abweichen. Ganzzahlen sind 32 Bit (vcc: 64 Bit).
- Liste mit mehr als etwa 900 Elementen sprengt den Listenspeicher (8 KB, `E211`); `x += [..]` kopiert die Liste jedes Mal.
- `.for x in range(…)` läuft ohne Liste (auch sehr lange Bereiche), `range(…)` im Ausdruck legt dagegen die Liste an.
- `.run` wird gelesen, hat aber keine Wirkung (`.cycles` siehe n2-assembler.md). `.atascii` (Atari) ist nicht vorgesehen.
- `.fill`/`.lohifill` werten den Ausdruck je Element aus (einfach, aber bei sehr großen Tabellen langsamer).
- Verschachtelungstiefe: 64 Rahmen, 7 Scopes, Namen bis 31 Zeichen samt Scope-Pfad (sonst `E211`).
- Struct-Felder vom Typ einer Struktur mit Anzahl > 1 legen die Unterfelder nur für das erste Element an (wie `vcc`).

## Geschwindigkeit

Die Symbole werden über eine Hash-Tabelle gefunden (vorher linear: 37,5 s). Selbstübersetzung (8477 Zeilen, 4 Durchläufe) in Xemu bei 40 MHz: **5,8 s**, also etwa 0,7 s je 1000 Zeilen über alle Durchläufe; das Ziel des Konzepts (unter 1 s für 1000 Zeilen) ist damit erreicht. Gemessen mit den CIA-Zählern (`tools/selfhost.py`); Xemu kennt keine Wartezustände, am echten MEGA65 ungeprüft.

## Tests

`tests/asm/t17_var` … `t27_list` decken die Stufe-2-Funktionen ab (Differenztest gegen `vcc`); die Beispiele der Hilfe laufen über `tools/conform.py` (**61 von 67 identisch**, siehe n2-assembler.md). Die Selbstübersetzung (`tools/selfhost.py`) besteht weiterhin.

### MEGA65-Beispielprojekte aus VintageCoder

`tools/examples.py [Name …]` kopiert ein Beispielprojekt (nur gelesen) nach `build/ex/<Name>`, lässt `vcc build` die Exportdateien (`build/export/*.asm`) erzeugen und vergleicht dann `vcc` und den nativen Assembler in Xemu Byte für Byte. Stand: **cputest, jumprun, music_demo, pal_demo und prallball (224 KB, 7531 Zeilen) sind identisch**. Dabei gefunden und behoben: Makros in per `#include` eingebundenen Dateien wurden von der Vorabsuche übersehen; `aslq q`/`lsrq q` (Q als Operand); anonyme Marken mit mehreren Zeichen (`jmp ++`, `bne --`); mehr als 16 Dateien in einem Projekt (ab der 17. teilen sie sich den letzten Namensplatz, nur die Zuordnung von Fehlern zur Datei leidet). Offen: **`hello`** benutzt Chip-Symbole (`vic2.border`, aus `data/chips/*.chip.json`), die der native Assembler noch nicht kennt; `play_demo`, `standard_charsets` und `tiles_demo` haben keinen Quelltext. Pfade, die über die Projektwurzel hinausführen (`../../common/…`), werden vom nativen Assembler zu `common/…` normalisiert; der Test legt die Dateien deshalb unter diesem Namen ab.

**E300 (Code oder Marke vor dem ersten `.org`):** Wie `vcc` meldet der native Assembler jetzt E300, wenn vor dem ersten `.org` (oder `*=`) ein Byte ausgegeben oder eine Marke definiert wird; Konstanten, Makrodefinitionen und `.align` ohne Wirkung bleiben erlaubt. Getestet in `tools/idetest.py` (`e300_code`, `e300_marke`).
